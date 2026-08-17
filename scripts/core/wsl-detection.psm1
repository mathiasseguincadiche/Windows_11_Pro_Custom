Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WpcWslRegistrationFact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Distribution,
        [string]$RegistryRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    )

    $names = [System.Collections.Generic.List[string]]::new()
    $basePath = $null

    try {
        if (-not (Test-Path -LiteralPath $RegistryRoot)) {
            return [pscustomobject]@{
                Known = $true
                Present = $false
                Names = @()
                BasePath = $null
                RegistryRoot = $RegistryRoot
                Error = $null
            }
        }

        foreach ($key in @(Get-ChildItem -LiteralPath $RegistryRoot -ErrorAction Stop)) {
            $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
            $name = [string]$item.DistributionName
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $names.Add($name)
            if ($name -eq $Distribution) { $basePath = [string]$item.BasePath }
        }

        $registeredNames = $names.ToArray()
        return [pscustomobject]@{
            Known = $true
            Present = ($registeredNames -contains $Distribution)
            Names = $registeredNames
            BasePath = $basePath
            RegistryRoot = $RegistryRoot
            Error = $null
        }
    } catch {
        return [pscustomobject]@{
            Known = $false
            Present = $false
            Names = @()
            BasePath = $null
            RegistryRoot = $RegistryRoot
            Error = $_.Exception.Message
        }
    }
}

Export-ModuleMember -Function Get-WpcWslRegistrationFact
