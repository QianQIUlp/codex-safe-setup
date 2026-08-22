#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(DontShow)][switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$windowsPowerShellModuleRoot = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules'
$currentModulePath = [string]$env:PSModulePath
$hasWindowsPowerShellModules = $false
foreach ($candidate in @($currentModulePath -split ';')) {
    if (-not $candidate) { continue }
    try {
        if ([IO.Path]::GetFullPath($candidate).Equals([IO.Path]::GetFullPath($windowsPowerShellModuleRoot), [StringComparison]::OrdinalIgnoreCase)) {
            $hasWindowsPowerShellModules = $true
            break
        }
    }
    catch { }
}
if (-not $hasWindowsPowerShellModules) {
    $env:PSModulePath = if ($currentModulePath) { $windowsPowerShellModuleRoot + ';' + $currentModulePath } else { $windowsPowerShellModuleRoot }
}

$loaderRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSCommandPath))
$statePath = Join-Path $loaderRoot 'desktop-selector-state.json'
$launchStatusPath = Join-Path $loaderRoot 'last-launch-status.json'
$loaderStatusPath = Join-Path $loaderRoot 'loader-status.json'

function Write-JsonRecord {
    param([string]$Path, [System.Collections.IDictionary]$Record)
    [IO.File]::WriteAllText($Path, ($Record | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
}

function Write-LaunchStatus {
    param(
        [string]$Status,
        [string]$Message,
        [Management.Automation.ErrorRecord]$ErrorRecord
    )
    $record = [ordered]@{
        status = $Status
        message = $Message
        timestampUtc = [DateTime]::UtcNow.ToString('o')
    }
    if ($null -ne $ErrorRecord) {
        $record.errorType = $ErrorRecord.Exception.GetType().FullName
        $record.scriptName = [string]$ErrorRecord.InvocationInfo.ScriptName
        $record.scriptLineNumber = [int]$ErrorRecord.InvocationInfo.ScriptLineNumber
        $record.positionMessage = [string]$ErrorRecord.InvocationInfo.PositionMessage
    }
    Write-JsonRecord -Path $launchStatusPath -Record $record
}

function Get-SequenceCount {
    param($Value)
    if ($null -eq $Value) { return 0 }
    if ($Value -is [Array]) { return $Value.Length }
    return 1
}

function Test-SamePath {
    param([string]$Left, [string]$Right)
    if (-not $Left -or -not $Right) { return $false }
    return [IO.Path]::GetFullPath($Left).Equals([IO.Path]::GetFullPath($Right), [StringComparison]::OrdinalIgnoreCase)
}

function Test-PathWithin {
    param([string]$Path, [string]$Root)
    $resolvedPath = [IO.Path]::GetFullPath($Path)
    $resolvedRoot = [IO.Path]::GetFullPath($Root)
    if ($resolvedPath.Equals($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    $prefix = $resolvedRoot.TrimEnd([char[]]@('\', '/')) + [IO.Path]::DirectorySeparatorChar
    return $resolvedPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Test-RecordedHash {
    param([string]$Path, [string]$Expected)
    if (-not $Path -or -not $Expected -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $stream = [IO.File]::OpenRead($Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $actual = ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '')
        return $actual.Equals($Expected, [StringComparison]::OrdinalIgnoreCase)
    }
    finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}

function Test-GraceProcess {
    param($Process, $Records)
    foreach ($record in @($Records)) {
        if ([int]$Process.ProcessId -eq [int]$record.processId -and
            [string]$Process.CreationDate -eq [string]$record.creationDate) {
            return $true
        }
    }
    return $false
}

try {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw 'Desktop selector loader state is missing. Reinstall or roll back the compatibility fix.'
    }
    $state = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
    if ([int]$state.stateSchemaVersion -ne 3 -or [string]$state.productVersion -ne '0.2.0' -or
        [string]$state.mode -ne 'ProcessScopedSessionPreload') {
        throw 'Desktop selector loader state has an unsupported version or mode.'
    }
    if (-not (Test-SamePath -Left ([string]$state.destinationRoot) -Right $loaderRoot)) {
        throw 'Desktop selector loader state points at a different installation root.'
    }

    $codexHome = [IO.Path]::GetFullPath([string]$state.codexHome)
    if (-not (Test-PathWithin -Path $loaderRoot -Root $codexHome) -or
        $loaderRoot.Equals($codexHome, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Desktop selector loader is outside the recorded Codex Home.'
    }
    $loaderPath = Join-Path $loaderRoot 'permission-selector-loader.cjs'
    $preloadPath = Join-Path $loaderRoot 'permission-selector-preload.cjs'
    $recertifierPath = Join-Path $loaderRoot 'Recertify-CodexDesktop.ps1'
    $compatibilityCommonPath = Join-Path $loaderRoot 'DesktopPermissionSelector.Common.ps1'
    $powerShell7Path = [IO.Path]::GetFullPath([string]$state.powerShell7Path)
    $nodeRequirePath = [string]$state.nodeRequirePath
    if (-not (Test-RecordedHash -Path $loaderPath -Expected ([string]$state.loaderSha256)) -or
        -not (Test-RecordedHash -Path $nodeRequirePath -Expected ([string]$state.loaderSha256)) -or
        -not (Test-RecordedHash -Path $preloadPath -Expected ([string]$state.preloadSha256)) -or
        -not (Test-RecordedHash -Path $recertifierPath -Expected ([string]$state.recertifierSha256)) -or
        -not (Test-RecordedHash -Path $compatibilityCommonPath -Expected ([string]$state.compatibilityCommonSha256))) {
        throw 'Desktop selector loader assets do not match their recorded hashes.'
    }
    if (-not (Test-Path -LiteralPath $powerShell7Path -PathType Leaf) -or
        [IO.Path]::GetExtension($powerShell7Path) -ne '.exe') {
        throw 'The recorded PowerShell 7 interpreter is unavailable.'
    }
    if ($nodeRequirePath -match '\s') {
        throw 'The recorded NODE_OPTIONS loader path contains whitespace.'
    }

    $package = Get-AppxPackage -Name OpenAI.Codex -ErrorAction Stop |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if ($null -eq $package) { throw 'The signed OpenAI.Codex Desktop package is not installed.' }
    $executable = Join-Path ([string]$package.InstallLocation) 'app\ChatGPT.exe'
    $asarPath = Join-Path ([string]$package.InstallLocation) 'app\resources\app.asar'
    $buildChanged = [string]$package.Version -ne [string]$state.sourcePackageVersion -or
        -not (Test-SamePath -Left ([string]$package.InstallLocation) -Right ([string]$state.sourceInstallLocation)) -or
        -not (Test-RecordedHash -Path $executable -Expected ([string]$state.sourceExecutableSha256)) -or
        -not (Test-RecordedHash -Path $asarPath -Expected ([string]$state.sourceAsarSha256))
    if ($buildChanged) {
        & $powerShell7Path -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $recertifierPath -StatePath $statePath
        if ($LASTEXITCODE -ne 0) {
            throw "The official Desktop update did not pass automatic compatibility recertification (exit $LASTEXITCODE)."
        }
        $state = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
        $package = Get-AppxPackage -Name OpenAI.Codex -ErrorAction Stop |
            Sort-Object Version -Descending |
            Select-Object -First 1
        if ($null -eq $package) { throw 'The signed OpenAI.Codex Desktop package disappeared after recertification.' }
        $executable = Join-Path ([string]$package.InstallLocation) 'app\ChatGPT.exe'
        $asarPath = Join-Path ([string]$package.InstallLocation) 'app\resources\app.asar'
    }
    if ([string]$package.Name -ne [string]$state.sourcePackageName -or
        [string]$package.PackageFamilyName -ne [string]$state.sourcePackageFamilyName -or
        [string]$package.PublisherId -ne [string]$state.sourcePublisherId -or
        [string]$package.Publisher -ne [string]$state.sourcePublisher) {
        throw 'The installed Desktop package identity does not match the recertified official identity.'
    }
    if ([string]$package.Version -ne [string]$state.sourcePackageVersion -or
        -not (Test-SamePath -Left ([string]$package.InstallLocation) -Right ([string]$state.sourceInstallLocation))) {
        throw 'The installed Desktop version or location changed during compatibility validation.'
    }
    if (-not (Test-RecordedHash -Path $executable -Expected ([string]$state.sourceExecutableSha256)) -or
        -not (Test-RecordedHash -Path $asarPath -Expected ([string]$state.sourceAsarSha256))) {
        throw 'The signed Desktop executable or source archive changed after compatibility recertification.'
    }
    if ([bool]$state.syntheticUnsignedTestFixture) {
        throw 'Synthetic unsigned fixture state cannot be launched.'
    }
    if ([string]$state.trustedSignerThumbprint -notmatch '^[a-fA-F0-9]{40}$') {
        throw 'The recorded signer pin is missing or invalid. The selector loader is disabled.'
    }
    $marker = '--codex-safe-setup-selector-loader=' + [string]$state.installationId
    $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" -ErrorAction Stop | Where-Object {
        $_.ExecutablePath -and (Test-SamePath -Left ([string]$_.ExecutablePath) -Right $executable)
    })
    $processIds = @($processes | ForEach-Object { [int]$_.ProcessId })
    $rootProcesses = @($processes | Where-Object { $_.ParentProcessId -notin $processIds })
    $activeLoaderRoots = @($rootProcesses | Where-Object {
        ([string]$_.CommandLine).IndexOf($marker, [StringComparison]::OrdinalIgnoreCase) -ge 0
    })
    $graceRoots = @($rootProcesses | Where-Object { Test-GraceProcess -Process $_ -Records $state.graceProcesses })
    $legacyAppDirectory = [string]$state.legacyDerivedAppDirectory
    $legacyRoots = if ($legacyAppDirectory) {
        @($rootProcesses | Where-Object {
            ([string]$_.CommandLine).IndexOf($legacyAppDirectory, [StringComparison]::OrdinalIgnoreCase) -ge 0
        })
    }
    else { @() }
    $activeLoaderCount = Get-SequenceCount -Value $activeLoaderRoots
    $graceCount = Get-SequenceCount -Value $graceRoots
    $legacyCount = Get-SequenceCount -Value $legacyRoots
    $officialRootCount = Get-SequenceCount -Value $rootProcesses

    if ($ValidateOnly) {
        $prospectiveRoute = if ($activeLoaderCount -gt 0) {
            'already-active'
        }
        elseif ($graceCount -gt 0 -or $legacyCount -gt 0) {
            'preserve-current-task'
        }
        elseif ($officialRootCount -gt 0) {
            'manual-action-required'
        }
        else {
            'start-instrumented-process'
        }
        Write-LaunchStatus -Status 'VALIDATED' -Message "Windows PowerShell validated the exact signed Desktop bytes, every loader asset, and the live process-routing branch without starting or closing a process (route: $prospectiveRoute)."
        return
    }

    if ($activeLoaderCount -gt 0) {
        Write-LaunchStatus -Status 'ALREADY_RUNNING' -Message 'The verified process-scoped selector loader is already running.'
        return
    }
    if ($graceCount -gt 0 -or $legacyCount -gt 0) {
        Write-LaunchStatus -Status 'CURRENT_TASK_PRESERVED' -Message 'The task that was running during migration was left untouched. The lightweight loader activates after that task exits.'
        return
    }
    if ($officialRootCount -gt 0) {
        $officialRoots = @($rootProcesses)
        $processIdsForAudit = @($officialRoots | ForEach-Object { [int]$_.ProcessId })
        Write-LaunchStatus -Status 'MANUAL_ACTION_REQUIRED' -Message ('An official Codex Desktop process is already running without the selector loader (audit PIDs: ' + ($processIdsForAudit -join ',') + '). Exit Codex completely, then start it again from the Codex (Stable Permissions) shortcut.')
        throw 'Refusing to close or restart a running official Codex Desktop process (fail-closed).'
    }

    $legacyRoot = [string]$state.legacyDerivedRoot
    $legacyArchive = [string]$state.legacyArchivePath
    if ($legacyRoot -and (Test-Path -LiteralPath $legacyRoot)) {
        $historyRoot = Join-Path ([IO.Path]::GetFullPath([string]$state.stateRoot)) 'desktop-selector-fix-history'
        if (-not (Test-PathWithin -Path $legacyRoot -Root $codexHome) -or
            [IO.Path]::GetFullPath($legacyRoot).Equals($codexHome, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-PathWithin -Path $legacyArchive -Root $historyRoot) -or
            [IO.Path]::GetFullPath($legacyArchive).Equals([IO.Path]::GetFullPath($historyRoot), [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Recorded legacy compatibility paths are outside their intended roots.'
        }
        if (Test-Path -LiteralPath $legacyArchive) {
            throw 'Both the legacy compatibility root and its archive target exist.'
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $legacyArchive) -Force | Out-Null
        Move-Item -LiteralPath $legacyRoot -Destination $legacyArchive
    }

    Write-JsonRecord -Path $loaderStatusPath -Record ([ordered]@{
        status = 'LAUNCH_PENDING'
        timestampUtc = [DateTime]::UtcNow.ToString('o')
        installationId = [string]$state.installationId
    })

    $requiredNodeOption = '--require=' + $nodeRequirePath
    $existingNodeOptions = [string]$env:NODE_OPTIONS
    $nodeOptions = if ([string]::IsNullOrWhiteSpace($existingNodeOptions)) {
        $requiredNodeOption
    }
    else {
        $requiredNodeOption + ' ' + $existingNodeOptions.Trim()
    }
    $environmentNames = @(
        'NODE_OPTIONS',
        'CSS_DESKTOP_SELECTOR_PRELOAD',
        'CSS_DESKTOP_SELECTOR_PRELOAD_SHA256',
        'CSS_DESKTOP_SELECTOR_STATUS_PATH',
        'CSS_DESKTOP_SELECTOR_INSTALLATION_ID'
    )
    $priorEnvironment = @{}
    foreach ($name in $environmentNames) { $priorEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    try {
        $env:NODE_OPTIONS = $nodeOptions
        $env:CSS_DESKTOP_SELECTOR_PRELOAD = $preloadPath
        $env:CSS_DESKTOP_SELECTOR_PRELOAD_SHA256 = [string]$state.preloadSha256
        $env:CSS_DESKTOP_SELECTOR_STATUS_PATH = $loaderStatusPath
        $env:CSS_DESKTOP_SELECTOR_INSTALLATION_ID = [string]$state.installationId
        $started = Start-Process -FilePath $executable -ArgumentList @($marker) -WorkingDirectory $loaderRoot -PassThru
    }
    finally {
        foreach ($name in $environmentNames) {
            $previous = $priorEnvironment[$name]
            if ($null -eq $previous) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable($name, [string]$previous, 'Process') }
        }
    }

    $activation = $null
    $activationDeadline = (Get-Date).AddSeconds(15)
    do {
        Start-Sleep -Milliseconds 200
        try { $activation = [IO.File]::ReadAllText($loaderStatusPath) | ConvertFrom-Json } catch { $activation = $null }
        if ($activation -and [string]$activation.installationId -eq [string]$state.installationId -and
            [string]$activation.status -in @('LOADER_ACTIVE', 'PRELOAD_ACTIVE', 'LOADER_REFUSED', 'PRELOAD_REFUSED')) { break }
    } while ((Get-Date) -lt $activationDeadline -and -not $started.HasExited)

    if ($activation -and [string]$activation.status -eq 'PRELOAD_ACTIVE') {
        Write-LaunchStatus -Status 'STARTED_ACTIVE' -Message "Started signed Desktop $($package.Version) with the verified process-scoped selector preload."
    }
    elseif ($activation -and [string]$activation.status -eq 'LOADER_ACTIVE') {
        Write-LaunchStatus -Status 'STARTED_LOADER_ACTIVE' -Message 'The main-process loader is active; the renderer preload will report when the first window is created.'
    }
    elseif ($activation -and [string]$activation.status -in @('LOADER_REFUSED', 'PRELOAD_REFUSED')) {
        throw "Desktop selector loader refused activation: $($activation.message)"
    }
    else {
        Write-LaunchStatus -Status 'STARTED_PENDING' -Message 'Desktop started, but renderer activation was not observed before the launcher timeout.'
    }
}
catch {
    Write-LaunchStatus -Status 'DISABLED' -Message $_.Exception.Message -ErrorRecord $_
    throw
}
