#requires -Version 5.1
<#
.SYNOPSIS
  Plan and install the OS-level ZCode cage (see references/os-boundary-model.md).
.DESCRIPTION
  Consent-driven, reversible installation of hard boundaries:
    1. a dedicated standard (non-admin) local Windows user
    2. a copy of the ZCode install under an admin-controlled path (Program Files)
       with an RX ACE for the sandbox user - REQUIRED on machines with path-based
       execution control, and correct hygiene everywhere
    3. Modify ACEs for the sandbox user on authorized workspace roots only
    4. deny ACEs on existing secret-looking files inside those roots
    5. a DPAPI-protected launcher credential + Start Menu shortcut
    6. an install-state.json that records every change for exact rollback
  The apply phase self-elevates once (UAC) because user creation and the
  Program Files copy require an administrator token.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$WorkspacePath,
    [string]$SandboxUserName = 'ZCode-Sandbox',
    [string]$ZCodeSourceDir = "$env:LOCALAPPDATA\Programs\ZCode",
    [string]$SandboxInstallDir = 'C:\Program Files\ZCodeSandbox',
    [bool]$ProtectSecrets = $true,
    [switch]$InstallCheckpoints,
    [string]$ZcodeHome,
    [string]$StateRoot,
    [switch]$AcknowledgeAdminSetup,
    [switch]$PlanOnly,
    [switch]$ConfirmApply,
    [switch]$NonInteractive,
    [switch]$ElevatedChild   # internal: set by the self-elevation relaunch
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') { throw 'The ZCode cage is Windows-only.' }
if ($SandboxUserName -notmatch '^[A-Za-z][A-Za-z0-9_.-]{0,19}$') { throw "Invalid sandbox account name '$SandboxUserName'." }
if (Get-LocalUser -Name $SandboxUserName -ErrorAction SilentlyContinue) {
    throw "Local user '$SandboxUserName' already exists. Run Rollback-ZcodeSafety.ps1 first if it belongs to a previous cage."
}

$home2 = Get-ZssZcodeHome -Override $ZcodeHome
Assert-ZssNotFilesystemRoot -Path $home2 -Label 'ZcodeHome'
$stateRoot = Get-ZssStateRoot -ZcodeHome $home2 -Override $StateRoot
$expectedState = [IO.Path]::GetFullPath((Join-Path $home2 $script:ZssStateDirName))
$pathComparison = [StringComparison]::OrdinalIgnoreCase
if (-not [string]::Equals($stateRoot, $expectedState, $pathComparison)) {
    throw "StateRoot must resolve to the safe-setup directory directly under the ZCode home: $expectedState"
}

$installStatePath = Join-Path $stateRoot 'install-state.json'
if (Test-Path -LiteralPath $installStatePath -PathType Leaf) {
    throw "An installation is already recorded at $installStatePath. Roll it back before installing again."
}

$zcodeExe = Join-Path $ZCodeSourceDir 'ZCode.exe'
if (-not (Test-Path -LiteralPath $zcodeExe -PathType Leaf)) { throw "ZCode executable not found: $zcodeExe" }
$programFilesRoot = [Environment]::GetFolderPath('ProgramFiles')
$sandboxInstallFull = [IO.Path]::GetFullPath($SandboxInstallDir)
if (-not $sandboxInstallFull.StartsWith($programFilesRoot, $pathComparison)) {
    throw "SandboxInstallDir must live under an admin-controlled path ($programFilesRoot). Refusing '$sandboxInstallFull' - user-writable install locations break the execution boundary on hardened machines."
}
if (Test-Path -LiteralPath $sandboxInstallFull) {
    throw "SandboxInstallDir already exists: $sandboxInstallFull. Remove it or choose another -SandboxInstallDir."
}

$resolvedRoots = [Collections.Generic.List[string]]::new()
foreach ($path in $WorkspacePath) {
    $resolvedRoots.Add((Get-ZssRepositoryRoot -Path $path))
}
$workspaceRoots = @($resolvedRoots | Sort-Object -Unique)
foreach ($root in $workspaceRoots) {
    Assert-ZssNotFilesystemRoot -Path $root -Label 'WorkspacePath'
    $mainProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    if ($root.StartsWith($mainProfile, $pathComparison) -and -not $root.StartsWith((Join-Path $mainProfile 'Desktop'), $pathComparison)) {
        Write-Warning "Workspace root is inside the main user profile: $root. Prefer roots like C:\Codes outside the profile."
    }
}

$secretFiles = @()
if ($ProtectSecrets) { $secretFiles = Find-ZssSecretFiles -Roots $workspaceRoots }

$gitExecutable = $null
$gitExecutableHash = $null
if ($InstallCheckpoints) {
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $gitCommand) { throw 'Git is required for checkpoints.' }
    $gitExecutable = [IO.Path]::GetFullPath($gitCommand.Source)
    $gitExecutableHash = (Get-FileHash -LiteralPath $gitExecutable -Algorithm SHA256).Hash
}

$shortcutPath = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)) 'ZCode (Sandboxed).lnk'
$binRoot = Join-Path $stateRoot 'bin'
$credentialPath = Join-Path $binRoot 'sandbox-credential.dpapi'
$canaryPath = Join-Path $stateRoot 'outside-workspace-canary.txt'
$authorizedPath = Join-Path $stateRoot 'authorized-workspaces.json'

$networkDisclosure = @(
    'The OS cage does not filter network traffic. Windows Firewall cannot scope rules by user for the same executable path, so WebFetch, WebSearch, MCP servers, and command-line tools inside the cage can reach any destination.'
    'Any data the sandbox user can read - workspace files, command output, and secret-like files not covered by deny ACEs - could be sent to any public Internet destination by a mistake or a prompt injection.'
    'This does not mean a leak will happen automatically; it means the consequence ceiling is high. Keep real secrets out of granted roots, and prefer reviewing what gets committed or transmitted.'
    'This is reported as NOT CONTROLLED in verification and must never be described as a boundary.'
) -join ' '

$plan = [pscustomobject]@{
    SandboxUserName = $SandboxUserName
    SandboxUserKind = 'standard local user, random 32-char password, DPAPI(CurrentUser)-protected at ' + $credentialPath
    ZCodeSourceDir = (Resolve-Path -LiteralPath $ZCodeSourceDir).Path
    SandboxInstallDir = $sandboxInstallFull
    SandboxInstallAccess = 'RX ACE for the sandbox user (recursive); required for hardened machines and correct hygiene everywhere'
    WorkspaceRoots = $workspaceRoots
    WorkspaceAccess = 'Modify ACE for the sandbox user on each root (recursive); nothing else is granted'
    ProtectSecrets = $ProtectSecrets
    SecretFilesDenied = $secretFiles
    Canary = $canaryPath
    Launcher = (Join-Path $binRoot 'Start-ZcodeSandboxed.ps1')
    Shortcut = $shortcutPath
    Checkpoints = if ($InstallCheckpoints) { "bridge installed; Git pinned to $gitExecutable (SHA256 $gitExecutableHash)" } else { 'Not requested' }
    StateRoot = $stateRoot
    RollbackCommand = "& '$PSScriptRoot\Rollback-ZcodeSafety.ps1'"
    Elevation = 'one UAC prompt (local user creation + Program Files copy require an administrator token)'
    NetworkRisk = $networkDisclosure
    NotControlled = 'network egress; secret files created after install; the sandbox user''s own credentials are readable by the main user'
}

Write-Output 'ZCode Safe Setup - OS cage change plan'
$plan | Format-List | Out-String | Write-Output
if ($PlanOnly) { Write-Output 'No changes made (PlanOnly).'; return }

if (-not $AcknowledgeAdminSetup) {
    if ($NonInteractive) { throw 'Apply requires -AcknowledgeAdminSetup (one UAC prompt for user creation and the Program Files copy).' }
    $adminAnswer = Read-Host 'The apply phase needs one administrator-approved prompt (UAC) to create the sandbox account and copy ZCode into Program Files. Continue? [y/N]'
    if ($adminAnswer -notmatch '^(?i:y|yes)$') { throw 'Installation cancelled.' }
}
if (-not $ConfirmApply) {
    if ($NonInteractive) { throw 'Non-interactive application requires -ConfirmApply.' }
    $applyAnswer = Read-Host 'Apply this exact plan? [y/N]'
    if ($applyAnswer -notmatch '^(?i:y|yes)$') { throw 'Installation cancelled.' }
}

# ---- self-elevate once, preserving every argument ----
if (-not (Test-ZssIsAdmin)) {
    $relayArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-ElevatedChild')
    foreach ($root in $WorkspacePath) { $relayArgs += @('-WorkspacePath', $root) }
    $relayArgs += @('-SandboxUserName', $SandboxUserName, '-ZCodeSourceDir', $ZCodeSourceDir, '-SandboxInstallDir', $sandboxInstallFull)
    if ($ProtectSecrets) { $relayArgs += @('-ProtectSecrets', '$true') }
    if ($InstallCheckpoints) { $relayArgs += '-InstallCheckpoints' }
    if ($ZcodeHome) { $relayArgs += @('-ZcodeHome', $home2) }
    $relayArgs += @('-AcknowledgeAdminSetup', '-ConfirmApply', '-NonInteractive')
    Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList $relayArgs
    if (Test-Path -LiteralPath $installStatePath -PathType Leaf) {
        Write-Output 'Elevated apply completed. Run Test-ZcodeSafety.ps1 to verify the boundaries.'
        return
    }
    throw 'Elevated apply did not complete (UAC declined or apply failed). No install-state.json was written; re-run to retry.'
}

# ================= elevated apply =================
$completed = [Collections.Generic.List[string]]::new()
try {
    # 1. sandbox account
    $password = New-ZssRandomPassword
    New-LocalUser -Name $SandboxUserName -Password (ConvertTo-SecureString $password -AsPlainText -Force) `
        -FullName 'ZCode Sandbox' -Description 'ZCode OS cage - do not delete manually' `
        -AccountNeverExpires -PasswordNeverExpires | Out-Null
    $completed.Add("user:$SandboxUserName")

    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $binRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $stateRoot 'backups') -Force | Out-Null

    # 2. credential blob BEFORE anything depends on it (same user, elevated: DPAPI CurrentUser still resolves to the profile master key)
    Protect-ZssSecret -PlainText $password -Path $credentialPath
    $completed.Add("credential:$credentialPath")

    # 3. Program Files copy + RX
    New-Item -ItemType Directory -Path $sandboxInstallFull -Force | Out-Null
    robocopy $ZCodeSourceDir $sandboxInstallFull /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null
    if ($LASTEXITCODE -gt 7) { throw "robocopy failed with exit code $LASTEXITCODE." }
    icacls $sandboxInstallFull /grant "${SandboxUserName}:(OI)(CI)RX" | Out-Null
    $completed.Add("installdir:$sandboxInstallFull")

    # 4. workspace grants
    foreach ($root in $workspaceRoots) {
        icacls $root /grant "${SandboxUserName}:(OI)(CI)M" | Out-Null
        $completed.Add("rootgrant:$root")
    }

    # 5. secret deny ACEs
    foreach ($secret in $secretFiles) {
        icacls $secret /deny "${SandboxUserName}:R" | Out-Null
        $completed.Add("secretdeny:$secret")
    }

    # 6. canary
    Write-ZssTextAtomic -Path $canaryPath -Text ("Synthetic canary only: {0}" -f [guid]::NewGuid().ToString('N'))
    $completed.Add("canary:$canaryPath")

    # 7. launcher + bridge
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Start-ZcodeSandboxed.ps1') -Destination (Join-Path $binRoot 'Start-ZcodeSandboxed.ps1') -Force
    $completed.Add("launcher:$(Join-Path $binRoot 'Start-ZcodeSandboxed.ps1')")
    if ($InstallCheckpoints) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'New-ZcodeCheckpoint.ps1') -Destination (Join-Path $binRoot 'New-ZcodeCheckpoint.ps1') -Force
        $completed.Add("bridge:$(Join-Path $binRoot 'New-ZcodeCheckpoint.ps1')")
    }

    # 8. authorized workspaces registry
    if ($InstallCheckpoints) {
        $registry = [pscustomobject]@{
            schemaVersion = 1
            gitExecutable = $gitExecutable
            gitExecutableSha256 = $gitExecutableHash
            roots = $workspaceRoots
        }
        Write-ZssTextAtomic -Path $authorizedPath -Text ($registry | ConvertTo-Json -Depth 3)
        $completed.Add("authorized:$authorizedPath")
    }

    # 9. Start Menu shortcut
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$binRoot\Start-ZcodeSandboxed.ps1`""
    $shortcut.WorkingDirectory = $env:PUBLIC
    $shortcut.Description = 'Launch ZCode inside the OS sandbox cage'
    $shortcut.Save()
    $completed.Add("shortcut:$shortcutPath")

    # 10. install state
    $state = [pscustomobject]@{
        SchemaVersion = 1
        InstalledAtUtc = [DateTime]::UtcNow.ToString('o')
        SandboxUserName = $SandboxUserName
        ZCodeSourceDir = (Resolve-Path -LiteralPath $ZCodeSourceDir).Path
        SandboxInstallDir = $sandboxInstallFull
        WorkspaceRoots = $workspaceRoots
        SecretFilesDenied = $secretFiles
        CanaryPath = $canaryPath
        CredentialPath = $credentialPath
        LauncherPath = (Join-Path $binRoot 'Start-ZcodeSandboxed.ps1')
        BridgePath = if ($InstallCheckpoints) { Join-Path $binRoot 'New-ZcodeCheckpoint.ps1' } else { $null }
        AuthorizedWorkspacesPath = if ($InstallCheckpoints) { $authorizedPath } else { $null }
        ShortcutPath = $shortcutPath
        StateRoot = $stateRoot
        CompletedSteps = @($completed)
    }
    Write-ZssTextAtomic -Path $installStatePath -Text ($state | ConvertTo-Json -Depth 5)
}
catch {
    Write-Warning "Apply failed: $($_.Exception.Message)"
    Write-Warning 'Undoing completed steps...'
    foreach ($entry in $completed) {
        $kind, $value = $entry -split ':', 2
        switch ($kind) {
            'rootgrant'  { icacls $value /remove:g $SandboxUserName 2>$null | Out-Null }
            'secretdeny' { icacls $value /remove:d $SandboxUserName 2>$null | Out-Null }
            'installdir' { Remove-Item -LiteralPath $value -Recurse -Force -ErrorAction SilentlyContinue }
            'shortcut'   { Remove-Item -LiteralPath $value -Force -ErrorAction SilentlyContinue }
            default      { }
        }
    }
    foreach ($entry in $completed) {
        if ($entry -like 'authorized:*' -or $entry -like 'bridge:*' -or $entry -like 'launcher:*' -or $entry -like 'credential:*' -or $entry -like 'canary:*') {
            $value = $entry -split ':', 2 | Select-Object -Last 1
            Remove-Item -LiteralPath $value -Force -ErrorAction SilentlyContinue
        }
    }
    Get-CimInstance Win32_UserProfile | Where-Object { $_.LocalPath -like "*\$SandboxUserName" } | Remove-CimInstance -ErrorAction SilentlyContinue
    Remove-LocalUser -Name $SandboxUserName -ErrorAction SilentlyContinue
    throw
}

[pscustomobject]@{
    Status = 'INSTALLED_ACTIVATION_REQUIRED'
    StateRoot = $stateRoot
    Shortcut = $shortcutPath
    Activation = 'Launch ZCode through the new shortcut (or the launcher script), log in once inside that window, and work only in that instance. Sessions in the main-user ZCode are NOT protected by the cage.'
    Verification = 'Run Test-ZcodeSafety.ps1, then start using the sandboxed instance.'
}
