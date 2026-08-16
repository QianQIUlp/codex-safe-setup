#requires -Version 5.1
<#
.SYNOPSIS
  Consolidated feasibility probes for the ZCode OS-cage design (see ../PROBE-REPORT.md).
.DESCRIPTION
  Reproduces the decisive experiments:
    Phase 1 - NTFS boundary matrix as a temporary standard user
    Phase 2 - path-based execution control detection
    Phase 3 - ZCode launch from an admin-controlled copy (optional, needs elevation once)
  A temporary local user is created for phase 1-2 and fully removed afterwards.
  Phase 3 copies the real ZCode install into C:\Program Files\ZCodeProbeCopy (619 MB)
  and launches it as the temp user; everything is removed at the end.
.NOTES
  Windows-only. Run from an elevated PowerShell for phases 1-3, or use -SkipLaunchPhase
  from a normal shell (phase 1-2 self-elevate once to create/remove the user).
#>
[CmdletBinding()]
param(
  [string]$ProbeUserName = 'zcode_cage_probe',
  [switch]$SkipLaunchPhase,
  [string]$ZCodeSourceDir = "$env:LOCALAPPDATA\Programs\ZCode",
  [string]$PfCopyDir = 'C:\Program Files\ZCodeProbeCopy'
)
$ErrorActionPreference = 'Stop'

function Assert-Admin {
  $id = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not $id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath,@('-SkipLaunchPhase')[0]
    throw 'Re-run this script from the elevated window that just opened.'
  }
}

function Invoke-AsProbeUser([pscredential]$Cred, [string]$ScriptPath, [string]$WorkDir) {
  # NOTE: -WindowStyle Hidden / -Wait are both broken with -Credential (see report).
  Start-Process powershell.exe -Credential $Cred -WorkingDirectory $WorkDir `
    -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$ScriptPath
  $deadline = (Get-Date).AddSeconds(60)
  while (-not (Test-Path "$WorkDir\probe-result.txt") -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
  }
  if (Test-Path "$WorkDir\probe-result.txt") { Get-Content "$WorkDir\probe-result.txt" }
}

function Get-ProcsOwnedBy([string]$User) {
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
    $o = Invoke-CimMethod -InputObject $_ -MethodName GetOwner -ErrorAction SilentlyContinue
    if ($o -and $o.User -eq $User) { $_ }
  }
}

# ---------- setup ----------
$scratch = "C:\Users\Public\$ProbeUserName"
$password = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 32 | ForEach-Object {[char]$_})
$secure = ConvertTo-SecureString $password -AsPlainText -Force
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
icacls $scratch /grant "${ProbeUserName}:(OI)(CI)M" | Out-Null
New-LocalUser -Name $ProbeUserName -Password $secure -FullName 'Cage Probe Temp' `
  -Description 'TEMP probe - safe to delete' -AccountNeverExpires -PasswordNeverExpires | Out-Null
$cred = [pscredential]::new("$env:COMPUTERNAME\$ProbeUserName", $secure)

$canary = Join-Path $env:USERPROFILE 'zcode-cage-probe-canary.txt'
"canary-$([guid]::NewGuid().ToString('N'))" | Set-Content $canary
$authRoot = "C:\Users\Public\$ProbeUserName-authroot"
New-Item -ItemType Directory -Path $authRoot -Force | Out-Null
icacls $authRoot /grant "${ProbeUserName}:(OI)(CI)M" | Out-Null
"FAKE" | Set-Content (Join-Path $authRoot '.env')
icacls (Join-Path $authRoot '.env') /deny "${ProbeUserName}:R" | Out-Null

# ---------- phase 1+2: boundary & execution-control matrix ----------
@'
$r = @()
$r += "whoami=$(whoami)"
$r += "isAdmin=$([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"
function T($n,[scriptblock]$s){ try{ & $s|Out-Null; $script:r+="$n=ALLOWED" }catch{ $script:r+="$n=DENIED" } }
T 'read-main-profile-canary' { Get-Content $env:_marked_canary -ErrorAction Stop }
T 'list-main-profile'        { Get-ChildItem $env:marked_home -ErrorAction Stop | Out-Null }
T 'write-authorized-root'    { 'x'|Set-Content "$env:marked_root\w.txt" }
T 'write-windows'            { 'x'|Set-Content 'C:\Windows\w.txt' -ErrorAction Stop }
T 'read-denied-secret'       { Get-Content "$env:marked_root\.env" -ErrorAction Stop }
Copy-Item C:\Windows\System32\where.exe "$env:TEMP\wcopy.exe" -Force
$raw = & "$env:TEMP\wcopy.exe" 2>&1 | Out-String
$r += "exec-own-profile-copy: rc=$LASTEXITCODE outputLen=$($raw.Length)"
$raw = & 'C:\Program Files\Git\mingw64\bin\git.exe' --version 2>&1 | Out-String
$r += "exec-git-from-PF: rc=$LASTEXITCODE out=$($raw.Trim())"
$r | Set-Content "$env:marked_scratch\probe-result.txt"
'@ | Set-Content "$scratch\sb.ps1"
$env:marked_home = $env:USERPROFILE; $env:marked_root = $authRoot; $env:marked_scratch = $scratch; $env:marked_canary = $canary
# re-mark env for the child via a wrapper (child cannot see our env): use literal replacement instead
((Get-Content "$scratch\sb.ps1" -Raw)
  -replace '\$env:marked_canary', "'$canary'"
  -replace '\$env:marked_home', "'$env:USERPROFILE'"
  -replace '\$env:marked_root', "'$authRoot'"
  -replace '\$env:marked_scratch', "'$scratch'"
  -replace '\$env:TEMP\\wcopy\.exe', "'C:\Users\Public\$ProbeUserName\wcopy.exe'") | Set-Content "$scratch\sb.ps1"
Copy-Item C:\Windows\System32\where.exe "$scratch\wcopy.exe" -Force
Remove-Item "$scratch\probe-result.txt" -ErrorAction SilentlyContinue
'===== PHASE 1+2 (boundary + execution control) ====='
Invoke-AsProbeUser $cred "$scratch\sb.ps1" $scratch

# ---------- phase 3: launch ZCode from admin-controlled path ----------
if (-not $SkipLaunchPhase -and (Test-Path "$ZCodeSourceDir\ZCode.exe")) {
  if (Test-Path $PfCopyDir) { Remove-Item $PfCopyDir -Recurse -Force }
  New-Item -ItemType Directory -Path $PfCopyDir | Out-Null
  robocopy $ZCodeSourceDir $PfCopyDir /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null
  if ($LASTEXITCODE -gt 7) { throw "robocopy failed: $LASTEXITCODE" }
  icacls $PfCopyDir /grant "${ProbeUserName}:(OI)(CI)RX" | Out-Null
  Start-Process "$PfCopyDir\ZCode.exe" -Credential $cred -WorkingDirectory $scratch
  '===== PHASE 3 (ZCode from Program Files) ====='
  $win = $false; $deadline = (Get-Date).AddSeconds(120)
  while ((Get-Date) -lt $deadline) {
    $zp = @(Get-ProcsOwnedBy $ProbeUserName | Where-Object Name -like 'ZCode*')
    $w = $zp | ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue } |
         Where-Object { $_.MainWindowHandle -ne 0 }
    if ($w) { $win = $true; break }
    Start-Sleep -Seconds 5
  }
  "windowSeen=$win alive=$((@(Get-ProcsOwnedBy $ProbeUserName | Where-Object Name -like 'ZCode*')).Count)"
} else { 'phase 3 skipped' }

# ---------- cleanup ----------
Get-ProcsOwnedBy $ProbeUserName | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep 2
if (Test-Path $PfCopyDir) { Remove-Item $PfCopyDir -Recurse -Force }
icacls $ZCodeSourceDir /remove:g $ProbeUserName 2>$null | Out-Null
Remove-Item $scratch,$authRoot,$canary -Recurse -Force -ErrorAction SilentlyContinue
Get-CimInstance Win32_UserProfile | Where-Object { $_.LocalPath -like "*\$ProbeUserName" } | Remove-CimInstance -ErrorAction SilentlyContinue
Remove-LocalUser -Name $ProbeUserName -ErrorAction SilentlyContinue
"userStillExists=$([bool](Get-LocalUser -Name $ProbeUserName -ErrorAction SilentlyContinue))"
