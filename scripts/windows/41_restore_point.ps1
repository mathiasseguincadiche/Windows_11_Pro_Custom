[CmdletBinding()]
param(
    [string]$Description = 'Windows_11_Pro_Custom before optimization'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'La création du point de restauration exige une session PowerShell administrateur.'
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

function Get-WpcWindowsPowerShell51Path {
    $explicit = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $explicit) { return $explicit }

    $command = Get-Command powershell.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return [string]$command.Source }
    return $null
}

function New-WpcRestorePointCurrentHost {
    param([Parameter(Mandatory)][string]$RestorePointDescription)

    if (-not (Get-Command Checkpoint-Computer -ErrorAction SilentlyContinue)) {
        return $false
    }

    $systemDrive = "$($env:SystemDrive)\"
    if (Get-Command Enable-ComputerRestore -ErrorAction SilentlyContinue) {
        Enable-ComputerRestore -Drive $systemDrive -ErrorAction Stop
    }
    Checkpoint-Computer -Description $RestorePointDescription -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    return $true
}

function New-WpcRestorePointWindowsPowerShell {
    param([Parameter(Mandatory)][string]$RestorePointDescription)

    $windowsPowerShell = Get-WpcWindowsPowerShell51Path
    if (-not $windowsPowerShell) {
        throw 'Checkpoint-Computer est indisponible dans cet hôte et Windows PowerShell 5.1 est introuvable.'
    }

    $escapedDescription = $RestorePointDescription.Replace("'", "''")
    $command = @'
$ErrorActionPreference = 'Stop'
$systemDrive = "$env:SystemDrive\"
if (Get-Command Enable-ComputerRestore -ErrorAction SilentlyContinue) {
    Enable-ComputerRestore -Drive $systemDrive -ErrorAction Stop
}
Checkpoint-Computer -Description '__DESCRIPTION__' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
'@
    $command = $command.Replace('__DESCRIPTION__', $escapedDescription)

    $global:LASTEXITCODE = 0
    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command $command
    $exitVariable = Get-Variable -Name LASTEXITCODE -ErrorAction SilentlyContinue
    $exitCode = if ($null -eq $exitVariable) { 0 } else { [int]$exitVariable.Value }
    $global:LASTEXITCODE = 0
    if ($exitCode -ne 0) {
        throw "Windows PowerShell n'a pas pu créer le point de restauration (code=$exitCode)."
    }
}

try {
    $before = Get-WpcLatestRestorePoint
    $recentThreshold = (Get-Date).AddHours(-24)
    if ($before.QuerySucceeded -and $before.Point -and $before.Point.CreationTime -ge $recentThreshold) {
        Write-Host ("[DÉJÀ OK] Point de restauration récent déjà présent ({0:yyyy-MM-dd HH:mm}, séquence {1}); aucun doublon créé." -f $before.Point.CreationTime, $before.Point.SequenceNumber) -ForegroundColor Green
        return
    }

    $startedAt = Get-Date
    $createdInCurrentHost = New-WpcRestorePointCurrentHost -RestorePointDescription $Description
    if (-not $createdInCurrentHost) {
        Write-Host '[INFO] Checkpoint-Computer indisponible dans cet hôte; bascule vers Windows PowerShell 5.1.' -ForegroundColor Cyan
        New-WpcRestorePointWindowsPowerShell -RestorePointDescription $Description
    }

    $after = Get-WpcLatestRestorePoint
    if ($after.QuerySucceeded) {
        if (-not $after.Point -or $after.Point.CreationTime -lt $startedAt.AddMinutes(-1)) {
            throw 'Checkpoint-Computer a terminé sans quʼun point de restauration récent puisse être confirmé.'
        }
        Write-Host ("[OK] Point de restauration Windows créé et vérifié ({0:yyyy-MM-dd HH:mm}, séquence {1})." -f $after.Point.CreationTime, $after.Point.SequenceNumber) -ForegroundColor Green
    } else {
        Write-Host "[OK] Point de restauration Windows créé avant les modifications. Vérification WMI indisponible: $($after.Error)" -ForegroundColor Green
    }
} catch {
    throw "Impossible de créer ou confirmer le point de restauration de sécurité. Aucune optimisation ne doit continuer sans ce garde-fou, sauf choix explicite via -SkipV4RestorePoint. Détail: $($_.Exception.Message)"
}
