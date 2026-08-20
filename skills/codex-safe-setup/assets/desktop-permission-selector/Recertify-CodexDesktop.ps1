#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StatePath,
    [Parameter(DontShow)][string]$InstallLocation,
    [Parameter(DontShow)][string]$PackageVersion,
    [Parameter(DontShow)][switch]$AllowUnsignedTestFixture,
    [Parameter(DontShow)][switch]$SkipRuntimeProbe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$loaderRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSCommandPath))
. (Join-Path $loaderRoot 'DesktopPermissionSelector.Common.ps1')

$resolvedStatePath = [IO.Path]::GetFullPath($StatePath)
$statusPath = Join-Path $loaderRoot 'last-recertification-status.json'

function ConvertTo-CssOrderedRecord {
    param([Parameter(Mandatory)]$InputObject)
    $record = [ordered]@{}
    foreach ($property in $InputObject.PSObject.Properties) { $record[$property.Name] = $property.Value }
    return $record
}

function Write-CssRecertificationStatus {
    param([string]$Status, [string]$Message, [Management.Automation.ErrorRecord]$ErrorRecord)
    $record = [ordered]@{
        status = $Status
        message = $Message
        timestampUtc = [DateTime]::UtcNow.ToString('o')
    }
    if ($null -ne $ErrorRecord) { $record.errorType = $ErrorRecord.Exception.GetType().FullName }
    Write-CssFileTextAtomic -Path $statusPath -Text ($record | ConvertTo-Json -Depth 10)
}

function Assert-CssSameValue {
    param([string]$Name, [string]$Expected, [string]$Actual)
    if (-not $Expected -or -not $Actual -or -not $Expected.Equals($Actual, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Official package identity mismatch for $Name."
    }
}

function Invoke-CssRendererPreloadProbe {
    param(
        [Parameter(Mandatory)]$Package,
        [Parameter(Mandatory)]$LocalState,
        [Parameter(Mandatory)][string]$LoaderPath,
        [Parameter(Mandatory)][string]$PreloadPath
    )

    $probeRoot = Join-Path ([IO.Path]::GetTempPath()) ('css-selector-recertify-probe-' + [guid]::NewGuid().ToString('N'))
    $appRoot = Join-Path $probeRoot 'app'
    $userDataRoot = Join-Path $probeRoot 'user-data'
    $appOutput = Join-Path $probeRoot 'app-result.json'
    $loaderOutput = Join-Path $probeRoot 'loader-result.json'
    New-Item -ItemType Directory -Path $appRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $userDataRoot -Force | Out-Null
    try {
        [IO.File]::WriteAllText((Join-Path $appRoot 'package.json'), '{"name":"codex-safe-setup-selector-recertify-probe","version":"1.0.0","main":"main.cjs"}', [Text.UTF8Encoding]::new($false))
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
  fs.writeFileSync(process.env.CSS_SELECTOR_PROBE_APP_OUTPUT, JSON.stringify(result), 'utf8');
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
        if ($null -eq $process -or -not $process.WaitForExit(15000)) {
            if ($null -ne $process) { try { $process.Kill() } catch { } }
            throw 'Document-start renderer compatibility probe timed out.'
        }
        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $appOutput -PathType Leaf) -or
            -not (Test-Path -LiteralPath $loaderOutput -PathType Leaf)) {
            throw "Document-start renderer compatibility probe failed (exit $($process.ExitCode))."
        }
        $appResult = [IO.File]::ReadAllText($appOutput) | ConvertFrom-Json -Depth 10
        $loaderResult = [IO.File]::ReadAllText($loaderOutput) | ConvertFrom-Json -Depth 10
        if (-not [bool]$appResult.overrideAtFirstScript -or -not [bool]$appResult.selectedGate -or
            [bool]$appResult.otherGate -or [string]$loaderResult.status -ne 'PRELOAD_ACTIVE') {
            throw 'Document-start renderer compatibility probe did not preserve the required gate boundary.'
        }
        return [pscustomobject]@{ App = $appResult; Loader = $loaderResult }
    }
    finally {
        if (Test-Path -LiteralPath $probeRoot) {
            $resolvedProbe = [IO.Path]::GetFullPath($probeRoot)
            $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
            if (Test-CssPathWithin -Path $resolvedProbe -Root $resolvedTemp) {
                Remove-Item -LiteralPath $resolvedProbe -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

$mutex = [Threading.Mutex]::new($false, 'Local\CodexSafeSetupDesktopRecertification')
$acquired = $false
try {
    $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds(45))
    if (-not $acquired) { throw 'Another Desktop update recertification did not finish in time.' }
    if (-not (Test-Path -LiteralPath $resolvedStatePath -PathType Leaf)) { throw 'Local compatibility state is missing.' }
    $oldLocalText = [IO.File]::ReadAllText($resolvedStatePath)
    $local = $oldLocalText | ConvertFrom-Json -Depth 50
    if ([int]$local.stateSchemaVersion -ne 3 -or [string]$local.mode -ne 'ProcessScopedSessionPreload') {
        throw 'Automatic recertification requires schema-3 loader state.'
    }
    if (-not [IO.Path]::GetFullPath([string]$local.destinationRoot).Equals($loaderRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Local compatibility state points at a different loader root.'
    }

    $package = Get-CssDesktopPackageInfo -InstallLocation $InstallLocation -PackageVersion $PackageVersion
    Assert-CssSameValue -Name 'package name' -Expected ([string]$local.sourcePackageName) -Actual ([string]$package.PackageName)
    Assert-CssSameValue -Name 'package family' -Expected ([string]$local.sourcePackageFamilyName) -Actual ([string]$package.PackageFamilyName)
    Assert-CssSameValue -Name 'publisher id' -Expected ([string]$local.sourcePublisherId) -Actual ([string]$package.PublisherId)
    Assert-CssSameValue -Name 'publisher' -Expected ([string]$local.sourcePublisher) -Actual ([string]$package.Publisher)

    $synthetic = [bool]$local.syntheticUnsignedTestFixture
    if ($synthetic) {
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $AllowUnsignedTestFixture -or -not $InstallLocation -or -not $SkipRuntimeProbe -or
            -not (Test-CssPathWithin -Path $package.InstallLocation -Root $tempRoot) -or
            -not (Test-CssPathWithin -Path $loaderRoot -Root $tempRoot)) {
            throw 'Synthetic recertification is restricted to explicit, isolated temporary test fixtures.'
        }
        $signerThumbprint = $null
        $signerSubject = 'SYNTHETIC-UNSIGNED-TEST-FIXTURE'
    }
    else {
        if ($InstallLocation -or $PackageVersion -or $AllowUnsignedTestFixture -or $SkipRuntimeProbe) {
            throw 'Production recertification does not accept fixture overrides or skipped probes.'
        }
        $signature = Get-AuthenticodeSignature -LiteralPath $package.ExecutablePath
        if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or $null -eq $signature.SignerCertificate) {
            throw 'The updated Desktop executable does not have a valid Authenticode signature.'
        }
        $signerThumbprint = [string]$signature.SignerCertificate.Thumbprint
        $signerSubject = [string]$signature.SignerCertificate.Subject
        Assert-CssSameValue -Name 'signer subject' -Expected ([string]$local.trustedSignerSubject) -Actual $signerSubject
    }

    $loaderPath = Join-Path $loaderRoot 'permission-selector-loader.cjs'
    $preloadPath = Join-Path $loaderRoot 'permission-selector-preload.cjs'
    if ((Get-CssFileSha256 -Path $loaderPath) -ne [string]$local.loaderSha256 -or
        (Get-CssFileSha256 -Path $preloadPath) -ne [string]$local.preloadSha256) {
        throw 'Loader assets changed before update recertification.'
    }

    $sourceEvidence = Get-CssDesktopSelectorSourceEvidence -ArchivePath $package.AsarPath
    if ([int]$sourceEvidence.StructureVersion -ne [int]$local.selectorStructureVersion) {
        throw 'The updated Desktop selector structure version is incompatible.'
    }

    if ($synthetic) {
        $mainProbeStatus = 'SKIPPED_SYNTHETIC_FIXTURE'
        $rendererProbeStatus = 'SKIPPED_SYNTHETIC_FIXTURE'
    }
    else {
        $mainProbe = Invoke-CssDesktopSelectorNodeOptionsProbe -ExecutablePath $package.ExecutablePath -LoaderPath $loaderPath -PreloadPath $preloadPath -PreloadSha256 ([string]$local.preloadSha256)
        $rendererProbe = Invoke-CssRendererPreloadProbe -Package $package -LocalState $local -LoaderPath $loaderPath -PreloadPath $preloadPath
        $mainProbeStatus = [string]$mainProbe.status
        $rendererProbeStatus = [string]$rendererProbe.Loader.status
    }

    $pointerPath = Join-Path ([IO.Path]::GetFullPath([string]$local.stateRoot)) 'desktop-selector-fix.json'
    if (-not (Test-Path -LiteralPath $pointerPath -PathType Leaf)) { throw 'Compatibility pointer state is missing.' }
    $oldPointerText = [IO.File]::ReadAllText($pointerPath)
    $pointer = $oldPointerText | ConvertFrom-Json -Depth 50
    if ([string]$pointer.installationId -ne [string]$local.installationId) { throw 'Pointer and local state disagree before recertification.' }

    $now = [DateTime]::UtcNow.ToString('o')
    $newLocal = ConvertTo-CssOrderedRecord -InputObject $local
    $newPointer = ConvertTo-CssOrderedRecord -InputObject $pointer
    foreach ($record in @($newLocal, $newPointer)) {
        $record.sourcePackageVersion = [string]$package.Version
        $record.sourceInstallLocation = [string]$package.InstallLocation
        $record.sourceExecutableSha256 = Get-CssFileSha256 -Path $package.ExecutablePath
        $record.sourceAsarSha256 = Get-CssFileSha256 -Path $package.AsarPath
        $record.trustedSignerThumbprint = $signerThumbprint
        $record.trustedSignerSubject = $signerSubject
        $record.lastRecertifiedUtc = $now
        $record.recertificationCount = [int]$local.recertificationCount + 1
    }
    $newLocal.selectorAssets = @($sourceEvidence.Assets)
    $newLocal.selectorStructureAnchors = @($sourceEvidence.StructureAnchors)
    $newLocal.nodeOptionsProbeStatus = $mainProbeStatus
    $newLocal.rendererProbeStatus = $rendererProbeStatus

    try {
        Write-CssFileTextAtomic -Path $pointerPath -Text ($newPointer | ConvertTo-Json -Depth 50)
        Write-CssFileTextAtomic -Path $resolvedStatePath -Text ($newLocal | ConvertTo-Json -Depth 50)
    }
    catch {
        Write-CssFileTextAtomic -Path $pointerPath -Text $oldPointerText
        Write-CssFileTextAtomic -Path $resolvedStatePath -Text $oldLocalText
        throw
    }
    Write-CssRecertificationStatus -Status 'RECERTIFIED' -Message "Accepted compatible signed Codex Desktop $($package.Version)."
}
catch {
    Write-CssRecertificationStatus -Status 'REJECTED' -Message $_.Exception.Message -ErrorRecord $_
    throw
}
finally {
    if ($acquired) { [void]$mutex.ReleaseMutex() }
    $mutex.Dispose()
}
