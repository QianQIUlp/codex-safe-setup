[CmdletBinding()]
param(
    [string]$CodexHome,
    [string]$StateRoot,
    [switch]$ConfirmRollback,
    [switch]$NonInteractive
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$ErrorActionPreference = 'Stop'
$resolvedHome = Get-CssCodexHome -Override $CodexHome
$resolvedState = Get-CssStateRoot -CodexHome $resolvedHome -Override $StateRoot
$statePath = Join-Path $resolvedState 'install-state.json'
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw "Install state not found: $statePath" }
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json

$pathComparison = if ($env:OS -eq 'Windows_NT') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
$expectedConfig = [IO.Path]::GetFullPath((Join-Path $resolvedHome 'config.toml'))
$expectedRules = [IO.Path]::GetFullPath((Join-Path (Join-Path $resolvedHome 'rules') 'codex-safe-setup.rules'))
$expectedBridge = [IO.Path]::GetFullPath((Join-Path (Join-Path $resolvedState 'bin') 'New-CodexCheckpoint.ps1'))
$expectedAuthorized = [IO.Path]::GetFullPath((Join-Path $resolvedState 'authorized-workspaces.json'))
$expectedCanary = [IO.Path]::GetFullPath((Join-Path $resolvedState 'outside-workspace-canary.txt'))
foreach ($targetCheck in @(
    @([IO.Path]::GetFullPath($state.ConfigPath), $expectedConfig, 'config'),
    @([IO.Path]::GetFullPath($state.RulesPath), $expectedRules, 'rules'),
    @([IO.Path]::GetFullPath($state.AuthorizedWorkspacesPath), $expectedAuthorized, 'workspace registry'),
    @([IO.Path]::GetFullPath($state.CanaryPath), $expectedCanary, 'canary')
)) {
    if (-not [string]::Equals($targetCheck[0], $targetCheck[1], $pathComparison)) {
        throw "Install state contains an unexpected $($targetCheck[2]) target. Refusing rollback."
    }
}
if ($state.BridgePath -and -not [string]::Equals([IO.Path]::GetFullPath($state.BridgePath), $expectedBridge, $pathComparison)) {
    throw 'Install state contains an unexpected bridge target. Refusing rollback.'
}
$expectedBackupRoot = [IO.Path]::GetFullPath((Join-Path $resolvedState 'backups')) + [IO.Path]::DirectorySeparatorChar
foreach ($backupPath in @($state.ConfigBackup, $state.RulesBackup, $state.BridgeBackup, $state.AuthorizedWorkspacesBackup, $state.CanaryBackup)) {
    if ($backupPath -and -not [IO.Path]::GetFullPath($backupPath).StartsWith($expectedBackupRoot, $pathComparison)) {
        throw 'Install state contains a backup path outside the safe-setup backup directory. Refusing rollback.'
    }
}

Write-Output 'Codex Safe Setup - rollback plan'
Write-Output ("Config: {0}" -f $state.ConfigPath)
Write-Output ("Original config existed: {0}" -f $state.OriginalConfigExists)
Write-Output ("Config backup: {0}" -f $(if ($state.ConfigBackup) { $state.ConfigBackup } else { '<none; installed file will be removed>' }))
Write-Output ("Rules: {0}" -f $state.RulesPath)
if (-not $ConfirmRollback) {
    if ($NonInteractive) { throw 'Non-interactive rollback requires -ConfirmRollback.' }
    $answer = Read-Host 'Restore the recorded configuration and rule state? [y/N]'
    if ($answer -notmatch '^(?i:y|yes)$') { Write-Output 'Rollback cancelled.'; return }
}

if ($state.OriginalConfigExists) {
    if (-not $state.ConfigBackup -or -not (Test-Path -LiteralPath $state.ConfigBackup -PathType Leaf)) { throw 'Configuration backup is missing; refusing rollback.' }
    Copy-Item -LiteralPath $state.ConfigBackup -Destination $state.ConfigPath -Force
}
elseif (Test-Path -LiteralPath $state.ConfigPath -PathType Leaf) {
    Remove-Item -LiteralPath $state.ConfigPath -Force
}

if ($state.RulesTouched) {
    if ($state.OriginalRulesExists) {
        if (-not $state.RulesBackup -or -not (Test-Path -LiteralPath $state.RulesBackup -PathType Leaf)) { throw 'Rules backup is missing; configuration was restored but rules were not changed.' }
        Copy-Item -LiteralPath $state.RulesBackup -Destination $state.RulesPath -Force
    }
    elseif (Test-Path -LiteralPath $state.RulesPath -PathType Leaf) {
        Remove-Item -LiteralPath $state.RulesPath -Force
    }
}

if ($state.BridgeTouched) {
    if ($state.OriginalBridgeExists) {
        if (-not $state.BridgeBackup -or -not (Test-Path -LiteralPath $state.BridgeBackup -PathType Leaf)) { throw 'Bridge backup is missing; refusing to remove the installed bridge.' }
        Copy-Item -LiteralPath $state.BridgeBackup -Destination $state.BridgePath -Force
    }
    elseif ($state.BridgePath -and (Test-Path -LiteralPath $state.BridgePath -PathType Leaf)) {
        Remove-Item -LiteralPath $state.BridgePath -Force
    }
}

if ($state.AuthorizedWorkspacesTouched) {
    if ($state.OriginalAuthorizedWorkspacesExists) {
        if (-not $state.AuthorizedWorkspacesBackup -or -not (Test-Path -LiteralPath $state.AuthorizedWorkspacesBackup -PathType Leaf)) { throw 'Authorized-workspaces backup is missing.' }
        Copy-Item -LiteralPath $state.AuthorizedWorkspacesBackup -Destination $state.AuthorizedWorkspacesPath -Force
    }
    elseif (Test-Path -LiteralPath $state.AuthorizedWorkspacesPath -PathType Leaf) {
        Remove-Item -LiteralPath $state.AuthorizedWorkspacesPath -Force
    }
}

if ($state.CanaryTouched) {
    if ($state.OriginalCanaryExists) {
        if (-not $state.CanaryBackup -or -not (Test-Path -LiteralPath $state.CanaryBackup -PathType Leaf)) { throw 'Canary backup is missing.' }
        Copy-Item -LiteralPath $state.CanaryBackup -Destination $state.CanaryPath -Force
    }
    elseif (Test-Path -LiteralPath $state.CanaryPath -PathType Leaf) {
        Remove-Item -LiteralPath $state.CanaryPath -Force
    }
}
$state | Add-Member -NotePropertyName RolledBackAtUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
Write-CssTextAtomic -Path $statePath -Text ($state | ConvertTo-Json -Depth 5)
Write-Output 'Rollback complete. Restart Codex so the restored configuration becomes active.'
