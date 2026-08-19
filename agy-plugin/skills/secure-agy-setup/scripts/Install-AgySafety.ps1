[CmdletBinding()]
param(
    [ValidateSet('BoundedAutonomy', 'AskMe', 'Strict')][string]$ApprovalMode = 'BoundedAutonomy',
    [ValidateSet('Off', 'Allowlist', 'Unrestricted')][string]$NetworkMode = 'Off',
    [string[]]$AllowedDomain = @(),
    [string]$WorkspacePath,
    [string]$GeminiHome,
    [string]$CliSettingsPath,
    [string]$GlobalSettingsPath,
    [string]$StateRoot,
    [switch]$AcknowledgeRisk,
    [switch]$PlanOnly,
    [switch]$ConfirmApply,
    [switch]$NonInteractive
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$ErrorActionPreference = 'Stop'

$resolvedHome = Get-AgyGeminiHome -Override $GeminiHome
$resolvedCliSettings = Get-AgyCliSettingsPath -GeminiHome $resolvedHome -Override $CliSettingsPath
$resolvedGlobalSettings = Get-AgyGlobalSettingsPath -GeminiHome $resolvedHome -Override $GlobalSettingsPath
$resolvedState = Get-AgyStateRoot -GeminiHome $resolvedHome -Override $StateRoot

if ($NetworkMode -eq 'Allowlist' -and $AllowedDomain.Count -eq 0) {
    throw 'Allowlist mode requires at least one -AllowedDomain.'
}

$toolExecutionPolicy = 'proceed-in-sandbox'
if ($ApprovalMode -eq 'AskMe') { $toolExecutionPolicy = 'request-review' }
elseif ($ApprovalMode -eq 'Strict') { $toolExecutionPolicy = 'strict' }

$internetPolicy = 'deny'
if ($NetworkMode -eq 'Allowlist') { $internetPolicy = 'ask' }
elseif ($NetworkMode -eq 'Unrestricted') { $internetPolicy = 'allow' }

$resolvedWorkspace = $null
$gitExecutableForBridge = $null
$gitExecutableHash = $null
if ($WorkspacePath) {
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $gitCmd) { throw 'Git is required to register a checkpoint workspace.' }
    $resolvedWorkspace = Get-AgyRepositoryRoot -Path $WorkspacePath
    $gitExecutableForBridge = [IO.Path]::GetFullPath($gitCmd.Source)
    $gitExecutableHash = (Get-FileHash -LiteralPath $gitExecutableForBridge -Algorithm SHA256).Hash
}

$plan = [pscustomobject]@{
    GeminiHome = $resolvedHome
    CliSettingsPath = $resolvedCliSettings
    StateRoot = $resolvedState
    ApprovalMode = $ApprovalMode
    ToolExecutionPolicy = $toolExecutionPolicy
    NonWorkspaceFileAccess = 'deny'
    TerminalSandbox = $true
    NetworkMode = $NetworkMode
    InternetAccessPolicy = $internetPolicy
    AllowedDomains = $AllowedDomain
    RegisteredWorkspace = $resolvedWorkspace
    CheckpointBridge = $(if ($resolvedWorkspace) { 'Ready to install' } else { 'Not requested' })
    ExternalSurfaces = 'Web Search, Browser, Computer Use, and third-party MCPs are not controlled.'
}

Write-Output 'Antigravity Safe Setup — Change Plan'
Write-Output '------------------------------------'
$plan | Format-List | Out-String | Write-Output

if ($PlanOnly) {
    Write-Output 'No files changed (PlanOnly mode).'
    return
}

if ($NetworkMode -eq 'Unrestricted' -and -not $AcknowledgeRisk) {
    if ($NonInteractive) { throw 'Unrestricted command networking requires -AcknowledgeRisk.' }
    Write-Warning 'Unrestricted network risk disclosure:'
    Write-Output '  - Any data accessible to tools could be transmitted to public internet endpoints.'
    Write-Output '  - Prompt injection in external websites or packages could induce data exfiltration.'
    $riskAnswer = Read-Host 'I understand and accept unrestricted network risk. Continue? [y/N]'
    if ($riskAnswer -notmatch '^(?i:y|yes)$') { throw 'Installation cancelled.' }
}

if (-not $ConfirmApply) {
    if ($NonInteractive) { throw 'Non-interactive apply requires -ConfirmApply.' }
    $applyAnswer = Read-Host 'Apply this safe setup plan and create rollback backup? [y/N]'
    if ($applyAnswer -notmatch '^(?i:y|yes)$') { throw 'Installation cancelled.' }
}

$timestamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$backupRoot = Join-Path $resolvedState 'backups'
$binaryRoot = Join-Path $resolvedState 'bin'
$bridgePath = Join-Path $binaryRoot 'New-AgyCheckpoint.ps1'
$authorizedPath = Join-Path $resolvedState 'authorized-workspaces.json'
$canaryPath = Join-Path $resolvedState 'outside-workspace-canary.txt'

$cliSettingsBackup = Join-Path $backupRoot ("settings.cli.$timestamp.json")
$globalSettingsBackup = Join-Path $backupRoot ("settings.global.$timestamp.json")
$bridgeBackup = Join-Path $backupRoot ("bridge.$timestamp.bak")
$authorizedBackup = Join-Path $backupRoot ("authorized-workspaces.$timestamp.bak")
$canaryBackup = Join-Path $backupRoot ("canary.$timestamp.bak")

$origCliSettingsExists = Test-Path -LiteralPath $resolvedCliSettings -PathType Leaf
$origGlobalSettingsExists = Test-Path -LiteralPath $resolvedGlobalSettings -PathType Leaf
$origBridgeExists = Test-Path -LiteralPath $bridgePath -PathType Leaf
$origAuthorizedExists = Test-Path -LiteralPath $authorizedPath -PathType Leaf
$origCanaryExists = Test-Path -LiteralPath $canaryPath -PathType Leaf

New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
New-Item -ItemType Directory -Path $binaryRoot -Force | Out-Null

if ($origCliSettingsExists) { Copy-Item -LiteralPath $resolvedCliSettings -Destination $cliSettingsBackup -Force }
if ($origGlobalSettingsExists) { Copy-Item -LiteralPath $resolvedGlobalSettings -Destination $globalSettingsBackup -Force }
if ($origBridgeExists) { Copy-Item -LiteralPath $bridgePath -Destination $bridgeBackup -Force }
if ($origAuthorizedExists) { Copy-Item -LiteralPath $authorizedPath -Destination $authorizedBackup -Force }
if ($origCanaryExists) { Copy-Item -LiteralPath $canaryPath -Destination $canaryBackup -Force }

$bridgeInstalled = $false
try {
    # Read existing CLI settings or create new
    $existingCli = Read-AgyJson -Path $resolvedCliSettings
    if (-not $existingCli) { $existingCli = [ordered]@{} }
    else {
        # Convert PSCustomObject to hashtable for safe key modification
        $hash = [ordered]@{}
        foreach ($prop in $existingCli.PSObject.Properties) {
            $hash[$prop.Name] = $prop.Value
        }
        $existingCli = $hash
    }

    $existingCli['nonWorkspaceFileAccess'] = 'deny'
    $existingCli['terminalSandbox'] = $true
    $existingCli['toolExecutionPolicy'] = $toolExecutionPolicy
    $existingCli['internetAccessPolicy'] = $internetPolicy
    if ($AllowedDomain.Count -gt 0) {
        $existingCli['browserAllowlist'] = @($AllowedDomain | Sort-Object -Unique)
    }

    Write-AgyJsonAtomic -Path $resolvedCliSettings -Object $existingCli
    Write-AgyTextAtomic -Path $canaryPath -Text ("Synthetic canary: {0}" -f [guid]::NewGuid().ToString('N'))

    if ($resolvedWorkspace) {
        $authorizedRoots = @()
        if (Test-Path -LiteralPath $authorizedPath -PathType Leaf) {
            try { $authorizedRoots = @((Get-Content -LiteralPath $authorizedPath -Raw | ConvertFrom-Json).roots) } catch { $authorizedRoots = @() }
        }
        $authorizedRoots = @($authorizedRoots + $resolvedWorkspace | Where-Object { $_ } | Sort-Object -Unique)
        $registry = [pscustomobject]@{
            schemaVersion = 1
            gitExecutable = $gitExecutableForBridge
            gitExecutableSha256 = $gitExecutableHash
            roots = $authorizedRoots
        }
        Write-AgyJsonAtomic -Path $authorizedPath -Object $registry

        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'New-AgyCheckpoint.ps1') -Destination $bridgePath -Force
        $bridgeInstalled = $true
    }

    $state = [pscustomobject]@{
        InstalledAtUtc = [DateTime]::UtcNow.ToString('o')
        GeminiHome = $resolvedHome
        CliSettingsPath = $resolvedCliSettings
        OriginalCliSettingsExists = $origCliSettingsExists
        CliSettingsBackup = $(if ($origCliSettingsExists) { $cliSettingsBackup } else { $null })
        BridgePath = $(if ($bridgeInstalled) { $bridgePath } else { $null })
        OriginalBridgeExists = $origBridgeExists
        BridgeBackup = $(if ($origBridgeExists) { $bridgeBackup } else { $null })
        BridgeTouched = $bridgeInstalled
        AuthorizedWorkspacesPath = $authorizedPath
        OriginalAuthorizedWorkspacesExists = $origAuthorizedExists
        AuthorizedWorkspacesBackup = $(if ($origAuthorizedExists) { $authorizedBackup } else { $null })
        AuthorizedWorkspacesTouched = [bool]$resolvedWorkspace
        CanaryPath = $canaryPath
        OriginalCanaryExists = $origCanaryExists
        CanaryBackup = $(if ($origCanaryExists) { $canaryBackup } else { $null })
        ApprovalMode = $ApprovalMode
        NetworkMode = $NetworkMode
        RegisteredWorkspace = $resolvedWorkspace
    }
    Write-AgyJsonAtomic -Path (Join-Path $resolvedState 'install-state.json') -Object $state
}
catch {
    if ($origCliSettingsExists) { Copy-Item -LiteralPath $cliSettingsBackup -Destination $resolvedCliSettings -Force }
    elseif (Test-Path -LiteralPath $resolvedCliSettings) { Remove-Item -LiteralPath $resolvedCliSettings -Force }
    if ($bridgeInstalled) {
        if ($origBridgeExists) { Copy-Item -LiteralPath $bridgeBackup -Destination $bridgePath -Force }
        elseif (Test-Path -LiteralPath $bridgePath) { Remove-Item -LiteralPath $bridgePath -Force }
    }
    throw
}

[pscustomobject]@{
    Status = 'INSTALLED_SUCCESS'
    CliSettingsPath = $resolvedCliSettings
    BackupPath = $(if ($origCliSettingsExists) { $cliSettingsBackup } else { '<new file; rollback removes it>' })
    CheckpointBridgeInstalled = $bridgeInstalled
    CanaryPath = $canaryPath
    Verification = 'Run Test-AgySafety.ps1 to verify active boundaries.'
}
