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
    throw "La creation du point de restauration exige une session PowerShell 7 administrateur."
}

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

function Invoke-WpcSystemRestoreMethod {
    param(
        [Parameter(Mandatory)][string]$MethodName,
        [Parameter(Mandatory)][hashtable]$Arguments
    )

    $result = Invoke-CimMethod -Namespace 'root/default' -ClassName 'SystemRestore' -MethodName $MethodName -Arguments $Arguments -ErrorAction Stop
    $returnValue = [uint32]$result.ReturnValue
    if ($returnValue -ne 0) {
        throw "SystemRestore.$MethodName a retourne le code $returnValue."
    }
    return $result
}

function New-WpcRestorePointPowerShell7 {
    param([Parameter(Mandatory)][string]$RestorePointDescription)

    $systemRestoreClass = Get-CimClass -Namespace 'root/default' -ClassName 'SystemRestore' -ErrorAction Stop
    $methodNames = @($systemRestoreClass.CimClassMethods.Keys)
    foreach ($requiredMethod in @('Enable','CreateRestorePoint')) {
        if ($methodNames -notcontains $requiredMethod) {
            throw "Methode SystemRestore requise absente: $requiredMethod"
        }
    }

    $systemDrive = "$($env:SystemDrive)\"
    Write-Host "[EN COURS] Activation/verification de System Restore sur $systemDrive via CIM..." -ForegroundColor Cyan
    [void](Invoke-WpcSystemRestoreMethod -MethodName 'Enable' -Arguments @{ Drive=$systemDrive })

    Write-Host '[EN COURS] Creation du point de restauration via SystemRestore.CreateRestorePoint...' -ForegroundColor Cyan
    [void](Invoke-WpcSystemRestoreMethod -MethodName 'CreateRestorePoint' -Arguments @{
        Description = $RestorePointDescription
        RestorePointType = [uint32]12
        EventType = [uint32]100
    })
}

try {
    $before = Get-WpcLatestRestorePoint
    $recentThreshold = (Get-Date).AddHours(-24)
    if ($before.QuerySucceeded -and $before.Point -and $before.Point.CreationTime -ge $recentThreshold) {
        Write-Host ("[DEJA OK] Point de restauration recent deja present ({0:yyyy-MM-dd HH:mm}, sequence {1}); aucun doublon cree." -f $before.Point.CreationTime, $before.Point.SequenceNumber) -ForegroundColor Green
        return
    }

    $startedAt = Get-Date
    New-WpcRestorePointPowerShell7 -RestorePointDescription $Description

    $after = Get-WpcLatestRestorePoint
    if ($after.QuerySucceeded) {
        if (-not $after.Point -or $after.Point.CreationTime -lt $startedAt.AddMinutes(-1)) {
            throw "SystemRestore.CreateRestorePoint a termine sans qu'un point de restauration recent puisse etre confirme."
        }
        Write-Host ("[OK] Point de restauration Windows cree et verifie via PowerShell 7/CIM ({0:yyyy-MM-dd HH:mm}, sequence {1})." -f $after.Point.CreationTime, $after.Point.SequenceNumber) -ForegroundColor Green
    } else {
        throw "Le point de restauration a ete demande mais la verification CIM est indisponible: $($after.Error)"
    }
} catch {
    throw "Impossible de creer ou confirmer le point de restauration de securite depuis PowerShell 7. Aucune optimisation ne doit continuer sans ce garde-fou, sauf choix explicite de l'orchestrateur via -SkipFoundationRestorePoint. Detail: $($_.Exception.Message)"
}
