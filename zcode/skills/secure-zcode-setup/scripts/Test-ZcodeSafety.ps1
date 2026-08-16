#requires -Version 5.1
<#
.SYNOPSIS
  Verify the installed OS cage: structural checks plus live boundary probes
  executed AS the sandbox user.
.DESCRIPTION
  Structural evidence is not runtime proof: the probe phase actually runs
  powershell.exe under the sandbox account and asserts that forbidden reads
  fail and allowed writes succeed. Anything that cannot be verified here is
  reported as PARTIAL or NOT CONTROLLED - never as PASS.
#>
[CmdletBinding()]
param(
    [string]$ZcodeHome,
    [string]$StateRoot
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$ErrorActionPreference = 'Stop'
$checks = [Collections.Generic.List[object]]::new()

$home2 = Get-ZssZcodeHome -Override $ZcodeHome
$stateRoot = Get-ZssStateRoot -ZcodeHome $home2 -Override $StateRoot
$installStatePath = Join-Path $stateRoot 'install-state.json'
if (-not (Test-Path -LiteralPath $installStatePath -PathType Leaf)) {
    throw "No installation recorded at $installStatePath. Run Install-ZcodeSafety.ps1 first."
}
$state = Get-Content -LiteralPath $installStatePath -Raw | ConvertFrom-Json
$userName = $state.SandboxUserName

# ---------- structural checks ----------
$sandboxUser = Get-LocalUser -Name $userName -ErrorAction SilentlyContinue
$checks.Add((New-ZssCheck -Status $(if ($sandboxUser -and $sandboxUser.Enabled) { 'PASS' } else { 'FAIL' }) `
    -Control 'Sandbox account exists (standard user)' `
    -Evidence $(if ($sandboxUser) { "name=$userName enabled=$($sandboxUser.Enabled)" } else { "missing: $userName" })))

$installDirOk = (Test-Path -LiteralPath $state.SandboxInstallDir -PathType Container) -and
    (Test-Path -LiteralPath (Join-Path $state.SandboxInstallDir 'ZCode.exe') -PathType Leaf)
$rxPresent = $installDirOk -and (Test-ZssIcaclsGrantPresent -Path $state.SandboxInstallDir -UserName $userName)
$checks.Add((New-ZssCheck -Status $(if ($rxPresent) { 'PASS' } else { 'FAIL' }) `
    -Control 'ZCode runs from an admin-controlled path with RX for the sandbox user' `
    -Evidence "$($state.SandboxInstallDir) exe=$installDirOk rxAce=$rxPresent"))

$grantsOk = $true
foreach ($root in @($state.WorkspaceRoots)) {
    if (-not (Test-ZssIcaclsGrantPresent -Path $root -UserName $userName)) { $grantsOk = $false }
}
$checks.Add((New-ZssCheck -Status $(if ($grantsOk) { 'PASS' } else { 'FAIL' }) `
    -Control 'Workspace roots granted (Modify)' -Evidence "roots=$(@($state.WorkspaceRoots) -join ', ') grants=$grantsOk"))

$deniedOk = $true
$deniedMissing = @()
foreach ($secret in @($state.SecretFilesDenied)) {
    if (-not (Test-ZssIcaclsGrantPresent -Path $secret -UserName $userName)) { $deniedOk = $false; $deniedMissing += $secret }
}
$checks.Add((New-ZssCheck -Status $(if ($deniedOk) { 'PASS' } else { 'PARTIAL' }) `
    -Control 'Secret files carry deny ACEs' `
    -Evidence $(if ($deniedOk) { "all $($state.SecretFilesDenied.Count) recorded files deny $userName" } else { "ACE missing on: $($deniedMissing -join ', ')" })))

$launcherOk = Test-Path -LiteralPath $state.LauncherPath -PathType Leaf
$shortcutOk = Test-Path -LiteralPath $state.ShortcutPath -PathType Leaf
$checks.Add((New-ZssCheck -Status $(if ($launcherOk -and $shortcutOk) { 'PASS' } else { 'PARTIAL' }) `
    -Control 'Launcher and shortcut present' -Evidence "launcher=$launcherOk shortcut=$shortcutOk"))

if ($state.BridgePath) {
    $bridgeOk = Test-Path -LiteralPath $state.BridgePath -PathType Leaf
    $registryOk = Test-Path -LiteralPath $state.AuthorizedWorkspacesPath -PathType Leaf
    $checks.Add((New-ZssCheck -Status $(if ($bridgeOk -and $registryOk) { 'PASS' } else { 'FAIL' }) `
        -Control 'Checkpoint bridge installed' -Evidence "bridge=$bridgeOk registry=$registryOk"))
}

# ---------- live boundary probes as the sandbox user ----------
$probeScratch = Join-Path $stateRoot 'probe-scratch'
New-Item -ItemType Directory -Path $probeScratch -Force | Out-Null
icacls $probeScratch /grant "${userName}:(OI)(CI)M" | Out-Null

$canaryLiteral = $state.CanaryPath
$mainProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
$rootsLiteral = (@($state.WorkspaceRoots) -join '|')
$probeScript = Join-Path $probeScratch 'boundary-probe.ps1'
$probeTemplate = @'
$r = @()
$r += "whoami=$(whoami)"
$r += "isAdmin=$([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"
function T($n,[scriptblock]$s){ try{ & $s | Out-Null; $script:r += "$n=ALLOWED" } catch { $script:r += "$n=DENIED" } }
T 'read-canary'        { Get-Content 'CANARY' -ErrorAction Stop }
T 'list-main-profile'  { Get-ChildItem 'MAINPROFILE' -ErrorAction Stop | Out-Null }
T 'read-cage-state'    { Get-ChildItem 'STATEROOT' -ErrorAction Stop | Out-Null }
T 'read-installdir-write' { 'x' | Set-Content 'INSTALLDIR\writetest.txt' -ErrorAction Stop }
T 'write-workspace-root' { 'x' | Set-Content 'FIRSTROOT\zss-writetest.txt' }
T 'write-windows'      { 'x' | Set-Content 'C:\Windows\zss-writetest.txt' -ErrorAction Stop }
T 'read-denied-secret' { Get-Content 'FIRSTSECRET' -ErrorAction Stop }
$r | Set-Content 'SCRATCH\probe-result.txt'
'@
$firstSecret = if (@($state.SecretFilesDenied).Count) { @($state.SecretFilesDenied)[0] } else { $canaryLiteral }
$probeText = $probeTemplate `
    -replace 'CANARY', $canaryLiteral.Replace('\', '\') `
    -replace 'MAINPROFILE', $mainProfile `
    -replace 'STATEROOT', $stateRoot `
    -replace 'INSTALLDIR', $state.SandboxInstallDir `
    -replace 'FIRSTROOT', (@($state.WorkspaceRoots)[0]) `
    -replace 'FIRSTSECRET', $firstSecret `
    -replace 'SCRATCH', $probeScratch
$probeText | Set-Content -LiteralPath $probeScript

try {
    $password = Unprotect-ZssSecret -Path $state.CredentialPath
    $cred = [pscredential]::new("$env:COMPUTERNAME\$userName", (ConvertTo-SecureString $password -AsPlainText -Force))
    $probe = @(Invoke-ZssAsSandboxUser -Credential $cred -ScriptPath $probeScript -WorkDir $probeScratch -ResultFileName 'probe-result.txt')
}
catch {
    $probe = @("probe-failed=$($_.Exception.Message)")
}

$map = @{}
foreach ($line in $probe) {
    $key, $value = $line -split '=', 2
    if ($key) { $map[$key] = $value }
}
function Assert-Probe([string]$Name, [string]$Expect, [string]$Control) {
    $actual = $map[$Name]
    if ($null -eq $actual) {
        $script:checks.Add((New-ZssCheck -Status 'PARTIAL' -Control $Control -Evidence 'probe produced no result for this item'))
    }
    elseif ($actual -eq $Expect) {
        $script:checks.Add((New-ZssCheck -Status 'PASS' -Control $Control -Evidence "$Name=$actual (expected $Expect)"))
    }
    else {
        $script:checks.Add((New-ZssCheck -Status 'FAIL' -Control $Control -Evidence "$Name=$actual (expected $Expect)"))
    }
}

if ($map.ContainsKey('isAdmin')) {
    $checks.Add((New-ZssCheck -Status $(if ($map['isAdmin'] -eq 'False') { 'PASS' } else { 'FAIL' }) `
        -Control 'Sandbox user is not an administrator' -Evidence "isAdmin=$($map['isAdmin'])"))
}
Assert-Probe 'read-canary' 'DENIED' 'Cannot read the main-profile canary'
Assert-Probe 'list-main-profile' 'DENIED' 'Cannot list the main user profile'
Assert-Probe 'read-cage-state' 'DENIED' 'Cannot read the cage state (boundary protects itself)'
Assert-Probe 'read-installdir-write' 'DENIED' 'Cannot write into the ZCode install directory'
Assert-Probe 'write-workspace-root' 'ALLOWED' 'Can write authorized workspace roots'
Assert-Probe 'write-windows' 'DENIED' 'Cannot write system directories'
if (@($state.SecretFilesDenied).Count) {
    Assert-Probe 'read-denied-secret' 'DENIED' 'Cannot read deny-ACE secret file'
}

# ---------- honest NOT CONTROLLED ----------
$checks.Add((New-ZssCheck -Status 'NOT CONTROLLED' -Control 'Network egress' `
    -Evidence 'Windows Firewall cannot scope by user for one exe path; WebFetch/WebSearch/MCP/curl are unfiltered for the sandbox user'))
$checks.Add((New-ZssCheck -Status 'NOT CONTROLLED' -Control 'Secrets created after install' `
    -Evidence 'deny ACEs cover files recorded at install time only; Test re-runs Find-ZssSecretFiles logic on demand'))
$checks.Add((New-ZssCheck -Status 'NOT CONTROLLED' -Control 'Sandbox user ZCode credentials' `
    -Evidence 'stored in the sandbox profile; readable by the main user (trusted root)'))
$checks.Add((New-ZssCheck -Status 'NOT CONTROLLED' -Control 'Main-user ZCode sessions' `
    -Evidence 'only sessions started through the sandbox shortcut are inside the cage'))

Remove-Item -LiteralPath (Join-Path $probeScratch 'boundary-probe.ps1'), (Join-Path $probeScratch 'probe-result.txt') -Force -ErrorAction SilentlyContinue

Write-Output 'ZCode Safe Setup - verification'
$checks | Format-Table -AutoSize | Out-String | Write-Output
$failCount = @($checks | Where-Object Status -eq 'FAIL').Count
$partialCount = @($checks | Where-Object Status -eq 'PARTIAL').Count
Write-Output "Result: $(if ($failCount) { 'FAIL' } elseif ($partialCount) { 'PARTIAL' } else { 'PASS' }) (fail=$failCount partial=$partialCount notControlled=$(@($checks | Where-Object Status -eq 'NOT CONTROLLED').Count))"
return $checks
