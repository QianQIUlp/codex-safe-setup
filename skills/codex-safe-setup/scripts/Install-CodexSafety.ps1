[CmdletBinding()]
param(
    [ValidateSet('BoundedAutonomy', 'AskMe', 'AutoReview')][string]$ApprovalMode = 'BoundedAutonomy',
    [ValidateSet('Off', 'Allowlist', 'Unrestricted')][string]$NetworkMode = 'Off',
    [string[]]$AllowedDomain = @(),
    [ValidateSet('Elevated', 'Unelevated', 'Keep')][string]$WindowsSandbox = 'Elevated',
    [bool]$ProtectWorkspaceSecrets = $true,
    [bool]$AllowTempWrite = $false,
    [string]$WorkspacePath,
    [bool]$EnableGitCommitBridge = $false,
    [string[]]$CommitBranchPrefix = @('codex/'),
    [string]$CodexHome,
    [string]$ConfigPath,
    [string]$StateRoot,
    [switch]$Upgrade,
    [switch]$MigrateLegacySettings,
    [switch]$AcknowledgeRisk,
    [switch]$AcknowledgeAdminSetup,
    [switch]$PlanOnly,
    [switch]$ConfirmApply,
    [switch]$NonInteractive
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$ErrorActionPreference = 'Stop'

$resolvedHome = Get-CssCodexHome -Override $CodexHome
$resolvedConfig = Get-CssConfigPath -CodexHome $resolvedHome -Override $ConfigPath
$resolvedState = Get-CssStateRoot -CodexHome $resolvedHome -Override $StateRoot
$statePath = Join-Path $resolvedState 'install-state.json'
$existingState = $null
$existingStateText = $null
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try {
        $existingStateText = Get-Content -LiteralPath $statePath -Raw
        $existingState = $existingStateText | ConvertFrom-Json
    }
    catch {
        throw "Existing install state is unreadable. Refusing to overwrite it: $statePath"
    }
}
if ($existingState -and -not $Upgrade) {
    throw "An existing Codex Safe Setup installation was found. Use Upgrade-CodexSafety.ps1 so prior choices, backups, and rollback history are preserved."
}
if ($Upgrade -and -not $existingState) {
    throw "Upgrade requested, but no install state exists at $statePath. Use Install-CodexSafety.ps1 for a first installation."
}
if ($existingState -and $existingState.PSObject.Properties['schemaVersion'] -and [int]$existingState.schemaVersion -gt $script:CssStateSchemaVersion) {
    throw "Install state schema $($existingState.schemaVersion) is newer than this installer supports. Update the plugin before changing configuration."
}
$previousVersion = if ($existingState -and $existingState.PSObject.Properties['productVersion']) {
    [string]$existingState.productVersion
}
elseif ($existingState -and $existingState.PSObject.Properties['installerVersion']) {
    [string]$existingState.installerVersion
}
elseif ($existingState) {
    '0.1.1-or-earlier'
}
else {
    $null
}
$filesystemRoot = [IO.Path]::GetPathRoot($resolvedHome)
$pathTrimCharacters = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$pathComparison = if ($env:OS -eq 'Windows_NT') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
if ([string]::Equals($resolvedHome.TrimEnd($pathTrimCharacters), $filesystemRoot.TrimEnd($pathTrimCharacters), $pathComparison)) {
    throw "Refusing to use a filesystem root as CodexHome: $resolvedHome"
}
$expectedConfig = [IO.Path]::GetFullPath((Join-Path $resolvedHome 'config.toml'))
$expectedState = [IO.Path]::GetFullPath((Join-Path $resolvedHome 'safe-setup'))
if (-not [string]::Equals($resolvedConfig, $expectedConfig, $pathComparison)) {
    throw "ConfigPath must resolve to the config.toml directly under CodexHome: $expectedConfig"
}
if (-not [string]::Equals($resolvedState, $expectedState, $pathComparison)) {
    throw "StateRoot must resolve to the safe-setup directory directly under CodexHome: $expectedState"
}
$existingConfig = Read-CssText -Path $resolvedConfig
$legacy = Test-CssLegacySettings -Text $existingConfig

$codexCommandForVersion = Get-Command codex -ErrorAction SilentlyContinue | Select-Object -First 1
if ($codexCommandForVersion) {
    $codexVersionText = (& $codexCommandForVersion.Source --version 2>$null | Select-Object -First 1)
    if ($codexVersionText -and $codexVersionText.ToString() -match '(\d+\.\d+\.\d+)' -and [version]$Matches[1] -lt [version]'0.138.0') {
        throw "Codex CLI $($Matches[1]) is too old for the managed permission-profile format. Update Codex or use a compatible installer version."
    }
}

if ($legacy.Present -and -not $MigrateLegacySettings) {
    throw 'Legacy sandbox settings are present. Review the plan and rerun with -MigrateLegacySettings to replace the conflicting keys with a backed-up permission profile.'
}
if ($NetworkMode -eq 'Allowlist' -and $AllowedDomain.Count -eq 0) {
    throw 'Allowlist mode requires at least one -AllowedDomain.'
}
if ($NetworkMode -ne 'Allowlist' -and $AllowedDomain.Count -gt 0) {
    throw '-AllowedDomain is valid only with -NetworkMode Allowlist.'
}
foreach ($domain in $AllowedDomain) {
    if ($domain -notmatch '^(\*\*?\.)?([A-Za-z0-9-]+\.)*[A-Za-z0-9-]+$') {
        throw "Invalid domain pattern '$domain'. Use a hostname or a leading *. / **. wildcard without a scheme, port, path, or quotes."
    }
}

if ($EnableGitCommitBridge -and -not $WorkspacePath) {
    throw '-EnableGitCommitBridge requires -WorkspacePath so the exact worktree can be registered.'
}
if ($CommitBranchPrefix.Count -eq 0) {
    throw 'At least one literal -CommitBranchPrefix is required.'
}
foreach ($prefix in $CommitBranchPrefix) {
    if ([string]::IsNullOrWhiteSpace($prefix) -or $prefix -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*/$' -or $prefix.Contains('..') -or $prefix.Contains('//')) {
        throw "Invalid commit branch prefix '$prefix'. Use a literal prefix ending in '/', for example codex/."
    }
}
$unrestrictedRiskSummary = @(
    'This network choice does not expand filesystem permissions or add deletion authority; existing workspace write and delete capability still applies.'
    'The command proxy and its destination filter are disabled so ordinary direct-network protocols, including SSH, can work. Any data a command can already read or generate could be sent to any public Internet destination, including source, configuration, private data, command output, or credentials missed by filename deny rules.'
    'Untrusted pages, issues, and dependency documentation can contain prompt injection; networked commands can also download malware, vulnerable dependencies, or license-restricted content.'
    'Unrestricted access does not mean a leak will happen automatically, but it increases the possible consequence of human, model, or prompt-injection mistakes. Prefer Allowlist for normal work.'
) -join ' '

$approvalPolicy = 'never'
$approvalReviewer = 'user'
if ($ApprovalMode -eq 'AskMe') { $approvalPolicy = 'on-request' }
if ($ApprovalMode -eq 'AutoReview') { $approvalPolicy = 'on-request'; $approvalReviewer = 'auto_review' }

$newConfig = Remove-CssManagedBlock -Text $existingConfig
if ($MigrateLegacySettings) {
    $newConfig = Remove-CssTomlTopLevelKeys -Text $newConfig -Keys @('sandbox_mode')
    $newConfig = Remove-CssTomlSections -Text $newConfig -SectionPrefixes @('sandbox_workspace_write')
}
$newConfig = Remove-CssTomlSections -Text $newConfig -SectionPrefixes @("permissions.$($script:CssProfileName)")
$newConfig = Set-CssTomlTopLevelValue -Text $newConfig -Key 'default_permissions' -Literal (ConvertTo-CssTomlString $script:CssProfileName)
$newConfig = Set-CssTomlTopLevelValue -Text $newConfig -Key 'approval_policy' -Literal (ConvertTo-CssTomlString $approvalPolicy)
$newConfig = Set-CssTomlTopLevelValue -Text $newConfig -Key 'approvals_reviewer' -Literal (ConvertTo-CssTomlString $approvalReviewer)

# Network filtering is active only for Allowlist; Off and Unrestricted disable stale proxy state.
$proxyEnabled = $NetworkMode -eq 'Allowlist'
$newConfig = Set-CssTomlSectionValue -Text $newConfig -Section 'features' -Key 'network_proxy' -Literal $(if ($proxyEnabled) { 'true' } else { 'false' })
if ($WindowsSandbox -ne 'Keep' -and $env:OS -eq 'Windows_NT') {
    $sandboxLiteral = if ($WindowsSandbox -eq 'Elevated') { 'elevated' } else { 'unelevated' }
    $newConfig = Set-CssTomlSectionValue -Text $newConfig -Section 'windows' -Key 'sandbox' -Literal (ConvertTo-CssTomlString $sandboxLiteral)
}

$managedLines = [Collections.Generic.List[string]]::new()
$managedLines.Add($script:CssManagedStart)
$managedLines.Add('# Generated by Install-CodexSafety.ps1. Re-run the installer instead of editing this block.')
$managedLines.Add("[permissions.$($script:CssProfileName)]")
$managedLines.Add('extends = ":workspace"')
$managedLines.Add('')
$managedLines.Add("[permissions.$($script:CssProfileName).filesystem]")
$managedLines.Add('":root" = "deny"')
$managedLines.Add('":minimal" = "read"')
if (-not $AllowTempWrite) {
    $managedLines.Add('":tmpdir" = "deny"')
    $managedLines.Add('":slash_tmp" = "deny"')
}
if ($ProtectWorkspaceSecrets) { $managedLines.Add('glob_scan_max_depth = 6') }
$managedLines.Add('')
$managedLines.Add(('[permissions.{0}.filesystem.":workspace_roots"]' -f $script:CssProfileName))
$managedLines.Add('"." = "write"')
if ($ProtectWorkspaceSecrets) {
    foreach ($pattern in @('.env', '.env.*', '**/.env', '**/.env.*', '**/.npmrc', '**/.pypirc', '**/.netrc', '**/credentials.json', '**/service-account.json', '**/*.pem', '**/*.key', '**/*.pfx', '**/*.p12')) {
        $managedLines.Add((ConvertTo-CssTomlString $pattern) + ' = "deny"')
    }
}
$managedLines.Add('')
$managedLines.Add("[permissions.$($script:CssProfileName).network]")
$managedLines.Add('enabled = ' + $(if ($NetworkMode -eq 'Off') { 'false' } else { 'true' }))
if ($NetworkMode -eq 'Allowlist') {
    $managedLines.Add('')
    $managedLines.Add("[permissions.$($script:CssProfileName).network.domains]")
    foreach ($domain in ($AllowedDomain | Sort-Object -Unique)) {
        $managedLines.Add((ConvertTo-CssTomlString $domain) + ' = "allow"')
    }
}
$managedLines.Add($script:CssManagedEnd)
$managedBlock = $managedLines -join [Environment]::NewLine
$newConfig = $newConfig.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $managedBlock + [Environment]::NewLine

$resolvedWorkspace = $null
if ($WorkspacePath) {
    $gitCommandForBridge = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $gitCommandForBridge) { throw 'Git is required to register a checkpoint workspace.' }
    $resolvedWorkspace = Get-CssRepositoryRoot -Path $WorkspacePath
    $gitExecutableForBridge = [IO.Path]::GetFullPath($gitCommandForBridge.Source)
    $gitExecutableHash = (Get-FileHash -LiteralPath $gitExecutableForBridge -Algorithm SHA256).Hash
}
$recordedWorkspace = $resolvedWorkspace
if (-not $recordedWorkspace -and $existingState -and $existingState.PSObject.Properties['RegisteredWorkspace']) {
    $recordedWorkspace = [string]$existingState.RegisteredWorkspace
}

$operation = if ($Upgrade) { 'Upgrade' } else { 'Install' }
$previousApprovalMode = if ($existingState -and $existingState.PSObject.Properties['ApprovalMode']) { [string]$existingState.ApprovalMode } else { $null }
$previousNetworkMode = if ($existingState -and $existingState.PSObject.Properties['NetworkMode']) { [string]$existingState.NetworkMode } else { $null }
$previousWindowsSandbox = if ($existingState -and $existingState.PSObject.Properties['WindowsSandbox']) { [string]$existingState.WindowsSandbox } else { $null }

$plan = [pscustomobject]@{
    Operation = $operation
    ProductVersion = $script:CssProductVersion
    StateSchema = $script:CssStateSchemaVersion
    PreviousVersion = $previousVersion
    PreviousApprovalMode = $previousApprovalMode
    PreviousNetworkMode = $previousNetworkMode
    PreviousWindowsSandbox = $previousWindowsSandbox
    ConfigurationChanged = [bool]($newConfig -ne $existingConfig)
    ConfigPath = $resolvedConfig
    StateRoot = $resolvedState
    ApprovalMode = $ApprovalMode
    ApprovalPolicy = $approvalPolicy
    ApprovalReviewer = $approvalReviewer
    NetworkMode = $NetworkMode
    NetworkRoute = $(switch ($NetworkMode) { 'Off' { 'Offline; proxy disabled' } 'Allowlist' { 'Proxy-enforced domain allowlist' } 'Unrestricted' { 'Direct unrestricted network; proxy disabled' } })
    AllowedDomains = $AllowedDomain
    NetworkRisk = $(if ($NetworkMode -eq 'Unrestricted') { $unrestrictedRiskSummary } else { 'No unrestricted command-network access selected.' })
    Filesystem = 'deny root; read minimal runtime; write workspace roots'
    ProtectWorkspaceSecrets = $ProtectWorkspaceSecrets
    AllowTempWrite = $AllowTempWrite
    WindowsSandbox = $WindowsSandbox
    MigrateLegacySettings = [bool]$MigrateLegacySettings
    RegisteredWorkspace = $recordedWorkspace
    CheckpointBridge = $(if ($resolvedWorkspace) { 'Install when PowerShell 7 is available' } else { 'Not requested' })
    GitCommitBridge = $(if ($EnableGitCommitBridge) { "Enabled only for explicit paths on branches matching: $($CommitBranchPrefix -join ', ')" } else { 'Disabled' })
    SharedGitMetadata = 'Remains protected from direct sandbox writes; linked-worktree commits use the constrained bridge.'
    ExternalSurfaces = 'Web Search, Browser, Computer Use, apps, plugins, MCP, and cloud tasks are not controlled.'
}

Write-Output 'Codex Safe Setup - change plan'
$plan | Format-List | Out-String | Write-Output
if ($PlanOnly) {
    Write-Output 'No files changed (PlanOnly).'
    return
}

if ($NetworkMode -eq 'Unrestricted' -and -not $AcknowledgeRisk) {
    if ($NonInteractive) { throw 'Unrestricted command networking requires -AcknowledgeRisk.' }
    Write-Warning 'Unrestricted command-network risk disclosure:'
    Write-Output '  - This choice does not expand filesystem permissions or add deletion authority; existing workspace write and delete capability still applies.'
    Write-Output '  - Any data a command can already read or generate could be sent to any public Internet destination, including source, configuration, private data, command output, or credentials missed by filename deny rules.'
    Write-Output '  - Direct protocols such as native SSH are enabled because the filtering proxy is disabled.'
    Write-Output '  - Prompt injection in pages, issues, or dependency documentation can induce exfiltration or unsafe commands.'
    Write-Output '  - Networked commands can download malware, vulnerable dependencies, or license-restricted content.'
    Write-Output '  - A leak is not automatic, but removing destination containment increases the consequence of mistakes. Prefer Allowlist for normal work.'
    $riskAnswer = Read-Host 'I understand and accept unrestricted command-network risk. Continue? [y/N]'
    if ($riskAnswer -notmatch '^(?i:y|yes)$') { throw 'Installation cancelled.' }
}
if ($WindowsSandbox -eq 'Elevated' -and $env:OS -eq 'Windows_NT' -and -not $AcknowledgeAdminSetup) {
    if ($NonInteractive) { throw 'Elevated Windows sandbox selection requires -AcknowledgeAdminSetup.' }
    $adminAnswer = Read-Host 'The elevated Windows sandbox may require an administrator-approved setup prompt. Continue? [y/N]'
    if ($adminAnswer -notmatch '^(?i:y|yes)$') { throw 'Installation cancelled.' }
}
if (-not $ConfirmApply) {
    if ($NonInteractive) { throw 'Non-interactive application requires -ConfirmApply.' }
    $applyAnswer = Read-Host 'Apply this exact plan and create a rollback backup? [y/N]'
    if ($applyAnswer -notmatch '^(?i:y|yes)$') { throw 'Installation cancelled.' }
}

$timestamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$transactionId = '{0}-{1}' -f $timestamp, [guid]::NewGuid().ToString('N').Substring(0, 8)
$historyRoot = Join-Path $resolvedState 'state-history'
$backupRoot = Join-Path (Join-Path $resolvedState 'backups') $transactionId
$previousStateSnapshot = $null
$binaryRoot = Join-Path $resolvedState 'bin'
$rulesRoot = Join-Path $resolvedHome 'rules'
$rulesPath = Join-Path $rulesRoot 'codex-safe-setup.rules'
$bridgePath = Join-Path $binaryRoot 'New-CodexCheckpoint.ps1'
$authorizedPath = Join-Path $resolvedState 'authorized-workspaces.json'
$canaryPath = Join-Path $resolvedState 'outside-workspace-canary.txt'
$configBackup = Join-Path $backupRoot ("config.$timestamp.toml")
$rulesBackup = Join-Path $backupRoot ("rules.$timestamp.bak")
$bridgeBackup = Join-Path $backupRoot ("bridge.$timestamp.bak")
$authorizedBackup = Join-Path $backupRoot ("authorized-workspaces.$timestamp.bak")
$canaryBackup = Join-Path $backupRoot ("canary.$timestamp.bak")
$originalConfigExists = Test-Path -LiteralPath $resolvedConfig -PathType Leaf
$originalRulesExists = Test-Path -LiteralPath $rulesPath -PathType Leaf
$originalBridgeExists = Test-Path -LiteralPath $bridgePath -PathType Leaf
$originalAuthorizedExists = Test-Path -LiteralPath $authorizedPath -PathType Leaf
$originalCanaryExists = Test-Path -LiteralPath $canaryPath -PathType Leaf

New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
New-Item -ItemType Directory -Path $binaryRoot -Force | Out-Null
New-Item -ItemType Directory -Path $rulesRoot -Force | Out-Null
New-Item -ItemType Directory -Path $historyRoot -Force | Out-Null
if ($existingStateText) {
    $previousStateSnapshot = Join-Path $historyRoot ("install-state.{0}.{1}.json" -f $timestamp, $transactionId)
    Write-CssTextAtomic -Path $previousStateSnapshot -Text $existingStateText
}
if ($originalConfigExists) { Copy-Item -LiteralPath $resolvedConfig -Destination $configBackup -Force }
if ($originalRulesExists) { Copy-Item -LiteralPath $rulesPath -Destination $rulesBackup -Force }
if ($originalBridgeExists) { Copy-Item -LiteralPath $bridgePath -Destination $bridgeBackup -Force }
if ($originalAuthorizedExists) { Copy-Item -LiteralPath $authorizedPath -Destination $authorizedBackup -Force }
if ($originalCanaryExists) { Copy-Item -LiteralPath $canaryPath -Destination $canaryBackup -Force }

$bridgeInstalled = $false
$ruleInstalled = $false
$authorizedTouched = [bool]$resolvedWorkspace
$canaryTouched = $true
try {
    Write-CssTextAtomic -Path $resolvedConfig -Text $newConfig
    Write-CssTextAtomic -Path $canaryPath -Text ("Synthetic canary only: {0}" -f [guid]::NewGuid().ToString('N'))

    if ($resolvedWorkspace) {
        $authorizedRoots = @()
        $commitRoots = @()
        if (Test-Path -LiteralPath $authorizedPath -PathType Leaf) {
            try {
                $existingRegistry = Get-Content -LiteralPath $authorizedPath -Raw | ConvertFrom-Json
                $authorizedRoots = @($existingRegistry.roots)
                if ($existingRegistry.PSObject.Properties['commitRoots']) { $commitRoots = @($existingRegistry.commitRoots) }
            }
            catch {
                $authorizedRoots = @()
                $commitRoots = @()
            }
        }
        $authorizedRoots = @($authorizedRoots + $resolvedWorkspace | Where-Object { $_ } | Sort-Object -Unique)
        $commitRoots = @($commitRoots | Where-Object { -not [string]::Equals([IO.Path]::GetFullPath($_), $resolvedWorkspace, $pathComparison) })
        if ($EnableGitCommitBridge) { $commitRoots = @($commitRoots + $resolvedWorkspace | Sort-Object -Unique) }
        $bridgeRegistry = [pscustomobject]@{
            schemaVersion = 2
            gitExecutable = $gitExecutableForBridge
            gitExecutableSha256 = $gitExecutableHash
            roots = $authorizedRoots
            commitRoots = $commitRoots
            commitBranchPrefixes = @($CommitBranchPrefix | Sort-Object -Unique)
        }
        Write-CssTextAtomic -Path $authorizedPath -Text ($bridgeRegistry | ConvertTo-Json -Depth 4)

        $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pwshCommand) {
            $bridgeInstalled = $true
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'New-CodexCheckpoint.ps1') -Destination $bridgePath -Force
            $pwshRulePath = [IO.Path]::GetFullPath($pwshCommand.Source)
            $scriptRulePath = [IO.Path]::GetFullPath($bridgePath)
            $workspaceRulePath = [IO.Path]::GetFullPath($resolvedWorkspace)
            $pwshLiteral = ConvertTo-CssStarlarkString -Value $pwshRulePath
            $scriptLiteral = ConvertTo-CssStarlarkString -Value $scriptRulePath
            $saveExample = ConvertTo-CssStarlarkString -Value ('"{0}" -NoProfile -NonInteractive -File "{1}" -Action Save -Repository "{2}"' -f $pwshRulePath, $scriptRulePath, $workspaceRulePath)
            $listExample = ConvertTo-CssStarlarkString -Value ('"{0}" -NoProfile -NonInteractive -File "{1}" -Action List -Repository "{2}"' -f $pwshRulePath, $scriptRulePath, $workspaceRulePath)
            $unsafeExample = ConvertTo-CssStarlarkString -Value ('"{0}" -NoProfile -File "{1}" -Action Save -Repository "{2}"' -f $pwshRulePath, $scriptRulePath, $workspaceRulePath)
            $statusExample = ConvertTo-CssStarlarkString -Value ('"{0}" -NoProfile -NonInteractive -File "{1}" -Action Status -Repository "{2}"' -f $pwshRulePath, $scriptRulePath, $workspaceRulePath)
            $commitExample = ConvertTo-CssStarlarkString -Value ('"{0}" -NoProfile -NonInteractive -File "{1}" -Action Commit -Repository "{2}" -Message "Scoped commit" -Path "README.md"' -f $pwshRulePath, $scriptRulePath, $workspaceRulePath)
            $ruleText = @"
# Generated by Codex Safe Setup. Exact bridge only; never general PowerShell or Git.
prefix_rule(
    pattern = [$pwshLiteral, "-NoProfile", "-NonInteractive", "-File", $scriptLiteral, "-Action", ["Save", "List", "Status", "Commit"]],
    decision = "allow",
    justification = "Inspect, checkpoint, or explicitly commit selected paths in a registered repository",
    match = [
        $saveExample,
        $listExample,
        $statusExample,
        $commitExample,
    ],
    not_match = [
        $unsafeExample,
        'git commit',
    ],
)
"@
            $ruleInstalled = $true
            Write-CssTextAtomic -Path $rulesPath -Text $ruleText
        }
    }

    $state = [pscustomobject]@{
        schemaVersion = $script:CssStateSchemaVersion
        productVersion = $script:CssProductVersion
        operation = $operation
        transactionId = $transactionId
        previousVersion = $previousVersion
        previousStateSnapshot = $previousStateSnapshot
        InstalledAtUtc = [DateTime]::UtcNow.ToString('o')
        ConfigPath = $resolvedConfig
        OriginalConfigExists = $originalConfigExists
        ConfigBackup = $(if ($originalConfigExists) { $configBackup } else { $null })
        RulesPath = $rulesPath
        OriginalRulesExists = $originalRulesExists
        RulesBackup = $(if ($originalRulesExists) { $rulesBackup } else { $null })
        RulesTouched = $ruleInstalled
        BridgePath = $(if ($bridgeInstalled) { $bridgePath } else { $null })
        OriginalBridgeExists = $originalBridgeExists
        BridgeBackup = $(if ($originalBridgeExists) { $bridgeBackup } else { $null })
        BridgeTouched = $bridgeInstalled
        AuthorizedWorkspacesPath = $authorizedPath
        OriginalAuthorizedWorkspacesExists = $originalAuthorizedExists
        AuthorizedWorkspacesBackup = $(if ($originalAuthorizedExists) { $authorizedBackup } else { $null })
        AuthorizedWorkspacesTouched = $authorizedTouched
        CanaryPath = $canaryPath
        OriginalCanaryExists = $originalCanaryExists
        CanaryBackup = $(if ($originalCanaryExists) { $canaryBackup } else { $null })
        CanaryTouched = $canaryTouched
        ApprovalMode = $ApprovalMode
        NetworkMode = $NetworkMode
        AllowedDomains = @($AllowedDomain | Sort-Object -Unique)
        ProtectWorkspaceSecrets = $ProtectWorkspaceSecrets
        AllowTempWrite = $AllowTempWrite
        MigrateLegacySettings = [bool]$MigrateLegacySettings
        EnableGitCommitBridge = $EnableGitCommitBridge
        CommitBranchPrefixes = @($CommitBranchPrefix | Sort-Object -Unique)
        WindowsSandbox = $WindowsSandbox
        RegisteredWorkspace = $recordedWorkspace
    }
    Write-CssTextAtomic -Path (Join-Path $resolvedState 'install-state.json') -Text ($state | ConvertTo-Json -Depth 5)
}
catch {
    if ($originalConfigExists) { Copy-Item -LiteralPath $configBackup -Destination $resolvedConfig -Force }
    elseif (Test-Path -LiteralPath $resolvedConfig) { Remove-Item -LiteralPath $resolvedConfig -Force }
    if ($originalRulesExists) { Copy-Item -LiteralPath $rulesBackup -Destination $rulesPath -Force }
    elseif (Test-Path -LiteralPath $rulesPath) { Remove-Item -LiteralPath $rulesPath -Force }
    if ($bridgeInstalled) {
        if ($originalBridgeExists) { Copy-Item -LiteralPath $bridgeBackup -Destination $bridgePath -Force }
        elseif (Test-Path -LiteralPath $bridgePath) { Remove-Item -LiteralPath $bridgePath -Force }
    }
    if ($authorizedTouched) {
        if ($originalAuthorizedExists) { Copy-Item -LiteralPath $authorizedBackup -Destination $authorizedPath -Force }
        elseif (Test-Path -LiteralPath $authorizedPath) { Remove-Item -LiteralPath $authorizedPath -Force }
    }
    if ($canaryTouched) {
        if ($originalCanaryExists) { Copy-Item -LiteralPath $canaryBackup -Destination $canaryPath -Force }
        elseif (Test-Path -LiteralPath $canaryPath) { Remove-Item -LiteralPath $canaryPath -Force }
    }
    if ($previousStateSnapshot -and (Test-Path -LiteralPath $previousStateSnapshot -PathType Leaf)) {
        Remove-Item -LiteralPath $previousStateSnapshot -Force
    }
    throw
}

[pscustomobject]@{
    Status = $(if ($Upgrade) { 'UPGRADED_RESTART_REQUIRED' } else { 'INSTALLED_RESTART_REQUIRED' })
    ProductVersion = $script:CssProductVersion
    TransactionId = $transactionId
    ConfigPath = $resolvedConfig
    BackupPath = $(if ($originalConfigExists) { $configBackup } else { '<new config; rollback removes it>' })
    CheckpointBridgeInstalled = $bridgeInstalled
    RuleInstalled = $ruleInstalled
    GitCommitBridgeEnabled = $EnableGitCommitBridge
    Verification = $(if (Get-Command codex -ErrorAction SilentlyContinue) { 'Run Test-CodexSafety.ps1 after restarting Codex.' } else { 'PARTIAL: install Codex CLI for rule verification.' })
    RequiredPermissionSelection = 'Open the Codex permission selector, choose Custom, and confirm codex-safe-workspace is selected. Do not choose Full Access.'
    RequiredRestart = $(if ($env:OS -eq 'Windows_NT') { 'Restart Codex and start a new task; do not resume a pre-install task because its proxy and sandbox state cannot be updated retroactively. If administrator prompts repeat, fully quit every Codex desktop window and CLI process, then relaunch once.' } else { 'Start a new Codex task or CLI session; the current execution environment does not retroactively adopt the new profile.' })
    RequiredElevatedSetup = $(if ($WindowsSandbox -eq 'Elevated' -and $env:OS -eq 'Windows_NT') { 'After relaunch, approve the Windows sandbox administrator setup once if prompted. Repeated prompts are not normal; run the assessment before changing sandbox mode.' } else { 'Not applicable.' })
}
