#requires -Version 7.0
# Canonical Desktop rollout/canary verifier shipped with the skill.
[CmdletBinding()]
param(
    [string]$RolloutPath,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{5,80}$')]
    [string]$RunId,
    [string]$CanaryRoot,
    [string]$CodexHome,
    [switch]$VisualStabilityConfirmed,
    [switch]$ShowPrompts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-E2E {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "DESKTOP E2E ASSERTION FAILED: $Message" }
}

function Get-OptionalProperty {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-NormalizedPath {
    param([Parameter(Mandatory)][string]$Path)
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Test-IsSameOrChildPath {
    param(
        [Parameter(Mandatory)][string]$Candidate,
        [Parameter(Mandatory)][string]$Parent
    )

    $candidatePath = Get-NormalizedPath $Candidate
    $parentPath = Get-NormalizedPath $Parent
    $comparison = if ([OperatingSystem]::IsWindows()) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if ($candidatePath.Equals($parentPath, $comparison)) { return $true }
    return $candidatePath.StartsWith($parentPath + [IO.Path]::DirectorySeparatorChar, $comparison)
}

function Get-SpecialDenyKinds {
    param([AllowNull()][object]$FileSystemPolicy)

    if ($null -eq $FileSystemPolicy) { return @() }
    $entries = @(Get-OptionalProperty $FileSystemPolicy 'entries')
    return @(
        $entries | Where-Object {
            $_.access -eq 'deny' -and
            $_.path.type -eq 'special' -and
            $_.path.value.kind -in @('root', 'slash_tmp', 'tmpdir')
        } | ForEach-Object { [string]$_.path.value.kind }
    )
}

function Get-DenySignatures {
    param([AllowNull()][object]$FileSystemPolicy)

    if ($null -eq $FileSystemPolicy) { return @() }
    return @(
        @(Get-OptionalProperty $FileSystemPolicy 'entries') |
            Where-Object { $_.access -eq 'deny' } |
            ForEach-Object { $_.path | ConvertTo-Json -Compress -Depth 12 }
    )
}

function Get-ConcreteWritableRoots {
    param([Parameter(Mandatory)][object]$TurnContext)

    $roots = [Collections.Generic.List[string]]::new()
    $payload = $TurnContext.payload
    foreach ($path in @(Get-OptionalProperty $payload 'workspace_roots')) {
        if (-not [string]::IsNullOrWhiteSpace([string]$path)) { $roots.Add([string]$path) }
    }
    $cwd = Get-OptionalProperty $payload 'cwd'
    if (-not [string]::IsNullOrWhiteSpace([string]$cwd)) {
        $roots.Add([string]$cwd)
    }
    $sandboxPolicy = Get-OptionalProperty $payload 'sandbox_policy'
    foreach ($path in @(Get-OptionalProperty $sandboxPolicy 'writable_roots')) {
        if (-not [string]::IsNullOrWhiteSpace([string]$path)) { $roots.Add([string]$path) }
    }
    $permissionProfile = Get-OptionalProperty $payload 'permission_profile'
    $fileSystem = Get-OptionalProperty $permissionProfile 'file_system'
    foreach ($entry in @(Get-OptionalProperty $fileSystem 'entries')) {
        if ($entry.access -eq 'write' -and $entry.path.type -eq 'path' -and -not [string]::IsNullOrWhiteSpace([string]$entry.path.path)) {
            $roots.Add([string]$entry.path.path)
        }
    }
    return @($roots | Select-Object -Unique)
}

function New-ProbeDefinitions {
    param(
        [Parameter(Mandatory)][string]$ProbeRunId,
        [Parameter(Mandatory)][string]$ProbeRoot
    )

    $root = Get-NormalizedPath $ProbeRoot
    return @(
        [pscustomobject]@{
            Name = 'custom-before'
            Mode = 'Custom'
            Marker = "CSS-E2E|$ProbeRunId|custom-before"
            Path = Join-Path $root "custom-before-$ProbeRunId.txt"
        },
        [pscustomobject]@{
            Name = 'full-access'
            Mode = 'Full'
            Marker = "CSS-E2E|$ProbeRunId|full-access"
            Path = Join-Path $root "full-access-$ProbeRunId.txt"
        },
        [pscustomobject]@{
            Name = 'workspace-after'
            Mode = 'Workspace'
            Marker = "CSS-E2E|$ProbeRunId|workspace-after"
            Path = Join-Path $root "workspace-after-$ProbeRunId.txt"
        }
    )
}

function ConvertTo-SingleQuotedPowerShellLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Get-ProbeCommand {
    param([Parameter(Mandatory)][object]$Probe)

    $pathLiteral = ConvertTo-SingleQuotedPowerShellLiteral $Probe.Path
    $markerLiteral = ConvertTo-SingleQuotedPowerShellLiteral $Probe.Marker
    return "`$ErrorActionPreference='Stop'; [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($pathLiteral)) | Out-Null; [IO.File]::WriteAllText($pathLiteral,$markerLiteral,[Text.UTF8Encoding]::new(`$false)); [IO.File]::ReadAllText($pathLiteral)"
}

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = [guid]::NewGuid().ToString('N')
}
if ([string]::IsNullOrWhiteSpace($CanaryRoot)) {
    $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    Assert-E2E (-not [string]::IsNullOrWhiteSpace($userProfile)) 'Cannot derive a user-profile canary location; pass -CanaryRoot explicitly.'
    $CanaryRoot = Join-Path (Join-Path $userProfile 'codex-safe-setup-e2e') $RunId
}
if ([string]::IsNullOrWhiteSpace($CodexHome)) {
    $CodexHome = if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        $env:CODEX_HOME
    }
    else {
        Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) '.codex'
    }
}

$probes = New-ProbeDefinitions -ProbeRunId $RunId -ProbeRoot $CanaryRoot
Assert-E2E (@($probes.Marker | Select-Object -Unique).Count -eq 3) 'Probe markers must be unique.'
Assert-E2E (@($probes.Path | Select-Object -Unique).Count -eq 3) 'Probe paths must be unique.'

if ($ShowPrompts) {
    Write-Output "Run ID: $RunId"
    Write-Output "Canary root: $(Get-NormalizedPath $CanaryRoot)"
    Write-Output 'Use the SAME Codex Desktop task for the setup turn and all three probes. Do not restart Codex or create another task.'
    Write-Output ''
    Write-Output 'SETUP TURN: Start one fresh task, choose the built-in Workspace approval mode / 帮我批准 (not Custom), and send this message before changing permissions:'
    Write-Output '---'
    Write-Output "CSS-E2E|$RunId|setup 权限探针初始化。不要调用任何工具，只回复 ready。"
    Write-Output '---'
    Write-Output ''
    for ($index = 0; $index -lt $probes.Count; $index++) {
        $probe = $probes[$index]
        $selector = switch ($probe.Mode) {
            'Custom' { 'codex-safe-workspace / 自定义（不要选择 offline 配置）' }
            'Full' { 'Full Access / 完全访问权限' }
            default { 'the built-in Workspace approval mode / 帮我批准（不要选择 Custom 配置）' }
        }
        Write-Output ("STEP {0}: In the task permission selector choose {1}, then send exactly this message:" -f ($index + 1), $selector)
        Write-Output 'VISUAL CHECK: note the selector label immediately before sending, while the turn is running, and after the answer finishes. All three labels must remain the option you deliberately clicked.'
        Write-Output '---'
        Write-Output "这是 Codex Desktop 权限端到端探针 $($probe.Marker)。只调用一次统一终端执行工具（unified exec），原样执行下面这一条 PowerShell 命令。不要请求批准或提权；不要调用 thread/settings/update、shellCommand、command/exec、apply_patch 或任何其他文件工具；不要让我去用户终端执行；失败后立即停止，不要重试。最后只报告该命令的退出码和标准输出。"
        Write-Output (Get-ProbeCommand $probe)
        Write-Output '---'
        Write-Output ''
    }
    Write-Output 'After all three turns have completed, verify the task rollout with:'
    Write-Output "& '$PSCommandPath' -RolloutPath '<absolute rollout jsonl>' -RunId '$RunId' -CanaryRoot '$(Get-NormalizedPath $CanaryRoot)' -VisualStabilityConfirmed"
    Write-Output 'Use -VisualStabilityConfirmed only after directly observing that none of the three labels changed during its turn. Rollout metadata cannot prove this UI condition.'
    return
}

Assert-E2E (-not [string]::IsNullOrWhiteSpace($RolloutPath)) 'Pass -RolloutPath, or use -ShowPrompts to generate the three probe turns.'
Assert-E2E $VisualStabilityConfirmed 'Visual stability was not confirmed. Directly observe each deliberately selected label before send, during execution, and after completion, then pass -VisualStabilityConfirmed. Rollout metadata alone is insufficient.'
$resolvedRollout = (Resolve-Path -LiteralPath $RolloutPath).Path
Assert-E2E ([IO.Path]::GetExtension($resolvedRollout) -eq '.jsonl') 'RolloutPath must be a Codex rollout .jsonl file.'
$sessionsRoot = Join-Path (Get-NormalizedPath $CodexHome) 'sessions'
Assert-E2E (Test-IsSameOrChildPath -Candidate $resolvedRollout -Parent $sessionsRoot) "RolloutPath must be an actual session under the selected Codex home: $sessionsRoot"

$snapshotBefore = Get-Item -LiteralPath $resolvedRollout
$snapshotLength = $snapshotBefore.Length
$snapshotWriteTime = $snapshotBefore.LastWriteTimeUtc
$contextsByTurn = @{}
$completionsByTurn = @{}
$settingsApplied = [Collections.Generic.List[object]]::new()
$sessionMetadata = [Collections.Generic.List[object]]::new()
$commandsByProbe = @{}
foreach ($probe in $probes) { $commandsByProbe[$probe.Name] = [Collections.Generic.List[object]]::new() }

$lineNumber = 0
foreach ($line in Get-Content -LiteralPath $resolvedRollout -Encoding utf8) {
    $lineNumber++
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    $isContext = $line.Contains('"type":"turn_context"')
    $isCompletion = $line.Contains('"type":"task_complete"')
    $isSettings = $line.Contains('"type":"thread_settings_applied"')
    $isSessionMeta = $line.Contains('"type":"session_meta"')
    $matchingProbes = @($probes | Where-Object { $line.Contains($_.Marker) })
    $isCandidateCommand = $matchingProbes.Count -gt 0 -and $line.Contains('"type":"CommandExecution"') -and $line.Contains('"type":"item_completed"')
    if (-not ($isContext -or $isCompletion -or $isSettings -or $isSessionMeta -or $isCandidateCommand)) { continue }

    try { $record = $line | ConvertFrom-Json -Depth 50 }
    catch { throw "Invalid rollout JSON at line $lineNumber. The rollout may still be changing: $($_.Exception.Message)" }
    $record | Add-Member -NotePropertyName CssLineNumber -NotePropertyValue $lineNumber -Force

    if ($record.type -eq 'session_meta') {
        $sessionMetadata.Add($record)
        continue
    }

    if ($record.type -eq 'turn_context') {
        $turnId = [string]$record.payload.turn_id
        if (-not $contextsByTurn.ContainsKey($turnId)) { $contextsByTurn[$turnId] = [Collections.Generic.List[object]]::new() }
        $contextsByTurn[$turnId].Add($record)
        continue
    }
    if ($record.type -eq 'event_msg' -and $record.payload.type -eq 'task_complete') {
        $turnId = [string]$record.payload.turn_id
        if (-not $completionsByTurn.ContainsKey($turnId)) { $completionsByTurn[$turnId] = [Collections.Generic.List[object]]::new() }
        $completionsByTurn[$turnId].Add($record)
        continue
    }
    if ($record.type -eq 'event_msg' -and $record.payload.type -eq 'thread_settings_applied') {
        $settingsApplied.Add($record)
        continue
    }
    if ($record.type -ne 'event_msg' -or $record.payload.type -ne 'item_completed' -or $record.payload.item.type -ne 'CommandExecution') { continue }

    $commandText = @($record.payload.item.command) -join ' '
    foreach ($probe in $matchingProbes) {
        if ($commandText.Contains($probe.Marker) -and $commandText.Contains($probe.Path)) {
            $commandsByProbe[$probe.Name].Add($record)
        }
    }
}

$snapshotAfter = Get-Item -LiteralPath $resolvedRollout
Assert-E2E ($snapshotAfter.Length -eq $snapshotLength -and $snapshotAfter.LastWriteTimeUtc -eq $snapshotWriteTime) 'The rollout changed while it was being read. Wait for the third turn to finish, then rerun verification.'

$observations = [Collections.Generic.List[object]]::new()
foreach ($probe in $probes) {
    $matches = @($commandsByProbe[$probe.Name])
    Assert-E2E ($matches.Count -eq 1) "Expected exactly one completed unified-exec CommandExecution containing the exact path and marker for '$($probe.Name)'; found $($matches.Count)."
    $commandRecord = $matches[0]
    $turnId = [string]$commandRecord.payload.turn_id
    Assert-E2E (-not [string]::IsNullOrWhiteSpace($turnId)) "The '$($probe.Name)' command has no turn_id."
    Assert-E2E ($commandRecord.payload.item.source -eq 'unified_exec_startup') "The '$($probe.Name)' probe did not run through unified exec."
    $expectedCommand = Get-ProbeCommand $probe
    $commandParts = @($commandRecord.payload.item.command | ForEach-Object { [string]$_ })
    $exactScriptParts = @($commandParts | Where-Object { $_ -ceq $expectedCommand })
    Assert-E2E ($exactScriptParts.Count -eq 1) "The '$($probe.Name)' unified-exec command did not contain the exact generated PowerShell probe as one complete argument."

    $contexts = if ($contextsByTurn.ContainsKey($turnId)) { @($contextsByTurn[$turnId] | Where-Object { [long]$_.ordinal -lt [long]$commandRecord.ordinal }) } else { @() }
    Assert-E2E ($contexts.Count -ge 1) "No preceding turn_context exists for '$($probe.Name)' turn $turnId."
    $context = $contexts | Sort-Object { [long]$_.ordinal } -Descending | Select-Object -First 1
    $settings = @($settingsApplied | Where-Object { [long]$_.ordinal -lt [long]$context.ordinal } | Sort-Object { [long]$_.ordinal } -Descending | Select-Object -First 1)
    Assert-E2E ($settings.Count -eq 1) "No preceding thread_settings_applied exists for '$($probe.Name)' turn $turnId."
    $activeProfile = Get-OptionalProperty $settings[0].payload.thread_settings 'active_permission_profile'
    $activeProfileId = [string](Get-OptionalProperty $activeProfile 'id')
    $completions = if ($completionsByTurn.ContainsKey($turnId)) { @($completionsByTurn[$turnId] | Where-Object { [long]$_.ordinal -gt [long]$commandRecord.ordinal }) } else { @() }
    Assert-E2E ($completions.Count -ge 1) "No later task_complete exists for '$($probe.Name)' turn $turnId."
    $completion = $completions | Sort-Object { [long]$_.ordinal } | Select-Object -First 1

    foreach ($writeRoot in @(Get-ConcreteWritableRoots $context)) {
        Assert-E2E (-not (Test-IsSameOrChildPath -Candidate $CanaryRoot -Parent $writeRoot)) "Canary root is inside a declared workspace/writable root for '$($probe.Name)': $writeRoot"
    }

    $item = $commandRecord.payload.item
    $exitCode = Get-OptionalProperty $item 'exit_code'
    if ($probe.Mode -eq 'Full') {
        Assert-E2E ($activeProfileId -eq ':danger-full-access') "Full Access turn selected '$activeProfileId', not :danger-full-access."
        Assert-E2E ($context.payload.sandbox_policy.type -eq 'danger-full-access') "Full Access turn used sandbox '$($context.payload.sandbox_policy.type)', not danger-full-access."
        Assert-E2E ($context.payload.permission_profile.type -eq 'disabled') "Full Access turn used permission profile '$($context.payload.permission_profile.type)', not disabled."
        Assert-E2E ($item.status -eq 'completed' -and $null -ne $exitCode -and [int]$exitCode -eq 0) "Full Access command did not complete with exit code 0 (status=$($item.status), exit=$exitCode)."
        Assert-E2E (([string]$item.stdout).Trim() -eq $probe.Marker) 'Full Access command stdout did not exactly match its marker.'
        Assert-E2E (Test-Path -LiteralPath $probe.Path -PathType Leaf) "Full Access canary file does not exist: $($probe.Path)"
        Assert-E2E ([IO.File]::ReadAllText($probe.Path) -ceq $probe.Marker) 'Full Access canary file content does not exactly match its marker.'
    }
    else {
        Assert-E2E ($context.payload.sandbox_policy.type -eq 'workspace-write') "Restricted turn '$($probe.Name)' used sandbox '$($context.payload.sandbox_policy.type)', not workspace-write."
        Assert-E2E ($context.payload.permission_profile.type -eq 'managed') "Restricted turn '$($probe.Name)' used permission profile '$($context.payload.permission_profile.type)', not managed."
        Assert-E2E ($context.payload.permission_profile.file_system.type -eq 'restricted') "Restricted turn '$($probe.Name)' did not expose a restricted permission-profile filesystem."
        $profileDenies = @(Get-SpecialDenyKinds $context.payload.permission_profile.file_system)
        $runtimeDenies = @(Get-SpecialDenyKinds $context.payload.file_system_sandbox_policy)
        $allProfileDenies = @(Get-DenySignatures $context.payload.permission_profile.file_system)
        $allRuntimeDenies = @(Get-DenySignatures $context.payload.file_system_sandbox_policy)
        if ($probe.Mode -eq 'Custom') {
            Assert-E2E ($activeProfileId -eq 'codex-safe-workspace') "Custom turn selected '$activeProfileId', not codex-safe-workspace."
            Assert-E2E ($allProfileDenies.Count -eq 0 -and $allRuntimeDenies.Count -eq 0) "DynamicUi Custom contains a sticky deny entry: $(@($allProfileDenies + $allRuntimeDenies) -join ', ')."
        }
        else {
            Assert-E2E ($activeProfileId -eq ':workspace') "Built-in Workspace turn selected '$activeProfileId', not :workspace."
            Assert-E2E ($allProfileDenies.Count -eq 0 -and $allRuntimeDenies.Count -eq 0) "Built-in Workspace turn is contaminated by stale Custom deny entries: $(@($allProfileDenies + $allRuntimeDenies) -join ', ')."
        }
        Assert-E2E ($item.status -eq 'failed' -and $null -ne $exitCode -and [int]$exitCode -ne 0) "Restricted turn '$($probe.Name)' must record a failed command with a nonzero exit code (status=$($item.status), exit=$exitCode)."
        Assert-E2E (-not (Test-Path -LiteralPath $probe.Path)) "Restricted canary exists but must not: $($probe.Path)"
    }

    $observations.Add([pscustomobject]@{
        Name = $probe.Name
        TurnId = $turnId
        Ordinal = [long]$commandRecord.ordinal
        ContextLine = [long]$context.CssLineNumber
        SettingsLine = [long]$settings[0].CssLineNumber
        CompletionLine = [long]$completion.CssLineNumber
        Sandbox = [string]$context.payload.sandbox_policy.type
        PermissionProfile = [string]$context.payload.permission_profile.type
        ActiveProfile = $activeProfileId
        Status = [string]$item.status
        ExitCode = $exitCode
    })
}

Assert-E2E (@($observations.TurnId | Select-Object -Unique).Count -eq 3) 'The three probes must belong to three distinct user turns in the same rollout.'
Assert-E2E ($observations[0].Ordinal -lt $observations[1].Ordinal -and $observations[1].Ordinal -lt $observations[2].Ordinal) 'Probe turns are not ordered Custom -> Full Access -> Workspace.'
Assert-E2E ($observations[0].SettingsLine -lt $observations[0].ContextLine) 'Custom UI selection was not recorded before its probe turn.'
Assert-E2E ($observations[1].SettingsLine -gt $observations[0].CompletionLine -and $observations[1].SettingsLine -lt $observations[1].ContextLine) 'Full Access UI selection was not recorded between the Custom and Full Access probe turns.'
Assert-E2E ($observations[2].SettingsLine -gt $observations[1].CompletionLine -and $observations[2].SettingsLine -lt $observations[2].ContextLine) 'Built-in Workspace UI selection was not recorded between the Full Access and Workspace probe turns.'

$activeSessionMeta = @($sessionMetadata | Where-Object { [long]$_.CssLineNumber -lt $observations[0].ContextLine } | Sort-Object CssLineNumber -Descending | Select-Object -First 1)
Assert-E2E ($activeSessionMeta.Count -eq 1) 'No session_meta exists before the first probe turn.'
Assert-E2E ([string]$activeSessionMeta[0].payload.originator -eq 'Codex Desktop') "The rollout originator is '$($activeSessionMeta[0].payload.originator)', not Codex Desktop."
$sessionId = [string](Get-OptionalProperty $activeSessionMeta[0].payload 'session_id')
if ([string]::IsNullOrWhiteSpace($sessionId)) { $sessionId = [string](Get-OptionalProperty $activeSessionMeta[0].payload 'id') }
Assert-E2E (-not [string]::IsNullOrWhiteSpace($sessionId) -and [IO.Path]::GetFileName($resolvedRollout).Contains($sessionId)) 'The Desktop session ID does not match the rollout filename.'
$probeWindowMetadata = @($sessionMetadata | Where-Object { [long]$_.CssLineNumber -ge [long]$activeSessionMeta[0].CssLineNumber -and [long]$_.CssLineNumber -le $observations[2].CompletionLine })
Assert-E2E ($probeWindowMetadata.Count -eq 1) 'A new session_meta appeared during the probe window, so no-restart same-process routing was not proved.'

$observations | Format-Table Name, TurnId, Sandbox, PermissionProfile, ActiveProfile, Status, ExitCode -AutoSize
Write-Output "PASS: Codex Desktop applied codex-safe-workspace -> Full Access -> built-in Workspace to three ordered probe turns without a new session_meta."
Write-Output "PASS: Full Access created the outside-workspace canary; Custom and Workspace failed to create theirs."
Write-Output "PASS: DynamicUi Custom and built-in Workspace contained no sticky deny entries."
Write-Output "PASS (DIRECT OBSERVATION): the deliberately selected label remained stable before send, during execution, and after completion for all three turns."
