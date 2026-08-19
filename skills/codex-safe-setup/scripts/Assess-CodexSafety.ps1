[CmdletBinding()]
param(
    [string]$CodexHome,
    [string]$ConfigPath,
    [switch]$AsJson
)

. (Join-Path $PSScriptRoot 'Common.ps1')

$resolvedHome = Get-CssCodexHome -Override $CodexHome
$resolvedConfig = Get-CssConfigPath -CodexHome $resolvedHome -Override $ConfigPath
$configText = Read-CssText -Path $resolvedConfig
$legacy = Test-CssLegacySettings -Text $configText

function Get-CommandSnapshot {
    param([string]$Name, [string[]]$VersionArguments)
    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        return [pscustomobject]@{ Present = $false; Path = $null; Version = $null }
    }
    $versionText = $null
    try {
        $versionText = (& $command.Source @VersionArguments 2>$null | Select-Object -First 1)
        if ($null -ne $versionText) { $versionText = $versionText.ToString().Trim() }
    }
    catch { $versionText = $null }
    return [pscustomobject]@{ Present = $true; Path = $command.Source; Version = $versionText }
}

$powershell7 = Get-CommandSnapshot -Name 'pwsh' -VersionArguments @('--version')
$codexCli = Get-CommandSnapshot -Name 'codex' -VersionArguments @('--version')
$gitCli = Get-CommandSnapshot -Name 'git' -VersionArguments @('--version')
$npmCli = Get-CommandSnapshot -Name 'npm' -VersionArguments @('--version')
$wingetCli = Get-CommandSnapshot -Name 'winget' -VersionArguments @('--version')
$codexVersionSupported = $false
if ($codexCli.Version -and $codexCli.Version -match '(\d+\.\d+\.\d+)') {
    $codexVersionSupported = [version]$Matches[1] -ge [version]'0.138.0'
}

$profileMatch = [regex]::Match($configText, '(?m)^\s*default_permissions\s*=\s*["'']([^"'']+)["'']')
$sandboxModeMatch = [regex]::Match($configText, '(?m)^\s*sandbox_mode\s*=\s*["'']([^"'']+)["'']')
$profileSettings = Get-CssPermissionProfileSettings -Text $configText
$fullAccess = ($profileMatch.Success -and $profileMatch.Groups[1].Value -eq ':danger-full-access') -or ($sandboxModeMatch.Success -and $sandboxModeMatch.Groups[1].Value -eq 'danger-full-access')
$approvalMatch = [regex]::Match($configText, '(?m)^\s*approval_policy\s*=\s*["'']([^"'']+)["'']')
$reviewerMatch = [regex]::Match($configText, '(?m)^\s*approvals_reviewer\s*=\s*["'']([^"'']+)["'']')
$windowsSectionText = Get-CssTomlSectionText -Text $configText -Section 'windows'
$windowsMatch = [regex]::Match($windowsSectionText, '(?m)^\s*sandbox\s*=\s*["'']([^"'']+)["'']')
$managedProfile = $configText.Contains($script:CssManagedStart) -and $configText -match '(?m)^\s*":root"\s*=\s*"deny"'
$dynamicUiRoutingReady = $sandboxModeMatch.Success -and -not $profileSettings.DefaultPresent -and -not $profileSettings.ManagedProfilePresent
$permissionRouting = if ($dynamicUiRoutingReady) { 'DynamicUi' } elseif ($managedProfile -and $profileMatch.Success) { 'StrictProfile' } else { 'Unknown' }
$profileNetworkSectionText = Get-CssTomlSectionText -Text $configText -Section 'permissions.codex-safe-workspace.network'
$legacyNetworkSectionText = Get-CssTomlSectionText -Text $configText -Section 'sandbox_workspace_write'
$featuresSectionText = Get-CssTomlSectionText -Text $configText -Section 'features'
$networkEnabled = if ($permissionRouting -eq 'DynamicUi') { $legacyNetworkSectionText -match '(?m)^\s*network_access\s*=\s*true' } else { $profileNetworkSectionText -match '(?m)^\s*enabled\s*=\s*true' }
$networkProxy = $featuresSectionText -match '(?m)^\s*network_proxy\s*=\s*true'
$commandNetworkRoute = if (-not $networkEnabled) { 'Off' } elseif ($networkProxy) { 'ProxyFiltered' } else { 'DirectUnrestricted' }
$windowsSandbox = $(if ($windowsMatch.Success) { $windowsMatch.Groups[1].Value } else { $null })
$sandboxSetupHealth = Get-CssWindowsSandboxSetupHealth -CodexHome $resolvedHome -ExpectedProxyPort $(if ($networkProxy) { @(3128, 8081) } else { @() })

$knownSensitiveLocations = @()
$userProfilePath = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
if ($userProfilePath) {
    foreach ($relativePath in @('.ssh', '.aws', '.azure', '.config\gcloud')) {
        $candidatePath = Join-Path $userProfilePath $relativePath
        if (Test-Path -LiteralPath $candidatePath -ErrorAction SilentlyContinue) { $knownSensitiveLocations += $candidatePath }
    }
}

$findings = [Collections.Generic.List[object]]::new()
if ($fullAccess) { $findings.Add([pscustomobject]@{ Severity = 'HIGH'; Finding = 'The configured default is Full Access, which removes the local sandbox boundary.' }) }
if ($legacy.Present -and $profileMatch.Success) { $findings.Add([pscustomobject]@{ Severity = 'HIGH'; Finding = 'Legacy sandbox keys and permission profiles coexist; legacy settings can take precedence.' }) }
if ($networkEnabled -and -not $networkProxy) { $findings.Add([pscustomobject]@{ Severity = 'HIGH'; Finding = 'Command network is direct and unrestricted; domain rules are not enforced. This is appropriate only when direct protocols are required and unrestricted-network risk was explicitly accepted.' }) }
if ($permissionRouting -eq 'DynamicUi') {
    $findings.Add([pscustomobject]@{ Severity = 'MEDIUM'; Finding = 'DynamicUi routing is active: same-task permission switching is available, but the strict profile credential deny-read boundary is not active.' })
}
elseif (-not $managedProfile) {
    $findings.Add([pscustomobject]@{ Severity = 'MEDIUM'; Finding = 'No verified root-deny, workspace-only managed profile was detected.' })
}
if (-not $codexCli.Present) { $findings.Add([pscustomobject]@{ Severity = 'INFO'; Finding = 'Codex CLI is absent, so rule and version checks will be partial.' }) }
elseif (-not $codexVersionSupported) { $findings.Add([pscustomobject]@{ Severity = 'HIGH'; Finding = 'Detected Codex CLI does not prove support for permission profiles (minimum recognized version: 0.138.0).' }) }
if ($env:OS -eq 'Windows_NT' -and -not $powershell7.Present) { $findings.Add([pscustomobject]@{ Severity = 'INFO'; Finding = 'PowerShell 7 is absent; bootstrap can continue with reduced shell consistency.' }) }
if ($windowsSandbox -eq 'elevated' -and $sandboxSetupHealth.Status -eq 'CONFLICT') {
    $findings.Add([pscustomobject]@{ Severity = 'HIGH'; Finding = 'The latest elevated Windows sandbox firewall setup uses proxy ports that conflict with the managed profile. Fully quit every Codex desktop and CLI process, relaunch once, and approve the setup prompt once.' })
}
elseif ($windowsSandbox -eq 'elevated' -and $sandboxSetupHealth.PortOscillationDetected) {
    $findings.Add([pscustomobject]@{ Severity = 'INFO'; Finding = 'Elevated sandbox firewall ports changed in both directions in the past, but the latest setup is aligned. No action is required unless administrator prompts repeat.' })
}

$report = [pscustomobject]@{
    TimestampUtc = [DateTime]::UtcNow.ToString('o')
    CodexHome = $resolvedHome
    ConfigPath = $resolvedConfig
    ConfigExists = (Test-Path -LiteralPath $resolvedConfig -PathType Leaf)
    FullAccessDetected = [bool]$fullAccess
    ConfiguredDefaultFullAccess = [bool]$fullAccess
    PermissionProfile = $(if ($profileMatch.Success) { $profileMatch.Groups[1].Value } else { $null })
    PermissionRouting = $permissionRouting
    DynamicUiRoutingReady = [bool]$dynamicUiRoutingReady
    RuntimePermissionSelection = 'NOT OBSERVED: this config assessment cannot see a task-level UI override; inspect activePermissionProfile or authoritative task permission metadata.'
    ManagedLeastPrivilegeProfile = [bool]$managedProfile
    LegacySettings = $legacy
    ApprovalPolicy = $(if ($approvalMatch.Success) { $approvalMatch.Groups[1].Value } else { $null })
    ApprovalReviewer = $(if ($reviewerMatch.Success) { $reviewerMatch.Groups[1].Value } else { $null })
    CommandNetworkEnabled = [bool]$networkEnabled
    NetworkProxyEnabled = [bool]$networkProxy
    CommandNetworkRoute = $commandNetworkRoute
    WindowsSandbox = $windowsSandbox
    WindowsSandboxSetupHealth = $sandboxSetupHealth
    SensitiveLocationCount = $knownSensitiveLocations.Count
    SensitiveLocationPaths = $knownSensitiveLocations
    ExternalSurfaces = [pscustomobject]@{
        WebSearch = 'NOT CONTROLLED'
        BrowserAndComputerUse = 'NOT CONTROLLED'
        AppsPluginsAndMcp = 'NOT CONTROLLED'
        CloudTasks = 'NOT CONTROLLED'
    }
    Tools = [pscustomobject]@{
        PowerShell7 = $powershell7
        CodexCli = $codexCli
        Git = $gitCli
        Npm = $npmCli
        Winget = $wingetCli
    }
    CodexPermissionProfilesSupported = [bool]$codexVersionSupported
    Findings = $findings
}

if ($AsJson) {
    $report | ConvertTo-Json -Depth 7
    exit 0
}

Write-Output 'Codex Safe Setup - read-only assessment'
Write-Output ("Config: {0}" -f $resolvedConfig)
Write-Output ("Configured default Full Access: {0}" -f $report.ConfiguredDefaultFullAccess)
Write-Output ("Permission routing: {0}; default profile: {1}" -f $report.PermissionRouting, $(if ($report.PermissionProfile) { $report.PermissionProfile } else { '<not set>' }))
Write-Output ("Approval: {0} / reviewer: {1}" -f $(if ($report.ApprovalPolicy) { $report.ApprovalPolicy } else { '<not set>' }), $(if ($report.ApprovalReviewer) { $report.ApprovalReviewer } else { '<not set>' }))
Write-Output ("Command network: {0}; proxy: {1}; route: {2}" -f $report.CommandNetworkEnabled, $report.NetworkProxyEnabled, $report.CommandNetworkRoute)
Write-Output ("Windows sandbox setup: {0} - {1}" -f $sandboxSetupHealth.Status, $sandboxSetupHealth.Evidence)
Write-Output ("PowerShell 7: {0}; Codex CLI: {1}; Git: {2}" -f $powershell7.Present, $codexCli.Present, $gitCli.Present)
Write-Output ("Known sensitive locations present (contents not read): {0}" -f $knownSensitiveLocations.Count)
foreach ($finding in $findings) { Write-Output ("[{0}] {1}" -f $finding.Severity, $finding.Finding) }
Write-Output '[NOT CONTROLLED] Web Search, Browser, Computer Use, apps, plugins, MCP, and cloud tasks use separate controls.'
