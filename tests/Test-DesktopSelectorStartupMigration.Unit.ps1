#requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$commonScript = Join-Path $projectRoot 'skills\codex-safe-setup\scripts\DesktopPermissionSelector.Common.ps1'
$installScript = Join-Path $projectRoot 'skills\codex-safe-setup\scripts\Install-DesktopPermissionSelectorFix.ps1'
$rollbackScript = Join-Path $projectRoot 'skills\codex-safe-setup\scripts\Rollback-DesktopPermissionSelectorFix.ps1'
$watcherAsset = Join-Path $projectRoot 'skills\codex-safe-setup\assets\desktop-permission-selector\Watch-CodexDesktop.ps1'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('css startup migration tests ' + [guid]::NewGuid().ToString('N'))
. $commonScript

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function New-ShortcutFixture {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$TargetPath,
        [string]$Arguments = '',
        [string]$WorkingDirectory = '',
        [string]$Description = ''
    )

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $path = Join-Path $Directory $Name
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($path)
    $shortcut.TargetPath = $TargetPath
    if ($Arguments) { $shortcut.Arguments = $Arguments }
    if ($WorkingDirectory) { $shortcut.WorkingDirectory = $WorkingDirectory }
    if ($Description) { $shortcut.Description = $Description }
    $shortcut.Save()
    return $path
}

function New-LegacyGenerationFixture {
    param([Parameter(Mandatory)][string]$CodexHome, [switch]$WithoutDirectory)

    $legacyRoot = Join-Path $CodexHome 'desktop-ui-fix'
    if (-not $WithoutDirectory) {
        New-Item -ItemType Directory -Path (Join-Path $legacyRoot 'app') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $legacyRoot 'Watch-CodexDesktop.vbs'), "' legacy watcher stub", [Text.UTF8Encoding]::new($false))
    }
    return $legacyRoot
}

$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
$realStartupFingerprints = @(
    (Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex Desktop UI Fix.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex Safe Setup Desktop Selector.lnk')
) | ForEach-Object {
    [pscustomobject]@{ Path = $_; Fingerprint = if (Test-Path $_) { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash } else { '<missing>' } }
}

try {
    # --- Scenario 1: legacy directory present and the shortcut targets its watcher exactly.
    $home1 = Join-Path $temporaryRoot 's1 codex home'
    $startup1 = Join-Path $temporaryRoot 's1 startup'
    $legacy1 = New-LegacyGenerationFixture -CodexHome $home1
    $lnk1 = New-ShortcutFixture -Directory $startup1 -Name 'Codex Desktop UI Fix.lnk' `
        -TargetPath $wscript -Arguments ('"' + (Join-Path $legacy1 'Watch-CodexDesktop.vbs') + '"') `
        -WorkingDirectory $legacy1 -Description 'Keeps Codex Desktop on the stable permission selector'
    $history1 = Join-Path $home1 'safe-setup\desktop-selector-fix-history'
    $removed1 = @(Remove-CssDesktopSelectorLegacyShortcuts -LegacyRoot $legacy1 -HistoryRoot $history1 -StartupDirectories @($startup1))
    Assert-True ($removed1.Count -eq 1 -and $removed1[0] -eq $lnk1) 'Scenario 1: the exact legacy watcher shortcut must be removed.'
    Assert-True (-not (Test-Path -LiteralPath $lnk1)) 'Scenario 1: the removed entry must no longer exist.'
    $archiveDirs1 = @(Get-ChildItem -LiteralPath $history1 -Directory -Filter '*-legacy-autostart')
    Assert-True ($archiveDirs1.Count -eq 1) 'Scenario 1: removal must archive into one recovery folder.'
    Assert-True (Test-Path -LiteralPath (Join-Path $archiveDirs1[0].FullName 'Codex Desktop UI Fix.lnk')) 'Scenario 1: the archived .lnk copy must exist.'
    $metadataFile = Join-Path $archiveDirs1[0].FullName 'Codex Desktop UI Fix.metadata.json'
    Assert-True (Test-Path -LiteralPath $metadataFile) 'Scenario 1: removal must write shortcut metadata.'
    $metadata1 = [IO.File]::ReadAllText($metadataFile) | ConvertFrom-Json
    Assert-True ($metadata1.sha256 -eq (Get-CssFileSha256 -Path (Join-Path $archiveDirs1[0].FullName 'Codex Desktop UI Fix.lnk'))) 'Scenario 1: metadata must record the archived file hash.'
    Assert-True ($metadata1.targetPath -ieq $wscript -and $metadata1.arguments -like '*Watch-CodexDesktop.vbs*') 'Scenario 1: metadata must record target and arguments.'

    # --- Scenario 2: legacy directory already gone but a stale shortcut remains (the field incident).
    $home2 = Join-Path $temporaryRoot 's2 codex home'
    $startup2 = Join-Path $temporaryRoot 's2 startup'
    $legacy2 = New-LegacyGenerationFixture -CodexHome $home2 -WithoutDirectory
    $lnk2 = New-ShortcutFixture -Directory $startup2 -Name 'Codex Desktop UI Fix.lnk' `
        -TargetPath $wscript -Arguments ('"' + (Join-Path $legacy2 'Watch-CodexDesktop.vbs') + '"')
    $history2 = Join-Path $home2 'safe-setup\desktop-selector-fix-history'
    $removed2 = @(Remove-CssDesktopSelectorLegacyShortcuts -LegacyRoot $legacy2 -HistoryRoot $history2 -StartupDirectories @($startup2))
    Assert-True ($removed2.Count -eq 1) 'Scenario 2: a stale shortcut must be removable without the legacy directory.'
    Assert-True (-not (Test-Path -LiteralPath $lnk2)) 'Scenario 2: the stale entry must be gone.'
    Assert-True (@(Get-ChildItem -LiteralPath $history2 -Directory -Filter '*-legacy-autostart').Count -eq 1) 'Scenario 2: stale removal must still be archived.'

    # --- Scenario 3: identical file name pointing somewhere else must be preserved.
    $home3 = Join-Path $temporaryRoot 's3 codex home'
    $startup3 = Join-Path $temporaryRoot 's3 startup'
    $otherRoot3 = Join-Path $temporaryRoot 'unrelated tools'
    $legacy3 = New-LegacyGenerationFixture -CodexHome $home3 -WithoutDirectory
    $lnk3 = New-ShortcutFixture -Directory $startup3 -Name 'Codex Desktop UI Fix.lnk' `
        -TargetPath $wscript -Arguments ('"' + (Join-Path $otherRoot3 'SomethingElse.vbs') + '"')
    $removed3 = @(Remove-CssDesktopSelectorLegacyShortcuts -LegacyRoot $legacy3 -HistoryRoot (Join-Path $home3 'history') -StartupDirectories @($startup3))
    Assert-True ($removed3.Count -eq 0) 'Scenario 3: nothing may be removed for an unrelated target.'
    Assert-True (Test-Path -LiteralPath $lnk3) 'Scenario 3: same-name shortcut with another target must be preserved.'

    # --- Scenario 4: quoting, casing, forward slashes, and case-varied wscript path still match.
    $home4 = Join-Path $temporaryRoot 's4 codex home'
    $startup4 = Join-Path $temporaryRoot 's4 startup'
    $legacy4 = New-LegacyGenerationFixture -CodexHome $home4
    $legacyVbs4 = (Join-Path $legacy4 'Watch-CodexDesktop.vbs')
    $variants = @(
        @{ Name = 'variant quoted.lnk'; Args = '"{0}"' -f $legacyVbs4 },
        @{ Name = 'variant upper.lnk'; Args = ('"{0}"' -f $legacyVbs4.ToUpperInvariant()) },
        @{ Name = 'variant slash.lnk'; Args = ('"{0}"' -f ($legacyVbs4.Replace('\', '/'))) },
        @{ Name = 'variant extra.lnk'; Args = ('//nologo "{0}" //b' -f $legacyVbs4) }
    )
    foreach ($variant in $variants) {
        [void](New-ShortcutFixture -Directory $startup4 -Name $variant.Name -TargetPath $WSCRIPT.ToUpperInvariant() -Arguments $variant.Args)
    }
    $removed4 = @(Remove-CssDesktopSelectorLegacyShortcuts -LegacyRoot $legacy4 -HistoryRoot (Join-Path $home4 'history') -StartupDirectories @($startup4))
    Assert-True ($removed4.Count -eq 4) "Scenario 4: all four normalization variants must match (got $($removed4.Count))."
    foreach ($variant in $variants) {
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $startup4 $variant.Name))) "Scenario 4: $($variant.Name) must be removed."
    }

    # --- Scenario 5: unrelated wscript shortcuts must survive.
    $home5 = Join-Path $temporaryRoot 's5 codex home'
    $startup5 = Join-Path $temporaryRoot 's5 startup'
    $legacy5 = New-LegacyGenerationFixture -CodexHome $home5 -WithoutDirectory
    $keep5a = New-ShortcutFixture -Directory $startup5 -Name 'My Backup Script.lnk' `
        -TargetPath $wscript -Arguments '"C:\tools\backup.vbs"'
    $removed5 = @(Remove-CssDesktopSelectorLegacyShortcuts -LegacyRoot $legacy5 -HistoryRoot (Join-Path $home5 'history') -StartupDirectories @($startup5))
    Assert-True ($removed5.Count -eq 0) 'Scenario 5: unrelated autostart entries must not be touched.'
    Assert-True (Test-Path -LiteralPath $keep5a) 'Scenario 5: unrelated wscript entry must be preserved.'

    # --- Scenario 6: repeated execution is idempotent.
    $home6 = Join-Path $temporaryRoot 's6 codex home'
    $startup6 = Join-Path $temporaryRoot 's6 startup'
    $legacy6 = New-LegacyGenerationFixture -CodexHome $home6
    [void](New-ShortcutFixture -Directory $startup6 -Name 'Codex Desktop UI Fix.lnk' `
        -TargetPath $wscript -Arguments ('"' + (Join-Path $legacy6 'Watch-CodexDesktop.vbs') + '"'))
    $history6 = Join-Path $home6 'history'
    $pass1 = @(Remove-CssDesktopSelectorLegacyShortcuts -LegacyRoot $legacy6 -HistoryRoot $history6 -StartupDirectories @($startup6))
    $pass2 = @(Remove-CssDesktopSelectorLegacyShortcuts -LegacyRoot $legacy6 -HistoryRoot $history6 -StartupDirectories @($startup6))
    $pass3 = @(Remove-CssDesktopSelectorLegacyShortcuts -LegacyRoot $legacy6 -HistoryRoot $history6 -StartupDirectories @($startup6))
    Assert-True ($pass1.Count -eq 1 -and $pass2.Count -eq 0 -and $pass3.Count -eq 0) 'Scenario 6: repeat runs must remove nothing further.'
    Assert-True (@(Get-ChildItem -LiteralPath $history6 -Directory -Filter '*-legacy-autostart').Count -eq 1) 'Scenario 6: idempotent runs must create only one archive folder.'

    # --- Scenario 7: enumeration is read-only when nothing matches and tolerates missing folders.
    $missing7 = @(Get-CssDesktopSelectorLegacyShortcuts -LegacyRoot (Join-Path $temporaryRoot 'nope') -StartupDirectories @(Join-Path $temporaryRoot 'does-not-exist-at-all'))
    Assert-True ($missing7.Count -eq 0) 'Scenario 7: missing folders must yield no entries.'

    # --- Scenario 8: installer ordering — legacy autostart cleanup happens before any state mutation.
    $installText = [IO.File]::ReadAllText($installScript)
    $cleanupIndex = $installText.IndexOf('$legacyStartupRemoved = @(Remove-CssDesktopSelectorLegacyShortcuts')
    $stopIndex = $installText.IndexOf('[void](Stop-CssDesktopSelectorWatcher -DestinationRoot $previousDestination)')
    $moveIndex = $installText.IndexOf('$previousRoot = Join-Path $historyRoot')
    Assert-True ($cleanupIndex -ge 0 -and $stopIndex -gt $cleanupIndex -and $moveIndex -gt $cleanupIndex) 'Scenario 8: installer must clean legacy autostart before stopping watchers or moving generations.'

    # --- Scenario 9: rollback never resurrects watcher autostart.
    $rollbackText = [IO.File]::ReadAllText($rollbackScript)
    Assert-True (-not $rollbackText.Contains('Start-Process')) 'Scenario 9: rollback must never start any process.'
    Assert-True ($rollbackText.Contains('never recreates startup-watcher autostart')) 'Scenario 9: rollback must document the autostart contract.'

    # --- Scenario 10: at most one watcher registration path remains, and it is opt-in.
    $installAst = [Management.Automation.Language.Parser]::ParseFile($installScript, [ref]$null, [ref]$null)
    $startupAssignments = @($installAst.Find({
        param($node)
        $node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -eq '$startupShortcut'
    }, $true))
    Assert-True ($startupAssignments.Count -le 1) 'Scenario 10: the installer must have a single startup-shortcut assignment point.'
    Assert-True ($installText.Contains('$EnableStartupWatcher')) 'Scenario 10: watcher registration must be opt-in via -EnableStartupWatcher.'
    $watcherText = [IO.File]::ReadAllText($watcherAsset)
    foreach ($forbiddenToken in @('CloseMainWindow', 'Stop-Process', 'Start-CodexFixed')) {
        Assert-True (-not $watcherText.Contains($forbiddenToken)) "Scenario 10: the watcher asset must never reference '$forbiddenToken'."
    }

    Write-Output 'PASS: legacy desktop selector autostart migration coverage'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    foreach ($record in $realStartupFingerprints) {
        $current = if (Test-Path -LiteralPath $record.Path -PathType Leaf) { (Get-FileHash -LiteralPath $record.Path -Algorithm SHA256).Hash } else { '<missing>' }
        if ($current -ne $record.Fingerprint) {
            throw "REAL STARTUP GUARD: unexpected change at $($record.Path)"
        }
    }
}
