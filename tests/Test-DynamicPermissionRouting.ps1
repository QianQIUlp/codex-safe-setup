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
$commonScript = Join-Path $scriptRoot 'Common.ps1'
. $commonScript

function Assert-Routing {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "DYNAMIC ROUTING ASSERTION FAILED: $Message" }
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

function Send-AppServerMessage {
    param(
        [Parameter(Mandatory)][Diagnostics.Process]$Process,
        [Parameter(Mandatory)]$Message
    )

    $json = $Message | ConvertTo-Json -Depth 30 -Compress
    $Process.StandardInput.WriteLine($json)
    $Process.StandardInput.Flush()
}

function Invoke-AppServerRequest {
    param(
        [Parameter(Mandatory)][Diagnostics.Process]$Process,
        [Parameter(Mandatory)][int]$Id,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)]$Params
    )

    Send-AppServerMessage -Process $Process -Message ([ordered]@{ method = $Method; id = $Id; params = $Params })
    $messages = [Collections.Generic.List[object]]::new()
    while ($true) {
        $message = Read-AppServerMessage -Process $Process
        if ($message.PSObject.Properties['id'] -and [int]$message.id -eq $Id) {
            if ($message.PSObject.Properties['error']) {
                throw "Codex app-server request '$Method' failed: $($message.error | ConvertTo-Json -Depth 10 -Compress)"
            }
            return [pscustomobject]@{ Response = $message; Messages = @($messages) }
        }
        $messages.Add($message)
    }
}

function Get-SettingsNotification {
    param(
        [Parameter(Mandatory)][Diagnostics.Process]$Process,
        [object[]]$BufferedMessages = @()
    )

    $notification = @($BufferedMessages | Where-Object { $_.PSObject.Properties['method'] -and $_.method -eq 'thread/settings/updated' } | Select-Object -Last 1)
    if ($notification.Count -gt 0) { return $notification[0] }

    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        $message = Read-AppServerMessage -Process $Process
        if ($message.PSObject.Properties['method'] -and $message.method -eq 'thread/settings/updated') {
            return $message
        }
    }
    throw 'Codex app-server did not emit thread/settings/updated.'
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('codex-safe-routing-' + [guid]::NewGuid().ToString('N'))
$appProcess = $null
try {
    $dynamicHome = Join-Path $temporaryRoot 'dynamic-home'
    $dynamicState = Join-Path $dynamicHome 'safe-setup'
    $dynamicConfig = Join-Path $dynamicHome 'config.toml'
    $workspace = Join-Path $temporaryRoot 'workspace'
    New-Item -ItemType Directory -Path $dynamicHome, $workspace -Force | Out-Null
    [IO.File]::WriteAllText($dynamicConfig, "model = `"gpt-5.5`"$([Environment]::NewLine)", [Text.UTF8Encoding]::new($false))

    & $installScript -PermissionRouting DynamicUi -NetworkMode Off -WindowsSandbox Keep -CodexHome $dynamicHome -ConfigPath $dynamicConfig -StateRoot $dynamicState -AcknowledgeDynamicUiReadScope -ConfirmApply -NonInteractive | Out-Null
    $dynamicText = [IO.File]::ReadAllText($dynamicConfig)
    Assert-Routing ($dynamicText -match '(?m)^\s*sandbox_mode\s*=\s*"workspace-write"') 'DynamicUi must install a workspace fallback when no UI sandbox setting exists.'
    Assert-Routing ($dynamicText -notmatch '(?m)^\s*default_permissions\s*=') 'DynamicUi must not pin default_permissions.'
    Assert-Routing ($dynamicText -notmatch '(?m)^\s*\[permissions\.codex-safe-workspace(?:\.|\])') 'DynamicUi must remove the named profile that pins Desktop routing.'
    Assert-Routing ($dynamicText -match '(?ms)\[sandbox_workspace_write\].*network_access\s*=\s*false') 'DynamicUi Off mode must keep fallback command networking disabled.'
    $dynamicInstallState = Get-Content -LiteralPath (Join-Path $dynamicState 'install-state.json') -Raw | ConvertFrom-Json
    Assert-Routing ($dynamicInstallState.schemaVersion -eq 5 -and $dynamicInstallState.productVersion -eq '0.1.6') 'DynamicUi install state must be version 0.1.6 schema 5.'
    Assert-Routing ($dynamicInstallState.PermissionRouting -eq 'DynamicUi') 'DynamicUi install state must record its routing mode.'
    $dynamicVerification = (& $testScript -CodexHome $dynamicHome -ConfigPath $dynamicConfig -StateRoot $dynamicState -SkipCliRuleCheck -AsJson) | ConvertFrom-Json
    Assert-Routing ($dynamicVerification.Overall -ne 'FAILED') 'DynamicUi static verification must not fail.'
    $dynamicCheck = @($dynamicVerification.Checks | Where-Object Control -eq 'Dynamic UI routing')
    Assert-Routing ($dynamicCheck.Count -eq 1 -and $dynamicCheck[0].Status -eq 'PASS') 'DynamicUi verifier must confirm the unpinned legacy route.'

    $mixedHome = Join-Path $temporaryRoot 'mixed-home'
    $mixedState = Join-Path $mixedHome 'safe-setup'
    $mixedConfig = Join-Path $mixedHome 'config.toml'
    New-Item -ItemType Directory -Path $mixedHome -Force | Out-Null
    [IO.File]::WriteAllText($mixedConfig, "model = `"gpt-5.5`"$([Environment]::NewLine)", [Text.UTF8Encoding]::new($false))
    & $installScript -PermissionRouting StrictProfile -NetworkMode Off -WindowsSandbox Keep -CodexHome $mixedHome -ConfigPath $mixedConfig -StateRoot $mixedState -ConfirmApply -NonInteractive | Out-Null

    $mixedText = [IO.File]::ReadAllText($mixedConfig)
    $mixedText = Remove-CssTomlTopLevelKeys -Text $mixedText -Keys @('default_permissions')
    $mixedText = Set-CssTomlTopLevelValue -Text $mixedText -Key 'sandbox_mode' -Literal '"danger-full-access"'
    [IO.File]::WriteAllText($mixedConfig, $mixedText, [Text.UTF8Encoding]::new($false))
    $mixedStatePath = Join-Path $mixedState 'install-state.json'
    $oldState = Get-Content -LiteralPath $mixedStatePath -Raw | ConvertFrom-Json
    $oldState.schemaVersion = 4
    $oldState.productVersion = '0.1.5'
    $oldState.PSObject.Properties.Remove('PermissionRouting')
    [IO.File]::WriteAllText($mixedStatePath, ($oldState | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))

    $beforePreview = [IO.File]::ReadAllText($mixedConfig)
    $preview = @(& $upgradeScript -CodexHome $mixedHome -ConfigPath $mixedConfig -StateRoot $mixedState -PlanOnly) -join [Environment]::NewLine
    Assert-Routing ($preview -match 'PermissionRouting\s*:\s*DynamicUi') 'A 0.1.5 upgrade must select DynamicUi routing by default.'
    Assert-Routing ($preview -match 'No files changed') 'DynamicUi upgrade preview must be non-mutating.'
    Assert-Routing ([IO.File]::ReadAllText($mixedConfig) -eq $beforePreview) 'DynamicUi preview must preserve the mixed reproduction byte-for-byte.'

    & $upgradeScript -CodexHome $mixedHome -ConfigPath $mixedConfig -StateRoot $mixedState -AcknowledgeDynamicUiReadScope -ConfirmUpgrade -NonInteractive | Out-Null
    $repairedText = [IO.File]::ReadAllText($mixedConfig)
    Assert-Routing ($repairedText -match '(?m)^\s*sandbox_mode\s*=\s*"danger-full-access"') 'Upgrade must preserve the UI-selected sandbox fallback.'
    Assert-Routing ($repairedText -notmatch '(?m)^\s*default_permissions\s*=') 'Upgrade must remove the default permission pin.'
    Assert-Routing ($repairedText -notmatch '(?m)^\s*\[permissions\.codex-safe-workspace(?:\.|\])') 'Upgrade must remove the stale named profile.'
    $repairedState = Get-Content -LiteralPath $mixedStatePath -Raw | ConvertFrom-Json
    Assert-Routing ($repairedState.schemaVersion -eq 5 -and $repairedState.productVersion -eq '0.1.6' -and $repairedState.PermissionRouting -eq 'DynamicUi') 'Upgrade must record repaired 0.1.6 DynamicUi state.'

    $codexCommand = Get-Command codex.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $codexCommand) { $codexCommand = Get-Command codex -ErrorAction Stop | Select-Object -First 1 }
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
    Assert-Routing ($appProcess.Start()) 'Codex app-server process must start.'

    [void](Invoke-AppServerRequest -Process $appProcess -Id 1 -Method 'initialize' -Params ([ordered]@{
        clientInfo = [ordered]@{ name = 'codex-safe-setup-tests'; title = 'Codex Safe Setup Tests'; version = '0.1.6' }
        capabilities = [ordered]@{ experimentalApi = $true }
    }))
    Send-AppServerMessage -Process $appProcess -Message ([ordered]@{ method = 'initialized'; params = @{} })

    $threadStart = Invoke-AppServerRequest -Process $appProcess -Id 2 -Method 'thread/start' -Params ([ordered]@{
        cwd = $workspace
        ephemeral = $true
        approvalPolicy = 'never'
    })
    $threadId = [string]$threadStart.Response.result.thread.id
    Assert-Routing (-not [string]::IsNullOrWhiteSpace($threadId)) 'App-server must create an ephemeral test thread.'

    $fullAccessUpdate = Invoke-AppServerRequest -Process $appProcess -Id 3 -Method 'thread/settings/update' -Params ([ordered]@{
        threadId = $threadId
        approvalPolicy = 'never'
        sandboxPolicy = [ordered]@{ type = 'dangerFullAccess' }
    })
    $fullAccessNotification = Get-SettingsNotification -Process $appProcess -BufferedMessages $fullAccessUpdate.Messages
    Assert-Routing ($fullAccessNotification.params.threadId -eq $threadId) 'Full Access update must target the same thread.'
    Assert-Routing ($fullAccessNotification.params.threadSettings.sandboxPolicy.type -eq 'dangerFullAccess') 'Full Access must become the effective next-turn sandbox in the same thread.'

    $workspaceUpdate = Invoke-AppServerRequest -Process $appProcess -Id 4 -Method 'thread/settings/update' -Params ([ordered]@{
        threadId = $threadId
        approvalPolicy = 'never'
        sandboxPolicy = [ordered]@{
            type = 'workspaceWrite'
            writableRoots = @($workspace)
            networkAccess = $false
            excludeTmpdirEnvVar = $true
            excludeSlashTmp = $true
        }
    })
    $workspaceNotification = Get-SettingsNotification -Process $appProcess -BufferedMessages $workspaceUpdate.Messages
    Assert-Routing ($workspaceNotification.params.threadSettings.sandboxPolicy.type -eq 'workspaceWrite') 'Switching back must update the next-turn sandbox in the same thread.'
    Assert-Routing (-not $workspaceNotification.params.threadSettings.sandboxPolicy.networkAccess) 'Switching back must restore the offline workspace fallback.'

    Write-Output 'PASS: v0.1.5 mixed-profile reproduction migrates to unpinned DynamicUi routing'
    Write-Output 'PASS: app-server applies Full Access and Workspace changes to subsequent turns in one thread'
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
