[CmdletBinding()]
param(
    [ValidateSet('BoundedAutonomy', 'AskMe', 'AutoReview')][string]$ApprovalMode,
    [ValidateSet('DynamicUi', 'StrictProfile')][string]$PermissionRouting,
    [ValidateSet('Off', 'Allowlist', 'Unrestricted')][string]$NetworkMode,
    [string[]]$AllowedDomain,
    [ValidateSet('Elevated', 'Unelevated', 'Keep')][string]$WindowsSandbox,
    [Nullable[bool]]$ProtectWorkspaceSecrets,
    [Nullable[bool]]$AllowTempWrite,
    [string]$WorkspacePath,
    [string]$CodexHome,
    [string]$ConfigPath,
    [string]$StateRoot,
    [switch]$MigrateLegacySettings,
    [switch]$AcknowledgeDynamicUiReadScope,
    [switch]$AcknowledgeRisk,
    [switch]$AcknowledgeAdminSetup,
    [switch]$PlanOnly,
    [switch]$ConfirmUpgrade,
    [switch]$NonInteractive
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$ErrorActionPreference = 'Stop'

$resolvedHome = Get-CssCodexHome -Override $CodexHome
$resolvedConfig = Get-CssConfigPath -CodexHome $resolvedHome -Override $ConfigPath
$resolvedState = Get-CssStateRoot -CodexHome $resolvedHome -Override $StateRoot
$statePath = Join-Path $resolvedState 'install-state.json'
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw "No existing install state was found at $statePath. Use Install-CodexSafety.ps1 for a first installation."
}
try {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
}
catch {
    throw "Existing install state is unreadable. Refusing upgrade: $statePath"
}

function Get-UpgradeStateValue {
    param([Parameter(Mandatory)][string]$Name, $Default)
    if ($state.PSObject.Properties[$Name] -and $null -ne $state.$Name -and [string]$state.$Name -ne '') {
        return $state.$Name
    }
    return $Default
}

$effectiveApproval = if ($PSBoundParameters.ContainsKey('ApprovalMode')) { $ApprovalMode } else { [string](Get-UpgradeStateValue -Name 'ApprovalMode' -Default 'BoundedAutonomy') }
$effectivePermissionRouting = if ($PSBoundParameters.ContainsKey('PermissionRouting')) { $PermissionRouting } else { [string](Get-UpgradeStateValue -Name 'PermissionRouting' -Default 'DynamicUi') }
$effectiveNetwork = if ($PSBoundParameters.ContainsKey('NetworkMode')) { $NetworkMode } else { [string](Get-UpgradeStateValue -Name 'NetworkMode' -Default 'Off') }
$effectiveWindows = if ($PSBoundParameters.ContainsKey('WindowsSandbox')) { $WindowsSandbox } else { [string](Get-UpgradeStateValue -Name 'WindowsSandbox' -Default 'Keep') }
$effectiveProtect = if ($PSBoundParameters.ContainsKey('ProtectWorkspaceSecrets')) { [bool]$ProtectWorkspaceSecrets } else { [bool](Get-UpgradeStateValue -Name 'ProtectWorkspaceSecrets' -Default $true) }
$effectiveTemp = if ($PSBoundParameters.ContainsKey('AllowTempWrite')) { [bool]$AllowTempWrite } else { [bool](Get-UpgradeStateValue -Name 'AllowTempWrite' -Default $false) }

$configText = Read-CssText -Path $resolvedConfig
if ($PSBoundParameters.ContainsKey('AllowedDomain')) {
    $effectiveDomains = @($AllowedDomain)
}
elseif ($state.PSObject.Properties['AllowedDomains']) {
    $effectiveDomains = @($state.AllowedDomains)
}
elseif ($effectiveNetwork -eq 'Allowlist') {
    $domainSection = Get-CssTomlSectionText -Text $configText -Section 'permissions.codex-safe-workspace.network.domains'
    $effectiveDomains = @([regex]::Matches($domainSection, '(?m)^\s*"(?<domain>[^"]+)"\s*=\s*"allow"\s*$') | ForEach-Object { $_.Groups['domain'].Value } | Where-Object { $_ -ne '*' } | Sort-Object -Unique)
}
else {
    $effectiveDomains = @()
}
if ($effectiveNetwork -ne 'Allowlist') { $effectiveDomains = @() }
if ($effectiveNetwork -eq 'Allowlist' -and $effectiveDomains.Count -eq 0) {
    throw 'The prior Allowlist domains could not be recovered. Pass one or more -AllowedDomain values after reviewing them.'
}

$effectiveWorkspace = if ($PSBoundParameters.ContainsKey('WorkspacePath')) { $WorkspacePath } else { [string](Get-UpgradeStateValue -Name 'RegisteredWorkspace' -Default '') }
$installArguments = @{
    ApprovalMode = $effectiveApproval
    PermissionRouting = $effectivePermissionRouting
    NetworkMode = $effectiveNetwork
    AllowedDomain = $effectiveDomains
    WindowsSandbox = $effectiveWindows
    ProtectWorkspaceSecrets = $effectiveProtect
    AllowTempWrite = $effectiveTemp
    CodexHome = $resolvedHome
    ConfigPath = $resolvedConfig
    StateRoot = $resolvedState
    Upgrade = $true
}
if ($effectiveWorkspace -and (Test-Path -LiteralPath $effectiveWorkspace -PathType Container)) {
    $installArguments.WorkspacePath = $effectiveWorkspace
}
elseif ($effectiveWorkspace) {
    throw "The recorded workspace no longer exists: $effectiveWorkspace. Pass an existing -WorkspacePath so the recovery registry can be rewritten; refusing to leave an older bridge rule active."
}
if ($MigrateLegacySettings) { $installArguments.MigrateLegacySettings = $true }
if ($AcknowledgeDynamicUiReadScope) { $installArguments.AcknowledgeDynamicUiReadScope = $true }
if ($AcknowledgeRisk) { $installArguments.AcknowledgeRisk = $true }
if ($AcknowledgeAdminSetup) { $installArguments.AcknowledgeAdminSetup = $true }

$installer = Join-Path $PSScriptRoot 'Install-CodexSafety.ps1'
if ($PlanOnly -or -not $ConfirmUpgrade) {
    & $installer @installArguments -PlanOnly
    if (-not $PlanOnly) {
        Write-Output 'No files changed. Review the plan, then rerun with -ConfirmUpgrade and the acknowledgements required by the selected profile.'
    }
    return
}

$installArguments.ConfirmApply = $true
if ($NonInteractive) { $installArguments.NonInteractive = $true }
& $installer @installArguments
