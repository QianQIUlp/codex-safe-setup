#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptDir = Join-Path (Join-Path (Join-Path $repoRoot 'agy-plugin') 'skills') 'secure-agy-setup\scripts'

Write-Output '=== Antigravity Safe Setup Test Suite ==='

$tempBase = Join-Path ([IO.Path]::GetTempPath()) ('agy-test-' + [guid]::NewGuid().ToString('N'))
$tempGeminiHome = Join-Path $tempBase '.gemini'
$tempGitRepo = Join-Path $tempBase 'workspace-repo'

New-Item -ItemType Directory -Path $tempGeminiHome -Force | Out-Null
New-Item -ItemType Directory -Path $tempGitRepo -Force | Out-Null

$passCount = 0
$failCount = 0

function Assert-Condition {
    param([bool]$Condition, [string]$TestName)
    if ($Condition) {
        Write-Output "  [PASS] $TestName"
        $script:passCount++
    }
    else {
        Write-Error "  [FAIL] $TestName"
        $script:failCount++
    }
}

try {
    # 1. Initialize dummy git repo
    & git -C $tempGitRepo init --quiet
    & git -C $tempGitRepo config user.name "Test User"
    & git -C $tempGitRepo config user.email "test@example.invalid"
    Set-Content -Path (Join-Path $tempGitRepo 'readme.txt') -Value 'Initial'
    & git -C $tempGitRepo add readme.txt
    & git -C $tempGitRepo commit -m "initial commit" --quiet

    # Test 1: Read-Only Assessment
    Write-Output "Test 1: Read-Only Assessment"
    $assessScript = Join-Path $scriptDir 'Assess-AgySafety.ps1'
    $assessOutput = & $assessScript -GeminiHome $tempGeminiHome -AsJson | ConvertFrom-Json
    Assert-Condition ($assessOutput.GeminiHome -eq $tempGeminiHome) "Assessment reports correct GeminiHome"
    Assert-Condition ($assessOutput.Findings.Count -gt 0) "Assessment identifies unconfigured initial state"

    # Test 2: Hook Unit Tests (AgySafetyHook.js)
    Write-Output "Test 2: Lifecycle Hook Guard (AgySafetyHook.js)"
    $hookScript = Join-Path $scriptDir 'AgySafetyHook.js'
    $nodeCmd = (Get-Command node -ErrorAction Stop).Source

    # 2a. Secret Deny (.env)
    $p1 = @{ toolCall = @{ name = 'view_file'; args = @{ AbsolutePath = (Join-Path $tempGitRepo '.env') } }; workspacePaths = @($tempGitRepo) } | ConvertTo-Json -Compress
    $res1 = ($p1 | & $nodeCmd $hookScript) | ConvertFrom-Json
    Assert-Condition ($res1.decision -eq 'deny') "Hook denies reading .env"

    # 2b. Secret Deny (id_rsa)
    $p2 = @{ toolCall = @{ name = 'view_file'; args = @{ AbsolutePath = 'C:\Users\test\.ssh\id_rsa' } }; workspacePaths = @($tempGitRepo) } | ConvertTo-Json -Compress
    $res2 = ($p2 | & $nodeCmd $hookScript) | ConvertFrom-Json
    Assert-Condition ($res2.decision -eq 'deny') "Hook denies reading id_rsa"

    # 2c. Benign Workspace File (Allow)
    $p3 = @{ toolCall = @{ name = 'view_file'; args = @{ AbsolutePath = (Join-Path $tempGitRepo 'src\index.js') } }; workspacePaths = @($tempGitRepo) } | ConvertTo-Json -Compress
    $res3 = ($p3 | & $nodeCmd $hookScript) | ConvertFrom-Json
    Assert-Condition ($res3.decision -eq 'allow') "Hook allows reading benign workspace file"

    # 2d. Out-of-Workspace Write (Deny)
    $p4 = @{ toolCall = @{ name = 'write_to_file'; args = @{ TargetFile = 'C:\Windows\malicious.dll' } }; workspacePaths = @($tempGitRepo) } | ConvertTo-Json -Compress
    $res4 = ($p4 | & $nodeCmd $hookScript) | ConvertFrom-Json
    Assert-Condition ($res4.decision -eq 'deny') "Hook denies write outside workspace"

    # 2e. Encoded PowerShell Command (Deny)
    $p5 = @{ toolCall = @{ name = 'run_command'; args = @{ CommandLine = 'powershell.exe -EncodedCommand JABFAHIAcg...' } }; workspacePaths = @($tempGitRepo) } | ConvertTo-Json -Compress
    $res5 = ($p5 | & $nodeCmd $hookScript) | ConvertFrom-Json
    Assert-Condition ($res5.decision -eq 'deny') "Hook denies -EncodedCommand execution"

    # Test 3: Installation
    Write-Output "Test 3: Safe Setup Installation"
    $installScript = Join-Path $scriptDir 'Install-AgySafety.ps1'
    $installResult = @(& $installScript `
        -GeminiHome $tempGeminiHome `
        -WorkspacePath $tempGitRepo `
        -ApprovalMode BoundedAutonomy `
        -NetworkMode Off `
        -ConfirmApply `
        -NonInteractive)
    $installSummary = @($installResult | Where-Object { $_ -is [pscustomobject] -and $_.PSObject.Properties['Status'] } | Select-Object -Last 1)
    Assert-Condition ($installSummary.Count -eq 1 -and $installSummary[0].Status -eq 'INSTALLED_SUCCESS') "Installation reported success"
    
    $cliSettingsPath = Join-Path (Join-Path $tempGeminiHome 'antigravity-cli') 'settings.json'
    $writtenSettings = Get-Content -Path $cliSettingsPath -Raw | ConvertFrom-Json
    Assert-Condition ($writtenSettings.nonWorkspaceFileAccess -eq 'deny') "Settings: nonWorkspaceFileAccess locked to deny"
    Assert-Condition ($writtenSettings.terminalSandbox -eq $true) "Settings: terminalSandbox is true"
    Assert-Condition ($writtenSettings.toolExecutionPolicy -eq 'proceed-in-sandbox') "Settings: toolExecutionPolicy is proceed-in-sandbox"

    # Test 4: Checkpoint Bridge
    Write-Output "Test 4: Git Checkpoint Bridge"
    $checkpointScript = Join-Path (Join-Path (Join-Path $tempGeminiHome 'safe-setup') 'bin') 'New-AgyCheckpoint.ps1'
    Set-Content -Path (Join-Path $tempGitRepo 'feature.js') -Value 'console.log("safe change");'
    $cpOutput = @(& $checkpointScript -Action Save -Repository $tempGitRepo -Message "Test Checkpoint")
    $cpResult = @($cpOutput | Where-Object { $_ -is [pscustomobject] -and $_.PSObject.Properties['Status'] } | Select-Object -Last 1)
    Assert-Condition ($cpResult.Count -eq 1 -and $cpResult[0].Status -eq 'SAVED') "Checkpoint saved successfully"
    Assert-Condition ($cpResult[0].BranchAndIndexChanged -eq $false) "Active branch and index unchanged"

    # Test 4b: Refuse sensitive untracked in Checkpoint
    Set-Content -Path (Join-Path $tempGitRepo '.env') -Value 'SECRET_KEY=123'
    $refused = $false
    try {
        & $checkpointScript -Action Save -Repository $tempGitRepo 2>$null
    }
    catch {
        $refused = $true
    }
    Assert-Condition ($refused -eq $true) "Checkpoint refuses saving when untracked .env exists"
    Remove-Item -LiteralPath (Join-Path $tempGitRepo '.env') -Force

    # Test 5: Boundary & Probes Verification
    Write-Output "Test 5: Verification Probes"
    $testScript = Join-Path $scriptDir 'Test-AgySafety.ps1'
    $testOutput = & $testScript -GeminiHome $tempGeminiHome -AsJson | ConvertFrom-Json
    $failChecks = @($testOutput | Where-Object { $_.Status -eq 'FAIL' })
    Assert-Condition ($failChecks.Count -eq 0) "All verification checks passed without FAIL"

    # Test 6: Clean Rollback
    Write-Output "Test 6: Rollback"
    $rollbackScript = Join-Path $scriptDir 'Rollback-AgySafety.ps1'
    & $rollbackScript -GeminiHome $tempGeminiHome -ConfirmRollback -NonInteractive
    $stateFile = Join-Path (Join-Path $tempGeminiHome 'safe-setup') 'install-state.json'
    Assert-Condition (-not (Test-Path -LiteralPath $stateFile)) "Install state removed after rollback"
}
finally {
    if (Test-Path -LiteralPath $tempBase) {
        Remove-Item -LiteralPath $tempBase -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output ""
Write-Output "=== Test Results: $passCount Passed, $failCount Failed ==="
if ($failCount -gt 0) {
    throw "$failCount test(s) failed."
}
