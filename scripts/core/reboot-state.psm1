Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-WpcPendingRebootState {
    [CmdletBinding()]
    param(
        [bool]$CbsPending = $false,
        [bool]$WindowsUpdatePending = $false,
        [AllowNull()][object[]]$PendingFileRenameOperations = @()
    )

    $blockingReasons = [System.Collections.Generic.List[string]]::new()
    $advisoryReasons = [System.Collections.Generic.List[string]]::new()

    if ($CbsPending) {
        $blockingReasons.Add('CBS')
    }

    if ($WindowsUpdatePending) {
        $blockingReasons.Add('WindowsUpdate')
    }

    $pendingRenameItems = @(
        $PendingFileRenameOperations | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_)
        }
    )
    if ($pendingRenameItems.Count -gt 0) {
        # PendingFileRenameOperations est un signal utile, mais il peut rester présent
        # ou être recréé après un reboot par un pilote/logiciel. À lui seul il ne doit
        # donc pas créer une boucle de redémarrage infinie ni bloquer la convergence.
        $advisoryReasons.Add('PendingFileRenameOperations')
    }

    $observedReasons = @($blockingReasons.ToArray()) + @($advisoryReasons.ToArray())

    return [pscustomobject]@{
        Pending = ($blockingReasons.Count -gt 0)
        Reasons = $blockingReasons.ToArray()
        BlockingReasons = $blockingReasons.ToArray()
        Advisory = ($advisoryReasons.Count -gt 0)
        AdvisoryReasons = $advisoryReasons.ToArray()
        ObservedReasons = $observedReasons
        PendingFileRenameOperationsCount = $pendingRenameItems.Count
    }
}

function Get-WpcPendingRebootState {
    [CmdletBinding()]
    param()

    $cbsPending = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    $windowsUpdatePending = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'

    $pendingRenameItems = @()
    try {
        $pendingRenameRaw = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop
        $pendingRenameItems = @(
            $pendingRenameRaw | Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_)
            }
        )
    } catch {
        # L'absence de la valeur signifie simplement qu'aucun renommage n'est observé.
    }

    return New-WpcPendingRebootState `
        -CbsPending:$cbsPending `
        -WindowsUpdatePending:$windowsUpdatePending `
        -PendingFileRenameOperations $pendingRenameItems
}

function Test-WpcRebootRequiredMessage {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Message = '')

    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }

    return [bool](
        $Message -match '(?i)RED[ÉE]MARRAGE\s+REQUIS' -or
        $Message -match '(?i)red[ée]marrage\s+Windows\s+est\s+en\s+attente' -or
        $Message -match '(?i)reboot\s+pending'
    )
}

Export-ModuleMember -Function Get-WpcPendingRebootState, Test-WpcRebootRequiredMessage
