Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:DelegationPath = 'HKCU:\Console\%%Startup'
$script:DelegationConsole = '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}'
$script:DelegationTerminal = '{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}'

function Get-WpcWindowsTerminalVersion {
    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $wt) { return $null }
    $output = @(& $wt.Source --version 2>$null)
    $global:LASTEXITCODE = 0
    $text = ($output -join ' ').Trim()
    if ($text -match '(\d+\.\d+\.\d+\.\d+)') { return [version]$Matches[1] }
    if ($text -match '(\d+\.\d+\.\d+)') { return [version]$Matches[1] }
    return $null
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
    'Get-WpcWindowsTerminalVersion',
    'Test-WpcWindowsTerminalMinimum',
    'Get-WpcDefaultTerminalEvidence',
    'Get-WpcDefaultTerminalRegistryState',
    'Set-WpcDefaultTerminalApplication',
    'Restore-WpcDefaultTerminalRegistryState'
)
