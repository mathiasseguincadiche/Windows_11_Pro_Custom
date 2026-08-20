#Requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WpcPowerShellRuntimeFact {
    [CmdletBinding()]
    param()

    $processPath = ''
    try { $processPath = [string](Get-Process -Id $PID -ErrorAction Stop).Path } catch {}
    $executableName = if ([string]::IsNullOrWhiteSpace($processPath)) { '' } else { [IO.Path]::GetFileName($processPath) }

    [pscustomobject]@{
        Edition = [string]$PSVersionTable.PSEdition
        Version = [version]$PSVersionTable.PSVersion
        Is64BitProcess = [bool][Environment]::Is64BitProcess
        Is64BitOperatingSystem = [bool][Environment]::Is64BitOperatingSystem
        ExecutablePath = $processPath
        ExecutableName = $executableName
        IsWindows = [bool]$IsWindows
    }
}

function Assert-WpcPowerShellRuntime {
    [CmdletBinding()]
    param(
        [version]$MinimumVersion = [version]'7.6.5',
        [switch]$RequireWindows,
        [switch]$PassThru
    )

    $fact = Get-WpcPowerShellRuntimeFact
    $failures = [System.Collections.Generic.List[string]]::new()

    if ($fact.Edition -ne 'Core') {
        $failures.Add("Edition=$($fact.Edition); PowerShell Core requis")
    }
    if ($fact.Version -lt $MinimumVersion) {
        $failures.Add("Version=$($fact.Version); minimum=$MinimumVersion")
    }
    if (-not $fact.Is64BitProcess) {
        $failures.Add('Processus PowerShell non x64')
    }
    if ($RequireWindows -and -not $fact.IsWindows) {
        $failures.Add('Hote Windows requis')
    }
    if ($fact.IsWindows -and -not [string]::IsNullOrWhiteSpace($fact.ExecutableName) -and $fact.ExecutableName -ine 'pwsh.exe') {
        $failures.Add("Executable=$($fact.ExecutableName); pwsh.exe requis")
    }

    if ($failures.Count -gt 0) {
        throw "Runtime PowerShell non conforme: $($failures -join '; '). Ce depot exige PowerShell 7.6.5 ou ulterieur (Core, x64, pwsh.exe). Windows PowerShell 5.1 n'est ni supporte ni utilise comme fallback."
    }

    if ($PassThru) { return $fact }
}

Export-ModuleMember -Function Get-WpcPowerShellRuntimeFact, Assert-WpcPowerShellRuntime
