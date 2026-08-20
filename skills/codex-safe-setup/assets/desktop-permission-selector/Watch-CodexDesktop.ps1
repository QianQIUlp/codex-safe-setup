#requires -Version 5.1
[CmdletBinding()]
param()

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
$launcher = Join-Path $loaderRoot 'Start-CodexFixed.ps1'
$statePath = Join-Path $loaderRoot 'desktop-selector-state.json'
$pidPath = Join-Path $loaderRoot 'watcher.pid.json'
$watcherStatusPath = Join-Path $loaderRoot 'watcher-status.json'
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf) -or
    -not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    exit 0
}
$state = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
if ([int]$state.stateSchemaVersion -ne 3 -or [string]$state.mode -ne 'ProcessScopedSessionPreload') { exit 0 }
$marker = '--codex-safe-setup-selector-loader=' + [string]$state.installationId

function Write-WatcherStatus {
    param([string]$Status, [string]$Message, [Management.Automation.ErrorRecord]$ErrorRecord)
    $record = [ordered]@{
        status = $Status
        message = $Message
        timestampUtc = [DateTime]::UtcNow.ToString('o')
        processId = $PID
        installationId = [string]$state.installationId
    }
    if ($null -ne $ErrorRecord) {
        $record.errorType = $ErrorRecord.Exception.GetType().FullName
        $record.scriptLineNumber = [int]$ErrorRecord.InvocationInfo.ScriptLineNumber
    }
    [IO.File]::WriteAllText($watcherStatusPath, ($record | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
}

$createdNew = $false
$mutex = [Threading.Mutex]::new($true, 'Local\CodexSafeSetupDesktopPermissionSelectorFix', [ref]$createdNew)
if (-not $createdNew) {
    $mutex.Dispose()
    exit 0
}

function Test-SamePath {
    param([string]$Left, [string]$Right)
    if (-not $Left -or -not $Right) { return $false }
    return [IO.Path]::GetFullPath($Left).Equals([IO.Path]::GetFullPath($Right), [StringComparison]::OrdinalIgnoreCase)
}

function Test-GraceProcess {
    param($Process)
    foreach ($record in @($state.graceProcesses)) {
        if ([int]$Process.ProcessId -eq [int]$record.processId -and
            [string]$Process.CreationDate -eq [string]$record.creationDate) {
            return $true
        }
    }
    return $false
}

function Test-NeedsRepair {
    $package = Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if ($null -eq $package) { return $false }
    $executable = [IO.Path]::GetFullPath((Join-Path ([string]$package.InstallLocation) 'app\ChatGPT.exe'))
    $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -and (Test-SamePath -Left ([string]$_.ExecutablePath) -Right $executable) })
    $ids = @($processes | ForEach-Object { [int]$_.ProcessId })
    $roots = @($processes | Where-Object { $_.ParentProcessId -notin $ids })
    foreach ($root in $roots) {
        if (([string]$root.CommandLine).IndexOf($marker, [StringComparison]::OrdinalIgnoreCase) -ge 0) { continue }
        if (Test-GraceProcess -Process $root) { continue }
        $legacyAppDirectory = [string]$state.legacyDerivedAppDirectory
        if ($legacyAppDirectory -and
            ([string]$root.CommandLine).IndexOf($legacyAppDirectory, [StringComparison]::OrdinalIgnoreCase) -ge 0) { continue }
        return $true
    }
    return $false
}

function Invoke-SelectorRepair {
    param([scriptblock]$Action)
    if ($null -eq $Action) { $Action = { & $launcher } }
    try {
        & $Action
        Write-WatcherStatus -Status 'RUNNING' -Message 'The watcher completed the latest Desktop routing check.'
        return $true
    }
    catch {
        Write-WatcherStatus -Status 'REPAIR_FAILED' -Message $_.Exception.Message -ErrorRecord $_
        return $false
    }
}

$sourceIdentifier = 'CodexSafeSetupDesktopProcessStart'
try {
    $pidRecord = [ordered]@{
        processId = $PID
        startedUtc = [DateTime]::UtcNow.ToString('o')
        scriptPath = $PSCommandPath
        installationId = [string]$state.installationId
    }
    [IO.File]::WriteAllText($pidPath, ($pidRecord | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    Write-WatcherStatus -Status 'RUNNING' -Message 'The Desktop process watcher is active.'
    if (Test-NeedsRepair) { [void](Invoke-SelectorRepair) }

    $null = Register-CimIndicationEvent -Query 'SELECT * FROM Win32_ProcessStartTrace' -SourceIdentifier $sourceIdentifier
    while ($true) {
        $event = Wait-Event -SourceIdentifier $sourceIdentifier -Timeout 10
        if ($null -eq $event) { continue }
        try {
            $name = [string]$event.SourceEventArgs.NewEvent.ProcessName
            if ($name -ne 'ChatGPT.exe') { continue }
            Start-Sleep -Milliseconds 300
            if (Test-NeedsRepair) { [void](Invoke-SelectorRepair) }
        }
        finally {
            Remove-Event -EventIdentifier $event.EventIdentifier -ErrorAction SilentlyContinue
        }
    }
}
catch {
    Write-WatcherStatus -Status 'STOPPED_UNEXPECTEDLY' -Message $_.Exception.Message -ErrorRecord $_
    throw
}
finally {
    Unregister-Event -SourceIdentifier $sourceIdentifier -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    [void]$mutex.ReleaseMutex()
    $mutex.Dispose()
}
