#requires -Version 7.0
# SYNTHETIC UNIT TEST ONLY.
# This test feeds fabricated rollout JSONL to the verifier. Passing it does not
# prove that Codex Desktop changed permissions, stayed in one real task, or ran
# any real unified-exec command.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-SyntheticUnit {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "SYNTHETIC UNIT ASSERTION FAILED: $Message" }
}

function ConvertTo-SingleQuotedPowerShellLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Get-SyntheticProbeCommand {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Marker
    )

    $pathLiteral = ConvertTo-SingleQuotedPowerShellLiteral $Path
    $markerLiteral = ConvertTo-SingleQuotedPowerShellLiteral $Marker
    return "`$ErrorActionPreference='Stop'; [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($pathLiteral)) | Out-Null; [IO.File]::WriteAllText($pathLiteral,$markerLiteral,[Text.UTF8Encoding]::new(`$false)); [IO.File]::ReadAllText($pathLiteral)"
}

function New-PathDenyEntry {
    param([Parameter(Mandatory)][string]$Path)
    return [ordered]@{
        access = 'deny'
        path = [ordered]@{ type = 'path'; path = $Path }
    }
}

function New-WriteEntry {
    param([Parameter(Mandatory)][string]$Path)
    return [ordered]@{
        access = 'write'
        path = [ordered]@{ type = 'path'; path = $Path }
    }
}

function New-RootDenyEntry {
    return [ordered]@{
        access = 'deny'
        path = [ordered]@{
            type = 'special'
            value = [ordered]@{ kind = 'root' }
        }
    }
}

function Add-JsonLine {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory)][object]$Record
    )
    $Lines.Add(($Record | ConvertTo-Json -Compress -Depth 30))
}

function New-SyntheticRolloutFixture {
    param(
        [Parameter(Mandatory)][string]$FixtureRoot,
        [Parameter(Mandatory)][ValidateSet('Valid', 'MarkerPathOnlyCommand', 'NewSessionMeta', 'CustomDeny', 'WorkspaceDeny')]
        [string]$Mutation
    )

    $runId = 'syntheticunit' + ([guid]::NewGuid().ToString('N').Substring(0, 16))
    $codexHome = Join-Path $FixtureRoot 'codex-home'
    $sessionsRoot = Join-Path $codexHome 'sessions'
    $workspaceRoot = Join-Path $FixtureRoot 'workspace'
    $canaryRoot = Join-Path $FixtureRoot 'outside-canary'
    New-Item -ItemType Directory -Path $sessionsRoot, $workspaceRoot, $canaryRoot -Force | Out-Null

    $sessionId = 'desktop-' + ([guid]::NewGuid().ToString('N'))
    $rolloutPath = Join-Path $sessionsRoot "rollout-$sessionId.jsonl"
    $definitions = @(
        [pscustomobject]@{ Name = 'custom-before'; Mode = 'Custom'; Profile = 'codex-safe-workspace' },
        [pscustomobject]@{ Name = 'full-access'; Mode = 'Full'; Profile = ':danger-full-access' },
        [pscustomobject]@{ Name = 'workspace-after'; Mode = 'Workspace'; Profile = ':workspace' }
    )
    $probes = @(
        foreach ($definition in $definitions) {
            [pscustomobject]@{
                Name = $definition.Name
                Mode = $definition.Mode
                Profile = $definition.Profile
                Marker = "CSS-E2E|$runId|$($definition.Name)"
                Path = Join-Path $canaryRoot "$($definition.Name)-$runId.txt"
            }
        }
    )

    # The verifier requires physical proof for Full Access and absence for both
    # restricted probes. This is fabricated fixture state, not a tool execution.
    [IO.File]::WriteAllText($probes[1].Path, $probes[1].Marker, [Text.UTF8Encoding]::new($false))

    $lines = [Collections.Generic.List[string]]::new()
    Add-JsonLine $lines ([ordered]@{
        type = 'session_meta'
        payload = [ordered]@{ originator = 'Codex Desktop'; session_id = $sessionId }
    })

    for ($index = 0; $index -lt $probes.Count; $index++) {
        $probe = $probes[$index]
        $turnId = "synthetic-turn-$($index + 1)"
        $baseOrdinal = 10 + ($index * 40)
        Add-JsonLine $lines ([ordered]@{
            type = 'event_msg'
            ordinal = $baseOrdinal
            payload = [ordered]@{
                type = 'thread_settings_applied'
                thread_settings = [ordered]@{
                    permission_profile = $(if ($probe.Mode -eq 'Full') { [ordered]@{ type = 'disabled' } } else { [ordered]@{ type = 'managed' } })
                }
            }
        })
        if ($null -ne $probe.Profile) {
            $settingsRecord = $lines[$lines.Count - 1] | ConvertFrom-Json -Depth 30
            $settingsRecord.payload.thread_settings | Add-Member -NotePropertyName active_permission_profile -NotePropertyValue ([pscustomobject]@{ id = $probe.Profile })
            $lines[$lines.Count - 1] = $settingsRecord | ConvertTo-Json -Compress -Depth 30
        }

        $sandboxPolicy = if ($probe.Mode -eq 'Full') {
            [ordered]@{ type = 'danger-full-access' }
        }
        else {
            [ordered]@{ type = 'workspace-write'; writable_roots = @($workspaceRoot) }
        }
        $permissionProfile = if ($probe.Mode -eq 'Full') {
            [ordered]@{
                type = 'disabled'
                file_system = [ordered]@{ type = 'unrestricted'; entries = @((New-WriteEntry -Path $workspaceRoot)) }
            }
        }
        else {
            $entries = @((New-WriteEntry -Path $workspaceRoot))
            if ($probe.Mode -eq 'Custom' -and $Mutation -eq 'CustomDeny') {
                $entries = @((New-WriteEntry -Path $workspaceRoot), (New-RootDenyEntry))
            }
            if ($probe.Mode -eq 'Workspace' -and $Mutation -eq 'WorkspaceDeny') {
                $entries = @(
                    (New-WriteEntry -Path $workspaceRoot)
                    (New-PathDenyEntry -Path (Join-Path $workspaceRoot '.synthetic-deny'))
                )
            }
            [ordered]@{
                type = 'managed'
                file_system = [ordered]@{ type = 'restricted'; entries = $entries }
            }
        }
        $runtimeFileSystem = if ($probe.Mode -eq 'Full') {
            $null
        }
        else {
            $runtimeEntries = @((New-WriteEntry -Path $workspaceRoot))
            if ($probe.Mode -eq 'Custom' -and $Mutation -eq 'CustomDeny') {
                $runtimeEntries = @((New-WriteEntry -Path $workspaceRoot), (New-RootDenyEntry))
            }
            [ordered]@{ type = 'restricted'; entries = $runtimeEntries }
        }

        $contextPayload = [ordered]@{
            turn_id = $turnId
            cwd = $workspaceRoot
            workspace_roots = @($workspaceRoot)
            sandbox_policy = $sandboxPolicy
            permission_profile = $permissionProfile
        }
        if ($null -ne $runtimeFileSystem) {
            $contextPayload.file_system_sandbox_policy = $runtimeFileSystem
        }
        Add-JsonLine $lines ([ordered]@{
            type = 'turn_context'
            ordinal = $baseOrdinal + 10
            payload = $contextPayload
        })

        $exactCommand = Get-SyntheticProbeCommand -Path $probe.Path -Marker $probe.Marker
        $command = @('pwsh', '-NoProfile', '-Command', $exactCommand)
        if ($Mutation -eq 'MarkerPathOnlyCommand' -and $probe.Mode -eq 'Custom') {
            $command = @('pwsh', '-NoProfile', '-Command', "Write-Output '$($probe.Marker)'; Write-Output '$($probe.Path)'")
        }
        $commandItem = [ordered]@{
            type = 'CommandExecution'
            source = 'unified_exec_startup'
            command = $command
            status = if ($probe.Mode -eq 'Full') { 'completed' } else { 'failed' }
            exit_code = if ($probe.Mode -eq 'Full') { 0 } else { 1 }
            stdout = if ($probe.Mode -eq 'Full') { $probe.Marker } else { '' }
        }
        Add-JsonLine $lines ([ordered]@{
            type = 'event_msg'
            ordinal = $baseOrdinal + 20
            payload = [ordered]@{
                type = 'item_completed'
                turn_id = $turnId
                item = $commandItem
            }
        })
        Add-JsonLine $lines ([ordered]@{
            type = 'event_msg'
            ordinal = $baseOrdinal + 30
            payload = [ordered]@{ type = 'task_complete'; turn_id = $turnId }
        })

        if ($Mutation -eq 'NewSessionMeta' -and $probe.Mode -eq 'Full') {
            Add-JsonLine $lines ([ordered]@{
                type = 'session_meta'
                payload = [ordered]@{ originator = 'Codex Desktop'; session_id = ('restarted-' + [guid]::NewGuid().ToString('N')) }
            })
        }
    }

    [IO.File]::WriteAllLines($rolloutPath, $lines, [Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{
        RolloutPath = $rolloutPath
        RunId = $runId
        CanaryRoot = $canaryRoot
        CodexHome = $codexHome
    }
}

function Invoke-SyntheticVerifierCase {
    param(
        [Parameter(Mandatory)][string]$VerifierPath,
        [Parameter(Mandatory)][object]$Fixture
    )

    try {
        $output = @(& $VerifierPath -RolloutPath $Fixture.RolloutPath -RunId $Fixture.RunId -CanaryRoot $Fixture.CanaryRoot -CodexHome $Fixture.CodexHome -VisualStabilityConfirmed 2>&1)
        return [pscustomobject]@{ Passed = $true; Text = ($output -join [Environment]::NewLine) }
    }
    catch {
        return [pscustomobject]@{ Passed = $false; Text = $_.Exception.Message }
    }
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$verifierPath = Join-Path $repositoryRoot 'skills\codex-safe-setup\scripts\Test-DesktopPermissionE2E.ps1'
Assert-SyntheticUnit (Test-Path -LiteralPath $verifierPath -PathType Leaf) "Canonical verifier not found: $verifierPath"
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('codex-safe-setup-e2e-verifier-unit-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

Write-Output 'SYNTHETIC UNIT ONLY: fabricated rollout fixtures exercise verifier parsing and refusal logic; this is not Codex Desktop E2E evidence.'
try {
    $validFixture = New-SyntheticRolloutFixture -FixtureRoot (Join-Path $temporaryRoot 'valid') -Mutation Valid
    $validResult = Invoke-SyntheticVerifierCase -VerifierPath $verifierPath -Fixture $validFixture
    Assert-SyntheticUnit $validResult.Passed "Valid synthetic rollout should parse and pass: $($validResult.Text)"
    Assert-SyntheticUnit ($validResult.Text -match 'PASS: Codex Desktop applied codex-safe-workspace -> Full Access -> built-in Workspace') 'Positive parser case did not reach the verifier success result.'

    $wrongCommandFixture = New-SyntheticRolloutFixture -FixtureRoot (Join-Path $temporaryRoot 'wrong-command') -Mutation MarkerPathOnlyCommand
    $wrongCommandResult = Invoke-SyntheticVerifierCase -VerifierPath $verifierPath -Fixture $wrongCommandFixture
    Assert-SyntheticUnit (-not $wrongCommandResult.Passed) 'A command containing only the marker and path must not pass.'
    Assert-SyntheticUnit ($wrongCommandResult.Text -match 'did not contain the exact generated PowerShell probe') "Wrong-command refusal was not specific: $($wrongCommandResult.Text)"

    $newSessionFixture = New-SyntheticRolloutFixture -FixtureRoot (Join-Path $temporaryRoot 'new-session') -Mutation NewSessionMeta
    $newSessionResult = Invoke-SyntheticVerifierCase -VerifierPath $verifierPath -Fixture $newSessionFixture
    Assert-SyntheticUnit (-not $newSessionResult.Passed) 'A new session_meta inside the probe window must not pass.'
    Assert-SyntheticUnit ($newSessionResult.Text -match 'new session_meta appeared during the probe window') "Session-restart refusal was not specific: $($newSessionResult.Text)"

    $customDenyFixture = New-SyntheticRolloutFixture -FixtureRoot (Join-Path $temporaryRoot 'custom-deny') -Mutation CustomDeny
    $customDenyResult = Invoke-SyntheticVerifierCase -VerifierPath $verifierPath -Fixture $customDenyFixture
    Assert-SyntheticUnit (-not $customDenyResult.Passed) 'DynamicUi Custom with an explicit deny must not pass.'
    Assert-SyntheticUnit ($customDenyResult.Text -match 'DynamicUi Custom contains a sticky deny entry') "Custom-deny refusal was not specific: $($customDenyResult.Text)"

    $workspaceDenyFixture = New-SyntheticRolloutFixture -FixtureRoot (Join-Path $temporaryRoot 'workspace-deny') -Mutation WorkspaceDeny
    $workspaceDenyResult = Invoke-SyntheticVerifierCase -VerifierPath $verifierPath -Fixture $workspaceDenyFixture
    Assert-SyntheticUnit (-not $workspaceDenyResult.Passed) 'Built-in Workspace with an arbitrary path deny must not pass.'
    Assert-SyntheticUnit ($workspaceDenyResult.Text -match 'contaminated by stale Custom deny entries') "Workspace-deny refusal was not specific: $($workspaceDenyResult.Text)"

    Write-Output 'PASS (SYNTHETIC UNIT): valid fabricated rollout parsing'
    Write-Output 'PASS (SYNTHETIC UNIT): marker/path-only wrong command rejected'
    Write-Output 'PASS (SYNTHETIC UNIT): new session_meta in probe window rejected'
    Write-Output 'PASS (SYNTHETIC UNIT): explicit DynamicUi Custom deny rejected'
    Write-Output 'PASS (SYNTHETIC UNIT): arbitrary built-in Workspace deny contamination rejected'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        $resolvedTemporary = [IO.Path]::GetFullPath($temporaryRoot)
        $systemTemporary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        Assert-SyntheticUnit ($resolvedTemporary.StartsWith($systemTemporary, [StringComparison]::OrdinalIgnoreCase) -and $resolvedTemporary -ne $systemTemporary) "Refusing to remove unexpected test path: $resolvedTemporary"
        Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force
    }
}
