#requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptRoot = Join-Path $projectRoot 'skills\codex-safe-setup\scripts'
$installScript = Join-Path $scriptRoot 'Install-CodexSafety.ps1'
$upgradeScript = Join-Path $scriptRoot 'Upgrade-CodexSafety.ps1'
$testScript = Join-Path $scriptRoot 'Test-CodexSafety.ps1'
$assessScript = Join-Path $scriptRoot 'Assess-CodexSafety.ps1'
$commonScript = Join-Path $scriptRoot 'Common.ps1'
. $commonScript

function Assert-Routing {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "DYNAMIC ROUTING ASSERTION FAILED: $Message" }
}

function Get-AffectedDesktopFallbackLabel {
    param(
        [string]$ActiveProfile,
        [bool]$ConfigCreatesGenericCustom,
        [string[]]$NamedProfiles
    )
    if ($ActiveProfile) { return $ActiveProfile }
    if ($ConfigCreatesGenericCustom) { return 'Custom (config.toml)' }
    if ($NamedProfiles.Count -eq 1) { return $NamedProfiles[0] }
    return $null
}

function Read-AppServerMessage {
    param([Parameter(Mandatory)][Diagnostics.Process]$Process, [int]$TimeoutMilliseconds = 30000)

    $readTask = $Process.StandardOutput.ReadLineAsync()
    if (-not $readTask.Wait($TimeoutMilliseconds)) {
        throw "Timed out waiting for Codex app-server output after $TimeoutMilliseconds ms."
    }
    $line = $readTask.Result
    if ($null -eq $line) {
        $stderr = $Process.StandardError.ReadToEnd()
        throw "Codex app-server closed its output stream unexpectedly. $stderr"
    }
    try { return $line | ConvertFrom-Json -Depth 30 }
    catch { throw "Codex app-server emitted invalid JSON: $line" }
}

function Invoke-AppServerRequest {
    param(
        [Parameter(Mandatory)][Diagnostics.Process]$Process,
        [Parameter(Mandatory)][int]$Id,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)]$Params
    )

    $json = ([ordered]@{ method = $Method; id = $Id; params = $Params }) | ConvertTo-Json -Depth 30 -Compress
    $Process.StandardInput.WriteLine($json)
    $Process.StandardInput.Flush()
    while ($true) {
        $message = Read-AppServerMessage -Process $Process
        if ($message.PSObject.Properties['id'] -and [int]$message.id -eq $Id) {
            if ($message.PSObject.Properties['error']) {
                throw "Codex app-server request '$Method' failed: $($message.error | ConvertTo-Json -Depth 10 -Compress)"
            }
            return $message
        }
    }
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('codex-safe-routing-' + [guid]::NewGuid().ToString('N'))
$appProcess = $null
try {
    $dynamicHome = Join-Path $temporaryRoot 'dynamic-home'
    $dynamicState = Join-Path $dynamicHome 'safe-setup'
    $dynamicConfig = Join-Path $dynamicHome 'config.toml'
    New-Item -ItemType Directory -Path $dynamicHome -Force | Out-Null
    [IO.File]::WriteAllText($dynamicConfig, "model = `"gpt-5.5`"$([Environment]::NewLine)", [Text.UTF8Encoding]::new($false))

    $dynamicInstallResult = @(& $installScript -PermissionRouting DynamicUi -NetworkMode Off -WindowsSandbox Keep -CodexHome $dynamicHome -ConfigPath $dynamicConfig -StateRoot $dynamicState -AcknowledgeDynamicUiReadScope -ConfirmApply -NonInteractive)
    $dynamicInstallSummary = @($dynamicInstallResult | Where-Object { $_.PSObject.Properties['Status'] } | Select-Object -Last 1)
    Assert-Routing ($dynamicInstallSummary.Count -eq 1 -and $dynamicInstallSummary[0].Status -eq 'INSTALLED_FRESH_TASK_REQUIRED') 'DynamicUi completion must require a fresh task, not a Codex restart.'
    Assert-Routing ($dynamicInstallSummary[0].RequiredPermissionSelection -match 'codex-safe-workspace.*Full Access.*Workspace.*Read-only') 'DynamicUi completion must describe the stable Custom profile and all built-in UI permission choices.'
    Assert-Routing ($dynamicInstallSummary[0].RequiredRestart -match '^Not required') 'DynamicUi completion must state that normal UI switching does not require a Codex restart.'
    $dynamicText = [IO.File]::ReadAllText($dynamicConfig)
    Assert-Routing ($dynamicText -match '(?m)^\s*default_permissions\s*=\s*":workspace"') 'DynamicUi must use built-in Workspace as the config startup default.'
    Assert-Routing ($dynamicText -notmatch '(?m)^\s*(sandbox_mode|approval_policy|approvals_reviewer)\s*=') 'DynamicUi must not create a generic config-derived Custom fallback.'
    Assert-Routing ($dynamicText -match '(?m)^\s*\[permissions\.codex-safe-workspace\]') 'DynamicUi must expose the primary named Custom profile.'
    Assert-Routing ($dynamicText -match '(?m)^\s*\[permissions\.codex-safe-workspace-offline\]') 'DynamicUi must expose the second real named profile that disables the single-profile fallback.'
    Assert-Routing ($dynamicText -notmatch '(?m)^\s*description\s*=') 'The Custom description must remain unset until its user-facing wording is separately approved.'
    Assert-Routing ($dynamicText -match '(?ms)\[permissions\.codex-safe-workspace\.network\].*enabled\s*=\s*false') 'DynamicUi Off mode must disable primary Custom command networking.'
    Assert-Routing ($dynamicText -match '(?ms)\[permissions\.codex-safe-workspace-offline\.network\].*enabled\s*=\s*false') 'The offline compatibility profile must always disable command networking.'
    $dynamicInstallState = Get-Content -LiteralPath (Join-Path $dynamicState 'install-state.json') -Raw | ConvertFrom-Json
    Assert-Routing ($dynamicInstallState.schemaVersion -eq 9 -and $dynamicInstallState.productVersion -eq '0.3.0') 'DynamicUi install state must record the current release version with schema 9.'
    Assert-Routing ($dynamicInstallState.PermissionRouting -eq 'DynamicUi') 'DynamicUi install state must record its routing mode.'
    Assert-Routing ($dynamicInstallState.DynamicUiDisplayRoute -eq 'DualNamedProfiles') 'DynamicUi install state must record the dual named-profile display route.'
    Assert-Routing (-not $dynamicInstallState.ProtectWorkspaceSecrets) 'DynamicUi must record that sticky credential deny-globs are not installed.'
    $dynamicVerification = (& $testScript -CodexHome $dynamicHome -ConfigPath $dynamicConfig -StateRoot $dynamicState -SkipCliRuleCheck -AsJson) | ConvertFrom-Json
    Assert-Routing ($dynamicVerification.Overall -ne 'FAILED') 'DynamicUi static verification must not fail.'
    $dynamicCheck = @($dynamicVerification.Checks | Where-Object Control -eq 'Dynamic UI routing')
    Assert-Routing ($dynamicCheck.Count -eq 1 -and $dynamicCheck[0].Status -eq 'PASS') 'DynamicUi verifier must confirm the dual named-profile display route.'

    Assert-Routing ((Get-AffectedDesktopFallbackLabel -ActiveProfile '' -ConfigCreatesGenericCustom $false -NamedProfiles @('only-custom')) -eq 'only-custom') 'Regression fixture must reproduce the affected selector single-profile fallback.'
    Assert-Routing ((Get-AffectedDesktopFallbackLabel -ActiveProfile '' -ConfigCreatesGenericCustom $true -NamedProfiles @()) -eq 'Custom (config.toml)') 'Regression fixture must reproduce the config-derived generic Custom fallback.'
    Assert-Routing ($null -eq (Get-AffectedDesktopFallbackLabel -ActiveProfile '' -ConfigCreatesGenericCustom $false -NamedProfiles @('codex-safe-workspace', 'codex-safe-workspace-offline'))) 'The repaired shape must provide no synthetic fallback label that can replace the last manual click.'

    $indistinctHome = Join-Path $temporaryRoot 'indistinct-custom-home'
    $indistinctConfig = Join-Path $indistinctHome 'config.toml'
    New-Item -ItemType Directory -Path $indistinctHome -Force | Out-Null
    [IO.File]::WriteAllText($indistinctConfig, @'
sandbox_mode = "workspace-write"

[sandbox_workspace_write]
network_access = false
exclude_tmpdir_env_var = false
exclude_slash_tmp = false
'@, [Text.UTF8Encoding]::new($false))
    $indistinctAssessment = (& $assessScript -CodexHome $indistinctHome -ConfigPath $indistinctConfig -AsJson) | ConvertFrom-Json
    Assert-Routing (-not $indistinctAssessment.DynamicUiRoutingReady -and -not $indistinctAssessment.CustomCatalogProfileAvailable -and -not $indistinctAssessment.SelectableCustomProfile) 'Assessment must reject the obsolete generic Custom route.'

    $nestedDynamicHome = Join-Path $temporaryRoot 'nested-dynamic-home'
    $nestedDynamicState = Join-Path $nestedDynamicHome 'safe-setup'
    $nestedDynamicConfig = Join-Path $nestedDynamicHome 'config.toml'
    New-Item -ItemType Directory -Path $nestedDynamicHome -Force | Out-Null
    [IO.File]::WriteAllText($nestedDynamicConfig, @'
model = "gpt-5.5"

[profiles.audit]
sandbox_mode = "read-only"
'@, [Text.UTF8Encoding]::new($false))
    & $installScript -PermissionRouting DynamicUi -NetworkMode Off -WindowsSandbox Keep -CodexHome $nestedDynamicHome -ConfigPath $nestedDynamicConfig -StateRoot $nestedDynamicState -AcknowledgeDynamicUiReadScope -ConfirmApply -NonInteractive | Out-Null
    $nestedDynamicText = [IO.File]::ReadAllText($nestedDynamicConfig)
    $nestedDynamicSandbox = Get-CssTomlTopLevelStringValue -Text $nestedDynamicText -Key 'sandbox_mode'
    Assert-Routing (-not $nestedDynamicSandbox.Present) 'DynamicUi must not install a top-level generic Custom route when an unrelated profile has sandbox_mode.'
    Assert-Routing ((Get-CssPermissionProfileSettings -Text $nestedDynamicText).DefaultProfile -eq ':workspace') 'DynamicUi must install built-in Workspace as its top-level default.'
    Assert-Routing ((Get-CssTomlSectionText -Text $nestedDynamicText -Section 'profiles.audit') -match '(?m)^\s*sandbox_mode\s*=\s*"read-only"') 'DynamicUi must preserve unrelated profile-local sandbox_mode settings.'
    $nestedDynamicAssessment = (& $assessScript -CodexHome $nestedDynamicHome -ConfigPath $nestedDynamicConfig -AsJson) | ConvertFrom-Json
    Assert-Routing ($nestedDynamicAssessment.PermissionRouting -eq 'DynamicUi' -and -not $nestedDynamicAssessment.PermissionConfigurationConflict) 'Assessment must classify the actual top-level DynamicUi route, not a nested profile key.'
    $nestedDynamicVerification = (& $testScript -CodexHome $nestedDynamicHome -ConfigPath $nestedDynamicConfig -StateRoot $nestedDynamicState -SkipCliRuleCheck -AsJson) | ConvertFrom-Json
    Assert-Routing ($nestedDynamicVerification.Overall -ne 'FAILED') 'Static verification must accept DynamicUi when unrelated profiles contain sandbox_mode.'

    $nestedStrictHome = Join-Path $temporaryRoot 'nested-strict-home'
    $nestedStrictState = Join-Path $nestedStrictHome 'safe-setup'
    $nestedStrictConfig = Join-Path $nestedStrictHome 'config.toml'
    New-Item -ItemType Directory -Path $nestedStrictHome -Force | Out-Null
    [IO.File]::WriteAllText($nestedStrictConfig, @'
model = "gpt-5.5"

[profiles.audit]
sandbox_mode = "read-only"
'@, [Text.UTF8Encoding]::new($false))
    & $installScript -PermissionRouting StrictProfile -NetworkMode Off -WindowsSandbox Keep -CodexHome $nestedStrictHome -ConfigPath $nestedStrictConfig -StateRoot $nestedStrictState -ConfirmApply -NonInteractive | Out-Null
    $nestedStrictText = [IO.File]::ReadAllText($nestedStrictConfig)
    $nestedStrictDefault = Get-CssTomlTopLevelStringValue -Text $nestedStrictText -Key 'default_permissions'
    Assert-Routing ($nestedStrictDefault.Present -and $nestedStrictDefault.Value -eq 'codex-safe-workspace') 'StrictProfile must install its top-level default when an unrelated profile has sandbox_mode.'
    Assert-Routing (-not (Test-CssLegacySettings -Text $nestedStrictText).Present) 'Profile-local sandbox_mode must not be classified as legacy top-level configuration.'
    $nestedStrictAssessment = (& $assessScript -CodexHome $nestedStrictHome -ConfigPath $nestedStrictConfig -AsJson) | ConvertFrom-Json
    Assert-Routing ($nestedStrictAssessment.PermissionRouting -eq 'StrictProfile' -and -not $nestedStrictAssessment.PermissionConfigurationConflict) 'Assessment must not invent a conflict from a profile-local sandbox_mode.'

    $nestedDefaultProbe = "model = `"gpt-5.5`"`n[profiles.audit]`ndefault_permissions = `":danger-full-access`"`n"
    Assert-Routing (-not (Get-CssPermissionProfileSettings -Text $nestedDefaultProbe).DefaultPresent) 'A profile-local default_permissions key must not be mistaken for the top-level default.'
    $arrayProbe = "model = `"gpt-5.5`"`n[[profiles]]`nsandbox_mode = `"danger-full-access`"`n"
    Assert-Routing (-not (Get-CssTomlTopLevelStringValue -Text $arrayProbe -Key 'sandbox_mode').Present) 'A key after an array-of-tables header must not be mistaken for a top-level setting.'

    $scopedRootHome = Join-Path $temporaryRoot 'scoped-root-home'
    $scopedRootConfig = Join-Path $scopedRootHome 'config.toml'
    New-Item -ItemType Directory -Path $scopedRootHome -Force | Out-Null
    [IO.File]::WriteAllText($scopedRootConfig, @'
sandbox_mode = "workspace-write"

# >>> codex-safe-setup managed >>>
[permissions.codex-safe-workspace]
extends = ":workspace"

[permissions.codex-safe-workspace.filesystem]
":minimal" = "read"

[permissions.other.filesystem]
":root" = "deny"
# <<< codex-safe-setup managed <<<
'@, [Text.UTF8Encoding]::new($false))
    $scopedRootAssessment = (& $assessScript -CodexHome $scopedRootHome -ConfigPath $scopedRootConfig -AsJson) | ConvertFrom-Json
    Assert-Routing (-not $scopedRootAssessment.ManagedProfileAvailable -and $scopedRootAssessment.PermissionRouting -eq 'Unknown') 'A root deny in another profile must not qualify codex-safe-workspace as a managed Custom profile.'

    $stickyDenyHome = Join-Path $temporaryRoot 'sticky-deny-home'
    $stickyDenyConfig = Join-Path $stickyDenyHome 'config.toml'
    New-Item -ItemType Directory -Path $stickyDenyHome -Force | Out-Null
    [IO.File]::WriteAllText($stickyDenyConfig, @'
default_permissions = ":danger-full-access"

# >>> codex-safe-setup managed >>>
[permissions.codex-safe-workspace.filesystem]
":minimal" = "read"
":root" = "deny"

[permissions.codex-safe-workspace.filesystem.":workspace_roots"]
"." = "write"
# <<< codex-safe-setup managed <<<
'@, [Text.UTF8Encoding]::new($false))
    $stickyDenyAssessment = (& $assessScript -CodexHome $stickyDenyHome -ConfigPath $stickyDenyConfig -AsJson) | ConvertFrom-Json
    Assert-Routing ($stickyDenyAssessment.PermissionRouting -eq 'Conflict' -and $stickyDenyAssessment.DynamicUiDenyMergeRisk) 'A built-in DynamicUi default plus an explicit Custom deny must be classified as the sticky-deny conflict.'
    Assert-Routing ($stickyDenyAssessment.FullAccessRequested -and -not $stickyDenyAssessment.FullAccessDetected) 'A sticky-deny conflict must not report configured Full Access as effective.'
    $stickyVerifierOutput = @(& pwsh -NoProfile -NonInteractive -File $testScript -CodexHome $stickyDenyHome -ConfigPath $stickyDenyConfig -StateRoot (Join-Path $stickyDenyHome 'safe-setup') -SkipCliRuleCheck -AsJson 2>&1)
    Assert-Routing ($LASTEXITCODE -ne 0) 'The static verifier must fail a DynamicUi Custom profile containing a deny.'
    $stickyVerification = ($stickyVerifierOutput -join [Environment]::NewLine) | ConvertFrom-Json
    $stickyRoutingCheck = @($stickyVerification.Checks | Where-Object Control -eq 'Permission routing')
    Assert-Routing ($stickyRoutingCheck.Count -eq 1 -and $stickyRoutingCheck[0].Evidence -match 'deny.*preserves') 'The verifier must identify deny preservation as the routing failure.'

    $noCliHome = Join-Path $temporaryRoot 'no-cli-home'
    $noCliState = Join-Path $noCliHome 'safe-setup'
    $noCliConfig = Join-Path $noCliHome 'config.toml'
    $emptyPath = Join-Path $temporaryRoot 'empty-path'
    New-Item -ItemType Directory -Path $noCliHome, $emptyPath -Force | Out-Null
    [IO.File]::WriteAllText($noCliConfig, "model = `"gpt-5.5`"`n", [Text.UTF8Encoding]::new($false))
    $originalPath = $env:PATH
    try {
        $env:PATH = $emptyPath
        $noCliPreview = @(& $installScript -PermissionRouting DynamicUi -NetworkMode Off -WindowsSandbox Keep -CodexHome $noCliHome -ConfigPath $noCliConfig -StateRoot $noCliState -PlanOnly) -join [Environment]::NewLine
        Assert-Routing ($noCliPreview -match 'CodexCompatibility\s*:\s*BLOCKED FOR APPLY') 'PlanOnly must show the missing DynamicUi CLI prerequisite instead of refusing the preview.'
        Assert-Routing ($noCliPreview -match 'No files changed') 'A prerequisite-blocked DynamicUi preview must remain non-mutating.'
        $noCliApplyFailed = $false
        try {
            & $installScript -PermissionRouting DynamicUi -NetworkMode Off -WindowsSandbox Keep -CodexHome $noCliHome -ConfigPath $noCliConfig -StateRoot $noCliState -AcknowledgeDynamicUiReadScope -ConfirmApply -NonInteractive | Out-Null
        }
        catch { $noCliApplyFailed = $_.Exception.Message -match 'requires a detected Codex CLI 0\.138\.0 or newer' }
        Assert-Routing $noCliApplyFailed 'DynamicUi apply must still refuse a missing Codex CLI after allowing PlanOnly.'
        Assert-Routing (-not (Test-Path -LiteralPath $noCliState)) 'A prerequisite-blocked DynamicUi apply must not create install state.'

        $noCliVerification = (& $testScript -CodexHome $dynamicHome -ConfigPath $dynamicConfig -StateRoot $dynamicState -SkipCliRuleCheck -AsJson) | ConvertFrom-Json
        $noCliCompatibilityCheck = @($noCliVerification.Checks | Where-Object Control -eq 'Dynamic UI catalog compatibility')
        Assert-Routing ($noCliCompatibilityCheck.Count -eq 1 -and $noCliCompatibilityCheck[0].Status -eq 'PARTIAL') 'Verifier must mark missing CLI catalog compatibility PARTIAL, not PASS.'
    }
    finally {
        $env:PATH = $originalPath
    }

    $codexCommand = Get-Command codex -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($codexCommand) {
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        $startInfo.WorkingDirectory = $projectRoot
        $startInfo.Environment['CODEX_HOME'] = $dynamicHome

        if ([IO.Path]::GetExtension($codexCommand.Source) -eq '.ps1') {
            $pwshCommand = Get-Command pwsh -ErrorAction Stop | Select-Object -First 1
            $startInfo.FileName = $pwshCommand.Source
            foreach ($argument in @('-NoProfile', '-NonInteractive', '-File', $codexCommand.Source, 'app-server', '--stdio')) { [void]$startInfo.ArgumentList.Add($argument) }
        }
        elseif ([IO.Path]::GetExtension($codexCommand.Source) -in @('.cmd', '.bat')) {
            $startInfo.FileName = $env:ComSpec
            foreach ($argument in @('/d', '/c', $codexCommand.Source, 'app-server', '--stdio')) { [void]$startInfo.ArgumentList.Add($argument) }
        }
        else {
            $startInfo.FileName = $codexCommand.Source
            foreach ($argument in @('app-server', '--stdio')) { [void]$startInfo.ArgumentList.Add($argument) }
        }

        $appProcess = [Diagnostics.Process]::new()
        $appProcess.StartInfo = $startInfo
        Assert-Routing ($appProcess.Start()) 'Codex app-server process must start for the profile-catalog check.'
        [void](Invoke-AppServerRequest -Process $appProcess -Id 1 -Method 'initialize' -Params ([ordered]@{
            clientInfo = [ordered]@{ name = 'codex-safe-setup-tests'; title = 'Codex Safe Setup Tests'; version = $script:CssProductVersion }
            capabilities = [ordered]@{ experimentalApi = $true }
        }))
        $appProcess.StandardInput.WriteLine('{"method":"initialized","params":{}}')
        $appProcess.StandardInput.Flush()
        $profileList = Invoke-AppServerRequest -Process $appProcess -Id 2 -Method 'permissionProfile/list' -Params ([ordered]@{ cwd = $projectRoot })
        $availableProfileIds = @($profileList.result.data | Where-Object allowed | ForEach-Object id)
        Assert-Routing ($script:CssProfileName -in $availableProfileIds) 'DynamicUi must expose its primary named Custom profile.'
        Assert-Routing ($script:CssOfflineProfileName -in $availableProfileIds) 'DynamicUi must expose its positive-only offline profile.'
        foreach ($builtInId in @(':read-only', ':workspace', ':danger-full-access')) {
            Assert-Routing ($builtInId -in $availableProfileIds) "DynamicUi must not hide the built-in profile $builtInId."
        }
        $appProcess.StandardInput.Close()
        if (-not $appProcess.WaitForExit(10000)) {
            $appProcess.Kill($true)
            $appProcess.WaitForExit(5000) | Out-Null
        }
        $appProcess.Dispose()
        $appProcess = $null
    }

    $mixedHome = Join-Path $temporaryRoot 'mixed-home'
    $mixedState = Join-Path $mixedHome 'safe-setup'
    $mixedConfig = Join-Path $mixedHome 'config.toml'
    New-Item -ItemType Directory -Path $mixedHome -Force | Out-Null
    [IO.File]::WriteAllText($mixedConfig, "model = `"gpt-5.5`"$([Environment]::NewLine)", [Text.UTF8Encoding]::new($false))
    & $installScript -PermissionRouting StrictProfile -NetworkMode Off -WindowsSandbox Keep -CodexHome $mixedHome -ConfigPath $mixedConfig -StateRoot $mixedState -ConfirmApply -NonInteractive | Out-Null

    $mixedText = [IO.File]::ReadAllText($mixedConfig)
    $mixedText = Set-CssTomlTopLevelValue -Text $mixedText -Key 'sandbox_mode' -Literal '"danger-full-access"'
    [IO.File]::WriteAllText($mixedConfig, $mixedText, [Text.UTF8Encoding]::new($false))
    $mixedStatePath = Join-Path $mixedState 'install-state.json'
    $oldState = Get-Content -LiteralPath $mixedStatePath -Raw | ConvertFrom-Json
    $oldState.schemaVersion = 5
    $oldState.productVersion = '0.1.6'
    $oldState.PermissionRouting = 'DynamicUi'
    [IO.File]::WriteAllText($mixedStatePath, ($oldState | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))

    $beforePreview = [IO.File]::ReadAllText($mixedConfig)
    $preview = @(& $upgradeScript -CodexHome $mixedHome -ConfigPath $mixedConfig -StateRoot $mixedState -MigrateLegacySettings -PlanOnly) -join [Environment]::NewLine
    Assert-Routing ($preview -match 'PermissionRouting\s*:\s*DynamicUi') 'A 0.1.6 upgrade must preserve DynamicUi routing while replacing the unsafe mixed family.'
    Assert-Routing ($preview -match 'No files changed') 'DynamicUi upgrade preview must be non-mutating.'
    Assert-Routing ([IO.File]::ReadAllText($mixedConfig) -eq $beforePreview) 'DynamicUi preview must preserve the mixed reproduction byte-for-byte.'

    & $upgradeScript -CodexHome $mixedHome -ConfigPath $mixedConfig -StateRoot $mixedState -MigrateLegacySettings -AcknowledgeDynamicUiReadScope -ConfirmUpgrade -NonInteractive | Out-Null
    $repairedText = [IO.File]::ReadAllText($mixedConfig)
    Assert-Routing ($repairedText -notmatch '(?m)^\s*sandbox_mode\s*=') 'Upgrade must remove the generic config.toml Custom route.'
    Assert-Routing ($repairedText -match '(?m)^\s*default_permissions\s*=\s*":workspace"') 'Upgrade must install the built-in Workspace startup default.'
    Assert-Routing ($repairedText -match '(?m)^\s*\[permissions\.codex-safe-workspace\]' -and $repairedText -match '(?m)^\s*\[permissions\.codex-safe-workspace-offline\]') 'Upgrade must install both named Custom profiles.'
    $repairedState = Get-Content -LiteralPath $mixedStatePath -Raw | ConvertFrom-Json
    Assert-Routing ($repairedState.schemaVersion -eq 9 -and $repairedState.productVersion -eq '0.3.0' -and $repairedState.PermissionRouting -eq 'DynamicUi' -and $repairedState.DynamicUiDisplayRoute -eq 'DualNamedProfiles') 'Upgrade must record the current DynamicUi release state.'

    $developmentState = Get-Content -LiteralPath $mixedStatePath -Raw | ConvertFrom-Json
    $developmentState.schemaVersion = 8
    $developmentState.productVersion = '0.1.9'
    [IO.File]::WriteAllText($mixedStatePath, ($developmentState | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    $developmentPreview = @(& $upgradeScript -CodexHome $mixedHome -ConfigPath $mixedConfig -StateRoot $mixedState -MigrateLegacySettings -PlanOnly) -join [Environment]::NewLine
    Assert-Routing ($developmentPreview -match 'No files changed') 'A schema-8 development-state migration must remain plan-first.'
    & $upgradeScript -CodexHome $mixedHome -ConfigPath $mixedConfig -StateRoot $mixedState -MigrateLegacySettings -AcknowledgeDynamicUiReadScope -ConfirmUpgrade -NonInteractive | Out-Null
    $releasedState = Get-Content -LiteralPath $mixedStatePath -Raw | ConvertFrom-Json
    Assert-Routing ($releasedState.schemaVersion -eq 9 -and $releasedState.productVersion -eq '0.3.0') 'The unreleased 0.1.9 schema-8 state must migrate to the current release state.'

    Write-Output 'PASS: known config-derived selector fallbacks are absent from the dual named-profile route'
    Write-Output 'PASS: static verification requires the authoritative dual named-profile runtime shape'
    Write-Output 'PASS: top-level routing ignores nested profile and array-table keys'
    Write-Output 'PASS: static assessment rejects the exact Custom-deny to Full-Access merge trigger'
    Write-Output 'PASS: DynamicUi PlanOnly discloses missing CLI while apply remains blocked'
    Write-Output 'PASS: unreleased schema-8 DynamicUi state migrates to the release schema 9'
    Write-Output 'NOTE: same-task runtime switching is verified separately by Test-DesktopPermissionE2E.ps1 using real turns and an outside-workspace canary'
}
finally {
    if ($appProcess) {
        try {
            if (-not $appProcess.HasExited) {
                try { $appProcess.StandardInput.Close() } catch {}
                if (-not $appProcess.WaitForExit(10000)) {
                    $appProcess.Kill($true)
                    $appProcess.WaitForExit(5000) | Out-Null
                }
            }
        }
        catch {}
        $appProcess.Dispose()
    }
    if (Test-Path -LiteralPath $temporaryRoot) {
        $resolvedTemporary = [IO.Path]::GetFullPath($temporaryRoot)
        $systemTemporary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolvedTemporary.StartsWith($systemTemporary, [StringComparison]::OrdinalIgnoreCase) -or $resolvedTemporary -eq $systemTemporary) {
            throw "Refusing to remove unexpected routing-test path: $resolvedTemporary"
        }
        Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force
    }
}
