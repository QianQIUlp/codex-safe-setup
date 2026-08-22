#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$CodexHome,
    [string]$StateRoot,
    [switch]$PlanOnly,
    [switch]$ConfirmRollback,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'DesktopPermissionSelector.Common.ps1')

$resolvedCodexHome = [IO.Path]::GetFullPath((Get-CssCodexHome -Override $CodexHome))
$resolvedStateRoot = [IO.Path]::GetFullPath((Get-CssStateRoot -CodexHome $resolvedCodexHome -Override $StateRoot))
$pointerPath = Join-Path $resolvedStateRoot $script:CssDesktopSelectorStateFile
if (-not (Test-Path -LiteralPath $pointerPath -PathType Leaf)) { throw "Compatibility state is missing: $pointerPath" }
$state = [IO.File]::ReadAllText($pointerPath) | ConvertFrom-Json -Depth 30
if ([int]$state.stateSchemaVersion -notin @(2, 3) -or [string]$state.mode -ne 'ProcessScopedSessionPreload') {
    throw 'Unsupported compatibility state schema or mode.'
}
$destination = [IO.Path]::GetFullPath([string]$state.destinationRoot)
if (-not (Test-CssPathWithin -Path $destination -Root $resolvedCodexHome) -or
    $destination.Equals($resolvedCodexHome, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Recorded compatibility destination is outside CodexHome.'
}
$historyRoot = Join-Path $resolvedStateRoot 'desktop-selector-fix-history'
$previousRoot = [string]$state.previousRoot
if ($previousRoot) {
    $resolvedPrevious = [IO.Path]::GetFullPath($previousRoot)
    if (-not (Test-CssPathWithin -Path $resolvedPrevious -Root $historyRoot) -or -not (Test-Path -LiteralPath $resolvedPrevious)) {
        throw 'Recorded previous loader generation is missing or outside recovery history.'
    }
}
$legacyRoot = [string]$state.legacyDerivedRoot
$legacyArchive = [string]$state.legacyArchivePath
if ($legacyRoot) {
    if (-not (Test-CssPathWithin -Path $legacyRoot -Root $resolvedCodexHome) -or
        [IO.Path]::GetFullPath($legacyRoot).Equals($resolvedCodexHome, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Recorded legacy compatibility root is outside CodexHome.'
    }
    if ($legacyArchive -and (-not (Test-CssPathWithin -Path $legacyArchive -Root $historyRoot) -or
        [IO.Path]::GetFullPath($legacyArchive).Equals([IO.Path]::GetFullPath($historyRoot), [StringComparison]::OrdinalIgnoreCase))) {
        throw 'Recorded legacy archive is outside recovery history.'
    }
}

Write-Output "Rollback lightweight Desktop permission-selector loader: $destination"
Write-Output '- Stop only the recorded loader watcher; never terminate the current Desktop task.'
Write-Output '- Remove only shortcuts that still point to this loader generation.'
Write-Output '- Move the active loader and state into recovery history; do not delete them.'
Write-Output '- Restore the immediately previous loader generation, or the preserved legacy compatibility generation when one existed.'
Write-Output '- Rollback never recreates startup-watcher autostart entries and never launches a watcher; use the Start Menu shortcut explicitly.'
if ($PlanOnly) { Write-Output 'No files changed (PlanOnly).'; return }
if (-not $ConfirmRollback) {
    if ($NonInteractive) { throw 'Non-interactive rollback requires -ConfirmRollback.' }
    if ((Read-Host 'Type ROLLBACK to disable the lightweight Desktop selector loader') -cne 'ROLLBACK') { throw 'Rollback was not confirmed.' }
}

$package = Get-CssDesktopPackageInfo -InstallLocation ([string]$state.sourceInstallLocation) -PackageVersion ([string]$state.sourcePackageVersion)
$marker = $script:CssDesktopSelectorLaunchMarkerPrefix + [string]$state.installationId
$activeLoaderProcesses = @(Get-CssDesktopRootProcesses -ExecutablePath $package.ExecutablePath | Where-Object {
    ([string]$_.CommandLine).IndexOf($marker, [StringComparison]::OrdinalIgnoreCase) -ge 0
})
if ($activeLoaderProcesses.Count -gt 0) {
    throw 'The process-scoped selector loader is running. Fully exit Codex before rollback; rollback will not terminate the active task.'
}
[void](Stop-CssDesktopSelectorWatcher -DestinationRoot $destination)

$shell = New-Object -ComObject WScript.Shell
foreach ($shortcutRecord in @(
    [pscustomobject]@{ Path = [string]$state.startMenuShortcut; Script = 'Start-CodexFixed.vbs' },
    [pscustomobject]@{ Path = [string]$state.startupShortcut; Script = 'Watch-CodexDesktop.vbs' }
)) {
    if (-not $shortcutRecord.Path -or -not (Test-Path -LiteralPath $shortcutRecord.Path -PathType Leaf)) { continue }
    $shortcut = $shell.CreateShortcut($shortcutRecord.Path)
    $expected = Join-Path $destination $shortcutRecord.Script
    if (([string]$shortcut.Arguments).IndexOf($expected, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        Remove-Item -LiteralPath $shortcutRecord.Path -Force
    }
    else {
        Write-Warning "Shortcut no longer points to this installation and was preserved: $($shortcutRecord.Path)"
    }
}

New-Item -ItemType Directory -Path $historyRoot -Force | Out-Null
$rollbackId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-loader-rollback'
if (Test-Path -LiteralPath $destination) {
    Move-Item -LiteralPath $destination -Destination (Join-Path $historyRoot $rollbackId)
}
Move-Item -LiteralPath $pointerPath -Destination (Join-Path $historyRoot ($rollbackId + '.json'))

function Set-CssRestoredShortcuts {
    param([string]$Root, $Pointer, [switch]$StartMenuOnly)
    if (-not $Root -or -not $Pointer -or -not (Test-Path -LiteralPath $Root -PathType Container)) { return }
    $wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $startProperty = $Pointer.PSObject.Properties['startMenuShortcut']
    $startPath = if ($null -ne $startProperty) { [string]$startProperty.Value } else { '' }
    if ($startPath -and (Test-Path -LiteralPath (Join-Path $Root 'Start-CodexFixed.vbs') -PathType Leaf)) {
        $start = $shell.CreateShortcut($startPath)
        $start.TargetPath = $wscript
        $start.Arguments = '"' + (Join-Path $Root 'Start-CodexFixed.vbs') + '"'
        $start.WorkingDirectory = $Root
        $start.Save()
    }
    if ($StartMenuOnly) { return }
    # Startup-watcher autostart is never recreated by rollback: a stale or
    # resurrected autostart entry is exactly the failure mode this fix removes.
    return
}

if ($previousRoot) {
    Move-Item -LiteralPath $resolvedPrevious -Destination $destination
    if ($null -ne $state.previousPointerState) {
        Write-CssTextAtomic -Path $pointerPath -Text ($state.previousPointerState | ConvertTo-Json -Depth 30)
    }
    Set-CssRestoredShortcuts -Root $destination -Pointer $state.previousPointerState
}
elseif ($legacyRoot) {
    if (-not (Test-Path -LiteralPath $legacyRoot) -and $legacyArchive -and (Test-Path -LiteralPath $legacyArchive)) {
        Move-Item -LiteralPath $legacyArchive -Destination $legacyRoot
    }
    if ($null -ne $state.previousPointerState) {
        Write-CssTextAtomic -Path $pointerPath -Text ($state.previousPointerState | ConvertTo-Json -Depth 30)
    }
    Write-Output 'Legacy compatibility generation restored without recreating any autostart entry; its watcher stays disabled.'
}
elseif ($null -ne $state.previousPointerState) {
    Write-CssTextAtomic -Path $pointerPath -Text ($state.previousPointerState | ConvertTo-Json -Depth 30)
}

Write-Output 'Desktop permission-selector loader rollback completed.'
