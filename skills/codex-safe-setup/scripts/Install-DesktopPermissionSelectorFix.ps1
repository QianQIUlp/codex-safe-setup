#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$CodexHome,
    [string]$StateRoot,
    [string]$DestinationRoot,
    [string]$InstallLocation,
    [string]$PackageVersion,
    [switch]$SkipShortcuts,
    [Parameter(DontShow)][switch]$AllowUnsignedTestFixture,
    [switch]$PlanOnly,
    [switch]$ConfirmApply,
    [switch]$AcknowledgeUnsupportedDesktopOverride,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'DesktopPermissionSelector.Common.ps1')

if ($env:OS -ne 'Windows_NT') {
    throw 'The Desktop permission-selector compatibility fix is Windows-only.'
}

$resolvedCodexHome = [IO.Path]::GetFullPath((Get-CssCodexHome -Override $CodexHome))
$resolvedStateRoot = [IO.Path]::GetFullPath((Get-CssStateRoot -CodexHome $resolvedCodexHome -Override $StateRoot))
if (-not $DestinationRoot) { $DestinationRoot = Join-Path $resolvedCodexHome 'desktop-selector-loader' }
$resolvedDestination = [IO.Path]::GetFullPath($DestinationRoot)
if (-not (Test-CssPathWithin -Path $resolvedStateRoot -Root $resolvedCodexHome) -or
    $resolvedStateRoot.Equals($resolvedCodexHome, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'StateRoot must be a child of CodexHome for this compatibility fix.'
}
if (-not (Test-CssPathWithin -Path $resolvedDestination -Root $resolvedCodexHome) -or
    $resolvedDestination.Equals($resolvedCodexHome, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'DestinationRoot must be a child of CodexHome for this compatibility fix.'
}

$package = Get-CssDesktopPackageInfo -InstallLocation $InstallLocation -PackageVersion $PackageVersion
$packageSignature = Get-AuthenticodeSignature -LiteralPath $package.ExecutablePath
$trustedSignerThumbprint = $null
$trustedSignerSubject = $null
$syntheticUnsignedFixture = $false
if ($packageSignature.Status -eq [Management.Automation.SignatureStatus]::Valid -and $null -ne $packageSignature.SignerCertificate) {
    $trustedSignerThumbprint = [string]$packageSignature.SignerCertificate.Thumbprint
    $trustedSignerSubject = [string]$packageSignature.SignerCertificate.Subject
}
else {
    $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $syntheticUnsignedFixture = $AllowUnsignedTestFixture -and $SkipShortcuts -and
        (Test-CssPathWithin -Path $package.InstallLocation -Root $systemTemp) -and
        (Test-CssPathWithin -Path $resolvedDestination -Root $systemTemp)
    if (-not $syntheticUnsignedFixture) {
        throw 'The source Desktop executable does not have a valid Authenticode signature. Refusing to install the process-scoped loader.'
    }
    $trustedSignerSubject = 'SYNTHETIC-UNSIGNED-TEST-FIXTURE'
}

foreach ($identityValue in @($package.PackageName, $package.PackageFamilyName, $package.PublisherId, $package.Publisher)) {
    if (-not [string]$identityValue) { throw 'The Desktop package identity is incomplete. Refusing to install the loader.' }
}

$sourceAsarHash = Get-CssFileSha256 -Path $package.AsarPath
$sourceExecutableHash = Get-CssFileSha256 -Path $package.ExecutablePath
$sourceEvidence = Get-CssDesktopSelectorSourceEvidence -ArchivePath $package.AsarPath
$assetsRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\desktop-permission-selector'
$assetSources = [ordered]@{
    $script:CssDesktopSelectorLoaderFile = Join-Path $assetsRoot $script:CssDesktopSelectorLoaderFile
    $script:CssDesktopSelectorPreloadFile = Join-Path $assetsRoot $script:CssDesktopSelectorPreloadFile
    'Start-CodexFixed.ps1' = Join-Path $assetsRoot 'Start-CodexFixed.ps1'
    'Start-CodexFixed.vbs' = Join-Path $assetsRoot 'Start-CodexFixed.vbs'
    'Watch-CodexDesktop.ps1' = Join-Path $assetsRoot 'Watch-CodexDesktop.ps1'
    'Watch-CodexDesktop.vbs' = Join-Path $assetsRoot 'Watch-CodexDesktop.vbs'
    'Recertify-CodexDesktop.ps1' = Join-Path $assetsRoot 'Recertify-CodexDesktop.ps1'
    'DesktopPermissionSelector.Common.ps1' = Join-Path $PSScriptRoot 'DesktopPermissionSelector.Common.ps1'
}
foreach ($assetName in $assetSources.Keys) {
    $asset = $assetSources[$assetName]
    if (-not (Test-Path -LiteralPath $asset -PathType Leaf)) { throw "Packaged compatibility asset is missing: $asset" }
}
$estimatedBytes = ($assetSources.Values | ForEach-Object { (Get-Item -LiteralPath $_).Length } | Measure-Object -Sum).Sum
$powerShell7Path = [IO.Path]::GetFullPath((Get-Command pwsh.exe -ErrorAction Stop).Source)

Write-Output 'Desktop permission-selector compatibility plan:'
Write-Output "- Source: signed OpenAI.Codex Desktop $($package.Version) at $($package.InstallLocation)"
if ($syntheticUnsignedFixture) { Write-Output '- Source signature: synthetic unsigned unit-test fixture (temporary paths only).' }
else { Write-Output "- Source signer thumbprint: $trustedSignerThumbprint" }
Write-Output "- Destination: $resolvedDestination"
Write-Output "- Local disk requirement: approximately $([Math]::Ceiling($estimatedBytes / 1KB)) KiB; no Desktop application copy is created."
Write-Output "- Confirm the signed app.asar contains selector gate $($sourceEvidence.SelectorGate) and the tested selector structure, then pin the official package identity and exact source bytes."
Write-Output '- Launch the original signed Desktop with a process-scoped NODE_OPTIONS loader; add one session preload before the first renderer script runs.'
Write-Output '- Preserve existing Electron session preloads and any pre-existing NODE_OPTIONS value; do not set a user or machine environment variable.'
Write-Output '- Do not modify or redistribute any file under the signed WindowsApps package, any ASAR, renderer bundle, executable, or DLL.'
Write-Output '- A later official Desktop update is accepted automatically only after identity, signature, selector-structure, main-process, and document-start probes pass; incompatible updates fail closed without changing the prior pins.'
if (-not $SkipShortcuts) {
    Write-Output '- Add a dedicated Start Menu shortcut and a per-user startup watcher. The task running during installation is explicitly exempt from redirection until it exits.'
}
Write-Output '- Preserve any previous loader generation and any legacy derived client copy in recoverable history.'

if ($PlanOnly) {
    Write-Output 'No files changed (PlanOnly).'
    return
}
if (-not $AcknowledgeUnsupportedDesktopOverride) {
    if ($NonInteractive) { throw 'Installation requires -AcknowledgeUnsupportedDesktopOverride.' }
    $answer = Read-Host 'This uses an undocumented Desktop feature gate and installs a process-scoped preload plus startup watcher. Type I UNDERSTAND to continue'
    if ($answer -cne 'I UNDERSTAND') { throw 'Desktop override acknowledgement was not provided.' }
}
if (-not $ConfirmApply) {
    if ($NonInteractive) { throw 'Non-interactive installation requires -ConfirmApply.' }
    $answer = Read-Host 'Type APPLY to install the lightweight Desktop selector loader'
    if ($answer -cne 'APPLY') { throw 'Installation was not confirmed.' }
}

New-Item -ItemType Directory -Path $resolvedStateRoot -Force | Out-Null
$stagingRoot = Join-Path $resolvedStateRoot ('desktop-selector-loader-staging-' + [guid]::NewGuid().ToString('N'))
$historyRoot = Join-Path $resolvedStateRoot 'desktop-selector-fix-history'
$pointerPath = Join-Path $resolvedStateRoot $script:CssDesktopSelectorStateFile
$legacyRoot = Join-Path $resolvedCodexHome 'desktop-ui-fix'
if ($legacyRoot.Equals($resolvedDestination, [StringComparison]::OrdinalIgnoreCase)) { $legacyRoot = $null }
$legacyAppDirectory = if ($legacyRoot) { Join-Path $legacyRoot 'app' } else { $null }
$legacyPresent = $legacyRoot -and (Test-Path -LiteralPath $legacyRoot -PathType Container)
$installationTimestamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$legacyArchivePath = if ($legacyPresent) { Join-Path $historyRoot ($installationTimestamp + '-legacy-derived-copy') } else { $null }
$previousPointer = $null
$previousRoot = $null
$activatedNew = $false
$pointerWritten = $false
$shortcutsWritten = [Collections.Generic.List[string]]::new()

try {
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
    foreach ($assetName in $assetSources.Keys) {
        Copy-Item -LiteralPath $assetSources[$assetName] -Destination (Join-Path $stagingRoot $assetName) -Force
    }
    $loaderStaging = Join-Path $stagingRoot $script:CssDesktopSelectorLoaderFile
    $preloadStaging = Join-Path $stagingRoot $script:CssDesktopSelectorPreloadFile
    $loaderHash = Get-CssFileSha256 -Path $loaderStaging
    $preloadHash = Get-CssFileSha256 -Path $preloadStaging
    $probeEvidence = if ($syntheticUnsignedFixture) {
        [pscustomobject]@{ status = 'SKIPPED_SYNTHETIC_FIXTURE'; electronAppAvailable = $null }
    }
    else {
        Invoke-CssDesktopSelectorNodeOptionsProbe -ExecutablePath $package.ExecutablePath -LoaderPath $loaderStaging -PreloadPath $preloadStaging -PreloadSha256 $preloadHash
    }

    if (Test-Path -LiteralPath $pointerPath -PathType Leaf) {
        $previousPointer = [IO.File]::ReadAllText($pointerPath) | ConvertFrom-Json -Depth 30
    }
    if ($previousPointer -and $previousPointer.destinationRoot) {
        $previousDestination = [IO.Path]::GetFullPath([string]$previousPointer.destinationRoot)
        if (Test-CssPathWithin -Path $previousDestination -Root $resolvedCodexHome) {
            [void](Stop-CssDesktopSelectorWatcher -DestinationRoot $previousDestination)
        }
    }
    if ($legacyPresent) { [void](Stop-CssDesktopSelectorWatcher -DestinationRoot $legacyRoot) }

    $rootProcesses = @(Get-CssDesktopRootProcesses -ExecutablePath $package.ExecutablePath)
    $graceProcesses = @($rootProcesses | ForEach-Object {
        [ordered]@{ processId = [int]$_.ProcessId; creationDate = [string]$_.CreationDate }
    })

    if (Test-Path -LiteralPath $resolvedDestination) {
        New-Item -ItemType Directory -Path $historyRoot -Force | Out-Null
        $previousRoot = Join-Path $historyRoot ($installationTimestamp + '-previous-loader')
        if (Test-Path -LiteralPath $previousRoot) { throw "Recovery target already exists: $previousRoot" }
        Move-Item -LiteralPath $resolvedDestination -Destination $previousRoot
    }
    Move-Item -LiteralPath $stagingRoot -Destination $resolvedDestination
    $stagingRoot = $null
    $activatedNew = $true

    $loaderPath = Join-Path $resolvedDestination $script:CssDesktopSelectorLoaderFile
    $preloadPath = Join-Path $resolvedDestination $script:CssDesktopSelectorPreloadFile
    $nodeRequirePath = Get-CssNodeRequirePath -Path $loaderPath
    $installationId = [guid]::NewGuid().ToString('N')
    $localState = [ordered]@{
        stateSchemaVersion = 3
        productVersion = '0.2.0'
        mode = 'ProcessScopedSessionPreload'
        installationId = $installationId
        installedUtc = [DateTime]::UtcNow.ToString('o')
        codexHome = $resolvedCodexHome
        stateRoot = $resolvedStateRoot
        destinationRoot = $resolvedDestination
        sourcePackageVersion = [string]$package.Version
        sourcePackageName = [string]$package.PackageName
        sourcePackageFamilyName = [string]$package.PackageFamilyName
        sourcePublisherId = [string]$package.PublisherId
        sourcePublisher = [string]$package.Publisher
        sourceInstallLocation = [string]$package.InstallLocation
        sourceExecutableSha256 = $sourceExecutableHash
        sourceAsarSha256 = $sourceAsarHash
        trustedSignerThumbprint = $trustedSignerThumbprint
        trustedSignerSubject = $trustedSignerSubject
        syntheticUnsignedTestFixture = $syntheticUnsignedFixture
        selectorGate = $script:CssDesktopSelectorGate
        selectorAssets = @($sourceEvidence.Assets)
        selectorStructureVersion = [int]$sourceEvidence.StructureVersion
        selectorStructureAnchors = @($sourceEvidence.StructureAnchors)
        loaderSha256 = $loaderHash
        preloadSha256 = $preloadHash
        nodeRequirePath = $nodeRequirePath
        launcherSha256 = Get-CssFileSha256 -Path (Join-Path $resolvedDestination 'Start-CodexFixed.ps1')
        watcherSha256 = Get-CssFileSha256 -Path (Join-Path $resolvedDestination 'Watch-CodexDesktop.ps1')
        recertifierSha256 = Get-CssFileSha256 -Path (Join-Path $resolvedDestination 'Recertify-CodexDesktop.ps1')
        compatibilityCommonSha256 = Get-CssFileSha256 -Path (Join-Path $resolvedDestination 'DesktopPermissionSelector.Common.ps1')
        powerShell7Path = $powerShell7Path
        nodeOptionsProbeStatus = [string]$probeEvidence.status
        rendererProbeStatus = 'PENDING_INSTALL_VERIFICATION'
        recertificationCount = 0
        lastRecertifiedUtc = $null
        graceProcesses = $graceProcesses
        legacyDerivedRoot = $legacyRoot
        legacyDerivedAppDirectory = $legacyAppDirectory
        legacyArchivePath = $legacyArchivePath
    }
    [IO.File]::WriteAllText(
        (Join-Path $resolvedDestination $script:CssDesktopSelectorLocalStateFile),
        ($localState | ConvertTo-Json -Depth 30),
        [Text.UTF8Encoding]::new($false)
    )

    $startMenuShortcut = $null
    $startupShortcut = $null
    if (-not $SkipShortcuts) {
        $wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
        $shell = New-Object -ComObject WScript.Shell
        $startMenuShortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Codex (Stable Permissions).lnk'
        $startupShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex Safe Setup Desktop Selector.lnk'
        $start = $shell.CreateShortcut($startMenuShortcut)
        $start.TargetPath = $wscript
        $start.Arguments = '"' + (Join-Path $resolvedDestination 'Start-CodexFixed.vbs') + '"'
        $start.WorkingDirectory = $resolvedDestination
        $start.Save()
        $shortcutsWritten.Add($startMenuShortcut)
        $watch = $shell.CreateShortcut($startupShortcut)
        $watch.TargetPath = $wscript
        $watch.Arguments = '"' + (Join-Path $resolvedDestination 'Watch-CodexDesktop.vbs') + '"'
        $watch.WorkingDirectory = $resolvedDestination
        $watch.Save()
        $shortcutsWritten.Add($startupShortcut)
    }

    $pointerState = [ordered]@{
        stateSchemaVersion = 3
        productVersion = '0.2.0'
        mode = 'ProcessScopedSessionPreload'
        active = $true
        installationId = $installationId
        installedUtc = $localState.installedUtc
        codexHome = $resolvedCodexHome
        stateRoot = $resolvedStateRoot
        destinationRoot = $resolvedDestination
        sourcePackageVersion = [string]$package.Version
        sourcePackageName = [string]$package.PackageName
        sourcePackageFamilyName = [string]$package.PackageFamilyName
        sourcePublisherId = [string]$package.PublisherId
        sourcePublisher = [string]$package.Publisher
        sourceInstallLocation = [string]$package.InstallLocation
        sourceExecutableSha256 = $sourceExecutableHash
        sourceAsarSha256 = $sourceAsarHash
        trustedSignerThumbprint = $trustedSignerThumbprint
        trustedSignerSubject = $trustedSignerSubject
        syntheticUnsignedTestFixture = $syntheticUnsignedFixture
        recertificationCount = 0
        lastRecertifiedUtc = $null
        startMenuShortcut = $startMenuShortcut
        startupShortcut = $startupShortcut
        legacyDerivedRoot = $legacyRoot
        legacyArchivePath = $legacyArchivePath
        previousRoot = $previousRoot
        previousPointerState = $previousPointer
    }
    Write-CssTextAtomic -Path $pointerPath -Text ($pointerState | ConvertTo-Json -Depth 30)
    $pointerWritten = $true

    if (-not $SkipShortcuts) {
        $wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
        Start-Process -FilePath $wscript -ArgumentList @('"' + (Join-Path $resolvedDestination 'Watch-CodexDesktop.vbs') + '"') -WindowStyle Hidden | Out-Null
        $watcherPidPath = Join-Path $resolvedDestination 'watcher.pid.json'
        $watcherReady = $false
        $watcherDeadline = (Get-Date).AddSeconds(8)
        do {
            Start-Sleep -Milliseconds 100
            try {
                $watcherRecord = [IO.File]::ReadAllText($watcherPidPath) | ConvertFrom-Json
                $watcherProcess = Get-CimInstance Win32_Process -Filter ("ProcessId = {0}" -f [int]$watcherRecord.processId) -ErrorAction SilentlyContinue
                $watcherReady = $null -ne $watcherProcess -and
                    [string]$watcherRecord.installationId -eq $installationId -and
                    ([string]$watcherProcess.CommandLine).IndexOf((Join-Path $resolvedDestination 'Watch-CodexDesktop.ps1'), [StringComparison]::OrdinalIgnoreCase) -ge 0
            }
            catch { $watcherReady = $false }
        } while (-not $watcherReady -and (Get-Date) -lt $watcherDeadline)
        if (-not $watcherReady) {
            throw 'The per-user Desktop watcher did not remain active after installation.'
        }
    }
    Write-Output "Installed and verified lightweight Desktop selector loader: $resolvedDestination"
    if (@($graceProcesses).Length -gt 0) {
        Write-Output 'The currently running Desktop task was preserved. The process-scoped loader activates automatically after that task exits and Desktop is launched again.'
    }
    else {
        Write-Output 'Activation is ready for the next Desktop launch.'
    }
}
catch {
    if ($stagingRoot -and (Test-Path -LiteralPath $stagingRoot) -and
        (Test-CssPathWithin -Path $stagingRoot -Root $resolvedStateRoot)) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
    if ($activatedNew -and (Test-Path -LiteralPath $resolvedDestination)) {
        [void](Stop-CssDesktopSelectorWatcher -DestinationRoot $resolvedDestination)
        New-Item -ItemType Directory -Path $historyRoot -Force | Out-Null
        $failedRoot = Join-Path $historyRoot ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-failed-loader-install')
        Move-Item -LiteralPath $resolvedDestination -Destination $failedRoot
    }
    if (-not (Test-Path -LiteralPath $resolvedDestination) -and $previousRoot -and (Test-Path -LiteralPath $previousRoot)) {
        Move-Item -LiteralPath $previousRoot -Destination $resolvedDestination
    }
    if ($pointerWritten) {
        if ($null -ne $previousPointer) {
            Write-CssTextAtomic -Path $pointerPath -Text ($previousPointer | ConvertTo-Json -Depth 30)
        }
        elseif (Test-Path -LiteralPath $pointerPath -PathType Leaf) {
            Move-Item -LiteralPath $pointerPath -Destination (Join-Path $historyRoot ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-failed-loader-install.json'))
        }
    }
    foreach ($shortcutPath in $shortcutsWritten) {
        if (Test-Path -LiteralPath $shortcutPath -PathType Leaf) {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($shortcutPath)
            if (([string]$shortcut.Arguments).IndexOf($resolvedDestination, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                Remove-Item -LiteralPath $shortcutPath -Force
            }
        }
    }
    throw
}
