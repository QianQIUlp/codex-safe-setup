#requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not [OperatingSystem]::IsWindows()) {
    Write-Output 'SKIP: legacy Desktop selector artifact cleanup requires Windows shortcut objects.'
    return
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$cleanupScript = Join-Path $projectRoot 'skills\codex-safe-setup\scripts\Remove-LegacyDesktopSelectorArtifacts.ps1'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('css-legacy-cleanup-' + [guid]::NewGuid().ToString('N'))

function Assert-Cleanup {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function New-SyntheticShortcut {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Arguments
    )
    $shell = New-Object -ComObject WScript.Shell
    $linkPath = Join-Path $Directory "$Name.lnk"
    $shortcut = $shell.CreateShortcut($linkPath)
    $shortcut.TargetPath = $target
    $shortcut.Arguments = $arguments
    $shortcut.Save()
    return $linkPath
}

try {
    $codexHome = Join-Path $temporaryRoot 'codex-home'
    $stateRoot = Join-Path $codexHome 'safe-setup'
    $userStartup = Join-Path $temporaryRoot 'startup-user'
    $commonStartup = Join-Path $temporaryRoot 'startup-common'
    New-Item -ItemType Directory -Path $stateRoot, $userStartup, $commonStartup -Force | Out-Null

    $wscriptTarget = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $legacyWatcherLink = New-SyntheticShortcut -Directory $userStartup -Name 'Codex Desktop UI Fix' `
        -Target $wscriptTarget `
        -Arguments ('"{0}"' -f (Join-Path $codexHome 'desktop-ui-fix\Watch-CodexDesktop.vbs'))
    $loaderWrapperLink = New-SyntheticShortcut -Directory $commonStartup -Name 'Codex' `
        -Target (Join-Path $codexHome 'desktop-selector-loader\Start-CodexFixed.vbs') `
        -Arguments ''
    $innocentLink = New-SyntheticShortcut -Directory $userStartup -Name 'Innocent' `
        -Target (Join-Path $env:SystemRoot 'System32\notepad.exe') `
        -Arguments ''
    $nearMissLink = New-SyntheticShortcut -Directory $userStartup -Name 'NearMiss' `
        -Target $wscriptTarget `
        -Arguments ('"{0}"' -f (Join-Path $codexHome 'desktop-ui-fixx\Other.vbs'))
    Assert-Cleanup (Test-Path -LiteralPath $nearMissLink) 'Fixture setup must create the near-miss shortcut.'

    New-Item -ItemType Directory -Path (Join-Path $stateRoot 'desktop-selector-fix-history') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $stateRoot 'desktop-selector-fix.json') -Value '{}' -Encoding utf8NoBOM

    $fakeEnvName = 'CSS_DESKTOP_SELECTOR_PROBE_MODE'
    $savedFakeEnvValue = [Environment]::GetEnvironmentVariable($fakeEnvName, 'User')
    [Environment]::SetEnvironmentVariable($fakeEnvName, 'synthetic-test-value', 'User')

    try {
        $planOutput = @(& $cleanupScript -CodexHome $codexHome -StateRoot $stateRoot -StartupRoots @($userStartup, $commonStartup) -EnvironmentVariables @($fakeEnvName) 2>&1)
        $planExitCode = $LASTEXITCODE
        Assert-Cleanup ($planExitCode -eq 2) "Plan mode must report residue with exit code 2, got $planExitCode."
        Assert-Cleanup (Test-Path -LiteralPath $legacyWatcherLink) 'Plan mode must not delete shortcuts.'
        Assert-Cleanup (([Environment]::GetEnvironmentVariable($fakeEnvName, 'User')) -eq 'synthetic-test-value') 'Plan mode must not modify environment variables.'
        Assert-Cleanup (($planOutput | Out-String) -match [regex]::Escape((Join-Path $codexHome 'desktop-selector-loader'))) 'Plan output must enumerate the retired loader wrapper shortcut.'
        Assert-Cleanup (($planOutput | Out-String) -notmatch 'NearMiss') 'The near-miss shortcut must never be matched.'

        & $cleanupScript -CodexHome $codexHome -StateRoot $stateRoot -StartupRoots @($userStartup, $commonStartup) -EnvironmentVariables @($fakeEnvName) -ConfirmApply *> $null
        $applyExitCode = $LASTEXITCODE
        Assert-Cleanup ($applyExitCode -eq 0) "Apply must succeed with exit code 0, got $applyExitCode."
        Assert-Cleanup (-not (Test-Path -LiteralPath $legacyWatcherLink)) 'Legacy watcher shortcut must be removed.'
        Assert-Cleanup (-not (Test-Path -LiteralPath $loaderWrapperLink)) 'Loader wrapper shortcut must be removed.'
        Assert-Cleanup (Test-Path -LiteralPath $innocentLink) 'Unrelated shortcuts must survive untouched.'
        Assert-Cleanup (Test-Path -LiteralPath $nearMissLink) 'A near-miss path that merely resembles a retired root must survive untouched.'
        Assert-Cleanup ([string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($fakeEnvName, 'User'))) 'The listed user environment variable must be removed.'
        Assert-Cleanup (-not (Test-Path -LiteralPath (Join-Path $stateRoot 'desktop-selector-fix-history'))) 'Retired selector history must be quarantined.'
        Assert-Cleanup (-not (Test-Path -LiteralPath (Join-Path $stateRoot 'desktop-selector-fix.json'))) 'Retired selector pointer must be quarantined.'

        $quarantine = Get-ChildItem -LiteralPath $stateRoot -Directory -Filter 'legacy-selector-quarantine-*' | Select-Object -First 1
        Assert-Cleanup ($null -ne $quarantine) 'Apply must create a timestamped quarantine folder under the state root.'
        $archivedLinks = @(Get-ChildItem -LiteralPath $quarantine.FullName -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue)
        $archivedMetadata = @(Get-ChildItem -LiteralPath $quarantine.FullName -Filter '*.metadata.json' -Recurse -ErrorAction SilentlyContinue)
        Assert-Cleanup ($archivedLinks.Count -ge 1 -and $archivedMetadata.Count -ge 1) 'Quarantine must preserve shortcut copies plus their archived metadata.'

        & $cleanupScript -CodexHome $codexHome -StateRoot $stateRoot -StartupRoots @($userStartup, $commonStartup) -EnvironmentVariables @($fakeEnvName) *> $null
        Assert-Cleanup ($LASTEXITCODE -eq 0) 'A second plan run over a clean system must report nothing to do with exit code 0.'
    }
    finally {
        [Environment]::SetEnvironmentVariable($fakeEnvName, $savedFakeEnvValue, 'User')
    }

    Write-Output 'PASS: legacy selector artifact cleanup is plan-first, precisely matched, process-free, and fully verified'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
