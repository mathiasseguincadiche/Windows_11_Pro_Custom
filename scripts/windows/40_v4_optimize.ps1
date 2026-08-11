[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify', 'Rollback')]
    [string]$Mode = 'Audit',

    [ValidateSet('standard', 'privacy', 'gaming', 'optional')]
    [string]$Profile = 'standard'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$profilePath = Join-Path $repoRoot "config\windows\v4\$Profile.json"
$stateDir = Join-Path $repoRoot 'state\windows-v4'
$statePath = Join-Path $stateDir "$Profile.before.json"

if (-not (Test-Path $profilePath)) {
    throw "V4 profile not found: $profilePath"
}

$config = Get-Content -Raw $profilePath | ConvertFrom-Json

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Apply and Rollback require an elevated PowerShell session.'
    }
}

function Get-RegistryState {
    param([Parameter(Mandatory)]$Entry)

    if (-not (Test-Path $Entry.path)) {
        return [pscustomobject]@{ Exists = $false; Value = $null; Kind = $null }
    }

    $item = Get-Item -LiteralPath $Entry.path
    try {
        $value = $item.GetValue($Entry.property, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -eq $value) {
            return [pscustomobject]@{ Exists = $false; Value = $null; Kind = $null }
        }

        return [pscustomobject]@{
            Exists = $true
            Value = $value
            Kind = $item.GetValueKind($Entry.property).ToString()
        }
    } catch {
        return [pscustomobject]@{ Exists = $false; Value = $null; Kind = $null }
    }
}

function Test-RegistryMatch {
    param(
        [Parameter(Mandatory)]$Entry,
        [Parameter(Mandatory)]$State
    )

    if (-not $State.Exists) { return $false }
    if ($Entry.type -eq 'String') {
        return ([string]$State.Value -ceq [string]$Entry.value)
    }
    return ([int64]$State.Value -eq [int64]$Entry.value)
}

function Get-ServiceState {
    param([Parameter(Mandatory)]$Entry)

    $service = Get-CimInstance Win32_Service | Where-Object Name -EQ $Entry.name | Select-Object -First 1
    if (-not $service) {
        return [pscustomobject]@{ Exists = $false; StartMode = $null; State = $null }
    }

    return [pscustomobject]@{
        Exists = $true
        StartMode = [string]$service.StartMode
        State = [string]$service.State
    }
}

function Convert-StartupTypeToCimMode {
    param([string]$StartupType)
    switch ($StartupType) {
        'Automatic' { return 'Auto' }
        'Manual' { return 'Manual' }
        'Disabled' { return 'Disabled' }
        default { return $StartupType }
    }
}

function Show-ProfileStatus {
    Write-Host "V4 profile: $Profile" -ForegroundColor Cyan
    Write-Host $config.description

    foreach ($entry in @($config.registry)) {
        $current = Get-RegistryState -Entry $entry
        $ok = Test-RegistryMatch -Entry $entry -State $current
        $label = if ($ok) { 'OK' } else { 'DIFF' }
        Write-Host ("[{0}] REG {1} | current={2} target={3}" -f $label, $entry.name, $current.Value, $entry.value)
    }

    foreach ($entry in @($config.services)) {
        $current = Get-ServiceState -Entry $entry
        $target = Convert-StartupTypeToCimMode -StartupType $entry.startupType
        $ok = $current.Exists -and ($current.StartMode -eq $target)
        $label = if ($ok) { 'OK' } else { 'DIFF' }
        Write-Host ("[{0}] SVC {1} | startup={2} target={3} runtime={4}" -f $label, $entry.name, $current.StartMode, $target, $current.State)
    }
}

switch ($Mode) {
    'Audit' {
        Show-ProfileStatus
    }

    'Apply' {
        Assert-Administrator
        New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

        if (-not (Test-Path $statePath)) {
            $registryBackup = @(
                foreach ($entry in @($config.registry)) {
                    $state = Get-RegistryState -Entry $entry
                    [pscustomobject]@{
                        Name = $entry.name
                        Path = $entry.path
                        Property = $entry.property
                        Exists = $state.Exists
                        Value = $state.Value
                        Kind = $state.Kind
                    }
                }
            )

            $serviceBackup = @(
                foreach ($entry in @($config.services)) {
                    $state = Get-ServiceState -Entry $entry
                    [pscustomobject]@{
                        Name = $entry.name
                        Exists = $state.Exists
                        StartMode = $state.StartMode
                    }
                }
            )

            [ordered]@{
                Profile = $Profile
                CapturedAt = (Get-Date).ToString('o')
                Registry = $registryBackup
                Services = $serviceBackup
            } | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 $statePath

            Write-Host "[OK] Initial V4 state saved: $statePath" -ForegroundColor Green
        } else {
            Write-Host "[INFO] Existing initial state preserved: $statePath" -ForegroundColor Yellow
        }

        foreach ($entry in @($config.registry)) {
            New-Item -ItemType Directory -Force -Path $entry.path | Out-Null
            New-ItemProperty -Path $entry.path -Name $entry.property -PropertyType $entry.type -Value $entry.value -Force | Out-Null
        }

        foreach ($entry in @($config.services)) {
            $current = Get-ServiceState -Entry $entry
            if (-not $current.Exists) {
                Write-Warning "Service not present, skipped: $($entry.name)"
                continue
            }
            Set-Service -Name $entry.name -StartupType $entry.startupType
        }

        Show-ProfileStatus
        if ($config.rebootRecommended) {
            Write-Host '[INFO] Reboot recommended for this profile.' -ForegroundColor Yellow
        }
    }

    'Verify' {
        $failed = 0

        foreach ($entry in @($config.registry)) {
            $current = Get-RegistryState -Entry $entry
            if (Test-RegistryMatch -Entry $entry -State $current) {
                Write-Host "[OK] REG $($entry.name)"
            } else {
                Write-Host "[KO] REG $($entry.name)" -ForegroundColor Red
                $failed++
            }
        }

        foreach ($entry in @($config.services)) {
            $current = Get-ServiceState -Entry $entry
            $target = Convert-StartupTypeToCimMode -StartupType $entry.startupType
            if ($current.Exists -and ($current.StartMode -eq $target)) {
                Write-Host "[OK] SVC $($entry.name)"
            } else {
                Write-Host "[KO] SVC $($entry.name)" -ForegroundColor Red
                $failed++
            }
        }

        if ($failed -gt 0) {
            throw "V4 profile '$Profile' failed $failed verification check(s)."
        }
        Write-Host "[OK] V4 profile '$Profile' verified." -ForegroundColor Green
    }

    'Rollback' {
        Assert-Administrator
        if (-not (Test-Path $statePath)) {
            throw "V4 backup not found: $statePath"
        }

        $backup = Get-Content -Raw $statePath | ConvertFrom-Json

        foreach ($entry in @($backup.Registry)) {
            if ($entry.Exists) {
                New-Item -ItemType Directory -Force -Path $entry.Path | Out-Null
                $kind = if ($entry.Kind) { [string]$entry.Kind } else { 'DWord' }
                New-ItemProperty -Path $entry.Path -Name $entry.Property -PropertyType $kind -Value $entry.Value -Force | Out-Null
            } elseif (Test-Path $entry.Path) {
                Remove-ItemProperty -Path $entry.Path -Name $entry.Property -ErrorAction SilentlyContinue
            }
        }

        foreach ($entry in @($backup.Services)) {
            if (-not $entry.Exists) { continue }
            $startupType = switch ([string]$entry.StartMode) {
                'Auto' { 'Automatic' }
                'Manual' { 'Manual' }
                'Disabled' { 'Disabled' }
                default { $null }
            }
            if ($startupType) {
                Set-Service -Name $entry.Name -StartupType $startupType
            }
        }

        Write-Host "[OK] V4 profile '$Profile' restored from initial state." -ForegroundColor Green
    }
}
