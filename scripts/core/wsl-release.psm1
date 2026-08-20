#Requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-WpcOsRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Lines
    )

    $values = @{}
    foreach ($rawLine in $Lines) {
        $line = ([string]$rawLine).Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
        if ($line -notmatch '^([A-Z0-9_]+)=(.*)$') { continue }

        $key = [string]$matches[1]
        $value = ([string]$matches[2]).Trim()
        if ($value.Length -ge 2) {
            $first = $value[0]
            $last = $value[$value.Length - 1]
            if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }
        $values[$key] = $value
    }

    $versionId = if ($values.ContainsKey('VERSION_ID')) { [string]$values['VERSION_ID'] } else { '' }
    $codename = if ($values.ContainsKey('VERSION_CODENAME')) { [string]$values['VERSION_CODENAME'] } else { '' }

    if ([string]::IsNullOrWhiteSpace($versionId) -or [string]::IsNullOrWhiteSpace($codename)) {
        throw "os-release incomplet: VERSION_ID='$versionId' VERSION_CODENAME='$codename'."
    }

    [pscustomobject]@{
        VersionId = $versionId
        Codename = $codename
    }
}

Export-ModuleMember -Function ConvertFrom-WpcOsRelease
