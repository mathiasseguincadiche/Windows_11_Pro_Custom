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

function ConvertTo-WpcComparableJson {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return 'null' }
    return ($Value | ConvertTo-Json -Depth 100 -Compress)
}

function Test-WpcEquivalent {
    param([AllowNull()][object]$Actual, [AllowNull()][object]$Expected)
    return (ConvertTo-WpcComparableJson -Value $Actual) -ceq (ConvertTo-WpcComparableJson -Value $Expected)
}

function Merge-WpcNamedObjects {
    param(
        [AllowNull()][object[]]$Existing,
        [AllowNull()][object[]]$Managed
    )

    $managedList = @($Managed)
    $managedNames = @($managedList | ForEach-Object { [string]$_.name })
    $result = [System.Collections.Generic.List[object]]::new()

    foreach ($entry in @($Existing)) {
        $name = if ($entry -and $entry.PSObject.Properties['name']) { [string]$entry.name } else { '' }
        if ($name -and $managedNames -contains $name) { continue }
        $result.Add($entry)
    }
    foreach ($entry in $managedList) {
        $result.Add($entry)
    }
    return @($result.ToArray())
}

function Get-WpcManagedArrayEvidence {
    param(
        [AllowNull()][object[]]$Actual,
        [AllowNull()][object[]]$Expected,
        [Parameter(Mandatory)][string]$Label
    )

    $missing = [System.Collections.Generic.List[string]]::new()
    $mismatched = [System.Collections.Generic.List[string]]::new()
    foreach ($expectedEntry in @($Expected)) {
        $name = [string]$expectedEntry.name
        $actualEntry = @($Actual | Where-Object { $_.PSObject.Properties['name'] -and [string]$_.name -eq $name } | Select-Object -First 1)
        if ($actualEntry.Count -eq 0) {
            $missing.Add($name)
            continue
        }
        if (-not (Test-WpcEquivalent -Actual $actualEntry[0] -Expected $expectedEntry)) {
            $mismatched.Add($name)
        }
    }

    return [pscustomobject]@{
        Label = $Label
        Missing = @($missing)
        Mismatched = @($mismatched)
        IsCompliant = ($missing.Count -eq 0 -and $mismatched.Count -eq 0)
    }
}

function Get-WpcTerminalSettingsEvidence {
    [CmdletBinding()]
    param(
        [AllowNull()]$Settings,
        [Parameter(Mandatory)][string]$ExpectedDefaultProfile,
        [Parameter(Mandatory)][string]$LegacyImportName,
        [Parameter(Mandatory)]$Contract
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
            GlobalMismatches = @('settings.json absent')
            ThemeEvidence = [pscustomobject]@{ IsCompliant=$false; Missing=@(); Mismatched=@() }
            SchemeEvidence = [pscustomobject]@{ IsCompliant=$false; Missing=@(); Mismatched=@() }
            NewTabMenuOk = $false
            IsCompliant = $false
        }
    }

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

    $globalMismatches = [System.Collections.Generic.List[string]]::new()
    foreach ($prop in $Contract.globals.PSObject.Properties) {
        $actual = if ($Settings.PSObject.Properties[$prop.Name]) { $Settings.PSObject.Properties[$prop.Name].Value } else { $null }
        if (-not (Test-WpcEquivalent -Actual $actual -Expected $prop.Value)) {
            $globalMismatches.Add($prop.Name)
        }
    }

    $themes = if ($Settings.PSObject.Properties['themes']) { @($Settings.themes) } else { @() }
    $schemes = if ($Settings.PSObject.Properties['schemes']) { @($Settings.schemes) } else { @() }
    $themeEvidence = Get-WpcManagedArrayEvidence -Actual $themes -Expected @($Contract.themes) -Label 'themes'
    $schemeEvidence = Get-WpcManagedArrayEvidence -Actual $schemes -Expected @($Contract.schemes) -Label 'schemes'

    $actualMenu = if ($Settings.PSObject.Properties['newTabMenu']) { @($Settings.newTabMenu) } else { @() }
    $newTabMenuOk = Test-WpcEquivalent -Actual $actualMenu -Expected @($Contract.newTabMenu)

    return [pscustomobject]@{
        DefaultProfile = $defaultProfile
        DefaultProfileOk = $defaultOk
        Imports = $imports
        LegacyImportAbsent = $legacyImportAbsent
        DisabledProfileSources = $disabled
        PowerShellCoreDisabled = $powershellCoreDisabled
        WslDisabled = $wslDisabled
        GlobalMismatches = @($globalMismatches)
        ThemeEvidence = $themeEvidence
        SchemeEvidence = $schemeEvidence
        NewTabMenuOk = $newTabMenuOk
        IsCompliant = (
            $defaultOk -and
            $legacyImportAbsent -and
            $powershellCoreDisabled -and
            $wslDisabled -and
            $globalMismatches.Count -eq 0 -and
            $themeEvidence.IsCompliant -and
            $schemeEvidence.IsCompliant -and
            $newTabMenuOk
        )
    }
}

function Set-WpcTerminalSettingsContract {
    [CmdletBinding()]
    param(
        [AllowNull()]$Settings,
        [Parameter(Mandatory)][string]$ExpectedDefaultProfile,
        [Parameter(Mandatory)][string]$LegacyImportName,
        [Parameter(Mandatory)]$Contract
    )

    if ($null -eq $Settings) {
        $Settings = [pscustomobject][ordered]@{
            '$schema' = 'https://aka.ms/terminal-profiles-schema'
            profiles = [pscustomobject][ordered]@{ list = @() }
        }
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

    foreach ($prop in $Contract.globals.PSObject.Properties) {
        Set-WpcObjectProperty -Object $Settings -Name $prop.Name -Value $prop.Value
    }

    $existingThemes = if ($Settings.PSObject.Properties['themes']) { @($Settings.themes) } else { @() }
    $existingSchemes = if ($Settings.PSObject.Properties['schemes']) { @($Settings.schemes) } else { @() }
    Set-WpcObjectProperty -Object $Settings -Name 'themes' -Value (Merge-WpcNamedObjects -Existing $existingThemes -Managed @($Contract.themes))
    Set-WpcObjectProperty -Object $Settings -Name 'schemes' -Value (Merge-WpcNamedObjects -Existing $existingSchemes -Managed @($Contract.schemes))
    Set-WpcObjectProperty -Object $Settings -Name 'newTabMenu' -Value @($Contract.newTabMenu)

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
