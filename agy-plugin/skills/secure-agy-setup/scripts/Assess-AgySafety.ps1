[CmdletBinding()]
param(
    [string]$GeminiHome,
    [string]$CliSettingsPath,
    [string]$GlobalSettingsPath,
    [switch]$AsJson
)

. (Join-Path $PSScriptRoot 'Common.ps1')

$resolvedHome = Get-AgyGeminiHome -Override $GeminiHome
$resolvedCliSettings = Get-AgyCliSettingsPath -GeminiHome $resolvedHome -Override $CliSettingsPath
$resolvedGlobalSettings = Get-AgyGlobalSettingsPath -GeminiHome $resolvedHome -Override $GlobalSettingsPath

$cliSettings = Read-AgyJson -Path $resolvedCliSettings
$globalSettings = Read-AgyJson -Path $resolvedGlobalSettings

function Get-CommandSnapshot {
    param([string]$Name, [string[]]$VersionArguments)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) {
        return [pscustomobject]@{ Present = $false; Path = $null; Version = $null }
    }
    $vText = $null
    try {
        $vText = (& $cmd.Source @VersionArguments 2>$null | Select-Object -First 1)
        if ($null -ne $vText) { $vText = $vText.ToString().Trim() }
    }
    catch { $vText = $null }
    return [pscustomobject]@{ Present = $true; Path = $cmd.Source; Version = $vText }
}

$pwshCli = Get-CommandSnapshot -Name 'pwsh' -VersionArguments @('--version')
$agyCli = Get-CommandSnapshot -Name 'agy' -VersionArguments @('--version')
$gitCli = Get-CommandSnapshot -Name 'git' -VersionArguments @('--version')
$nodeCli = Get-CommandSnapshot -Name 'node' -VersionArguments @('--version')

# Inspect sensitive directories existence (never read contents)
$knownSensitiveLocations = @()
$userProfilePath = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
if ($userProfilePath) {
    foreach ($rel in @('.ssh', '.aws', '.azure', '.config\gcloud')) {
        $cand = Join-Path $userProfilePath $rel
        if (Test-Path -LiteralPath $cand -ErrorAction SilentlyContinue) {
            $knownSensitiveLocations += $cand
        }
    }
}

# Inspect active Antigravity settings
$nonWorkspaceAccess = $null
$toolExecutionPolicy = $null
$terminalSandbox = $null
$internetAccessPolicy = $null

if ($cliSettings) {
    if ($cliSettings.PSObject.Properties['nonWorkspaceFileAccess']) { $nonWorkspaceAccess = $cliSettings.nonWorkspaceFileAccess }
    if ($cliSettings.PSObject.Properties['toolExecutionPolicy']) { $toolExecutionPolicy = $cliSettings.toolExecutionPolicy }
    if ($cliSettings.PSObject.Properties['terminalSandbox']) { $terminalSandbox = $cliSettings.terminalSandbox }
    if ($cliSettings.PSObject.Properties['internetAccessPolicy']) { $internetAccessPolicy = $cliSettings.internetAccessPolicy }
}

$findings = [Collections.Generic.List[object]]::new()

if ($nonWorkspaceAccess -eq 'allow' -or -not $nonWorkspaceAccess) {
    $findings.Add([pscustomobject]@{ Severity = 'HIGH'; Finding = 'Non-Workspace file access is not locked to deny.' })
}
if ($toolExecutionPolicy -eq 'always-proceed') {
    $findings.Add([pscustomobject]@{ Severity = 'MEDIUM'; Finding = 'Tool execution policy is set to always-proceed without sandbox enforcement.' })
}
if ($terminalSandbox -eq $false -or -not $terminalSandbox) {
    $findings.Add([pscustomobject]@{ Severity = 'HIGH'; Finding = 'Terminal Sandbox is not enabled.' })
}
if ($internetAccessPolicy -eq 'allow') {
    $findings.Add([pscustomobject]@{ Severity = 'MEDIUM'; Finding = 'Internet access policy is unrestricted (allow).' })
}
if (-not $pwshCli.Present -and $env:OS -eq 'Windows_NT') {
    $findings.Add([pscustomobject]@{ Severity = 'INFO'; Finding = 'PowerShell 7 is not detected; recommended for script consistency.' })
}

$report = [pscustomobject]@{
    TimestampUtc = [DateTime]::UtcNow.ToString('o')
    GeminiHome = $resolvedHome
    CliSettingsPath = $resolvedCliSettings
    CliSettingsExists = (Test-Path -LiteralPath $resolvedCliSettings -PathType Leaf)
    GlobalSettingsPath = $resolvedGlobalSettings
    NonWorkspaceFileAccess = $nonWorkspaceAccess
    ToolExecutionPolicy = $toolExecutionPolicy
    TerminalSandbox = $terminalSandbox
    InternetAccessPolicy = $internetAccessPolicy
    SensitiveLocationCount = $knownSensitiveLocations.Count
    SensitiveLocationPaths = $knownSensitiveLocations
    Tools = [pscustomobject]@{
        PowerShell7 = $pwshCli
        AgyCLI = $agyCli
        Git = $gitCli
        Node = $nodeCli
    }
    Findings = $findings
    ExternalSurfaces = [pscustomobject]@{
        WebSearch = 'NOT CONTROLLED'
        ThirdPartyMcp = 'NOT CONTROLLED'
        HostMalware = 'NOT CONTROLLED'
    }
}

if ($AsJson) {
    $report | ConvertTo-Json -Depth 5
}
else {
    Write-Output "Antigravity Safe Setup — Read-Only Assessment"
    Write-Output "---------------------------------------------"
    Write-Output ("Gemini Home: {0}" -f $report.GeminiHome)
    Write-Output ("Non-Workspace File Access: {0}" -f $(if ($nonWorkspaceAccess) { $nonWorkspaceAccess } else { 'unconfigured (default)' }))
    Write-Output ("Tool Execution Policy:     {0}" -f $(if ($toolExecutionPolicy) { $toolExecutionPolicy } else { 'unconfigured (default)' }))
    Write-Output ("Terminal Sandbox:          {0}" -f $(if ($null -ne $terminalSandbox) { $terminalSandbox } else { 'unconfigured (default)' }))
    Write-Output ("Internet Access Policy:    {0}" -f $(if ($internetAccessPolicy) { $internetAccessPolicy } else { 'unconfigured (default)' }))
    Write-Output ("Sensitive Paths Found:     {0}" -f $report.SensitiveLocationCount)
    Write-Output ""
    if ($findings.Count -gt 0) {
        Write-Output "Findings:"
        foreach ($f in $findings) {
            Write-Output ("  [{0}] {1}" -f $f.Severity, $f.Finding)
        }
    }
    else {
        Write-Output "All baseline settings meet the least-privilege standard."
    }
}
