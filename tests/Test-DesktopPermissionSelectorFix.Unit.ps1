#requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptRoot = Join-Path $projectRoot 'skills\codex-safe-setup\scripts'
$commonScript = Join-Path $scriptRoot 'DesktopPermissionSelector.Common.ps1'
$installScript = Join-Path $scriptRoot 'Install-DesktopPermissionSelectorFix.ps1'
$testScript = Join-Path $scriptRoot 'Test-DesktopPermissionSelectorFix.ps1'
$rollbackScript = Join-Path $scriptRoot 'Rollback-DesktopPermissionSelectorFix.ps1'
$recertifierAsset = Join-Path $projectRoot 'skills\codex-safe-setup\assets\desktop-permission-selector\Recertify-CodexDesktop.ps1'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('css desktop selector tests ' + [guid]::NewGuid().ToString('N'))
. $commonScript

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Get-BytesSha256([byte[]]$Bytes) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}

function Get-FileFingerprint([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '<missing>' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function New-AsarFixture {
    param(
        [string]$PackageRoot,
        [string]$PackageVersion = '26.999.1.0',
        [switch]$MissingGate,
        [switch]$MissingGateIntegrity,
        [switch]$MissingStructureAnchor,
        [switch]$UnsafeEntry
    )

    $resourceRoot = Join-Path $PackageRoot 'app\resources'
    New-Item -ItemType Directory -Path $resourceRoot -Force | Out-Null
    $manifest = '<Package><Identity Name="OpenAI.Codex" Publisher="CN=50BDFD77-8903-4850-9FFE-6E8522F64D5B" PublisherId="2p2nqsd0c76g0" PackageFamilyName="OpenAI.Codex_2p2nqsd0c76g0" Version="' + $PackageVersion + '" /></Package>'
    [IO.File]::WriteAllText((Join-Path $PackageRoot 'AppxManifest.xml'), $manifest, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $PackageRoot 'app\ChatGPT.exe'), 'fixture', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $resourceRoot 'codex.exe'), 'fixture', [Text.UTF8Encoding]::new($false))
    $archivePath = Join-Path $resourceRoot 'app.asar'
    $utf8 = [Text.UTF8Encoding]::new($false)
    $structureText = if ($MissingStructureAnchor) {
        'useAppServerPermissionDefault permissionProfileId disableDefaultPermissions'
    }
    else {
        'useAppServerPermissionDefault permissionProfileId disableDefaultPermissions disableCustomPermissions'
    }
    $gateValue = if ($MissingGate) { 'not-present' } else { '4226282475' }
    $gateText = 'const permissionSelectorGate="{0}"; {1}' -f $gateValue, $structureText
    $fixtureFiles = [ordered]@{
        'package.json' = $utf8.GetBytes('{"name":"fixture"}')
        'webview/assets/app.js' = $utf8.GetBytes($gateText)
    }
    if ($UnsafeEntry) { $fixtureFiles = [ordered]@{ '..' = $utf8.GetBytes('unsafe') } }

    $root = [ordered]@{ files = [ordered]@{} }
    $offset = 0L
    $payload = [Collections.Generic.List[byte]]::new()
    foreach ($entry in $fixtureFiles.GetEnumerator()) {
        $parts = $entry.Key -split '/'
        $node = $root
        for ($index = 0; $index -lt $parts.Count - 1; $index++) {
            $part = $parts[$index]
            if (-not $node.files.Contains($part)) { $node.files[$part] = [ordered]@{ files = [ordered]@{} } }
            $node = $node.files[$part]
        }
        $record = [ordered]@{ size = $entry.Value.Length; offset = [string]$offset }
        if (-not ($MissingGateIntegrity -and $entry.Key -eq 'webview/assets/app.js')) {
            $hash = Get-BytesSha256 -Bytes $entry.Value
            $record.integrity = [ordered]@{ algorithm = 'SHA256'; hash = $hash; blockSize = 4194304; blocks = @($hash) }
        }
        $node.files[$parts[-1]] = $record
        $payload.AddRange([byte[]]$entry.Value)
        $offset += $entry.Value.Length
    }

    $jsonBytes = $utf8.GetBytes(($root | ConvertTo-Json -Depth 30 -Compress))
    $alignedJsonLength = [int](4 * [Math]::Ceiling($jsonBytes.Length / 4.0))
    $headerPayloadSize = 4 + $alignedJsonLength
    $headerPickleSize = 4 + $headerPayloadSize
    $stream = [IO.File]::Open($archivePath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        foreach ($number in @([uint32]4, [uint32]$headerPickleSize, [uint32]$headerPayloadSize, [uint32]$jsonBytes.Length)) {
            $bytes = [BitConverter]::GetBytes($number)
            $stream.Write($bytes, 0, $bytes.Length)
        }
        $stream.Write($jsonBytes, 0, $jsonBytes.Length)
        $padding = New-Object byte[] ($alignedJsonLength - $jsonBytes.Length)
        if ($padding.Length -gt 0) { $stream.Write($padding, 0, $padding.Length) }
        $payloadBytes = $payload.ToArray()
        $stream.Write($payloadBytes, 0, $payloadBytes.Length)
    }
    finally { $stream.Dispose() }
    return $archivePath
}

try {
    $realShortcutPaths = @(
        (Join-Path ([Environment]::GetFolderPath('Programs')) 'Codex (Stable Permissions).lnk'),
        (Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex Safe Setup Desktop Selector.lnk')
    )
    $realShortcutFingerprints = @($realShortcutPaths | ForEach-Object { Get-FileFingerprint -Path $_ })
    $packageRoot = Join-Path $temporaryRoot 'package source'
    $archivePath = New-AsarFixture -PackageRoot $packageRoot
    $codexHome = Join-Path $temporaryRoot 'codex home'
    $stateRoot = Join-Path $codexHome 'safe-setup'
    $destination = Join-Path $codexHome 'desktop selector loader'

    $launcherAssetPath = Join-Path $projectRoot 'skills\codex-safe-setup\assets\desktop-permission-selector\Start-CodexFixed.ps1'
    $launcherTokens = $null
    $launcherErrors = $null
    $launcherAst = [Management.Automation.Language.Parser]::ParseFile($launcherAssetPath, [ref]$launcherTokens, [ref]$launcherErrors)
    Assert-True ($launcherErrors.Count -eq 0) 'The Windows PowerShell launcher asset must parse.'
    $hashFunctionAst = $launcherAst.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-RecordedHash'
    }, $true)
    Assert-True ($null -ne $hashFunctionAst) 'The launcher must define Test-RecordedHash.'
    $hashFixturePath = Join-Path $temporaryRoot 'launcher hash fixture.txt'
    [IO.File]::WriteAllText($hashFixturePath, 'module-independent-hash-probe', [Text.UTF8Encoding]::new($false))
    $expectedFixtureHash = Get-CssFileSha256 -Path $hashFixturePath
    $escapedHashFixturePath = $hashFixturePath.Replace("'", "''")
    $hashProbePath = Join-Path $temporaryRoot 'windows-powershell-hash-probe.ps1'
    $hashProbe = @"
`$env:PSModulePath = ''
Get-Module Microsoft.PowerShell.Utility | Remove-Module -Force -ErrorAction SilentlyContinue
$($hashFunctionAst.Extent.Text)
if (-not (Test-RecordedHash -Path '$escapedHashFixturePath' -Expected '$expectedFixtureHash')) { exit 91 }
if (Test-RecordedHash -Path '$escapedHashFixturePath' -Expected ('$([string]'0' * 64)')) { exit 92 }
"@
    [IO.File]::WriteAllText($hashProbePath, $hashProbe, [Text.UTF8Encoding]::new($false))
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $hashProbeOutput = @(& $windowsPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $hashProbePath 2>&1)
    $hashProbeExitCode = $LASTEXITCODE
    Assert-True ($hashProbeExitCode -eq 0) "The launcher hash check must work without PowerShell module discovery. exit=$hashProbeExitCode output=$($hashProbeOutput -join ' | ')"

    $countFunctionAst = $launcherAst.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-SequenceCount'
    }, $true)
    Assert-True ($null -ne $countFunctionAst) 'The launcher must normalize live process query results before counting them.'
    $countProbePath = Join-Path $temporaryRoot 'windows-powershell-count-probe.ps1'
    $countProbe = @"
Set-StrictMode -Version Latest
$($countFunctionAst.Extent.Text)
if ((Get-SequenceCount -Value `$null) -ne 0) { exit 93 }
if ((Get-SequenceCount -Value ([pscustomobject]@{ ProcessId = 1 })) -ne 1) { exit 94 }
if ((Get-SequenceCount -Value @([pscustomobject]@{ ProcessId = 1 }, [pscustomobject]@{ ProcessId = 2 })) -ne 2) { exit 95 }
"@
    [IO.File]::WriteAllText($countProbePath, $countProbe, [Text.UTF8Encoding]::new($false))
    $countProbeOutput = @(& $windowsPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $countProbePath 2>&1)
    $countProbeExitCode = $LASTEXITCODE
    Assert-True ($countProbeExitCode -eq 0) "The Windows PowerShell routing count must accept empty, scalar, and array query results. exit=$countProbeExitCode output=$($countProbeOutput -join ' | ')"

    $watcherAssetPath = Join-Path $projectRoot 'skills\codex-safe-setup\assets\desktop-permission-selector\Watch-CodexDesktop.ps1'
    $watcherTokens = $null
    $watcherErrors = $null
    $watcherAst = [Management.Automation.Language.Parser]::ParseFile($watcherAssetPath, [ref]$watcherTokens, [ref]$watcherErrors)
    Assert-True ($watcherErrors.Count -eq 0) 'The Windows PowerShell watcher asset must parse.'
    $watcherStatusFunctionAst = $watcherAst.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-WatcherStatus'
    }, $true)
    $watcherRepairFunctionAst = $watcherAst.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-SelectorRepair'
    }, $true)
    Assert-True ($null -ne $watcherStatusFunctionAst -and $null -ne $watcherRepairFunctionAst) 'The watcher must expose its repair boundary and health status.'
    $watcherProbePath = Join-Path $temporaryRoot 'windows-powershell-watcher-probe.ps1'
    $watcherStatusFixture = Join-Path $temporaryRoot 'watcher-status-fixture.json'
    $escapedWatcherStatusFixture = $watcherStatusFixture.Replace("'", "''")
    $watcherProbe = @"
Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Stop'
`$state = [pscustomobject]@{ installationId = 'unit-fixture' }
`$watcherStatusPath = '$escapedWatcherStatusFixture'
$($watcherStatusFunctionAst.Extent.Text)
$($watcherRepairFunctionAst.Extent.Text)
`$continued = Invoke-SelectorRepair -Action { throw 'synthetic launcher failure' }
if (`$continued) { exit 96 }
`$status = [IO.File]::ReadAllText(`$watcherStatusPath) | ConvertFrom-Json
if (`$status.status -ne 'REPAIR_FAILED' -or `$status.installationId -ne 'unit-fixture') { exit 97 }
"@
    [IO.File]::WriteAllText($watcherProbePath, $watcherProbe, [Text.UTF8Encoding]::new($false))
    $watcherProbeOutput = @(& $windowsPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $watcherProbePath 2>&1)
    $watcherProbeExitCode = $LASTEXITCODE
    Assert-True ($watcherProbeExitCode -eq 0) "A failed redirect attempt must be recorded without terminating the startup watcher. exit=$watcherProbeExitCode output=$($watcherProbeOutput -join ' | ')"

    $unsignedRefused = $false
    try {
        & $installScript -CodexHome $codexHome -StateRoot $stateRoot -DestinationRoot $destination -InstallLocation $packageRoot -PackageVersion '26.999.1.0' -SkipShortcuts -ConfirmApply -AcknowledgeUnsupportedDesktopOverride -NonInteractive | Out-Null
    }
    catch { $unsignedRefused = $true }
    Assert-True $unsignedRefused 'Installer must reject an unsigned source outside the hidden temp-fixture opt-in.'
    Assert-True (-not (Test-Path -LiteralPath $destination)) 'Unsigned-source refusal must not create a loader destination.'

    & $installScript -CodexHome $codexHome -StateRoot $stateRoot -DestinationRoot $destination -InstallLocation $packageRoot -PackageVersion '26.999.1.0' -SkipShortcuts -AllowUnsignedTestFixture -ConfirmApply -AcknowledgeUnsupportedDesktopOverride -NonInteractive | Out-Null
    Assert-True (Test-Path -LiteralPath (Join-Path $destination 'permission-selector-loader.cjs')) 'Installer must copy the small main-process loader.'
    Assert-True (Test-Path -LiteralPath (Join-Path $destination 'permission-selector-preload.cjs')) 'Installer must copy the small renderer preload.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $destination 'app'))) 'Installer must not derive or extract a Desktop application copy.'
    $localState = [IO.File]::ReadAllText((Join-Path $destination 'desktop-selector-state.json')) | ConvertFrom-Json -Depth 30
    Assert-True ($localState.stateSchemaVersion -eq 3 -and $localState.mode -eq 'ProcessScopedSessionPreload') 'Installer must record schema-3 process-scoped loader state.'
    Assert-True ([string]$localState.sourcePackageFamilyName -eq 'OpenAI.Codex_2p2nqsd0c76g0') 'Installer must pin the exact official package-family identity.'
    Assert-True (Test-Path -LiteralPath (Join-Path $destination 'Recertify-CodexDesktop.ps1') -PathType Leaf) 'Installer must include the automatic update recertifier.'
    Assert-True (-not ([string]$localState.nodeRequirePath).Contains(' ')) 'Whitespace destinations must use a no-space Windows short path for NODE_OPTIONS.'
    Assert-True ((Get-CssFileSha256 -Path ([string]$localState.nodeRequirePath)) -eq [string]$localState.loaderSha256) 'Recorded NODE_OPTIONS path must resolve to the exact loader hash.'

    $verification = (& $testScript -CodexHome $codexHome -StateRoot $stateRoot -InstallLocation $packageRoot -PackageVersion '26.999.1.0' -SkipShortcutCheck -SkipRuntimeProbe -AsJson) | ConvertFrom-Json -Depth 30
    Assert-True ($verification.Overall -eq 'PASS') 'Installed synthetic lightweight loader must verify.'

    & $installScript -CodexHome $codexHome -StateRoot $stateRoot -DestinationRoot $destination -InstallLocation $packageRoot -PackageVersion '26.999.1.0' -SkipShortcuts -AllowUnsignedTestFixture -ConfirmApply -AcknowledgeUnsupportedDesktopOverride -NonInteractive | Out-Null
    [IO.File]::AppendAllText((Join-Path $destination 'permission-selector-preload.cjs'), '// tamper', [Text.UTF8Encoding]::new($false))
    $tamperedOutput = @(& pwsh -NoProfile -NonInteractive -File $testScript -CodexHome $codexHome -StateRoot $stateRoot -InstallLocation $packageRoot -PackageVersion '26.999.1.0' -SkipShortcutCheck -SkipRuntimeProbe -AsJson 2>&1)
    Assert-True ($LASTEXITCODE -ne 0) 'Verifier must reject a changed preload hash.'
    Assert-True ((($tamperedOutput -join [Environment]::NewLine) | ConvertFrom-Json).Overall -eq 'FAIL') 'Tamper result must be FAIL.'

    & $rollbackScript -CodexHome $codexHome -StateRoot $stateRoot -ConfirmRollback -NonInteractive | Out-Null
    Assert-True (Test-Path -LiteralPath $destination) 'First rollback after a loader upgrade must restore the previous generation.'
    $restoredVerification = (& $testScript -CodexHome $codexHome -StateRoot $stateRoot -InstallLocation $packageRoot -PackageVersion '26.999.1.0' -SkipShortcutCheck -SkipRuntimeProbe -AsJson) | ConvertFrom-Json -Depth 30
    Assert-True ($restoredVerification.Overall -eq 'PASS') 'Restored previous lightweight loader must verify.'
    & $rollbackScript -CodexHome $codexHome -StateRoot $stateRoot -ConfirmRollback -NonInteractive | Out-Null
    Assert-True (-not (Test-Path -LiteralPath $destination)) 'Second rollback must deactivate the loader destination.'
    for ($shortcutIndex = 0; $shortcutIndex -lt $realShortcutPaths.Count; $shortcutIndex++) {
        Assert-True ((Get-FileFingerprint -Path $realShortcutPaths[$shortcutIndex]) -eq $realShortcutFingerprints[$shortcutIndex]) 'A SkipShortcuts test lifecycle must not create, replace, or remove real Desktop shortcuts.'
    }

    & $installScript -CodexHome $codexHome -StateRoot $stateRoot -DestinationRoot $destination -InstallLocation $packageRoot -PackageVersion '26.999.1.0' -SkipShortcuts -AllowUnsignedTestFixture -ConfirmApply -AcknowledgeUnsupportedDesktopOverride -NonInteractive | Out-Null
    $compatiblePackageRoot = Join-Path $temporaryRoot 'compatible update source'
    [void](New-AsarFixture -PackageRoot $compatiblePackageRoot -PackageVersion '26.999.2.0')
    & (Join-Path $destination 'Recertify-CodexDesktop.ps1') -StatePath (Join-Path $destination 'desktop-selector-state.json') -InstallLocation $compatiblePackageRoot -PackageVersion '26.999.2.0' -AllowUnsignedTestFixture -SkipRuntimeProbe
    $recertifiedLocal = [IO.File]::ReadAllText((Join-Path $destination 'desktop-selector-state.json')) | ConvertFrom-Json -Depth 50
    $recertifiedPointer = [IO.File]::ReadAllText((Join-Path $stateRoot 'desktop-selector-fix.json')) | ConvertFrom-Json -Depth 50
    Assert-True ([string]$recertifiedLocal.sourcePackageVersion -eq '26.999.2.0' -and [int]$recertifiedLocal.recertificationCount -eq 1) 'A compatible package update must atomically refresh local pins.'
    Assert-True ([string]$recertifiedPointer.sourcePackageVersion -eq '26.999.2.0' -and [int]$recertifiedPointer.recertificationCount -eq 1) 'A compatible package update must atomically refresh pointer pins.'
    $compatibleVerification = (& $testScript -CodexHome $codexHome -StateRoot $stateRoot -InstallLocation $compatiblePackageRoot -PackageVersion '26.999.2.0' -SkipShortcutCheck -SkipRuntimeProbe -AsJson) | ConvertFrom-Json -Depth 30
    Assert-True ($compatibleVerification.Overall -eq 'PASS') 'A synthetically compatible official-update shape must verify after automatic recertification.'

    $beforeRejectedLocal = [IO.File]::ReadAllText((Join-Path $destination 'desktop-selector-state.json'))
    $beforeRejectedPointer = [IO.File]::ReadAllText((Join-Path $stateRoot 'desktop-selector-fix.json'))
    $incompatiblePackageRoot = Join-Path $temporaryRoot 'incompatible update source'
    [void](New-AsarFixture -PackageRoot $incompatiblePackageRoot -PackageVersion '26.999.3.0' -MissingStructureAnchor)
    $updateRefused = $false
    try {
        & (Join-Path $destination 'Recertify-CodexDesktop.ps1') -StatePath (Join-Path $destination 'desktop-selector-state.json') -InstallLocation $incompatiblePackageRoot -PackageVersion '26.999.3.0' -AllowUnsignedTestFixture -SkipRuntimeProbe
    }
    catch { $updateRefused = $true }
    Assert-True $updateRefused 'An update missing a tested selector structure anchor must fail closed.'
    Assert-True ([IO.File]::ReadAllText((Join-Path $destination 'desktop-selector-state.json')) -ceq $beforeRejectedLocal) 'Rejected update must not alter local pins.'
    Assert-True ([IO.File]::ReadAllText((Join-Path $stateRoot 'desktop-selector-fix.json')) -ceq $beforeRejectedPointer) 'Rejected update must not alter pointer pins.'
    & $rollbackScript -CodexHome $codexHome -StateRoot $stateRoot -ConfirmRollback -NonInteractive | Out-Null

    foreach ($case in @(
        [pscustomobject]@{ Name = 'missing-gate'; MissingGate = $true; MissingGateIntegrity = $false; MissingStructureAnchor = $false; UnsafeEntry = $false },
        [pscustomobject]@{ Name = 'missing-gate-integrity'; MissingGate = $false; MissingGateIntegrity = $true; MissingStructureAnchor = $false; UnsafeEntry = $false },
        [pscustomobject]@{ Name = 'missing-structure-anchor'; MissingGate = $false; MissingGateIntegrity = $false; MissingStructureAnchor = $true; UnsafeEntry = $false },
        [pscustomobject]@{ Name = 'unsafe-entry'; MissingGate = $false; MissingGateIntegrity = $false; MissingStructureAnchor = $false; UnsafeEntry = $true }
    )) {
        $caseRoot = Join-Path $temporaryRoot $case.Name
        $caseArchive = New-AsarFixture -PackageRoot $caseRoot -MissingGate:$case.MissingGate -MissingGateIntegrity:$case.MissingGateIntegrity -MissingStructureAnchor:$case.MissingStructureAnchor -UnsafeEntry:$case.UnsafeEntry
        $refused = $false
        try { Get-CssDesktopSelectorSourceEvidence -ArchivePath $caseArchive | Out-Null } catch { $refused = $true }
        Assert-True $refused "Selector source verifier must fail closed for $($case.Name)."
    }

    Write-Output 'PASS: lightweight Desktop selector loader install, automatic compatible-update recertification, incompatible-update refusal, tamper refusal, and recoverable rollback'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        $resolved = [IO.Path]::GetFullPath($temporaryRoot)
        $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not (Test-CssPathWithin -Path $resolved -Root $temp) -or $resolved -eq $temp) {
            throw "Refusing to remove unexpected test path: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
