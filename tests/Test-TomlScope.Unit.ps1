#requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$commonScript = Join-Path $projectRoot 'skills\codex-safe-setup\scripts\Common.ps1'
. $commonScript

$fixturePath = Join-Path $projectRoot 'tests\fixtures\css-broken-config-fixture.toml'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('css-toml-scope-' + [guid]::NewGuid().ToString('N'))
$installScript = Join-Path $projectRoot 'skills\codex-safe-setup\scripts\Install-CodexSafety.ps1'
$pythonCommand = Get-Command python -ErrorAction SilentlyContinue | Select-Object -First 1

function Assert-Scope {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Get-MisplacedFindings {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $document = Get-CssTomlDocument -Text $Text -IncludeDiagnostics
    return @($document.Diagnostics | Where-Object Code -eq 'MisplacedTopLevelKey')
}

try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    $fixtureText = [IO.File]::ReadAllText($fixturePath)

    # 1. The real incident fixture must produce exactly the diagnosed misplacements.
    $findings = Get-MisplacedFindings -Text $fixtureText
    Assert-Scope ($findings.Count -eq 8) ("Fixture must yield exactly 8 misplaced-key findings, got {0}." -f $findings.Count)
    $errorFindings = @($findings | Where-Object Severity -eq 'Error')
    $warningFindings = @($findings | Where-Object Severity -eq 'Warning')
    Assert-Scope ($errorFindings.Count -eq 1 -and $errorFindings[0].Key -eq 'default_permissions' -and $errorFindings[0].SectionPath -eq 'model_providers.openrouter') 'The swallowed plugin default_permissions under [model_providers.openrouter] must be the single Error finding.'
    foreach ($expected in @(
        [pscustomobject]@{ Key = 'web_search'; Section = 'model_providers.openrouter' },
        [pscustomobject]@{ Key = 'service_tier'; Section = 'model_providers.openrouter' },
        [pscustomobject]@{ Key = 'notify'; Section = 'model_providers.openrouter' },
        [pscustomobject]@{ Key = 'notify'; Section = 'windows' },
        [pscustomobject]@{ Key = 'model'; Section = 'windows' },
        [pscustomobject]@{ Key = 'model_reasoning_effort'; Section = 'windows' },
        [pscustomobject]@{ Key = 'model_verbosity'; Section = 'windows' }
    )) {
        $match = @($warningFindings | Where-Object { $_.Key -eq $expected.Key -and $_.SectionPath -eq $expected.Section })
        Assert-Scope ($match.Count -eq 1) ("Expected warning finding for '{0}' under [{1}]." -f $expected.Key, $expected.Section)
    }

    # 2. Multi-line values must not confuse the section tracker.
    $tricky = @'
title = "demo"
notify = [
  "first-agent",
  "[definitely-not-a-table]",
]
summary = """
[also-not-a-table]
inside = a string
"""
[real]
name = "yes"
'@
    $trickyDoc = Get-CssTomlDocument -Text $tricky -IncludeDiagnostics
    $realNameElement = @($trickyDoc.Elements | Where-Object { $_.Kind -eq 'KeyValue' -and $_.Key -eq 'name' })
    Assert-Scope ($realNameElement.Count -eq 1 -and $realNameElement[0].SectionPath -eq 'real') 'Keys after a multi-line array and multi-line string must resolve to the correct section.'
    Assert-Scope ((@($trickyDoc.Diagnostics | Where-Object Code -eq 'UnterminatedValue')).Count -eq 0) 'Balanced multi-line constructs must not raise UnterminatedValue.'
    $unterminated = $tricky + "`nopen = ["
    $unterminatedDoc = Get-CssTomlDocument -Text $unterminated -IncludeDiagnostics
    Assert-Scope ((@($unterminatedDoc.Diagnostics | Where-Object Code -eq 'UnterminatedValue')).Count -eq 1) 'An unterminated array at EOF must be reported.'

    # 3. Duplicate tables are structural errors.
    $duplicateDoc = Get-CssTomlDocument -Text "model = `"x`"`n[a]`nkey1 = 1`n[b]`nkey2 = 2`n[a]`nkey3 = 3`n" -IncludeDiagnostics
    Assert-Scope ((@($duplicateDoc.Diagnostics | Where-Object Code -eq 'DuplicateTableHeader')).Count -eq 1) 'A repeated table header must be reported exactly once.'

    # 4. Plugin-owned repair removes only the plugin line.
    $repaired = Repair-CssMisplacedPluginKeys -Text $fixtureText
    Assert-Scope ($repaired.RemovedCount -eq 1) 'Plugin repair on the fixture must remove exactly the one swallowed default_permissions.'
    Assert-Scope (-not $repaired.Text.Contains('default_permissions = ":workspace"')) 'After repair the swallowed plugin key must be gone from the wrong section.'
    Assert-Scope ($repaired.Text.Contains('web_search = "live"')) 'Foreign keys must survive plugin repair untouched.'

    # 5. Full installer run over the broken fixture: legacy block migrates, dual
    #    blocks appear, candidate validates clean, foreign keys remain untouched.
    $homeA = Join-Path $temporaryRoot 'home-a'
    $configA = Join-Path $homeA 'config.toml'
    New-Item -ItemType Directory -Path $homeA -Force | Out-Null
    [IO.File]::WriteAllText($configA, $fixtureText, [Text.UTF8Encoding]::new($false))
    & $installScript -PermissionRouting DynamicUi -NetworkMode Off -WindowsSandbox Keep `
        -CodexHome $homeA -ConfigPath $configA -StateRoot (Join-Path $homeA 'safe-setup') `
        -MigrateLegacySettings -AcknowledgeDynamicUiReadScope -ConfirmApply -NonInteractive *> $null
    Assert-Scope ($?) "Installer must succeed against the incident fixture."
    $installedA = [IO.File]::ReadAllText($configA)
    Assert-Scope (-not $installedA.Contains('# >>> codex-safe-setup managed >>>')) 'The retired single managed block must be migrated away.'
    Assert-Scope ($installedA.Contains($script:CssTomlTopBlockStart) -and $installedA.Contains($script:CssTomlProfileStart)) 'Both new managed regions must exist after migration.'
    $topBlockIndex = $installedA.IndexOf($script:CssTomlTopBlockStart)
    $firstHeaderIndex = ([regex]::Match($installedA, '(?m)^\[')).Index
    Assert-Scope ($topBlockIndex -lt $firstHeaderIndex) 'The managed top-level block must sit before the first [table] header.'
    $installedFindings = @(Get-MisplacedFindings -Text $installedA | Where-Object Severity -eq 'Error')
    Assert-Scope ($installedFindings.Count -eq 0) 'No plugin-owned misplacement may remain after installation.'
    $foreignStill = @(Get-MisplacedFindings -Text $installedA | Where-Object Severity -eq 'Warning')
    Assert-Scope ($foreignStill.Count -eq 7) 'Report-only ownership: all seven foreign misplacements must remain flagged, untouched.'
    Assert-Scope ($installedA.Contains('web_search = "live"') -and $installedA.Contains('localeOverride = "zh-CN"')) 'Foreign content must survive byte-for-byte.'
    if ($pythonCommand) {
        $parseOutput = @(& $pythonCommand.Source -c 'import sys,tomllib; tomllib.load(open(sys.argv[1], "rb"))' $configA 2>&1)
        Assert-Scope ($LASTEXITCODE -eq 0) ("Repaired fixture config must parse as TOML: {0}" -f ($parseOutput -join ' | '))
    }

    # 6. Explicit foreign repair relocates the seven lines to the top level.
    $homeB = Join-Path $temporaryRoot 'home-b'
    $configB = Join-Path $homeB 'config.toml'
    New-Item -ItemType Directory -Path $homeB -Force | Out-Null
    [IO.File]::WriteAllText($configB, $fixtureText, [Text.UTF8Encoding]::new($false))
    & $installScript -PermissionRouting DynamicUi -NetworkMode Off -WindowsSandbox Keep `
        -CodexHome $homeB -ConfigPath $configB -StateRoot (Join-Path $homeB 'safe-setup') `
        -MigrateLegacySettings -AcknowledgeDynamicUiReadScope -RepairForeignMisplacedKeys -ConfirmApply -NonInteractive *> $null
    Assert-Scope ($?) "Installer with -RepairForeignMisplacedKeys must succeed."
    $installedB = [IO.File]::ReadAllText($configB)
    $remainingForeign = @(Get-MisplacedFindings -Text $installedB)
    Assert-Scope ($remainingForeign.Count -eq 4) ("Collision policy: exactly the three top-level-shadowing keys plus the intra-batch notify collision must stay flagged, got {0}." -f $remainingForeign.Count)
    Assert-Scope (@($remainingForeign | Where-Object { $_.Key -notin @('model', 'model_reasoning_effort', 'model_verbosity', 'notify') }).Count -eq 0 -and @($remainingForeign | Where-Object { $_.SectionPath -ne 'windows' }).Count -eq 0) 'Only the four colliding keys under [windows] may remain.'
    $webSearchElements = @((Get-CssTomlDocument -Text $installedB).Elements | Where-Object { $_.Kind -eq 'KeyValue' -and $_.Key -eq 'web_search' })
    Assert-Scope ($webSearchElements.Count -eq 1 -and $webSearchElements[0].SectionPath -eq '') 'Unique foreign keys must be relocated to the TOML top level.'
    $topLevelNotifyCount = @((Get-CssTomlDocument -Text $installedB).Elements | Where-Object { $_.Kind -eq 'KeyValue' -and $_.SectionPath -eq '' -and $_.Key -eq 'notify' }).Count
    Assert-Scope ($topLevelNotifyCount -eq 1) 'Only the first notify line may be relocated; the second must be skipped as an intra-batch collision.'
    $duplicateTopLevel = @((Get-CssTomlDocument -Text $installedB -IncludeDiagnostics).Diagnostics | Where-Object Code -eq 'DuplicateTopLevelKey')
    Assert-Scope ($duplicateTopLevel.Count -eq 0) 'No duplicate top-level keys may exist after repair.'
    if ($pythonCommand) {
        $parseOutputB = @(& $pythonCommand.Source -c 'import sys,tomllib; tomllib.load(open(sys.argv[1], "rb"))' $configB 2>&1)
        Assert-Scope ($LASTEXITCODE -eq 0) ("Foreign-repaired config must parse as TOML: {0}" -f ($parseOutputB -join ' | '))
    }

    # 7. Concurrency guard: bytes changed between plan and write abort cleanly.
    $guardConfig = Join-Path $temporaryRoot 'guard.toml'
    [IO.File]::WriteAllText($guardConfig, "model = `"a`"`n", [Text.UTF8Encoding]::new($false))
    $staleHash = Get-CssFileTextSha256 -Text "model = `"a`"`n"
    [IO.File]::WriteAllText($guardConfig, "model = `"b`"`n", [Text.UTF8Encoding]::new($false))
    $concurrentRefused = $false
    try {
        Invoke-CssGuardedConfigWrite -Path $guardConfig -ExpectedOriginalSha256 $staleHash -NewText "model = `"c`"`n"
    } catch {
        $concurrentRefused = $_.Exception.Message -match 'CONCURRENT_MODIFICATION'
    }
    Assert-Scope $concurrentRefused 'A hash mismatch since plan time must refuse the write with CONCURRENT_MODIFICATION.'
    Assert-Scope (([IO.File]::ReadAllText($guardConfig)) -eq "model = `"b`"`n") 'A refused guarded write must leave the current bytes untouched.'

    # 8. CRLF configurations keep their newline style through every editor path.
    $crlfInput = "model = `"x`"`r`n`r`n[owner]`r`nname = `"y`"`r`ndefault_permissions = `"oops`"`r`n"
    $crlfRepaired = Repair-CssMisplacedPluginKeys -Text $crlfInput
    Assert-Scope ($crlfRepaired.Text.Contains("`r`n")) 'Plugin repair must preserve CRLF newlines.'
    $residualAfterCrlfStrip = $crlfRepaired.Text.Replace("`r`n", '')
    Assert-Scope (-not $residualAfterCrlfStrip.Contains("`r") -and -not $residualAfterCrlfStrip.Contains("`n")) 'CRLF document must not gain stray bare LF or CR characters.'
    $crlfBlocked = Set-CssTomlTopLevelBlock -Text $crlfRepaired.Text -BlockLines @(
        $script:CssTomlTopBlockStart,
        'default_permissions = ":workspace"',
        $script:CssTomlTopBlockEnd
    )
    Assert-Scope ($crlfBlocked.Contains("`r`n")) 'Managed-block insertion must preserve CRLF style.'
    Assert-Scope (-not (($crlfBlocked -replace "`r`n", '' ).Contains("`n"))) 'No stray bare LF may be introduced into a CRLF document.'
    $crlfFindings = @(Get-MisplacedFindings -Text $crlfBlocked)
    Assert-Scope ($crlfFindings.Count -eq 0) 'The repaired CRLF document must be structurally clean.'

    Write-Output 'PASS: scope-aware TOML editing diagnoses, repairs, relocates, guards, and preserves the incident fixture'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
