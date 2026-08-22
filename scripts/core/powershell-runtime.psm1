#Requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-WpcUtf8Console {
    [CmdletBinding()]
    param()

    # Every managed pwsh process must use UTF-8 even when launched with -NoProfile.
    # This is especially important for UTF-8 output crossing WSL -> wsl.exe -> PowerShell.
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    try { [Console]::InputEncoding = $utf8 } catch {}
    try { [Console]::OutputEncoding = $utf8 } catch {}
    $global:OutputEncoding = $utf8

    return [pscustomobject]@{
        InputEncoding = try { [Console]::InputEncoding.WebName } catch { '' }
        OutputEncoding = try { [Console]::OutputEncoding.WebName } catch { '' }
        NativeOutputEncoding = $global:OutputEncoding.WebName
    }
}

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
        ConsoleInputEncoding = try { [Console]::InputEncoding.WebName } catch { '' }
        ConsoleOutputEncoding = try { [Console]::OutputEncoding.WebName } catch { '' }
        NativeOutputEncoding = $global:OutputEncoding.WebName
    }
}

function Assert-WpcPowerShellRuntime {
    [CmdletBinding()]
    param(
        [version]$MinimumVersion = [version]'7.6.4',
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
    if ($fact.NativeOutputEncoding -ne 'utf-8') {
        $failures.Add("OutputEncoding=$($fact.NativeOutputEncoding); UTF-8 requis")
    }

    if ($failures.Count -gt 0) {
        throw "Runtime PowerShell non conforme: $($failures -join '; '). Ce depot exige PowerShell 7.6.4 ou ulterieur (Core, x64, pwsh.exe, UTF-8). Windows PowerShell 5.1 n'est ni supporte ni utilise comme fallback."
    }

    if ($PassThru) { return $fact }
}

# Module import is the runtime bootstrap. It must work even for pwsh -NoProfile.
[void](Initialize-WpcUtf8Console)

Export-ModuleMember -Function Initialize-WpcUtf8Console, Get-WpcPowerShellRuntimeFact, Assert-WpcPowerShellRuntime
