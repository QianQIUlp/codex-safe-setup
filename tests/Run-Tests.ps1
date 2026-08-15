#requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptRoot = Join-Path $projectRoot 'skills\secure-codex-setup\scripts'
$assessScript = Join-Path $scriptRoot 'Assess-CodexSafety.ps1'
$installScript = Join-Path $scriptRoot 'Install-CodexSafety.ps1'
$testScript = Join-Path $scriptRoot 'Test-CodexSafety.ps1'
$rollbackScript = Join-Path $scriptRoot 'Rollback-CodexSafety.ps1'
$commonScript = Join-Path $scriptRoot 'Common.ps1'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('codex-safe-setup-tests-' + [guid]::NewGuid().ToString('N'))

. $commonScript

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Invoke-GitTest {
    param([string]$Repository, [string[]]$GitArguments)
    $output = @(& git -C $Repository @GitArguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArguments -join ' ') failed: $($output -join [Environment]::NewLine)" }
    return $output
}

try {
    $codexHome = Join-Path $temporaryRoot 'codex-home'
    $stateRoot = Join-Path $codexHome 'safe-setup'
    $configPath = Join-Path $codexHome 'config.toml'
    $repository = Join-Path $temporaryRoot 'repo'
    New-Item -ItemType Directory -Path $codexHome, $repository -Force | Out-Null

    if ($env:OS -eq 'Windows_NT') {
        $oscillationHome = Join-Path $temporaryRoot 'oscillation-home'
        $oscillationLogRoot = Join-Path $oscillationHome '.sandbox'
        New-Item -ItemType Directory -Path $oscillationLogRoot -Force | Out-Null
        $oscillationLog = @'
[2026-08-15 23:48:49.477 codex.exe] sandbox setup required: offline firewall settings changed (stored_ports=[7897], desired_ports=[3128, 8081], stored_allow_local_binding=false, desired_allow_local_binding=false)
[2026-08-15 23:52:51.728 codex.exe] sandbox setup required: offline firewall settings changed (stored_ports=[3128, 8081], desired_ports=[7897], stored_allow_local_binding=false, desired_allow_local_binding=false)
[2026-08-15 23:58:36.480 codex.exe] sandbox setup required: offline firewall settings changed (stored_ports=[7897], desired_ports=[3128, 8081], stored_allow_local_binding=false, desired_allow_local_binding=false)
'@
        [IO.File]::WriteAllText((Join-Path $oscillationLogRoot 'sandbox.test.log'), $oscillationLog, [Text.UTF8Encoding]::new($false))
        $oscillationHealth = Get-CssWindowsSandboxSetupHealth -CodexHome $oscillationHome -ExpectedProxyPort @(3128, 8081)
        Assert-True $oscillationHealth.PortOscillationDetected 'Sandbox diagnostics must detect a direct proxy-port reversal.'
        Assert-True ($oscillationHealth.Status -eq 'OSCILLATION_HISTORY') 'An aligned latest setup with earlier reversal must retain oscillation history.'
        Assert-True $oscillationHealth.LatestDesiredMatchesExpected 'The latest managed proxy port set must be recognized as aligned.'

        $conflictHome = Join-Path $temporaryRoot 'conflict-home'
        $conflictLogRoot = Join-Path $conflictHome '.sandbox'
        New-Item -ItemType Directory -Path $conflictLogRoot -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $conflictLogRoot 'sandbox.test.log'), '[2026-08-15 23:52:51.728 codex.exe] sandbox setup required: offline firewall settings changed (stored_ports=[3128, 8081], desired_ports=[7897], stored_allow_local_binding=false, desired_allow_local_binding=false)', [Text.UTF8Encoding]::new($false))
        $conflictHealth = Get-CssWindowsSandboxSetupHealth -CodexHome $conflictHome -ExpectedProxyPort @(3128, 8081)
        Assert-True ($conflictHealth.Status -eq 'CONFLICT') 'A latest setup using another proxy port set must fail alignment.'
    }

    $originalConfig = @"
model = "test-model"
sandbox_mode = "workspace-write"

[sandbox_workspace_write]
network_access = true

[features]
unified_exec = true
"@
    [IO.File]::WriteAllText($configPath, $originalConfig, [Text.UTF8Encoding]::new($false))

    $legacyRefused = $false
    try { & $installScript -ApprovalMode AskMe -NetworkMode Off -WindowsSandbox Keep -CodexHome $codexHome -ConfigPath $configPath -StateRoot $stateRoot -PlanOnly | Out-Null } catch { $legacyRefused = $true }
    Assert-True $legacyRefused 'Installer must refuse conflicting legacy settings without explicit migration consent.'
    Assert-True ([IO.File]::ReadAllText($configPath) -eq $originalConfig) 'A refused migration must not modify configuration.'

    $domainInjectionRefused = $false
    try { & $installScript -NetworkMode Allowlist -AllowedDomain 'example.com" = "allow' -WindowsSandbox Keep -CodexHome $codexHome -ConfigPath $configPath -StateRoot $stateRoot -MigrateLegacySettings -PlanOnly | Out-Null } catch { $domainInjectionRefused = $true }
    Assert-True $domainInjectionRefused 'Installer must reject malformed or injectable domain values.'

    $unrestrictedPlan = @(& $installScript -NetworkMode Unrestricted -WindowsSandbox Keep -CodexHome $codexHome -ConfigPath $configPath -StateRoot $stateRoot -MigrateLegacySettings -PlanOnly) -join [Environment]::NewLine
    Assert-True ($unrestrictedPlan -match 'does not expand filesystem permissions or add deletion authority') 'Unrestricted plan must explain that network access does not widen filesystem authority.'
    Assert-True ($unrestrictedPlan -match 'prompt injection') 'Unrestricted plan must disclose prompt-injection risk before acknowledgement.'
    Assert-True ($unrestrictedPlan -match 'any public Internet destination') 'Unrestricted plan must disclose the loss of destination containment.'

    $unrestrictedRefused = $false
    try { & $installScript -NetworkMode Unrestricted -WindowsSandbox Keep -CodexHome $codexHome -ConfigPath $configPath -StateRoot $stateRoot -MigrateLegacySettings -ConfirmApply -NonInteractive | Out-Null } catch { $unrestrictedRefused = $true }
    Assert-True $unrestrictedRefused 'Non-interactive unrestricted networking must require -AcknowledgeRisk.'
    Assert-True ([IO.File]::ReadAllText($configPath) -eq $originalConfig) 'A refused unrestricted-network acknowledgement must not modify configuration.'

    Invoke-GitTest -Repository $repository -GitArguments @('init') | Out-Null
    Invoke-GitTest -Repository $repository -GitArguments @('config', 'user.name', 'Test User') | Out-Null
    Invoke-GitTest -Repository $repository -GitArguments @('config', 'user.email', 'test@example.invalid') | Out-Null
    [IO.File]::WriteAllText((Join-Path $repository 'tracked.txt'), 'original', [Text.UTF8Encoding]::new($false))
    Invoke-GitTest -Repository $repository -GitArguments @('add', 'tracked.txt') | Out-Null
    Invoke-GitTest -Repository $repository -GitArguments @('commit', '-m', 'initial') | Out-Null

    $installResult = @(& $installScript -ApprovalMode AskMe -NetworkMode Allowlist -AllowedDomain 'example.com' -WindowsSandbox Keep -WorkspacePath $repository -CodexHome $codexHome -ConfigPath $configPath -StateRoot $stateRoot -MigrateLegacySettings -ConfirmApply -NonInteractive)
    $installSummary = @($installResult | Where-Object { $_.PSObject.Properties['Status'] } | Select-Object -Last 1)
    Assert-True ($installSummary.Count -eq 1) 'Installer must return a structured completion summary.'
    Assert-True ($installSummary[0].RequiredPermissionSelection -match 'choose Custom') 'Completion summary must direct the user to Custom permissions.'
    Assert-True ($installSummary[0].RequiredPermissionSelection -match 'codex-safe-workspace') 'Completion summary must name the custom profile.'
    Assert-True ($installSummary[0].RequiredPermissionSelection -match 'Do not choose Full Access') 'Completion summary must distinguish Custom from Full Access.'
    if ($env:OS -eq 'Windows_NT') {
        Assert-True ($installSummary[0].RequiredRestart -match 'Restart Codex and start a new task') 'Windows activation must require a restart and fresh task.'
        Assert-True ($installSummary[0].RequiredRestart -match 'fully quit every Codex desktop window and CLI process') 'Repeated prompts must escalate to a complete process shutdown.'
    }

    $installedConfig = [IO.File]::ReadAllText($configPath)
    Assert-True ($installedConfig -match 'model = "test-model"') 'Unrelated top-level settings must be preserved.'
    Assert-True ($installedConfig -match 'unified_exec = true') 'Unrelated feature settings must be preserved.'
    Assert-True ($installedConfig -notmatch '(?m)^\s*sandbox_mode\s*=') 'Legacy sandbox_mode must be removed during migration.'
    Assert-True ($installedConfig -notmatch '(?m)^\s*\[sandbox_workspace_write\]') 'Legacy workspace section must be removed during migration.'
    Assert-True ($installedConfig -match 'default_permissions = "codex-safe-workspace"') 'Managed permission profile must become active.'
    Assert-True ($installedConfig -match '(?m)^\s*":root"\s*=\s*"deny"') 'Filesystem root must be denied.'
    Assert-True ($installedConfig -match '(?m)^\s*"\*\*/\.env"\s*=\s*"deny"') 'Workspace .env glob must be denied.'
    Assert-True ($installedConfig -match '(?ms)\[features\].*network_proxy = true') 'Allowlist mode must activate the network proxy.'
    Assert-True ($installedConfig -match '"example.com" = "allow"') 'Allowlisted domain must be written.'

    $assessment = (& $assessScript -CodexHome $codexHome -ConfigPath $configPath -AsJson) | ConvertFrom-Json
    Assert-True $assessment.ManagedLeastPrivilegeProfile 'Assessment must recognize the installed managed profile.'
    Assert-True ($assessment.CommandNetworkEnabled -and $assessment.NetworkProxyEnabled) 'Assessment must distinguish enabled network from active proxy enforcement.'
    Assert-True (-not $assessment.FullAccessDetected) 'Assessment must not report Full Access for the managed profile.'

    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pythonCommand) {
        $tomlParseOutput = @(& $pythonCommand.Source -c 'import sys,tomllib; tomllib.load(open(sys.argv[1], "rb"))' $configPath 2>&1)
        Assert-True ($LASTEXITCODE -eq 0) ("Generated config must parse as TOML: {0}" -f ($tomlParseOutput -join [Environment]::NewLine))
    }

    $verificationJson = & $testScript -CodexHome $codexHome -ConfigPath $configPath -StateRoot $stateRoot -AsJson
    $verification = $verificationJson | ConvertFrom-Json
    Assert-True ($verification.Overall -ne 'FAILED') ("Static verification must not fail after installation. Report: {0}" -f $verificationJson)
    $ruleCheck = @($verification.Checks | Where-Object Control -eq 'Rule engine')
    if (Get-Command codex -ErrorAction SilentlyContinue) {
        Assert-True ($ruleCheck.Count -eq 1 -and $ruleCheck[0].Status -eq 'PASS') 'Installed exact-prefix rule must pass codex execpolicy validation.'
    }
    $installState = Get-Content -LiteralPath (Join-Path $stateRoot 'install-state.json') -Raw | ConvertFrom-Json
    $installedCheckpointScript = $installState.BridgePath

    [IO.File]::WriteAllText((Join-Path $repository 'tracked.txt'), 'changed after checkpoint', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $repository 'ordinary-untracked.txt'), 'untracked', [Text.UTF8Encoding]::new($false))
    $branchBefore = (Invoke-GitTest -Repository $repository -GitArguments @('branch', '--show-current') | Select-Object -First 1).Trim()
    $indexBefore = (Invoke-GitTest -Repository $repository -GitArguments @('write-tree') | Select-Object -First 1).Trim()
    $checkpoint = & $installedCheckpointScript -Action Save -Repository $repository -Message 'test checkpoint'
    Assert-True ($checkpoint.Status -eq 'SAVED') 'Checkpoint bridge must return SAVED.'
    $branchAfter = (Invoke-GitTest -Repository $repository -GitArguments @('branch', '--show-current') | Select-Object -First 1).Trim()
    $indexAfter = (Invoke-GitTest -Repository $repository -GitArguments @('write-tree') | Select-Object -First 1).Trim()
    Assert-True ($branchBefore -eq $branchAfter) 'Checkpoint must not change the branch.'
    Assert-True ($indexBefore -eq $indexAfter) 'Checkpoint must not change the real index.'
    $checkpointContent = (Invoke-GitTest -Repository $repository -GitArguments @('show', "$($checkpoint.Commit):tracked.txt") | Select-Object -First 1).Trim()
    Assert-True ($checkpointContent -eq 'changed after checkpoint') 'Checkpoint commit must contain the working-tree version.'

    [IO.File]::WriteAllText((Join-Path $repository '.env'), 'SYNTHETIC_ONLY=not-a-secret', [Text.UTF8Encoding]::new($false))
    $refusedSensitive = $false
    try { & $installedCheckpointScript -Action Save -Repository $repository -Message 'must refuse' | Out-Null } catch { $refusedSensitive = $true }
    Assert-True $refusedSensitive 'Checkpoint must refuse sensitive-looking untracked files.'
    Remove-Item -LiteralPath (Join-Path $repository '.env') -Force

    $unauthorizedRepository = Join-Path $temporaryRoot 'unauthorized-repo'
    New-Item -ItemType Directory -Path $unauthorizedRepository | Out-Null
    Invoke-GitTest -Repository $unauthorizedRepository -GitArguments @('init') | Out-Null
    $unauthorizedRefused = $false
    try { & $installedCheckpointScript -Action List -Repository $unauthorizedRepository | Out-Null } catch { $unauthorizedRefused = $true }
    Assert-True $unauthorizedRefused 'Checkpoint bridge must refuse repositories not registered by the installer.'

    $stateOverrideRefused = $false
    try { & $installedCheckpointScript -Action List -Repository $repository -StateRoot $stateRoot | Out-Null } catch { $stateOverrideRefused = $true }
    Assert-True $stateOverrideRefused 'Installed bridge must not expose an authorization-registry override parameter.'

    $registryPath = Join-Path $stateRoot 'authorized-workspaces.json'
    $untamperedRegistry = [IO.File]::ReadAllText($registryPath)
    $tamperedRegistry = $untamperedRegistry | ConvertFrom-Json
    $tamperedRegistry.gitExecutableSha256 = ('0' * 64)
    [IO.File]::WriteAllText($registryPath, ($tamperedRegistry | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
    $gitPinRefused = $false
    try { & $installedCheckpointScript -Action List -Repository $repository | Out-Null } catch { $gitPinRefused = $true }
    Assert-True $gitPinRefused 'Checkpoint bridge must refuse a changed pinned-Git hash.'
    [IO.File]::WriteAllText($registryPath, $untamperedRegistry, [Text.UTF8Encoding]::new($false))

    $statePath = Join-Path $stateRoot 'install-state.json'
    $untamperedState = [IO.File]::ReadAllText($statePath)
    $tamperedState = $untamperedState | ConvertFrom-Json
    $tamperedState.ConfigPath = Join-Path $temporaryRoot 'unexpected-config.toml'
    [IO.File]::WriteAllText($statePath, ($tamperedState | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    $tamperedRollbackRefused = $false
    try { & $rollbackScript -CodexHome $codexHome -StateRoot $stateRoot -ConfirmRollback -NonInteractive | Out-Null } catch { $tamperedRollbackRefused = $true }
    Assert-True $tamperedRollbackRefused 'Rollback must refuse state that redirects a target outside its fixed layout.'
    [IO.File]::WriteAllText($statePath, $untamperedState, [Text.UTF8Encoding]::new($false))

    & $rollbackScript -CodexHome $codexHome -StateRoot $stateRoot -ConfirmRollback -NonInteractive | Out-Null
    $restoredConfig = [IO.File]::ReadAllText($configPath)
    Assert-True ($restoredConfig -eq $originalConfig) 'Rollback must restore the exact original configuration.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $codexHome 'rules\codex-safe-setup.rules'))) 'Rollback must remove a newly created rule file.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $stateRoot 'bin\New-CodexCheckpoint.ps1'))) 'Rollback must remove a newly installed bridge.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $stateRoot 'authorized-workspaces.json'))) 'Rollback must remove a newly created workspace registry.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $stateRoot 'outside-workspace-canary.txt'))) 'Rollback must remove a newly created synthetic canary.'

    Write-Output 'PASS: configuration migration and preservation'
    Write-Output 'PASS: read-only assessment classification'
    Write-Output 'PASS: migration-consent and domain-injection guards'
    Write-Output 'PASS: unrestricted-network disclosure and acknowledgement guard'
    Write-Output 'PASS: Custom permission activation handoff'
    if ($env:OS -eq 'Windows_NT') { Write-Output 'PASS: elevated sandbox proxy-port oscillation diagnostics' }
    Write-Output 'PASS: least-privilege and allowlist generation'
    Write-Output 'PASS: static and execpolicy verification'
    Write-Output 'PASS: branch/index-neutral Git checkpoint'
    Write-Output 'PASS: sensitive-file, registry-override, Git-pin, and unauthorized-repository refusals'
    Write-Output 'PASS: rollback target-lock validation'
    Write-Output 'PASS: exact rollback'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        $resolvedTemporary = [IO.Path]::GetFullPath($temporaryRoot)
        $systemTemporary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolvedTemporary.StartsWith($systemTemporary, [StringComparison]::OrdinalIgnoreCase) -or $resolvedTemporary -eq $systemTemporary) {
            throw "Refusing to remove unexpected test path: $resolvedTemporary"
        }
        Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force
    }
}
