Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:DelegationPath = 'HKCU:\Console\%%Startup'
$script:DelegationConsole = '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}'
$script:DelegationTerminal = '{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}'

function ConvertTo-WpcTerminalVersion {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $null }
    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $match = [regex]::Match($text, '(?<!\d)(\d+\.\d+\.\d+(?:\.\d+)?)(?!\d)')
    if (-not $match.Success) { return $null }

    try {
        return [version]$match.Groups[1].Value
    } catch {
        return $null
    }
}

function Get-WpcWindowsTerminalEvidence {
    $candidates = [System.Collections.Generic.List[object]]::new()
    $inventoryError = $null
    $wingetError = $null

    try {
        $programs = @(Get-CimInstance `
            -ClassName Win32_InstalledStoreProgram `
            -Filter "ProgramId LIKE 'Microsoft.WindowsTerminal%' OR Name LIKE 'Windows Terminal%'" `
            -ErrorAction Stop)

        foreach ($program in $programs) {
            $programId = [string]$program.ProgramId
            $name = [string]$program.Name
            if (
                $programId -notmatch '(?i)^Microsoft\.WindowsTerminal(?:Preview)?(?:_|$)' -and
                $name -notmatch '(?i)^Windows Terminal(?: Preview)?$'
            ) {
                continue
            }

            $version = ConvertTo-WpcTerminalVersion -Value $program.Version
            if ($null -eq $version) { continue }

            $candidates.Add([pscustomobject]@{
                Version = $version
                Source = 'Win32_InstalledStoreProgram'
                Identity = if ($programId) { $programId } else { $name }
            })
        }
    } catch {
        $inventoryError = $_.Exception.Message
    }

    if ($candidates.Count -eq 0) {
        $winget = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($winget) {
            try {
                $output = @(& $winget.Source list `
                    --id Microsoft.WindowsTerminal `
                    --exact `
                    --disable-interactivity `
                    --accept-source-agreements 2>$null)
                $exitCode = $LASTEXITCODE
                $global:LASTEXITCODE = 0

                if ($exitCode -eq 0) {
                    foreach ($line in $output) {
                        $text = [string]$line
                        $id = 'Microsoft.WindowsTerminal'
                        $index = $text.IndexOf($id, [System.StringComparison]::OrdinalIgnoreCase)
                        if ($index -lt 0) { continue }

                        $tail = $text.Substring($index + $id.Length)
                        $version = ConvertTo-WpcTerminalVersion -Value $tail
                        if ($null -eq $version) { continue }

                        $candidates.Add([pscustomobject]@{
                            Version = $version
                            Source = 'WinGet'
                            Identity = $id
                        })
                        break
                    }
                } else {
                    $wingetError = "winget list a retourné le code $exitCode"
                }
            } catch {
                $wingetError = $_.Exception.Message
                $global:LASTEXITCODE = 0
            }
        } else {
            $wingetError = 'winget.exe introuvable'
        }
    }

    $best = @($candidates | Sort-Object -Property Version -Descending | Select-Object -First 1)
    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue | Select-Object -First 1

    return [pscustomobject]@{
        Version = if ($best.Count -gt 0) { [version]$best[0].Version } else { $null }
        Source = if ($best.Count -gt 0) { [string]$best[0].Source } else { $null }
        Identity = if ($best.Count -gt 0) { [string]$best[0].Identity } else { $null }
        AliasAvailable = [bool]$wt
        Executable = if ($wt) { [string]$wt.Source } else { $null }
        InventoryError = $inventoryError
        WinGetError = $wingetError
    }
}

function Get-WpcWindowsTerminalVersion {
    return (Get-WpcWindowsTerminalEvidence).Version
}

function Test-WpcWindowsTerminalMinimum {
    param([version]$MinimumVersion = [version]'1.22.0.0')
    $version = Get-WpcWindowsTerminalVersion
    return ($null -ne $version -and $version -ge $MinimumVersion)
}

function Get-WpcDefaultTerminalEvidence {
    $consoleValue = $null
    $terminalValue = $null
    if (Test-Path $script:DelegationPath) {
        $props = Get-ItemProperty -Path $script:DelegationPath -ErrorAction SilentlyContinue
        if ($props.PSObject.Properties['DelegationConsole']) { $consoleValue = [string]$props.DelegationConsole }
        if ($props.PSObject.Properties['DelegationTerminal']) { $terminalValue = [string]$props.DelegationTerminal }
    }
    return [pscustomobject]@{
        Path = $script:DelegationPath
        DelegationConsole = $consoleValue
        DelegationTerminal = $terminalValue
        ExpectedDelegationConsole = $script:DelegationConsole
        ExpectedDelegationTerminal = $script:DelegationTerminal
        IsCompliant = (
            $consoleValue -eq $script:DelegationConsole -and
            $terminalValue -eq $script:DelegationTerminal
        )
    }
}

function Get-WpcRegistryValueState {
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Test-Path $script:DelegationPath)) {
        return [ordered]@{ Existed=$false; Value=$null }
    }
    $props = Get-ItemProperty -Path $script:DelegationPath -ErrorAction SilentlyContinue
    $prop = $props.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        return [ordered]@{ Existed=$false; Value=$null }
    }
    return [ordered]@{ Existed=$true; Value=[string]$prop.Value }
}

function Get-WpcDefaultTerminalRegistryState {
    return [ordered]@{
        Path = $script:DelegationPath
        KeyExisted = [bool](Test-Path $script:DelegationPath)
        Values = [ordered]@{
            DelegationConsole = Get-WpcRegistryValueState -Name 'DelegationConsole'
            DelegationTerminal = Get-WpcRegistryValueState -Name 'DelegationTerminal'
        }
    }
}

function Set-WpcDefaultTerminalApplication {
    New-Item -Path $script:DelegationPath -Force | Out-Null
    New-ItemProperty -Path $script:DelegationPath -Name 'DelegationConsole' -PropertyType String -Value $script:DelegationConsole -Force | Out-Null
    New-ItemProperty -Path $script:DelegationPath -Name 'DelegationTerminal' -PropertyType String -Value $script:DelegationTerminal -Force | Out-Null
}

function Restore-WpcDefaultTerminalRegistryState {
    param([Parameter(Mandatory)]$State)
    $path = [string]$State.Path
    foreach ($name in @('DelegationConsole','DelegationTerminal')) {
        $entry = $State.Values.PSObject.Properties[$name].Value
        if ([bool]$entry.Existed) {
            New-Item -Path $path -Force | Out-Null
            New-ItemProperty -Path $path -Name $name -PropertyType String -Value ([string]$entry.Value) -Force | Out-Null
        } elseif (Test-Path $path) {
            Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function @(
    'Get-WpcWindowsTerminalEvidence',
    'Get-WpcWindowsTerminalVersion',
    'Test-WpcWindowsTerminalMinimum',
    'Get-WpcDefaultTerminalEvidence',
    'Get-WpcDefaultTerminalRegistryState',
    'Set-WpcDefaultTerminalApplication',
    'Restore-WpcDefaultTerminalRegistryState'
)
