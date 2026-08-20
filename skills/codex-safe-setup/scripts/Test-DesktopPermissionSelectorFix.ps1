#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$CodexHome,
    [string]$StateRoot,
    [string]$InstallLocation,
    [string]$PackageVersion,
    [switch]$SkipShortcutCheck,
    [switch]$SkipRuntimeProbe,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'DesktopPermissionSelector.Common.ps1')

$resolvedCodexHome = [IO.Path]::GetFullPath((Get-CssCodexHome -Override $CodexHome))
$resolvedStateRoot = [IO.Path]::GetFullPath((Get-CssStateRoot -CodexHome $resolvedCodexHome -Override $StateRoot))
$pointerPath = Join-Path $resolvedStateRoot $script:CssDesktopSelectorStateFile
$checks = [Collections.Generic.List[object]]::new()
function Add-Check([string]$Control, [bool]$Passed, [string]$Evidence) {
    $checks.Add([pscustomobject]@{ Control = $Control; Status = $(if ($Passed) { 'PASS' } else { 'FAIL' }); Evidence = $Evidence })
}

function Invoke-CssRendererPreloadProbe {
    param(
        [Parameter(Mandatory)]$Package,
        [Parameter(Mandatory)]$LocalState,
        [Parameter(Mandatory)][string]$LoaderPath,
        [Parameter(Mandatory)][string]$PreloadPath
    )

    $probeRoot = Join-Path ([IO.Path]::GetTempPath()) ('css-selector-renderer-probe-' + [guid]::NewGuid().ToString('N'))
    $appRoot = Join-Path $probeRoot 'app'
    $userDataRoot = Join-Path $probeRoot 'user-data'
    $appOutput = Join-Path $probeRoot 'app-result.json'
    $loaderOutput = Join-Path $probeRoot 'loader-result.json'
    New-Item -ItemType Directory -Path $appRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $userDataRoot -Force | Out-Null
    try {
        [IO.File]::WriteAllText((Join-Path $appRoot 'package.json'), '{"name":"codex-safe-setup-selector-probe","version":"1.0.0","main":"main.cjs"}', [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $appRoot 'probe.html'), @'
<!doctype html><meta charset="utf-8"><script>
globalThis.__CSS_OVERRIDE_AT_FIRST_SCRIPT__ = globalThis.__STATSIG__?.__permissionSelectorOverrideInstalled === true;
const client = { overrideAdapter: { getGateOverride: (gate) => gate } };
globalThis.__STATSIG__.instances.probe = client;
globalThis.__CSS_SELECTED_GATE__ = client.overrideAdapter.getGateOverride({ name: "4226282475", value: false, details: {} }).value;
globalThis.__CSS_OTHER_GATE__ = client.overrideAdapter.getGateOverride({ name: "unrelated", value: false, details: {} }).value;
</script>
'@, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $appRoot 'main.cjs'), @'
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { app, BrowserWindow } = require('electron');
app.whenReady().then(async () => {
  const window = new BrowserWindow({ show: false, webPreferences: { contextIsolation: true, nodeIntegration: false } });
  await window.loadFile(path.join(__dirname, 'probe.html'));
  const result = await window.webContents.executeJavaScript('({ overrideAtFirstScript: globalThis.__CSS_OVERRIDE_AT_FIRST_SCRIPT__ ?? null, selectedGate: globalThis.__CSS_SELECTED_GATE__ ?? null, otherGate: globalThis.__CSS_OTHER_GATE__ ?? null })', true);
  fs.writeFileSync(process.env.CSS_SELECTOR_PROBE_APP_OUTPUT, JSON.stringify(result, null, 2), 'utf8');
  app.quit();
});
'@, [Text.UTF8Encoding]::new($false))

        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = [string]$Package.ExecutablePath
        $startInfo.Arguments = '"' + $appRoot + '" --user-data-dir="' + $userDataRoot + '"'
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
        $startInfo.EnvironmentVariables['NODE_OPTIONS'] = '--require=' + [string]$LocalState.nodeRequirePath
        $startInfo.EnvironmentVariables['CSS_DESKTOP_SELECTOR_PRELOAD'] = $PreloadPath
        $startInfo.EnvironmentVariables['CSS_DESKTOP_SELECTOR_PRELOAD_SHA256'] = [string]$LocalState.preloadSha256
        $startInfo.EnvironmentVariables['CSS_DESKTOP_SELECTOR_STATUS_PATH'] = $loaderOutput
        $startInfo.EnvironmentVariables['CSS_DESKTOP_SELECTOR_INSTALLATION_ID'] = [string]$LocalState.installationId
        $startInfo.EnvironmentVariables['CSS_SELECTOR_PROBE_APP_OUTPUT'] = $appOutput
        $process = [Diagnostics.Process]::Start($startInfo)
        if ($null -eq $process) { throw 'Could not start the renderer preload probe.' }
        $completed = $process.WaitForExit(15000)
        if (-not $completed) {
            try { $process.Kill() } catch { }
            throw 'Renderer preload probe timed out.'
        }
        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $appOutput -PathType Leaf) -or
            -not (Test-Path -LiteralPath $loaderOutput -PathType Leaf)) {
            throw "Renderer preload probe failed (exit $($process.ExitCode))."
        }
        $appResult = [IO.File]::ReadAllText($appOutput) | ConvertFrom-Json
        $loaderResult = [IO.File]::ReadAllText($loaderOutput) | ConvertFrom-Json
        return [pscustomobject]@{ App = $appResult; Loader = $loaderResult }
    }
    finally {
        if (Test-Path -LiteralPath $probeRoot) {
            $resolvedProbe = [IO.Path]::GetFullPath($probeRoot)
            $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
            if (-not (Test-CssPathWithin -Path $resolvedProbe -Root $resolvedTemp) -or
                $resolvedProbe.Equals($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to remove unexpected renderer probe path: $resolvedProbe"
            }
            Remove-Item -LiteralPath $resolvedProbe -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-CssWindowsPowerShellLauncherValidation {
    param([Parameter(Mandatory)][string]$Destination)

    $wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $launcherPath = Join-Path $Destination 'Start-CodexFixed.vbs'
    $statusPath = Join-Path $Destination 'last-launch-status.json'
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $wscript
    $startInfo.Arguments = '"' + $launcherPath + '" -validateonly'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.EnvironmentVariables['PSModulePath'] = Join-Path ([IO.Path]::GetTempPath()) 'codex-safe-setup-intentionally-missing-modules'
    $process = [Diagnostics.Process]::Start($startInfo)
    if ($null -eq $process) { throw 'Could not start the hidden Windows launcher validation.' }
    if (-not $process.WaitForExit(15000)) {
        try { $process.Kill() } catch { }
        throw 'Hidden Windows launcher validation timed out.'
    }
    $exitCode = $process.ExitCode
    $status = $null
    try { $status = [IO.File]::ReadAllText($statusPath) | ConvertFrom-Json } catch { }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Status = [string]$status.status
        Message = [string]$status.message
        Output = ''
    }
}

try {
    if (-not (Test-Path -LiteralPath $pointerPath -PathType Leaf)) { throw "Compatibility state is missing: $pointerPath" }
    $state = [IO.File]::ReadAllText($pointerPath) | ConvertFrom-Json -Depth 30
    $destination = [IO.Path]::GetFullPath([string]$state.destinationRoot)
    Add-Check 'State version' (
        $state.stateSchemaVersion -eq 3 -and $state.productVersion -eq '0.2.0' -and
        $state.mode -eq 'ProcessScopedSessionPreload' -and $state.active
    ) "schema=$($state.stateSchemaVersion) product=$($state.productVersion) mode=$($state.mode) active=$($state.active)"
    Add-Check 'Target containment' ((Test-CssPathWithin -Path $destination -Root $resolvedCodexHome) -and -not $destination.Equals($resolvedCodexHome, [StringComparison]::OrdinalIgnoreCase)) $destination

    $localStatePath = Join-Path $destination $script:CssDesktopSelectorLocalStateFile
    if (-not (Test-Path -LiteralPath $localStatePath -PathType Leaf)) { throw "Local compatibility state is missing: $localStatePath" }
    $local = [IO.File]::ReadAllText($localStatePath) | ConvertFrom-Json -Depth 30
    Add-Check 'State agreement' (
        [string]$local.installationId -eq [string]$state.installationId -and
        [string]$local.sourcePackageVersion -eq [string]$state.sourcePackageVersion -and
        [string]$local.sourceAsarSha256 -eq [string]$state.sourceAsarSha256 -and
        [IO.Path]::GetFullPath([string]$local.destinationRoot).Equals($destination, [StringComparison]::OrdinalIgnoreCase) -and
        [string]$local.sourcePackageFamilyName -eq [string]$state.sourcePackageFamilyName -and
        [int]$local.recertificationCount -eq [int]$state.recertificationCount
    ) 'Pointer and local schema-3 loader state agree.'

    $package = Get-CssDesktopPackageInfo -InstallLocation $InstallLocation -PackageVersion $PackageVersion
    Add-Check 'Desktop version pin' (
        [string]$package.Version -eq [string]$state.sourcePackageVersion -and
        [IO.Path]::GetFullPath([string]$package.InstallLocation).Equals([IO.Path]::GetFullPath([string]$state.sourceInstallLocation), [StringComparison]::OrdinalIgnoreCase)
    ) "installed=$($package.Version) pinned=$($state.sourcePackageVersion)"
    Add-Check 'Official package identity pin' (
        [string]$package.PackageName -eq [string]$local.sourcePackageName -and
        [string]$package.PackageFamilyName -eq [string]$local.sourcePackageFamilyName -and
        [string]$package.PublisherId -eq [string]$local.sourcePublisherId -and
        [string]$package.Publisher -eq [string]$local.sourcePublisher
    ) "name=$($package.PackageName) family=$($package.PackageFamilyName) publisherId=$($package.PublisherId)"
    $currentAsarHash = Get-CssFileSha256 -Path $package.AsarPath
    $currentExecutableHash = Get-CssFileSha256 -Path $package.ExecutablePath
    Add-Check 'Signed source pins' (
        $currentAsarHash -eq [string]$state.sourceAsarSha256 -and
        $currentExecutableHash -eq [string]$state.sourceExecutableSha256
    ) "asar=$currentAsarHash executable=$currentExecutableHash"
    if ([bool]$local.syntheticUnsignedTestFixture) {
        Add-Check 'Source signer pin' $true 'Synthetic unsigned unit-test fixture recorded by the temp-path-only installer guard.'
    }
    else {
        $signature = Get-AuthenticodeSignature -LiteralPath $package.ExecutablePath
        $signerMatches = $signature.Status -eq [Management.Automation.SignatureStatus]::Valid -and
            $null -ne $signature.SignerCertificate -and
            ([string]$signature.SignerCertificate.Thumbprint).Equals([string]$local.trustedSignerThumbprint, [StringComparison]::OrdinalIgnoreCase)
        $subjectMatches = $null -ne $signature.SignerCertificate -and
            ([string]$signature.SignerCertificate.Subject).Equals([string]$local.trustedSignerSubject, [StringComparison]::OrdinalIgnoreCase)
        Add-Check 'Source signer pin' ($signerMatches -and $subjectMatches) "status=$($signature.Status) thumbprint=$($signature.SignerCertificate.Thumbprint) subject=$($signature.SignerCertificate.Subject)"
    }

    $sourceEvidence = Get-CssDesktopSelectorSourceEvidence -ArchivePath $package.AsarPath
    Add-Check 'Selector gate source pin' (
        $sourceEvidence.SelectorGate -eq [string]$local.selectorGate -and $sourceEvidence.MatchCount -gt 0 -and
        [int]$sourceEvidence.StructureVersion -eq [int]$local.selectorStructureVersion -and
        @($sourceEvidence.StructureAnchors).Count -eq @($local.selectorStructureAnchors).Count
    ) "gate=$($sourceEvidence.SelectorGate) assets=$($sourceEvidence.MatchCount) structure=$($sourceEvidence.StructureVersion)"

    $loaderPath = Join-Path $destination $script:CssDesktopSelectorLoaderFile
    $preloadPath = Join-Path $destination $script:CssDesktopSelectorPreloadFile
    Add-Check 'Loader asset hashes' (
        (Get-CssFileSha256 -Path $loaderPath) -eq [string]$local.loaderSha256 -and
        (Get-CssFileSha256 -Path ([string]$local.nodeRequirePath)) -eq [string]$local.loaderSha256 -and
        (Get-CssFileSha256 -Path $preloadPath) -eq [string]$local.preloadSha256 -and
        (Get-CssFileSha256 -Path (Join-Path $destination 'Start-CodexFixed.ps1')) -eq [string]$local.launcherSha256 -and
        (Get-CssFileSha256 -Path (Join-Path $destination 'Watch-CodexDesktop.ps1')) -eq [string]$local.watcherSha256 -and
        (Get-CssFileSha256 -Path (Join-Path $destination 'Recertify-CodexDesktop.ps1')) -eq [string]$local.recertifierSha256 -and
        (Get-CssFileSha256 -Path (Join-Path $destination 'DesktopPermissionSelector.Common.ps1')) -eq [string]$local.compatibilityCommonSha256 -and
        (Test-Path -LiteralPath ([string]$local.powerShell7Path) -PathType Leaf)
    ) 'Loader, preload, launcher, watcher, recertifier, compatibility verifier, recorded PowerShell 7 path, and no-space NODE_OPTIONS path are valid.'
    Add-Check 'No client derivative' (-not (Test-Path -LiteralPath (Join-Path $destination 'app'))) 'The compatibility root contains no extracted Desktop application tree.'

    if (-not $SkipRuntimeProbe -and -not [bool]$local.syntheticUnsignedTestFixture) {
        $launcherValidation = Invoke-CssWindowsPowerShellLauncherValidation -Destination $destination
        Add-Check 'Real hidden Windows launch-chain validation' (
            $launcherValidation.ExitCode -eq 0 -and $launcherValidation.Status -eq 'VALIDATED'
        ) "exit=$($launcherValidation.ExitCode) status=$($launcherValidation.Status) message=$($launcherValidation.Message) output=$($launcherValidation.Output)"
        $mainProbe = Invoke-CssDesktopSelectorNodeOptionsProbe -ExecutablePath $package.ExecutablePath -LoaderPath $loaderPath -PreloadPath $preloadPath -PreloadSha256 ([string]$local.preloadSha256)
        Add-Check 'Main-process loader probe' ([string]$mainProbe.status -eq 'PROBE_PASS' -and [bool]$mainProbe.electronAppAvailable) "status=$($mainProbe.status) electron=$($mainProbe.electronAppAvailable)"
        $rendererProbe = Invoke-CssRendererPreloadProbe -Package $package -LocalState $local -LoaderPath $loaderPath -PreloadPath $preloadPath
        Add-Check 'Document-start renderer probe' (
            [bool]$rendererProbe.App.overrideAtFirstScript -and
            [bool]$rendererProbe.App.selectedGate -and
            -not [bool]$rendererProbe.App.otherGate -and
            [string]$rendererProbe.Loader.status -eq 'PRELOAD_ACTIVE' -and
            [string]$rendererProbe.Loader.installationId -eq [string]$local.installationId
        ) "firstScript=$($rendererProbe.App.overrideAtFirstScript) selected=$($rendererProbe.App.selectedGate) unrelated=$($rendererProbe.App.otherGate) loader=$($rendererProbe.Loader.status)"
    }
    else {
        Add-Check 'Runtime loader probes' $true $(if ($SkipRuntimeProbe) { 'Explicitly skipped.' } else { 'Synthetic fixture: runtime process launch is intentionally unavailable.' })
    }

    if (-not $SkipShortcutCheck) {
        $shell = New-Object -ComObject WScript.Shell
        foreach ($shortcutRecord in @(
            [pscustomobject]@{ Name = 'Start Menu shortcut'; Path = [string]$state.startMenuShortcut; Script = 'Start-CodexFixed.vbs' },
            [pscustomobject]@{ Name = 'Startup watcher shortcut'; Path = [string]$state.startupShortcut; Script = 'Watch-CodexDesktop.vbs' }
        )) {
            $valid = $false
            if ($shortcutRecord.Path -and (Test-Path -LiteralPath $shortcutRecord.Path -PathType Leaf)) {
                $shortcut = $shell.CreateShortcut($shortcutRecord.Path)
                $expectedScript = Join-Path $destination $shortcutRecord.Script
                $valid = ([string]$shortcut.Arguments).IndexOf($expectedScript, [StringComparison]::OrdinalIgnoreCase) -ge 0
            }
            Add-Check $shortcutRecord.Name $valid $shortcutRecord.Path
        }

        $watcherPidPath = Join-Path $destination 'watcher.pid.json'
        $watcherStatusPath = Join-Path $destination 'watcher-status.json'
        $watcherRecord = $null
        $watcherStatus = $null
        $watcherProcess = $null
        try { $watcherRecord = [IO.File]::ReadAllText($watcherPidPath) | ConvertFrom-Json } catch { }
        try { $watcherStatus = [IO.File]::ReadAllText($watcherStatusPath) | ConvertFrom-Json } catch { }
        if ($null -ne $watcherRecord) {
            $watcherProcess = Get-CimInstance Win32_Process -Filter ("ProcessId = {0}" -f [int]$watcherRecord.processId) -ErrorAction SilentlyContinue
        }
        $watcherHealthy = $null -ne $watcherRecord -and $null -ne $watcherProcess -and
            [string]$watcherRecord.installationId -eq [string]$local.installationId -and
            ([string]$watcherProcess.CommandLine).IndexOf((Join-Path $destination 'Watch-CodexDesktop.ps1'), [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
            [string]$watcherStatus.installationId -eq [string]$local.installationId -and
            [string]$watcherStatus.status -eq 'RUNNING'
        Add-Check 'Live startup watcher' $watcherHealthy "pid=$($watcherRecord.processId) status=$($watcherStatus.status) installation=$($watcherStatus.installationId)"
    }
}
catch {
    Add-Check 'Verifier execution' $false $_.Exception.Message
}

$overall = if (@($checks | Where-Object Status -eq 'FAIL').Count -eq 0) { 'PASS' } else { 'FAIL' }
$result = [pscustomobject]@{ Overall = $overall; Checks = $checks }
if ($AsJson) { $result | ConvertTo-Json -Depth 10 } else { $result }
if ($overall -ne 'PASS') { exit 1 }
