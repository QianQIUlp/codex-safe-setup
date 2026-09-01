[CmdletBinding()]
param(
    [string]$GeminiHome,
    [string]$CliSettingsPath,
    [string]$StateRoot,
    [switch]$AsJson
)

. (Join-Path $PSScriptRoot 'Common.ps1')

$resolvedHome = Get-AgyGeminiHome -Override $GeminiHome
$resolvedCliSettings = Get-AgyCliSettingsPath -GeminiHome $resolvedHome -Override $CliSettingsPath
$resolvedState = Get-AgyStateRoot -GeminiHome $resolvedHome -Override $StateRoot

$cliSettings = Read-AgyJson -Path $resolvedCliSettings
$statePath = Join-Path $resolvedState 'install-state.json'
$state = Read-AgyJson -Path $statePath

$checks = [Collections.Generic.List[object]]::new()

if (-not $cliSettings) {
    $checks.Add((New-AgyCheckResult -Status FAIL -Control 'CLI Settings' -Evidence "Missing or invalid: $resolvedCliSettings"))
}
else {
    $nwAccess = if ($cliSettings.PSObject.Properties['nonWorkspaceFileAccess']) { $cliSettings.nonWorkspaceFileAccess } else { $null }
    $checks.Add((New-AgyCheckResult -Status $(if ($nwAccess -eq 'deny') { 'PASS' } else { 'FAIL' }) -Control 'Non-Workspace File Access' -Evidence "nonWorkspaceFileAccess is '$nwAccess' (expected 'deny')"))

    $tSandbox = if ($cliSettings.PSObject.Properties['terminalSandbox']) { $cliSettings.terminalSandbox } else { $null }
    $checks.Add((New-AgyCheckResult -Status $(if ($tSandbox -eq $true) { 'PASS' } else { 'FAIL' }) -Control 'Terminal Sandbox' -Evidence "terminalSandbox is '$tSandbox' (expected true)"))

    $execPolicy = if ($cliSettings.PSObject.Properties['toolExecutionPolicy']) { $cliSettings.toolExecutionPolicy } else { $null }
    $checks.Add((New-AgyCheckResult -Status $(if ($execPolicy -in @('proceed-in-sandbox', 'request-review', 'strict')) { 'PASS' } else { 'FAIL' }) -Control 'Tool Execution Policy' -Evidence "toolExecutionPolicy is '$execPolicy'"))

    $netPolicy = if ($cliSettings.PSObject.Properties['internetAccessPolicy']) { $cliSettings.internetAccessPolicy } else { $null }
    $checks.Add((New-AgyCheckResult -Status $(if ($netPolicy) { 'PASS' } else { 'PARTIAL' }) -Control 'Internet Access Policy' -Evidence "internetAccessPolicy is '$netPolicy'"))
}

if ($state) {
    $backupOkay = (-not $state.OriginalCliSettingsExists) -or ($state.CliSettingsBackup -and (Test-Path -LiteralPath $state.CliSettingsBackup -PathType Leaf))
    $checks.Add((New-AgyCheckResult -Status $(if ($backupOkay) { 'PASS' } else { 'FAIL' }) -Control 'Rollback Backup' -Evidence "State records valid backup file"))

    if ($state.BridgePath) {
        $bridgeOkay = Test-Path -LiteralPath $state.BridgePath -PathType Leaf
        $checks.Add((New-AgyCheckResult -Status $(if ($bridgeOkay) { 'PASS' } else { 'FAIL' }) -Control 'Checkpoint Bridge' -Evidence "New-AgyCheckpoint.ps1 is installed"))
    }
}

# Hook Verification Probes
$hookScript = Join-Path $PSScriptRoot 'AgySafetyHook.js'
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
if ($nodeCmd -and (Test-Path -LiteralPath $hookScript -PathType Leaf)) {
    # Probe 1: Secret Deny
    $secretPayload = @{
        toolCall = @{ name = 'view_file'; args = @{ AbsolutePath = 'C:\project\.env' } }
        workspacePaths = @('C:\project')
    } | ConvertTo-Json -Compress

    $secretOutput = $secretPayload | & $nodeCmd.Source $hookScript 2>$null
    $secretBlocked = $secretOutput -match '"decision"\s*:\s*"deny"'
    $checks.Add((New-AgyCheckResult -Status $(if ($secretBlocked) { 'PASS' } else { 'FAIL' }) -Control 'Hook Secret Blocker (.env)' -Evidence $(if ($secretBlocked) { 'PreToolUse hook denied access to .env' } else { 'Hook failed to block .env' })))

    # Probe 2: Out-of-Workspace Write Deny
    $outWritePayload = @{
        toolCall = @{ name = 'write_to_file'; args = @{ TargetFile = 'C:\Windows\System32\malicious.dll' } }
        workspacePaths = @('C:\project')
    } | ConvertTo-Json -Compress

    $outWriteOutput = $outWritePayload | & $nodeCmd.Source $hookScript 2>$null
    $outWriteBlocked = $outWriteOutput -match '"decision"\s*:\s*"deny"'
    $checks.Add((New-AgyCheckResult -Status $(if ($outWriteBlocked) { 'PASS' } else { 'FAIL' }) -Control 'Hook Non-Workspace Write Deny' -Evidence $(if ($outWriteBlocked) { 'PreToolUse hook blocked out-of-workspace write' } else { 'Hook failed to block out-of-workspace write' })))
}
else {
    $checks.Add((New-AgyCheckResult -Status PARTIAL -Control 'Hook Probes' -Evidence 'Node.js is not available for hook verification'))
}

# External surfaces
$checks.Add((New-AgyCheckResult -Status 'NOT CONTROLLED' -Control 'Web Search Engine' -Evidence 'Separate external control plane'))
$checks.Add((New-AgyCheckResult -Status 'NOT CONTROLLED' -Control 'Third-Party MCP Servers' -Evidence 'External tool integration plane'))
$checks.Add((New-AgyCheckResult -Status 'NOT CONTROLLED' -Control 'Host OS Malware' -Evidence 'Requires host-level endpoint protection'))

if ($AsJson) {
    $checks | ConvertTo-Json -Depth 3
}
else {
    Write-Output "Antigravity Safe Setup — Verification Report"
    Write-Output "--------------------------------------------"
    foreach ($c in $checks) {
        $mark = switch ($c.Status) {
            'PASS' { '[PASS]' }
            'PARTIAL' { '[WARN]' }
            'FAIL' { '[FAIL]' }
            default { '[ - ]' }
        }
        Write-Output ("{0,-8} {1,-30} : {2}" -f $mark, $c.Control, $c.Evidence)
    }
}
