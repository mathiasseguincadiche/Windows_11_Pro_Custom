Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WpcPendingRebootState {
    [CmdletBinding()]
    param()

    $reasons = [System.Collections.Generic.List[string]]::new()

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $reasons.Add('CBS')
    }

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $reasons.Add('WindowsUpdate')
    }

    try {
        $pendingRenameRaw = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop
        $pendingRenameItems = @(
            $pendingRenameRaw | Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_)
            }
        )
        if ($pendingRenameItems.Count -gt 0) {
            $reasons.Add('PendingFileRenameOperations')
        }
    } catch {
        # L'absence de la valeur signifie simplement qu'aucun renommage n'est en attente.
    }

    return [pscustomobject]@{
        Pending = ($reasons.Count -gt 0)
        Reasons = @($reasons)
    }
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
