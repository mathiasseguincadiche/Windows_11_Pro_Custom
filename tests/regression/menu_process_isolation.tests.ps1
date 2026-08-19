[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$menuPath = Join-Path $repoRoot 'menu.ps1'
$preflightPath = Join-Path $repoRoot 'scripts\bootstrap\00_preflight.ps1'
$rebootModulePath = Join-Path $repoRoot 'scripts\core\reboot-state.psm1'

foreach ($path in @($menuPath, $preflightPath, $rebootModulePath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Fichier requis introuvable: $path"
    }
}

function Assert-PowerShellSyntax {
    param([Parameter(Mandatory)][string]$Path)

    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $details = @($errors | ForEach-Object { $_.Message }) -join ' | '
        throw "Erreur de syntaxe PowerShell dans $Path : $details"
    }
}

Assert-PowerShellSyntax -Path $menuPath
Assert-PowerShellSyntax -Path $preflightPath
Assert-PowerShellSyntax -Path $rebootModulePath

$menu = Get-Content -Raw -LiteralPath $menuPath
$preflight = Get-Content -Raw -LiteralPath $preflightPath

if ($menu.Contains('& $Path @Arguments')) {
    throw 'Régression: le menu ne doit jamais réutiliser son propre scope pour exécuter un script du dépôt.'
}
foreach ($required in @(
    '$childArgs = $argList.ToArray()',
    '& $exe @childArgs',
    'Assert-WpcRebootStateCommands',
    'Le processus PowerShell isolé'
)) {
    if (-not $menu.Contains($required)) {
        throw "Contrat d’isolation absent de menu.ps1: $required"
    }
}

foreach ($required in @(
    'STORAGE_IDENTITY_BASELINE_ACTION_REQUIRED',
    '.\scripts\bootstrap\00_storage_identity.ps1 -Mode Record -ConfirmHealthyTopology -ReplaceBaseline',
    'Aucune convergence n''a été autorisée et aucune baseline n''a été remplacée automatiquement'
)) {
    if (-not $preflight.Contains($required)) {
        throw "Contrat de migration de baseline absent du préflight: $required"
    }
}
if ($preflight.Contains('& $storageIdentityScript -Mode Record')) {
    throw 'Régression de sécurité: le préflight ne doit jamais ré-enrôler automatiquement une baseline stockage.'
}
if ($preflight -match '(?m)^.*\[ANALYSE\].*\bV\d+\b') {
    throw 'Le préflight utilisateur ne doit plus exposer de numéro de jalon interne Vxx.'
}

Import-Module $rebootModulePath -Force
foreach ($command in @('Get-WpcPendingRebootState', 'Test-WpcRebootRequiredMessage')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Commande parent absente avant test: $command"
    }
}

$pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if (-not $pwsh) { $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue }
if (-not $pwsh) { throw 'pwsh est requis pour le test de frontière de processus.' }

$tempScript = Join-Path ([IO.Path]::GetTempPath()) ("wpc-isolation-child-{0}.ps1" -f [guid]::NewGuid().ToString('N'))
try {
    @"
Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Stop'
Import-Module '$($rebootModulePath.Replace("'", "''"))' -Force
if (-not (Get-Command Test-WpcRebootRequiredMessage -ErrorAction SilentlyContinue)) { throw 'module enfant incomplet' }
exit 17
"@ | Set-Content -LiteralPath $tempScript -Encoding UTF8

    & $pwsh.Source -NoLogo -NoProfile -ExecutionPolicy Bypass -File $tempScript
    $childExitCode = $LASTEXITCODE
    if ($childExitCode -ne 17) {
        throw "Le processus enfant de test devait retourner 17, observé=$childExitCode"
    }
} finally {
    Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
}

foreach ($command in @('Get-WpcPendingRebootState', 'Test-WpcRebootRequiredMessage')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Régression de scope après processus enfant: $command a disparu du parent."
    }
}

$global:LASTEXITCODE = 0

Write-Host '[OK] Syntaxe PowerShell valide.' -ForegroundColor Green
Write-Host '[OK] Scripts du dépôt isolés du scope du menu.' -ForegroundColor Green
Write-Host '[OK] Contrat reboot-state intact après rechargement -Force dans un enfant.' -ForegroundColor Green
Write-Host '[OK] Baseline héritée reste fail-closed avec ré-enrôlement explicitement guidé.' -ForegroundColor Green
