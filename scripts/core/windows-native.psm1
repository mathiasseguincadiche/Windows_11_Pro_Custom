Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-WpcWindowsHost {
    # Ne jamais utiliser $env:OS comme source de vérité : cette variable peut être
    # absente, altérée ou non transmise dans certains environnements PowerShell.
    # PowerShell 7 expose $IsWindows de façon native ; Windows PowerShell 5.1
    # utilise le fallback .NET historique.
    if ($PSVersionTable.PSEdition -eq 'Core') {
        return [bool]$IsWindows
    }

    return ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
}

function Get-WpcWindowsPowerShellModuleRoot {
    if (-not (Test-WpcWindowsHost)) {
        throw 'Les modules Windows natifs ne sont disponibles que sous Windows.'
    }
    if ([string]::IsNullOrWhiteSpace($env:SystemRoot)) {
        throw 'SystemRoot est indisponible; impossible de localiser les modules Windows natifs.'
    }
    return (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules')
}

function Add-WpcWindowsPowerShellModulePath {
    $legacyRoot = Get-WpcWindowsPowerShellModuleRoot
    if (-not (Test-Path -LiteralPath $legacyRoot)) {
        throw "Répertoire des modules Windows introuvable: $legacyRoot"
    }

    $separator = [IO.Path]::PathSeparator
    $paths = @(
        ([string]$env:PSModulePath -split [regex]::Escape([string]$separator)) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $alreadyPresent = @($paths | Where-Object {
        try {
            [string]::Equals(
                [IO.Path]::GetFullPath($_).TrimEnd('\'),
                [IO.Path]::GetFullPath($legacyRoot).TrimEnd('\'),
                [StringComparison]::OrdinalIgnoreCase
            )
        } catch {
            $false
        }
    }).Count -gt 0

    if (-not $alreadyPresent) {
        $env:PSModulePath = if ([string]::IsNullOrWhiteSpace($env:PSModulePath)) {
            $legacyRoot
        } else {
            $legacyRoot + $separator + $env:PSModulePath
        }
    }

    return $legacyRoot
}

function Import-WpcWindowsModule {
    param(
        [Parameter(Mandatory)][string]$ModuleName,
        [Parameter(Mandatory)][string[]]$RequiredCommands,
        [switch]$Optional
    )

    $missingBefore = @($RequiredCommands | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
    if ($missingBefore.Count -eq 0) {
        return [pscustomobject]@{ Module=$ModuleName; Available=$true; Imported=$false; Source='already-available'; Missing=@() }
    }

    $legacyRoot = Add-WpcWindowsPowerShellModulePath
    $errors = [System.Collections.Generic.List[string]]::new()

    try {
        Import-Module -Name $ModuleName -ErrorAction Stop
    } catch {
        $errors.Add("Import-Module ${ModuleName}: $($_.Exception.Message)")
    }

    $missingAfterName = @($RequiredCommands | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
    if ($missingAfterName.Count -gt 0) {
        $manifest = Join-Path (Join-Path $legacyRoot $ModuleName) "$ModuleName.psd1"
        if (Test-Path -LiteralPath $manifest) {
            try {
                Import-Module -Name $manifest -ErrorAction Stop
            } catch {
                $errors.Add("Import-Module ${manifest}: $($_.Exception.Message)")
            }
        }
    }

    $missing = @($RequiredCommands | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
    if ($missing.Count -eq 0) {
        return [pscustomobject]@{ Module=$ModuleName; Available=$true; Imported=$true; Source='explicit-import'; Missing=@() }
    }

    $detail = "Module=$ModuleName | commandes manquantes=$($missing -join ', ') | PowerShell=$($PSVersionTable.PSVersion) $($PSVersionTable.PSEdition) | PSModulePath=$env:PSModulePath"
    if ($errors.Count -gt 0) { $detail += " | erreurs=$($errors -join ' || ')" }

    if ($Optional) {
        Write-Warning "Module Windows optionnel indisponible. $detail"
        return [pscustomobject]@{ Module=$ModuleName; Available=$false; Imported=$false; Source='unavailable'; Missing=$missing }
    }

    throw "Module Windows requis indisponible. $detail"
}

function Initialize-WpcWindowsNativeModules {
    param(
        [ValidateSet('StorageOnly', 'Discovery', 'Full')]
        [string]$Profile = 'Discovery'
    )

    if (-not (Test-WpcWindowsHost)) {
        throw 'Un hôte Windows est requis pour initialiser les modules natifs de la workstation.'
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $results.Add((Import-WpcWindowsModule -ModuleName 'Storage' -RequiredCommands @('Get-Volume','Get-PhysicalDisk','Get-StorageReliabilityCounter')))

    if ($Profile -in @('Discovery','Full')) {
        $results.Add((Import-WpcWindowsModule -ModuleName 'MMAgent' -RequiredCommands @('Get-MMAgent','Enable-MMAgent','Disable-MMAgent') -Optional))
        $results.Add((Import-WpcWindowsModule -ModuleName 'ScheduledTasks' -RequiredCommands @('Get-ScheduledTask') -Optional))
        $results.Add((Import-WpcWindowsModule -ModuleName 'NetAdapter' -RequiredCommands @('Get-NetAdapter','Get-NetAdapterRss') -Optional))
        $results.Add((Import-WpcWindowsModule -ModuleName 'TrustedPlatformModule' -RequiredCommands @('Get-Tpm') -Optional))
        $results.Add((Import-WpcWindowsModule -ModuleName 'Defender' -RequiredCommands @('Get-MpComputerStatus','Get-MpPreference') -Optional))
    }

    if ($Profile -eq 'Full') {
        $missingImportant = @($results | Where-Object { -not $_.Available -and $_.Module -in @('MMAgent','ScheduledTasks','Defender') })
        if ($missingImportant.Count -gt 0) {
            throw "Modules Windows requis pour la convergence complète indisponibles: $($missingImportant.Module -join ', ')."
        }
    }

    return $results.ToArray()
}

Export-ModuleMember -Function Test-WpcWindowsHost, Get-WpcWindowsPowerShellModuleRoot, Add-WpcWindowsPowerShellModulePath, Import-WpcWindowsModule, Initialize-WpcWindowsNativeModules
