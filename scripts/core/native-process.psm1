Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WpcNativeApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name
    )

    return Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Invoke-WpcNativeCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [switch]$SuppressErrorOutput
    )

    # Important pour les App Execution Aliases (ex. winget.exe sous WindowsApps) :
    # l'exécutable doit être le seul élément de son pipeline. On capture d'abord
    # sa sortie, puis on la transforme dans un second temps. Ne pas écrire
    # `& $FilePath ... | Out-String` ici : PowerShell peut refuser l'alias MSIX
    # avec CantActivateDocumentInPipeline.
    $raw = if ($SuppressErrorOutput) {
        @(& $FilePath @ArgumentList 2>$null)
    } else {
        @(& $FilePath @ArgumentList 2>&1)
    }

    $exitCode = [int]$LASTEXITCODE
    $global:LASTEXITCODE = 0
    $lines = @($raw | ForEach-Object { [string]$_ })

    return [pscustomobject]@{
        ExitCode = $exitCode
        Lines = $lines
        Text = ($lines -join [Environment]::NewLine)
    }
}

Export-ModuleMember -Function Get-WpcNativeApplication, Invoke-WpcNativeCapture
