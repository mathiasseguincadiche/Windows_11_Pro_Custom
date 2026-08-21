Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WpcWslConfDefaultUser {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines = @()
    )

    $section = ''
    foreach ($rawLine in @($Lines)) {
        $line = ([string]$rawLine) -replace "`0", ''
        if ($line -match '^\s*\[([^\]]+)\]\s*(?:[#;].*)?$') {
            $section = $matches[1].Trim().ToLowerInvariant()
            continue
        }
        if ($section -eq 'user' -and $line -match '^\s*default\s*=\s*([a-z_][a-z0-9_-]{0,31})\s*(?:[#;].*)?$') {
            return [string]$matches[1]
        }
    }

    return $null
}

function Set-WpcWslConfDefaultUser {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines = @(),
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z_][a-z0-9_-]{0,31}$')]
        [string]$User
    )

    $result = [System.Collections.Generic.List[string]]::new()
    $inUserSection = $false
    $userSectionSeen = $false
    $defaultWritten = $false

    foreach ($rawLine in @($Lines)) {
        $line = ([string]$rawLine) -replace "`0", ''
        if ($line -match '^\s*\[([^\]]+)\]\s*(?:[#;].*)?$') {
            $section = $matches[1].Trim().ToLowerInvariant()
            $inUserSection = ($section -eq 'user')
            $result.Add($line)
            if ($inUserSection) {
                $userSectionSeen = $true
                if (-not $defaultWritten) {
                    $result.Add("default=$User")
                    $defaultWritten = $true
                }
            }
            continue
        }

        if ($inUserSection -and $line -match '^\s*default\s*=') {
            continue
        }
        $result.Add($line)
    }

    if (-not $userSectionSeen) {
        if ($result.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($result[$result.Count - 1])) {
            $result.Add('')
        }
        $result.Add('[user]')
        $result.Add("default=$User")
    }

    return $result.ToArray()
}

function ConvertTo-WpcWslConfText {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines = @()
    )

    if (@($Lines).Count -eq 0) { return '' }
    $text = (@($Lines) -join "`n").TrimEnd([char[]]"`r`n")
    return ($text + "`n")
}

Export-ModuleMember -Function Get-WpcWslConfDefaultUser, Set-WpcWslConfDefaultUser, ConvertTo-WpcWslConfText
