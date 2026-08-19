[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify', 'Rollback')]
    [string]$Mode = 'Audit'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$runtimeModule = Join-Path $repoRoot 'scripts\core\runtime.psm1'
Import-Module $runtimeModule
$context = Get-WpcRunContextFromEnvironment -RepoRoot $repoRoot

$components = @(
    [pscustomobject]@{ Name='OneDrive absent'; Path=(Join-Path $repoRoot 'scripts\windows\33_onedrive.ps1') },
    [pscustomobject]@{ Name='VS Code'; Path=(Join-Path $repoRoot 'scripts\windows\30_vscode.ps1') },
    [pscustomobject]@{ Name='Windows Terminal DevOps'; Path=(Join-Path $repoRoot 'scripts\windows\31_windows_terminal.ps1') },
    [pscustomobject]@{ Name='OpenSSH Client'; Path=(Join-Path $repoRoot 'scripts\windows\32_openssh_client.ps1') }
)

$changed = 0
foreach ($component in $components) {
    switch ($Mode) {
        'Apply' {
            $result = Invoke-WpcIdempotentScript -Context $context -Path $component.Path -DisplayName $component.Name -VerifyArguments @{ Mode='Verify' } -ApplyArguments @{ Mode='Apply' }
            if ($result.Changed) { $changed++ }
        }
        'Audit' {
            [void](Invoke-WpcManagedScript -Context $context -Path $component.Path -DisplayName $component.Name -Arguments @{ Mode='Audit' } -Phase 'WorkstationAudit')
        }
        'Verify' {
            [void](Invoke-WpcManagedScript -Context $context -Path $component.Path -DisplayName $component.Name -Arguments @{ Mode='Verify' } -Phase 'WorkstationVerify')
        }
        'Rollback' {
            [void](Invoke-WpcManagedScript -Context $context -Path $component.Path -DisplayName $component.Name -Arguments @{ Mode='Rollback' } -Phase 'WorkstationRollback')
        }
    }
}

if ($Mode -eq 'Apply' -and $changed -eq 0) {
    Write-Host '[DÉJÀ OK] Poste de travail déjà conforme; aucune configuration nʼa été réappliquée.' -ForegroundColor Green
} elseif ($Mode -eq 'Apply') {
    Write-Host "[FAIT] Poste de travail: $changed composant(s) corrigé(s), tous revalidés." -ForegroundColor Green
} else {
    Write-Host "[OK] Poste de travail: $Mode terminé." -ForegroundColor Green
}
