[CmdletBinding()]
param(
    [string]$GeminiHome,
    [string]$StateRoot,
    [switch]$ConfirmRollback,
    [switch]$NonInteractive
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$ErrorActionPreference = 'Stop'

$resolvedHome = Get-AgyGeminiHome -Override $GeminiHome
$resolvedState = Get-AgyStateRoot -GeminiHome $resolvedHome -Override $StateRoot

$statePath = Join-Path $resolvedState 'install-state.json'
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw "Install state not found: $statePath"
}
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json

Write-Output 'Antigravity Safe Setup — Rollback Plan'
Write-Output '--------------------------------------'
Write-Output ("Settings:                {0}" -f $state.CliSettingsPath)
Write-Output ("Original settings existed: {0}" -f $state.OriginalCliSettingsExists)
Write-Output ("Backup file:             {0}" -f $(if ($state.CliSettingsBackup) { $state.CliSettingsBackup } else { '<none; will delete>' }))

if (-not $ConfirmRollback) {
    if ($NonInteractive) { throw 'Non-interactive rollback requires -ConfirmRollback.' }
    $answer = Read-Host 'Restore previous Antigravity configuration? [y/N]'
    if ($answer -notmatch '^(?i:y|yes)$') {
        Write-Output 'Rollback cancelled.'
        return
    }
}

# 1. Restore CLI settings
if ($state.OriginalCliSettingsExists) {
    if (-not $state.CliSettingsBackup -or -not (Test-Path -LiteralPath $state.CliSettingsBackup -PathType Leaf)) {
        throw 'Configuration backup is missing; refusing rollback.'
    }
    Copy-Item -LiteralPath $state.CliSettingsBackup -Destination $state.CliSettingsPath -Force
}
elseif (Test-Path -LiteralPath $state.CliSettingsPath -PathType Leaf) {
    Remove-Item -LiteralPath $state.CliSettingsPath -Force
}

# 2. Restore / Remove Bridge
if ($state.BridgeTouched) {
    if ($state.OriginalBridgeExists -and $state.BridgeBackup -and (Test-Path -LiteralPath $state.BridgeBackup -PathType Leaf)) {
        Copy-Item -LiteralPath $state.BridgeBackup -Destination $state.BridgePath -Force
    }
    elseif ($state.BridgePath -and (Test-Path -LiteralPath $state.BridgePath -PathType Leaf)) {
        Remove-Item -LiteralPath $state.BridgePath -Force
    }
}

# 3. Restore / Remove Authorized Workspaces
if ($state.AuthorizedWorkspacesTouched) {
    if ($state.OriginalAuthorizedWorkspacesExists -and $state.AuthorizedWorkspacesBackup -and (Test-Path -LiteralPath $state.AuthorizedWorkspacesBackup -PathType Leaf)) {
        Copy-Item -LiteralPath $state.AuthorizedWorkspacesBackup -Destination $state.AuthorizedWorkspacesPath -Force
    }
    elseif ($state.AuthorizedWorkspacesPath -and (Test-Path -LiteralPath $state.AuthorizedWorkspacesPath -PathType Leaf)) {
        Remove-Item -LiteralPath $state.AuthorizedWorkspacesPath -Force
    }
}

# 4. Remove Canary
if ($state.CanaryPath -and (Test-Path -LiteralPath $state.CanaryPath -PathType Leaf)) {
    Remove-Item -LiteralPath $state.CanaryPath -Force
}

# 5. Remove State file
Remove-Item -LiteralPath $statePath -Force

Write-Output 'Rollback completed successfully.'
