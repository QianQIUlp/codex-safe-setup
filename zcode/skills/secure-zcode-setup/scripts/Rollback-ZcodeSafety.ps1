#requires -Version 5.1
<#
.SYNOPSIS
  Exact rollback of the OS cage, driven by install-state.json only.
.DESCRIPTION
  Removes exactly what the installer recorded - ACEs, the Program Files copy,
  the shortcut, the state directory, and the sandbox account with its profile.
  Nothing outside the recorded targets is touched; a missing or mismatched
  state file aborts. Needs one UAC prompt (account + Program Files deletion).
#>
[CmdletBinding()]
param(
    [string]$ZcodeHome,
    [string]$StateRoot,
    [switch]$Confirm,
    [switch]$NonInteractive,
    [switch]$ElevatedChild
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$ErrorActionPreference = 'Stop'

$home2 = Get-ZssZcodeHome -Override $ZcodeHome
$stateRoot = Get-ZssStateRoot -ZcodeHome $home2 -Override $StateRoot
$installStatePath = Join-Path $stateRoot 'install-state.json'
if (-not (Test-Path -LiteralPath $installStatePath -PathType Leaf)) {
    throw "No installation recorded at $installStatePath; nothing to roll back."
}
$state = Get-Content -LiteralPath $installStatePath -Raw | ConvertFrom-Json
$expectedState = [IO.Path]::GetFullPath((Join-Path $home2 'safe-setup'))
if (-not [string]::Equals($state.StateRoot, [IO.Path]::GetFullPath($stateRoot), [StringComparison]::OrdinalIgnoreCase)) {
    throw "install-state.json was written for a different StateRoot ($($state.StateRoot)). Refusing to touch this machine."
}
$userName = $state.SandboxUserName

Write-Output 'ZCode Safe Setup - rollback targets'
[pscustomobject]@{
    SandboxAccount = $userName
    Profile = "C:\Users\$userName"
    InstallDir = $state.SandboxInstallDir
    WorkspaceRootACEs = @($state.WorkspaceRoots) -join ', '
    SecretDenyACEs = "$(@($state.SecretFilesDenied).Count) files"
    Shortcut = $state.ShortcutPath
    StateRoot = $stateRoot
} | Format-List | Out-String | Write-Output
Write-Output 'The workspace trees themselves are NOT touched - only the sandbox ACEs are removed.'

if (-not $Confirm) {
    if ($NonInteractive) { throw 'Rollback requires -Confirm.' }
    $answer = Read-Host 'Roll back this exact installation? [y/N]'
    if ($answer -notmatch '^(?i:y|yes)$') { throw 'Rollback cancelled.' }
}

if (-not (Test-ZssIsAdmin)) {
    $relayArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Confirm', '-NonInteractive', '-ElevatedChild')
    if ($ZcodeHome) { $relayArgs += @('-ZcodeHome', $home2) }
    Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList $relayArgs
    if (Get-LocalUser -Name $userName -ErrorAction SilentlyContinue) {
        throw 'Elevated rollback did not complete (UAC declined or rollback failed); the account still exists.'
    }
    Write-Output 'Rollback completed.'
    return
}

# stop anything still running as the sandbox user
Get-ZssProcsOwnedBy -UserName $userName | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

foreach ($root in @($state.WorkspaceRoots)) {
    icacls $root /remove:g $userName 2>$null | Out-Null
}
foreach ($secret in @($state.SecretFilesDenied)) {
    icacls $secret /remove:d $userName 2>$null | Out-Null
}
if (Test-Path -LiteralPath $state.SandboxInstallDir) {
    icacls $state.SandboxInstallDir /remove:g $userName 2>$null | Out-Null
    Remove-Item -LiteralPath $state.SandboxInstallDir -Recurse -Force
}
if (Test-Path -LiteralPath $state.ShortcutPath) { Remove-Item -LiteralPath $state.ShortcutPath -Force }
if (Test-Path -LiteralPath $stateRoot) { Remove-Item -LiteralPath $stateRoot -Recurse -Force }
Get-CimInstance Win32_UserProfile | Where-Object { $_.LocalPath -like "*\$userName" } | Remove-CimInstance -ErrorAction SilentlyContinue
Remove-LocalUser -Name $userName -ErrorAction SilentlyContinue

$userStill = [bool](Get-LocalUser -Name $userName -ErrorAction SilentlyContinue)
$dirStill = Test-Path -LiteralPath $state.SandboxInstallDir
if ($userStill -or $dirStill) { throw "Rollback incomplete: userStill=$userStill installDirStill=$dirStill. Remove them manually." }
Write-Output "Rollback completed: account '$userName', install copy, ACEs, shortcut, and state removed."
