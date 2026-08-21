#Requires -Version 7.6
[CmdletBinding()]
param(
    [string]$Description = 'Windows_11_Pro_Custom before optimization'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$powerShellRuntimeModule = Join-Path $repoRoot 'scripts\core\powershell-runtime.psm1'
if (-not (Test-Path -LiteralPath $powerShellRuntimeModule)) { throw "Contrat PowerShell introuvable: $powerShellRuntimeModule" }
Import-Module $powerShellRuntimeModule -Force
[void](Assert-WpcPowerShellRuntime -MinimumVersion ([version]'7.6.4') -RequireWindows -PassThru)

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "La création du point de restauration exige une session PowerShell 7 administrateur."
}

$restoreRegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
$restoreFrequencyName = 'SystemRestorePointCreationFrequency'

function ConvertFrom-WpcRestorePointTime {
    param([Parameter(Mandatory)]$Value)

    if ($Value -is [datetime]) { return [datetime]$Value }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    try {
        return [System.Management.ManagementDateTimeConverter]::ToDateTime($text)
    } catch {
        if ($text.Length -ge 14) {
            try {
                return [datetime]::ParseExact(
                    $text.Substring(0, 14),
                    'yyyyMMddHHmmss',
                    [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::AssumeLocal
                )
            } catch {}
        }
    }
    return $null
}

function Get-WpcLatestRestorePoint {
    try {
        $points = @(
            Get-CimInstance -Namespace 'root/default' -ClassName 'SystemRestore' -ErrorAction Stop |
                ForEach-Object {
                    $created = ConvertFrom-WpcRestorePointTime -Value $_.CreationTime
                    if ($created) {
                        [pscustomobject]@{
                            SequenceNumber = [uint32]$_.SequenceNumber
                            Description = [string]$_.Description
                            CreationTime = $created
                        }
                    }
                }
        )
        $latest = @($points | Sort-Object CreationTime -Descending | Select-Object -First 1)
        return [pscustomobject]@{
            QuerySucceeded = $true
            Point = if ($latest.Count -gt 0) { $latest[0] } else { $null }
            Error = $null
        }
    } catch {
        return [pscustomobject]@{ QuerySucceeded=$false; Point=$null; Error=$_.Exception.Message }
    }
}

function Get-WpcRestorePointFrequencyState {
    if (-not (Test-Path -LiteralPath $restoreRegistryPath)) {
        throw "Clé System Restore introuvable: $restoreRegistryPath"
    }

    $item = Get-ItemProperty -LiteralPath $restoreRegistryPath -ErrorAction Stop
    $exists = $item.PSObject.Properties.Name -contains $restoreFrequencyName
    $value = if ($exists) { [uint32]$item.$restoreFrequencyName } else { $null }

    [pscustomobject]@{
        Exists = $exists
        Value = $value
    }
}

function Enable-WpcDeterministicRestorePointCreation {
    New-ItemProperty -LiteralPath $restoreRegistryPath -Name $restoreFrequencyName -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
    Write-Host '[EN COURS] Fréquence System Restore temporairement forcée à 0 minute pour garantir un nouveau point...' -ForegroundColor Cyan
}

function Restore-WpcRestorePointFrequencyState {
    param([Parameter(Mandatory)]$State)

    if ($State.Exists) {
        New-ItemProperty -LiteralPath $restoreRegistryPath -Name $restoreFrequencyName -PropertyType DWord -Value ([uint32]$State.Value) -Force -ErrorAction Stop | Out-Null
        Write-Host "[OK] Fréquence System Restore restaurée à sa valeur précédente: $($State.Value) minute(s)." -ForegroundColor DarkGray
    } else {
        Remove-ItemProperty -LiteralPath $restoreRegistryPath -Name $restoreFrequencyName -ErrorAction SilentlyContinue
        Write-Host '[OK] Fréquence System Restore restaurée à son état précédent: valeur personnalisée absente.' -ForegroundColor DarkGray
    }
}

function Invoke-WpcSystemRestoreMethod {
    param(
        [Parameter(Mandatory)][string]$MethodName,
        [Parameter(Mandatory)][hashtable]$Arguments
    )

    $result = Invoke-CimMethod -Namespace 'root/default' -ClassName 'SystemRestore' -MethodName $MethodName -Arguments $Arguments -ErrorAction Stop
    $returnValue = [uint32]$result.ReturnValue
    if ($returnValue -ne 0) {
        throw "SystemRestore.$MethodName a retourné le code $returnValue."
    }
    return $result
}

function New-WpcRestorePointPowerShell7 {
    param([Parameter(Mandatory)][string]$RestorePointDescription)

    $systemRestoreClass = Get-CimClass -Namespace 'root/default' -ClassName 'SystemRestore' -ErrorAction Stop
    $methodNames = @(
        $systemRestoreClass.CimClassMethods |
            ForEach-Object { [string]$_.Name }
    )
    foreach ($requiredMethod in @('Enable','CreateRestorePoint')) {
        if ($methodNames -notcontains $requiredMethod) {
            throw "Méthode SystemRestore requise absente: $requiredMethod"
        }
    }

    $systemDrive = "$($env:SystemDrive)\"
    Write-Host "[EN COURS] Activation/vérification de System Restore sur $systemDrive via CIM..." -ForegroundColor Cyan
    [void](Invoke-WpcSystemRestoreMethod -MethodName 'Enable' -Arguments @{ Drive=$systemDrive })

    Write-Host '[EN COURS] Création du point de restauration via SystemRestore.CreateRestorePoint...' -ForegroundColor Cyan
    [void](Invoke-WpcSystemRestoreMethod -MethodName 'CreateRestorePoint' -Arguments @{
        Description = $RestorePointDescription
        RestorePointType = [uint32]12
        EventType = [uint32]100
    })
}

function Wait-WpcRestorePointEvidence {
    param(
        [Parameter(Mandatory)][datetime]$StartedAt,
        [AllowNull()]$BeforeSequence,
        [int]$TimeoutSeconds = 90
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastQuery = $null

    do {
        $lastQuery = Get-WpcLatestRestorePoint
        if ($lastQuery.QuerySucceeded -and $lastQuery.Point) {
            $point = $lastQuery.Point
            $isRecent = $point.CreationTime -ge $StartedAt.AddMinutes(-2)
            $isNewSequence = ($null -eq $BeforeSequence) -or ([uint32]$point.SequenceNumber -gt [uint32]$BeforeSequence)
            if ($isRecent -and $isNewSequence) {
                return $point
            }
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    if ($lastQuery -and -not $lastQuery.QuerySucceeded) {
        throw "La création a été demandée, mais la preuve CIM reste indisponible après ${TimeoutSeconds}s: $($lastQuery.Error)"
    }

    $observed = if ($lastQuery -and $lastQuery.Point) {
        "dernier point=$($lastQuery.Point.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')) séquence=$($lastQuery.Point.SequenceNumber) description='$($lastQuery.Point.Description)'"
    } else {
        'aucun point visible via CIM'
    }
    throw "SystemRestore.CreateRestorePoint a retourné S_OK, mais aucun nouveau point récent n'a été confirmé après ${TimeoutSeconds}s ($observed)."
}

try {
    $before = Get-WpcLatestRestorePoint
    $recentThreshold = (Get-Date).AddHours(-24)
    if ($before.QuerySucceeded -and $before.Point -and $before.Point.CreationTime -ge $recentThreshold) {
        Write-Host ("[DÉJÀ OK] Point de restauration récent déjà présent ({0:yyyy-MM-dd HH:mm}, séquence {1}); aucun doublon créé." -f $before.Point.CreationTime, $before.Point.SequenceNumber) -ForegroundColor Green
        return
    }

    $frequencyState = Get-WpcRestorePointFrequencyState
    try {
        Enable-WpcDeterministicRestorePointCreation
        $startedAt = Get-Date
        $beforeSequence = if ($before.QuerySucceeded -and $before.Point) { [uint32]$before.Point.SequenceNumber } else { $null }
        New-WpcRestorePointPowerShell7 -RestorePointDescription $Description
        $createdPoint = Wait-WpcRestorePointEvidence -StartedAt $startedAt -BeforeSequence $beforeSequence -TimeoutSeconds 90
        Write-Host ("[OK] Point de restauration Windows créé et vérifié via PowerShell 7/CIM ({0:yyyy-MM-dd HH:mm}, séquence {1}, description='{2}')." -f $createdPoint.CreationTime, $createdPoint.SequenceNumber, $createdPoint.Description) -ForegroundColor Green
    } finally {
        Restore-WpcRestorePointFrequencyState -State $frequencyState
    }
} catch {
    throw "Impossible de créer ou confirmer le point de restauration de sécurité depuis PowerShell 7. Aucune optimisation ne doit continuer sans ce garde-fou, sauf choix explicite de l'orchestrateur via -SkipFoundationRestorePoint. Détail: $($_.Exception.Message)"
}
