[CmdletBinding()]
param(
    [string]$CodexHome,
    [string]$ConfigPath,
    [string]$StateRoot,
    [switch]$SkipCliRuleCheck,
    [switch]$AsJson
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$resolvedHome = Get-CssCodexHome -Override $CodexHome
$resolvedConfig = Get-CssConfigPath -CodexHome $resolvedHome -Override $ConfigPath
$resolvedState = Get-CssStateRoot -CodexHome $resolvedHome -Override $StateRoot
$configText = Read-CssText -Path $resolvedConfig
$statePath = Join-Path $resolvedState 'install-state.json'
$state = $null
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { $state = $null }
}

$checks = [Collections.Generic.List[object]]::new()
if (-not $configText) {
    $checks.Add((New-CssCheck -Status FAIL -Control 'Configuration' -Evidence "Missing or empty: $resolvedConfig"))
}
else {
    $profileSectionText = Get-CssTomlSectionText -Text $configText -Section 'permissions.codex-safe-workspace'
    $filesystemSectionText = Get-CssTomlSectionText -Text $configText -Section 'permissions.codex-safe-workspace.filesystem'
    $workspaceSectionText = Get-CssTomlSectionText -Text $configText -Section 'permissions.codex-safe-workspace.filesystem.":workspace_roots"'
    $checks.Add((New-CssCheck -Status $(if ($configText -match '(?m)^\s*default_permissions\s*=\s*"codex-safe-workspace"') { 'PASS' } else { 'FAIL' }) -Control 'Active profile' -Evidence 'default_permissions must select codex-safe-workspace'))
    $checks.Add((New-CssCheck -Status $(if ($filesystemSectionText -match '(?m)^\s*":root"\s*=\s*"deny"') { 'PASS' } else { 'FAIL' }) -Control 'Reads outside workspace' -Evidence 'root deny is present in the active managed filesystem table'))
    $checks.Add((New-CssCheck -Status $(if ($filesystemSectionText -match '(?m)^\s*":minimal"\s*=\s*"read"') { 'PASS' } else { 'FAIL' }) -Control 'Minimal runtime reads' -Evidence 'minimal runtime read grant is present in the active managed filesystem table'))
    $checks.Add((New-CssCheck -Status $(if ($workspaceSectionText -match '(?m)^\s*"\."\s*=\s*"write"') { 'PASS' } else { 'FAIL' }) -Control 'Workspace writes' -Evidence 'workspace root write grant is present in the active managed workspace table'))
    $checks.Add((New-CssCheck -Status $(if ($workspaceSectionText -match '(?m)^\s*"\*\*/\.env"\s*=\s*"deny"') { 'PASS' } else { 'PARTIAL' }) -Control 'Workspace secret reads' -Evidence 'common credential deny globs are in the active managed workspace table'))
    $checks.Add((New-CssCheck -Status $(if ($profileSectionText -match '(?m)^\s*extends\s*=\s*":workspace"') { 'PASS' } else { 'FAIL' }) -Control 'Protected metadata' -Evidence 'The managed profile inherits .git, .codex, and .agents protection from :workspace'))
    $legacy = Test-CssLegacySettings -Text $configText
    $checks.Add((New-CssCheck -Status $(if ($legacy.Present) { 'FAIL' } else { 'PASS' }) -Control 'Configuration precedence' -Evidence 'legacy sandbox settings must not override permission profiles'))
    $activeFullAccess = $configText -match '(?m)^\s*(default_permissions|sandbox_mode)\s*=\s*["'']:?danger-full-access["'']'
    $checks.Add((New-CssCheck -Status $(if ($activeFullAccess) { 'FAIL' } else { 'PASS' }) -Control 'Full Access' -Evidence 'No active top-level danger-full-access selection was found'))
}

if ($state) {
    $stateSchema = if ($state.PSObject.Properties['schemaVersion']) { [int]$state.schemaVersion } else { 0 }
    $stateVersion = if ($state.PSObject.Properties['productVersion']) { [string]$state.productVersion } else { '<legacy>' }
    $stateCurrent = $stateSchema -eq $script:CssStateSchemaVersion -and $stateVersion -eq $script:CssProductVersion
    $checks.Add((New-CssCheck -Status $(if ($stateCurrent) { 'PASS' } else { 'FAIL' }) -Control 'Install state schema' -Evidence "Expected schema $($script:CssStateSchemaVersion) and product $($script:CssProductVersion); found schema $stateSchema and product $stateVersion. Run Upgrade-CodexSafety.ps1 when this is legacy state."))
    if ($state.PSObject.Properties['operation'] -and $state.operation -eq 'Upgrade') {
        $historyOkay = $state.PSObject.Properties['previousStateSnapshot'] -and $state.previousStateSnapshot -and (Test-Path -LiteralPath $state.previousStateSnapshot -PathType Leaf)
        $checks.Add((New-CssCheck -Status $(if ($historyOkay) { 'PASS' } else { 'FAIL' }) -Control 'Upgrade rollback chain' -Evidence 'An upgrade must retain an immutable previous-state snapshot.'))
    }

    $approvalExpected = if ($state.ApprovalMode -eq 'BoundedAutonomy') { 'never' } else { 'on-request' }
    $approvalOkay = $configText -match ('(?m)^\s*approval_policy\s*=\s*"' + [regex]::Escape($approvalExpected) + '"')
    $checks.Add((New-CssCheck -Status $(if ($approvalOkay) { 'PASS' } else { 'FAIL' }) -Control 'Approval policy' -Evidence "Expected $approvalExpected for $($state.ApprovalMode)"))

    $networkSectionText = Get-CssTomlSectionText -Text $configText -Section 'permissions.codex-safe-workspace.network'
    $networkDomainsSectionText = Get-CssTomlSectionText -Text $configText -Section 'permissions.codex-safe-workspace.network.domains'
    $featuresSectionText = Get-CssTomlSectionText -Text $configText -Section 'features'
    $networkEnabled = $networkSectionText -match '(?m)^\s*enabled\s*=\s*true'
    $proxyEnabled = $featuresSectionText -match '(?m)^\s*network_proxy\s*=\s*true'
    $hasDomainRules = -not [string]::IsNullOrWhiteSpace($networkDomainsSectionText)
    $configuredDomains = @([regex]::Matches($networkDomainsSectionText, '(?m)^\s*"(?<domain>[^"]+)"\s*=\s*"allow"\s*$') | ForEach-Object { $_.Groups['domain'].Value } | Sort-Object -Unique)
    $recordedDomains = @()
    if ($state.PSObject.Properties['AllowedDomains']) { $recordedDomains = @($state.AllowedDomains | Sort-Object -Unique) }
    if ($state.NetworkMode -eq 'Off') {
        $networkOkay = -not $networkEnabled -and -not $proxyEnabled -and -not $hasDomainRules -and $recordedDomains.Count -eq 0
        $checks.Add((New-CssCheck -Status $(if ($networkOkay) { 'PASS' } else { 'FAIL' }) -Control 'Command network configuration' -Evidence 'Off requires network disabled, proxy disabled, and no domain rules'))
    }
    elseif ($state.NetworkMode -eq 'Allowlist') {
        $domainsMatchState = $configuredDomains.Count -gt 0 -and (($configuredDomains -join [Environment]::NewLine) -eq ($recordedDomains -join [Environment]::NewLine))
        $hasGlobalWildcard = $networkDomainsSectionText -match '(?m)^\s*"\*"\s*=\s*"allow"'
        $networkOkay = $networkEnabled -and $proxyEnabled -and $domainsMatchState -and -not $hasGlobalWildcard
        $checks.Add((New-CssCheck -Status $(if ($networkOkay) { 'PASS' } else { 'FAIL' }) -Control 'Command network configuration' -Evidence 'Allowlist requires enabled network, an active proxy, exact recorded allow rules, and no global wildcard'))
    }
    elseif ($state.NetworkMode -eq 'Unrestricted') {

        $networkOkay = $networkEnabled -and -not $proxyEnabled -and -not $hasDomainRules -and $recordedDomains.Count -eq 0
        $checks.Add((New-CssCheck -Status $(if ($networkOkay) { 'PASS' } else { 'FAIL' }) -Control 'Command network configuration' -Evidence 'Unrestricted requires direct network access with the filtering proxy disabled and no inert domain table'))
    }
    else {
        $checks.Add((New-CssCheck -Status FAIL -Control 'Command network configuration' -Evidence "Unknown recorded network mode: $($state.NetworkMode)"))
    }

    $backupOkay = (-not $state.OriginalConfigExists) -or ($state.ConfigBackup -and (Test-Path -LiteralPath $state.ConfigBackup -PathType Leaf))
    $checks.Add((New-CssCheck -Status $(if ($backupOkay) { 'PASS' } else { 'FAIL' }) -Control 'Rollback' -Evidence 'Original configuration backup or new-file marker is available'))

    if ($env:OS -eq 'Windows_NT' -and $state.WindowsSandbox -eq 'Elevated') {
        $sandboxHealth = Get-CssWindowsSandboxSetupHealth -CodexHome $resolvedHome -ExpectedProxyPort $(if ($state.NetworkMode -eq 'Allowlist') { @(3128, 8081) } else { @() })
        $sandboxStatus = if ($sandboxHealth.Status -eq 'CONFLICT') { 'FAIL' } elseif ($sandboxHealth.LatestDesiredMatchesExpected -or $sandboxHealth.Status -eq 'ALIGNED') { 'PASS' } else { 'PARTIAL' }
        $checks.Add((New-CssCheck -Status $sandboxStatus -Control 'Elevated sandbox activation' -Evidence $sandboxHealth.Evidence))
    }

    if ($state.BridgePath) {
        $bridgeOkay = Test-Path -LiteralPath $state.BridgePath -PathType Leaf
        $rulesOkay = Test-Path -LiteralPath $state.RulesPath -PathType Leaf
        $checks.Add((New-CssCheck -Status $(if ($bridgeOkay -and $rulesOkay) { 'PASS' } else { 'FAIL' }) -Control 'Checkpoint bridge' -Evidence 'Exact bridge and rules files exist outside workspace'))
        if (-not $SkipCliRuleCheck) {
            $codexCommand = Get-Command codex -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $codexCommand) {
                $checks.Add((New-CssCheck -Status PARTIAL -Control 'Rule engine' -Evidence 'Codex CLI is unavailable; execpolicy was not tested'))
            }
            elseif ($bridgeOkay -and $rulesOkay) {
                $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $pwshCommand) {
                    $checks.Add((New-CssCheck -Status FAIL -Control 'Rule engine' -Evidence 'Checkpoint rule requires PowerShell 7'))
                }
                else {
                    $activeRuleFiles = [Collections.Generic.List[string]]::new()
                    $userRulesRoot = Join-Path $resolvedHome 'rules'
                    if (Test-Path -LiteralPath $userRulesRoot -PathType Container) {
                        Get-ChildItem -LiteralPath $userRulesRoot -Filter '*.rules' -File | ForEach-Object { $activeRuleFiles.Add($_.FullName) }
                    }
                    if ($state.RegisteredWorkspace) {
                        $projectRulesRoot = Join-Path (Join-Path $state.RegisteredWorkspace '.codex') 'rules'
                        if (Test-Path -LiteralPath $projectRulesRoot -PathType Container) {
                            Get-ChildItem -LiteralPath $projectRulesRoot -Filter '*.rules' -File | ForEach-Object { $activeRuleFiles.Add($_.FullName) }
                        }
                    }
                    $ruleArguments = [Collections.Generic.List[string]]::new()
                    $ruleArguments.Add('execpolicy'); $ruleArguments.Add('check'); $ruleArguments.Add('--pretty')
                    foreach ($ruleFile in @($activeRuleFiles | Sort-Object -Unique)) { $ruleArguments.Add('--rules'); $ruleArguments.Add($ruleFile) }
                    $exactArguments = @($ruleArguments) + @('--', $pwshCommand.Source, '-NoProfile', '-NonInteractive', '-File', $state.BridgePath, '-Action', 'List', '-Repository', $state.RegisteredWorkspace)
                    $output = @(& $codexCommand.Source @exactArguments 2>&1)
                    $decisionAllowed = $LASTEXITCODE -eq 0 -and (($output -join [Environment]::NewLine) -match '(?i)"decision"\s*:\s*"allow"')
                    $checks.Add((New-CssCheck -Status $(if ($decisionAllowed) { 'PASS' } else { 'FAIL' }) -Control 'Rule engine' -Evidence $(if ($decisionAllowed) { 'Exact checkpoint invocation resolves to allow' } else { 'execpolicy did not confirm the exact allow rule' })))

                    $unsafeProbes = @(
                        @($pwshCommand.Source, '-NoProfile', '-Command', 'Remove-Item -Recurse -Force C:\'),
                        @('git', 'reset', '--hard', 'HEAD'),
                        @('cmd.exe', '/c', 'del', '/s', '/q', 'C:\*')
                    )
                    $unsafeAllowed = $false
                    foreach ($probe in $unsafeProbes) {
                        $probeArguments = @($ruleArguments) + @('--') + @($probe)
                        $probeOutput = @(& $codexCommand.Source @probeArguments 2>&1)
                        if ($LASTEXITCODE -ne 0 -or (($probeOutput -join [Environment]::NewLine) -match '(?i)"decision"\s*:\s*"allow"')) {
                            $unsafeAllowed = $true
                            break
                        }
                    }
                    $checks.Add((New-CssCheck -Status $(if ($unsafeAllowed) { 'FAIL' } else { 'PASS' }) -Control 'Rule escape probes' -Evidence $(if ($unsafeAllowed) { 'An active rule allowed or failed to evaluate a broad shell/destructive Git probe' } else { 'Active user/project rules did not allow broad PowerShell, Git reset, or cmd deletion probes' })))
                }
            }
        }
    }
    else {
        $checks.Add((New-CssCheck -Status PARTIAL -Control 'Workspace deletion recovery' -Evidence 'No Git workspace was registered for checkpoints'))
    }
}
else {
    $checks.Add((New-CssCheck -Status FAIL -Control 'Install state' -Evidence "Missing or invalid: $statePath"))
}

$runtimeNetworkEvidence = if (-not $state) {
    'Install state is unavailable, so the expected runtime network behavior is unknown'
}
elseif ($state.NetworkMode -eq 'Off') {
    'A fresh task must prove that a known-reachable external TCP endpoint is blocked'
}
elseif ($state.NetworkMode -eq 'Allowlist') {
    'A fresh task must prove one allowed destination succeeds through the proxy and one denied destination fails; proxy-unaware tools require an explicit proxy adapter'
}
else {
    'A fresh task must prove a direct TCP connection succeeds with a native client such as Test-NetConnection or OpenSSH; a proxy-only banner is not sufficient'
}
$checks.Add((New-CssCheck -Status PARTIAL -Control 'Runtime command egress' -Evidence $runtimeNetworkEvidence))
$checks.Add((New-CssCheck -Status PARTIAL -Control 'Runtime filesystem enforcement' -Evidence 'Restart Codex, select Custom, and run a new sandboxed task to prove OS filesystem enforcement; fully quit all Codex processes only if administrator prompts repeat'))
$checks.Add((New-CssCheck -Status 'NOT CONTROLLED' -Control 'Other egress surfaces' -Evidence 'Web Search, Browser, Computer Use, apps, plugins, MCP, and cloud tasks use separate controls'))

$overall = if (@($checks | Where-Object Status -eq 'FAIL').Count -gt 0) { 'FAILED' } elseif (@($checks | Where-Object Status -eq 'PARTIAL').Count -gt 0) { 'PARTIALLY VERIFIED' } else { 'VERIFIED' }
$report = [pscustomobject]@{ Overall = $overall; ConfigPath = $resolvedConfig; Checks = $checks }
if ($AsJson) { $report | ConvertTo-Json -Depth 6 } else { Write-Output "Codex Safe Setup - $overall"; $checks | Format-Table -AutoSize | Out-String | Write-Output }
if ($overall -eq 'FAILED') { exit 1 }
