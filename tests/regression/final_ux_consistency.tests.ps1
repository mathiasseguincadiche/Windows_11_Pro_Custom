[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$installPath = Join-Path $repoRoot 'install.ps1'
$interactivePath = Join-Path $repoRoot 'scripts\bootstrap\16_external_auth_interactive.ps1'
$auditPath = Join-Path $repoRoot 'scripts\bootstrap\15_external_auth.ps1'

foreach ($path in @($installPath,$interactivePath,$auditPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Fichier requis introuvable: $path" }
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Erreur de syntaxe PowerShell dans $path : $($errors.Message -join '; ')"
    }
}

$install = Get-Content -Raw -LiteralPath $installPath
$interactive = Get-Content -Raw -LiteralPath $interactivePath
$audit = Get-Content -Raw -LiteralPath $auditPath

# Hardware manual evidence: a successful non-strict probe must not be presented as
# fully confirmed when the underlying script reports ACTION REQUISE.
foreach ($needle in @(
    "-Purpose 'ManualEvidenceProbe'",
    "[string]`$probe.Outcome -eq 'ACTION_REQUISE'",
    "-Status 'AVERTISSEMENT' -Message 'Validation matérielle manuelle en attente'",
    'non bloquants pour Installation complete',
    'Toutes les preuves manuelles strictes ont déjà été confirmées'
)) {
    if (-not $install.Contains($needle)) {
        throw "Contrat UX des preuves matérielles absent: $needle"
    }
}

foreach ($forbidden in @(
    'Veux-tu enregistrer maintenant les contrôles matériels manuels avant toute convergence ?',
    'Qualification matérielle laissée incomplète. Aucune convergence physique complète ne sera lancée.'
)) {
    if ($install.Contains($forbidden)) {
        throw "Ancien comportement bloquant/trompeur encore présent: $forbidden"
    }
}

# External auth: the assistant must always finish by rebuilding the non-secret audit
# after all interactive Git/GitHub/AWS decisions.
$servicesIndex = $interactive.IndexOf("`$services = if (`$Service -eq 'All')")
$loopIndex = $interactive.IndexOf('foreach ($item in $services)', [Math]::Max(0,$servicesIndex))
$finalAuditLabelIndex = $interactive.IndexOf("[ANALYSE] Revalidation sans secret des connexions externes", [Math]::Max(0,$loopIndex))
$finalAuditCallIndex = $interactive.IndexOf('& $auditScript -Mode Audit -Distribution $Distribution -LinuxUser $LinuxUser', [Math]::Max(0,$finalAuditLabelIndex))
$finishedIndex = $interactive.IndexOf("[TERMINE] Assistant de connexions externes terminé.", [Math]::Max(0,$finalAuditCallIndex))

if ($servicesIndex -lt 0 -or $loopIndex -lt 0 -or $finalAuditLabelIndex -lt 0 -or $finalAuditCallIndex -lt 0 -or $finishedIndex -lt 0) {
    throw 'Contrat de réaudit final des connexions externes incomplet.'
}
if (-not ($servicesIndex -lt $loopIndex -and $loopIndex -lt $finalAuditLabelIndex -and $finalAuditLabelIndex -lt $finalAuditCallIndex -and $finalAuditCallIndex -lt $finishedIndex)) {
    throw 'Le réaudit final doit avoir lieu après les services interactifs et avant la fin de l assistant.'
}

foreach ($needle in @(
    "`$reportPath = Join-Path `$reportDir 'external-auth.json'",
    'Timestamp = (Get-Date).ToString(''o'')',
    'SecretMaterialRecorded = $false',
    'AuthenticatedProfiles = $awsAuthenticatedProfiles.ToArray()',
    'PlaintextFallbackExplicitlyAccepted = $githubPlaintextAccepted'
)) {
    if (-not $audit.Contains($needle)) {
        throw "Contrat du rapport final external-auth absent: $needle"
    }
}

if ($audit -match '(?i)(aws_secret_access_key|aws_access_key_id|oauth_token)\s*=\s*\$') {
    throw 'Le rapport d audit ne doit jamais sérialiser de secret brut.'
}

Write-Host '[OK] Hardware manual-evidence UX is explicit and non-blocking.' -ForegroundColor Green
Write-Host '[OK] External auth final audit is ordered after interactive decisions.' -ForegroundColor Green
Write-Host '[OK] Final external-auth report remains timestamped and secret-free by contract.' -ForegroundColor Green
