Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Remove-WpcJsonComments {
    param([Parameter(Mandatory)][string]$Text)

    $sb = [System.Text.StringBuilder]::new()
    $inString = $false
    $escape = $false
    $lineComment = $false
    $blockComment = $false

    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }

        if ($lineComment) {
            if ($c -eq "`n") {
                $lineComment = $false
                [void]$sb.Append($c)
            }
            continue
        }
        if ($blockComment) {
            if ($c -eq '*' -and $next -eq '/') {
                $blockComment = $false
                $i++
            }
            continue
        }
        if ($inString) {
            [void]$sb.Append($c)
            if ($escape) {
                $escape = $false
                continue
            }
            if ($c -eq '\') {
                $escape = $true
                continue
            }
            if ($c -eq '"') { $inString = $false }
            continue
        }
        if ($c -eq '"') {
            $inString = $true
            [void]$sb.Append($c)
            continue
        }
        if ($c -eq '/' -and $next -eq '/') {
            $lineComment = $true
            $i++
            continue
        }
        if ($c -eq '/' -and $next -eq '*') {
            $blockComment = $true
            $i++
            continue
        }
        [void]$sb.Append($c)
    }

    return $sb.ToString()
}

function ConvertFrom-WpcTerminalSettingsText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $clean = Remove-WpcJsonComments -Text $Text
    $clean = [regex]::Replace($clean, ',\s*(?=[}\]])', '')
    try {
        return ($clean | ConvertFrom-Json)
    } catch {
        throw "settings.json Windows Terminal invalide ou non analysable: $($_.Exception.Message)"
    }
}

function Set-WpcObjectProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Value
    )

    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    } else {
        $prop.Value = $Value
    }
}

function Remove-WpcObjectProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($Object.PSObject.Properties[$Name]) {
        [void]$Object.PSObject.Properties.Remove($Name)
    }
}

function Get-WpcTerminalSettingsEvidence {
    [CmdletBinding()]
    param(
        [AllowNull()]$Settings,
        [Parameter(Mandatory)][string]$ExpectedDefaultProfile,
        [Parameter(Mandatory)][string]$LegacyImportName
    )

    if ($null -eq $Settings) {
        return [pscustomobject]@{
            DefaultProfile = $null
            DefaultProfileOk = $false
            Imports = @()
            LegacyImportAbsent = $true
            DisabledProfileSources = @()
            PowerShellCoreDisabled = $false
            WslDisabled = $false
            IsCompliant = $false
        }
    }

    # Wrap the whole conditional in @(...). PowerShell unwraps single-element
    # pipeline output from an if statement; keeping the outer array boundary
    # prevents += from becoming string concatenation when only one value exists.
    $imports = @(
        if ($Settings.PSObject.Properties['import']) {
            $Settings.PSObject.Properties['import'].Value | ForEach-Object { [string]$_ }
        }
    )
    $disabled = @(
        if ($Settings.PSObject.Properties['disabledProfileSources']) {
            $Settings.PSObject.Properties['disabledProfileSources'].Value | ForEach-Object { [string]$_ }
        }
    )
    $defaultProfile = if ($Settings.PSObject.Properties['defaultProfile']) { [string]$Settings.defaultProfile } else { $null }
    $defaultOk = (-not [string]::IsNullOrWhiteSpace($defaultProfile) -and $defaultProfile -eq $ExpectedDefaultProfile)
    $legacyImportAbsent = ($imports -notcontains $LegacyImportName)
    $powershellCoreDisabled = ($disabled -contains 'Windows.Terminal.PowershellCore')
    $wslDisabled = ($disabled -contains 'Windows.Terminal.Wsl')

    return [pscustomobject]@{
        DefaultProfile = $defaultProfile
        DefaultProfileOk = $defaultOk
        Imports = $imports
        LegacyImportAbsent = $legacyImportAbsent
        DisabledProfileSources = $disabled
        PowerShellCoreDisabled = $powershellCoreDisabled
        WslDisabled = $wslDisabled
        IsCompliant = ($defaultOk -and $legacyImportAbsent -and $powershellCoreDisabled -and $wslDisabled)
    }
}

function Set-WpcTerminalSettingsContract {
    [CmdletBinding()]
    param(
        [AllowNull()]$Settings,
        [Parameter(Mandatory)][string]$ExpectedDefaultProfile,
        [Parameter(Mandatory)][string]$LegacyImportName
    )

    if ($null -eq $Settings) {
        $Settings = [pscustomobject][ordered]@{
            '$schema' = 'https://aka.ms/terminal-profiles-schema'
            defaultProfile = $ExpectedDefaultProfile
            disabledProfileSources = @('Windows.Terminal.PowershellCore', 'Windows.Terminal.Wsl')
            profiles = [pscustomobject][ordered]@{ list = @() }
        }
        return $Settings
    }

    Set-WpcObjectProperty -Object $Settings -Name 'defaultProfile' -Value $ExpectedDefaultProfile

    $imports = @(
        if ($Settings.PSObject.Properties['import']) {
            $Settings.PSObject.Properties['import'].Value | ForEach-Object { [string]$_ }
        }
    )
    $imports = @($imports | Where-Object { $_ -and $_ -ne $LegacyImportName })
    if ($imports.Count -eq 0) {
        Remove-WpcObjectProperty -Object $Settings -Name 'import'
    } else {
        Set-WpcObjectProperty -Object $Settings -Name 'import' -Value $imports
    }

    $disabled = @(
        if ($Settings.PSObject.Properties['disabledProfileSources']) {
            $Settings.PSObject.Properties['disabledProfileSources'].Value | ForEach-Object { [string]$_ }
        }
    )
    foreach ($source in @('Windows.Terminal.PowershellCore', 'Windows.Terminal.Wsl')) {
        if ($disabled -notcontains $source) { $disabled += $source }
    }
    Set-WpcObjectProperty -Object $Settings -Name 'disabledProfileSources' -Value $disabled

    return $Settings
}

function ConvertTo-WpcTerminalSettingsText {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Settings)

    return (($Settings | ConvertTo-Json -Depth 100) + "`n")
}

Export-ModuleMember -Function @(
    'ConvertFrom-WpcTerminalSettingsText',
    'Get-WpcTerminalSettingsEvidence',
    'Set-WpcTerminalSettingsContract',
    'ConvertTo-WpcTerminalSettingsText'
)
