#requires -Version 7.0
<#
.SYNOPSIS
Removes retired Desktop selector compatibility artifacts left by codex-safe-setup 0.2.0
and earlier development builds. This script cleans up only; it provides no compatibility
functionality and never touches the official Codex client.

.DESCRIPTION
Plan-first by default. With -ConfirmApply it:
  1. Archives and deletes known legacy autostart shortcuts whose target resolves to
     wscript.exe/cscript.exe AND whose arguments reference a retired artifact root.
  2. Removes known CSS_DESKTOP_SELECTOR_* user-scope environment variables.
  3. Moves retired state directories/files into a quarantine folder under the state root.

It never starts, stops, closes, or restarts any process, never reads or scans any part of
the signed official client, never writes persistent machine-scope values, and never
recreates any launcher, watcher, shortcut, or loader.

Exit codes: 0 = clean or successfully applied; 2 = plan/apply found residue (plan mode);
3 = verification failed after apply.
#>
[CmdletBinding()]
param(
    [switch]$PlanOnly,
    [switch]$ConfirmApply,
    [string]$CodexHome,
    [string]$StateRoot,
    [string[]]$StartupRoots,
    [string[]]$EnvironmentVariables
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($ConfirmApply -and $PlanOnly) {
    throw 'Pass either -PlanOnly or -ConfirmApply, not both.'
}
$apply = $ConfirmApply.IsPresent

if ([string]::IsNullOrWhiteSpace($CodexHome)) {
    $CodexHome = if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { $env:CODEX_HOME }
    else { Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) '.codex' }
}
$resolvedCodexHome = [IO.Path]::GetFullPath($CodexHome)
if ([string]::IsNullOrWhiteSpace($StateRoot)) {
    $StateRoot = Join-Path $resolvedCodexHome 'safe-setup'
}
$resolvedStateRoot = [IO.Path]::GetFullPath($StateRoot)

$retiredRootNames = @('desktop-ui-fix', 'desktop-selector-loader')
$retiredRoots = @($retiredRootNames | ForEach-Object { Join-Path $resolvedCodexHome $_ })
$retiredStatePaths = @(
    (Join-Path $resolvedStateRoot 'desktop-selector-fix.json'),
    (Join-Path $resolvedStateRoot 'desktop-selector-fix-history')
)
if ($null -eq $EnvironmentVariables -or $EnvironmentVariables.Count -eq 0) {
    $EnvironmentVariables = @(
        'CSS_DESKTOP_SELECTOR_INSTALLATION_ID',
        'CSS_DESKTOP_SELECTOR_PRELOAD',
        'CSS_DESKTOP_SELECTOR_PRELOAD_SHA256',
        'CSS_DESKTOP_SELECTOR_PROBE_MODE',
        'CSS_DESKTOP_SELECTOR_STATUS_PATH'
    )
}

function Get-NormalizedLowerPath {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    try {
        return [IO.Path]::GetFullPath($Value).TrimEnd('\', '/').ToLowerInvariant()
    }
    catch {
        return $Value.Trim().Trim('"').ToLowerInvariant()
    }
}

function Test-ReferencesRetiredRoot {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $normalized = Get-NormalizedLowerPath ($Text.Trim().Trim('"'))
    foreach ($root in $retiredRoots) {
        $normalizedRoot = Get-NormalizedLowerPath $root
        if ($normalized -eq $normalizedRoot -or $normalized.StartsWith($normalizedRoot + '\')) { return $true }
    }
    return $false
}

function Get-LegacyShortcutEntries {
    if ($null -eq $StartupRoots -or $StartupRoots.Count -eq 0) {
        $userStartup = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
        $commonStartup = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp'
        $StartupRoots = @($userStartup, $commonStartup) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    $shell = New-Object -ComObject WScript.Shell
    $entries = [Collections.Generic.List[object]]::new()
    foreach ($startupRoot in $StartupRoots) {
        if (-not (Test-Path -LiteralPath $startupRoot -PathType Container)) { continue }
        foreach ($linkFile in @(Get-ChildItem -LiteralPath $startupRoot -Filter '*.lnk' -File -ErrorAction SilentlyContinue)) {
            try { $shortcut = $shell.CreateShortcut($linkFile.FullName) } catch { continue }
            $target = [string]$shortcut.TargetPath
            $arguments = [string]$shortcut.Arguments
            $targetFileName = [IO.Path]::GetFileName($target).ToLowerInvariant()
            $isWindowsScriptHost = $targetFileName -in @('wscript.exe', 'cscript.exe')
            $referencesRetiredRoot = (Test-ReferencesRetiredRoot $arguments) -or (Test-ReferencesRetiredRoot $target)
            if (($isWindowsScriptHost -and $arguments -match 'Watch-CodexDesktop\.vbs') -or $referencesRetiredRoot) {
                $entries.Add([pscustomobject]@{
                    LinkPath      = $linkFile.FullName
                    TargetPath    = $target
                    Arguments     = $arguments
                    MatchedReason = if ($referencesRetiredRoot) { 'ReferencesRetiredArtifactRoot' } else { 'WindowsScriptHostLegacyWatcher' }
                })
            }
        }
    }
    return @($entries)
}

function Get-ResidualEnvironmentEntries {
    $found = [Collections.Generic.List[string]]::new()
    foreach ($name in $EnvironmentVariables) {
        if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'User'))) {
            $found.Add($name)
        }
    }
    return @($found)
}

function Get-ResidualStatePaths {
    return @($retiredStatePaths | Where-Object { Test-Path -LiteralPath $_ }) +
           @($retiredRoots | Where-Object { Test-Path -LiteralPath $_ })
}

$shortcuts = @(Get-LegacyShortcutEntries)
$environmentEntries = @(Get-ResidualEnvironmentEntries)
$statePaths = @(Get-ResidualStatePaths)
$totalResidue = $shortcuts.Count + $environmentEntries.Count + $statePaths.Count

if (-not $apply) {
    if ($totalResidue -eq 0) {
        Write-Output 'PLAN: no retired Desktop selector artifacts found. Nothing to do.'
        exit 0
    }
    Write-Output ("PLAN: {0} retired artifact(s) found. Re-run with -ConfirmApply to remove them." -f $totalResidue)
    foreach ($entry in $shortcuts) {
        Write-Output ("  SHORTCUT [{0}]: {1} -> {2} {3}" -f $entry.MatchedReason, $entry.LinkPath, $entry.TargetPath, $entry.Arguments)
    }
    foreach ($name in $environmentEntries) { Write-Output ("  ENV (User): {0}" -f $name) }
    foreach ($path in $statePaths) { Write-Output ("  PATH: {0}" -f $path) }
    exit 2
}

$quarantineRoot = Join-Path $resolvedStateRoot ('legacy-selector-quarantine-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))
New-Item -ItemType Directory -Path $quarantineRoot -Force | Out-Null

foreach ($entry in $shortcuts) {
    $archiveName = [IO.Path]::GetFileNameWithoutExtension($entry.LinkPath)
    Copy-Item -LiteralPath $entry.LinkPath -Destination (Join-Path $quarantineRoot "$archiveName.lnk") -Force
    [pscustomobject]@{
        archivedUtc = [DateTime]::UtcNow.ToString('o')
        linkPath    = $entry.LinkPath
        targetPath  = $entry.TargetPath
        arguments   = $entry.Arguments
        matched     = $entry.MatchedReason
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $quarantineRoot "$archiveName.metadata.json") -Encoding utf8NoBOM
    Remove-Item -LiteralPath $entry.LinkPath -Force
}

foreach ($name in $environmentEntries) {
    [Environment]::SetEnvironmentVariable($name, $null, 'User')
}

foreach ($path in $statePaths) {
    $destination = Join-Path $quarantineRoot (([IO.Path]::GetFileName($path.TrimEnd('\'))) + '_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    Move-Item -LiteralPath $path -Destination $destination -Force
}

$remainingShortcuts = @(Get-LegacyShortcutEntries)
$remainingEnvironmentEntries = @(Get-ResidualEnvironmentEntries)
$remainingStatePaths = @(Get-ResidualStatePaths)
$remainingTotal = $remainingShortcuts.Count + $remainingEnvironmentEntries.Count + $remainingStatePaths.Count
if ($remainingTotal -gt 0) {
    Write-Output 'VERIFY: FAILED. Residue remains after apply:'
    foreach ($entry in $remainingShortcuts) { Write-Output ("  SHORTCUT: {0}" -f $entry.LinkPath) }
    foreach ($name in $remainingEnvironmentEntries) { Write-Output ("  ENV: {0}" -f $name) }
    foreach ($path in $remainingStatePaths) { Write-Output ("  PATH: {0}" -f $path) }
    exit 3
}

Write-Output ("APPLIED: removed {0} artifact(s); archive at {1}" -f $totalResidue, $quarantineRoot)
Write-Output 'VERIFY: PASS. Startup, user environment, and Codex home contain no retired selector artifacts.'
exit 0
