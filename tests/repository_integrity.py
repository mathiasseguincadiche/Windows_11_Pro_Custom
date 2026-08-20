from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise SystemExit(message)


def relative(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def normalize(text: str) -> str:
    return text.replace("\\", "/")


# P0 — le stockage doit consommer la politique matérielle canonique.
storage_script = REPO_ROOT / "scripts/bootstrap/00_storage_integrity.ps1"
canonical_policy = REPO_ROOT / "config/hardware/symbiosis.json"
if not storage_script.is_file():
    fail("Storage integrity script missing.")
if not canonical_policy.is_file():
    fail("Canonical hardware symbiosis policy missing: config/hardware/symbiosis.json")

storage_source = storage_script.read_text(encoding="utf-8")
expected_assignment = (
    "$storagePolicyPath = Join-Path $repoRoot 'config\\hardware\\symbiosis.json'"
)
if expected_assignment not in storage_source:
    fail(
        "00_storage_integrity.ps1 must assign storagePolicyPath to "
        "config\\hardware\\symbiosis.json."
    )
if "symbiosis-v5.json" in storage_source:
    fail("Legacy symbiosis-v5.json reference detected in storage integrity.")


# P0 — aucun ancien chemin de composant ne doit rester dans le code actif.
# Les fichiers qui maintiennent volontairement la liste noire sont exclus.
forbidden_legacy_paths = (
    "00_storage_identity_v25.ps1",
    "00_storage_integrity_v24.ps1",
    "90_workstation_fingerprint_v26.ps1",
    "63_restore_drill_v26.ps1",
    "60_create_backup_v7.ps1",
    "61_validate_backup_v7.ps1",
    "62_restore_plan_v7.ps1",
    "11_validate_v3.ps1",
    "12_validate_v4.ps1",
    "13_validate_hardware_v5.ps1",
    "14_validate_wsl_v6.ps1",
    "40_v4_optimize.ps1",
    "53_responsiveness_v8.ps1",
    "config/backup/v7-policy.json",
    "config/hardware/target-v5.json",
    "config/hardware/symbiosis-v5.json",
    "config/updates/v11.json",
    "config/windows/v4/",
    "config/windows/v8/",
    "tests/powershell/v26_contract.tests.ps1",
    "SkipV4RestorePoint",
)

active_files: list[Path] = [
    REPO_ROOT / "install.ps1",
    REPO_ROOT / "menu.ps1",
    REPO_ROOT / "update.ps1",
]
active_files.extend(
    path
    for path in (REPO_ROOT / "scripts").rglob("*")
    if path.is_file() and path.suffix.lower() in {".ps1", ".psm1", ".sh"}
)
workflow_exclusions = {
    "documentation.yml",
    "versioning-contract.yml",
    "repository-integrity.yml",
}
active_files.extend(
    path
    for path in (REPO_ROOT / ".github/workflows").glob("*.yml")
    if path.name not in workflow_exclusions
)

legacy_violations: list[str] = []
for path in active_files:
    if not path.is_file():
        fail(f"Expected active code file missing: {relative(path)}")
    text = normalize(path.read_text(encoding="utf-8"))
    for legacy in forbidden_legacy_paths:
        if normalize(legacy) in text:
            legacy_violations.append(f"{relative(path)}: obsolete reference: {legacy}")

if legacy_violations:
    fail("Legacy active-path regression detected:\n" + "\n".join(sorted(legacy_violations)))


# P1 — toutes les dépendances statiques versionnées référencées par le code
# PowerShell exécutable doivent exister dans le dépôt. Les chemins construits avec
# des variables restent couverts par leurs contrats spécifiques. La frontière négative
# évite de prendre un chemin utilisateur comme .config/... pour un chemin racine repo.
runtime_powershell_files = [
    REPO_ROOT / "install.ps1",
    REPO_ROOT / "menu.ps1",
    REPO_ROOT / "update.ps1",
]
runtime_powershell_files.extend(
    path
    for path in (REPO_ROOT / "scripts").rglob("*")
    if path.is_file() and path.suffix.lower() in {".ps1", ".psm1"}
)

dependency_pattern = re.compile(
    r"(?<![A-Za-z0-9._/\\-])"
    r"(?P<path>(?:config|scripts|manifests)[\\/]"
    r"[A-Za-z0-9._-]+(?:[\\/][A-Za-z0-9._-]+)*\."
    r"(?:ps1|psm1|sh|json|toml|wslconfig|txt))",
    re.IGNORECASE,
)

missing_dependencies: set[str] = set()
for source_file in runtime_powershell_files:
    source = source_file.read_text(encoding="utf-8")
    for match in dependency_pattern.finditer(source):
        referenced = match.group("path").replace("\\", "/")
        candidate = REPO_ROOT / Path(referenced)
        if not candidate.is_file():
            missing_dependencies.add(f"{relative(source_file)} -> {referenced}")

if missing_dependencies:
    fail(
        "Missing static repository dependencies detected:\n"
        + "\n".join(sorted(missing_dependencies))
    )


# P1 — le centre de contrôle doit remonter le contexte d'échec courant et disposer
# d'un fallback sur le résumé du RunId, pas uniquement latest-run.json.
menu_source = (REPO_ROOT / "menu.ps1").read_text(encoding="utf-8")
required_menu_fragments = (
    "Get-WpcFailureSummaryCandidates",
    "Read-WpcFailureSummaryContext",
    "Get-WpcLatestFailureContext",
    "Format-WpcProcessFailure",
    "reports\\orchestration\\latest-run.json",
    "logs\\runs",
    "summary.json",
    "LatestScriptState",
    "ScriptExecutions",
    "Run     :",
    "Étape   :",
    "Script  :",
    "Cause   :",
    "Journal :",
)
missing_menu_fragments = [
    fragment for fragment in required_menu_fragments if fragment not in menu_source
]
if missing_menu_fragments:
    fail(
        "Control-center detailed failure contract incomplete: "
        + ", ".join(missing_menu_fragments)
    )


# P1 — une qualification matérielle KO doit exposer le nom du HardCheck et son détail,
# puis le préflight doit propager cette information jusqu'au résumé d'orchestration.
hardware_source = (
    REPO_ROOT / "scripts/windows/52_hardware_symbiosis.ps1"
).read_text(encoding="utf-8")
required_hardware_fragments = (
    "Get-HardCheckDetail",
    "HardCheckFailures",
    "ArcDriverAtLeastApproved",
    "Realtek8126Present",
    "WifiAdapterPresent",
    "AmdChipsetNotBelowApprovedBaseline",
    "versionDétectée=",
    "minimum=",
)
missing_hardware_fragments = [
    fragment for fragment in required_hardware_fragments if fragment not in hardware_source
]
if missing_hardware_fragments:
    fail(
        "Hardware-symbiosis diagnostics contract incomplete: "
        + ", ".join(missing_hardware_fragments)
    )

preflight_source = (
    REPO_ROOT / "scripts/bootstrap/00_preflight.ps1"
).read_text(encoding="utf-8")
required_preflight_fragments = (
    "hardware-symbiosis.json",
    "Get-WpcHardwareSymbiosisFailureDetail",
    "HardCheckFailures",
    "Détail matériel/pilotes:",
)
missing_preflight_fragments = [
    fragment for fragment in required_preflight_fragments if fragment not in preflight_source
]
if missing_preflight_fragments:
    fail(
        "Physical preflight failure-propagation contract incomplete: "
        + ", ".join(missing_preflight_fragments)
    )

print("[OK] storagePolicyPath -> config/hardware/symbiosis.json")
print("[OK] no legacy component path in active code")
print("[OK] all detected static repository dependencies exist")
print("[OK] resilient current-run failure context available in control center")
print("[OK] hardware HardCheck failures expose detected and expected values")
print("[OK] physical preflight propagates hardware details to orchestration")
print("VERDICT: REPOSITORY INTEGRITY READY")
