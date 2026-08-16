#requires -Version 5.1
<#
.SYNOPSIS
  Read-only audit of the ZCode exposure surface relevant to the OS-cage design.
.DESCRIPTION
  Inventory only: no configuration is changed, no secrets are read. Reports the
  ZCode install location, existing cage state, credential-location existence,
  execution-control posture, and the NOT CONTROLLED surface. Exit code 0 always;
  consumers read the result objects.
#>
[CmdletBinding()]
param(
    [string]$ZcodeHome,
    [string]$ZCodeSourceDir = "$env:LOCALAPPDATA\Programs\ZCode",
    [string]$SandboxUserName = 'ZCode-Sandbox'
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$ErrorActionPreference = 'Stop'

$home2 = Get-ZssZcodeHome -Override $ZcodeHome
Assert-ZssNotFilesystemRoot -Path $home2 -Label 'ZcodeHome'
$stateRoot = Get-ZssStateRoot -ZcodeHome $home2
$findings = [Collections.Generic.List[object]]::new()

# ---- ZCode installation ----
$zcodeExe = Join-Path $ZCodeSourceDir 'ZCode.exe'
$zcodeInstalled = Test-Path -LiteralPath $zcodeExe -PathType Leaf
$installLocation = if ($zcodeInstalled) { 'user-profile path (cage requires a Program Files copy)' }
                   elseif (Test-Path 'C:\Program Files\ZCode\ZCode.exe' -PathType Leaf) { 'Program Files (already admin-controlled)' }
                   else { 'not found' }
$findings.Add([pscustomobject]@{ Area = 'ZCodeInstall'; State = if ($zcodeInstalled -or $installLocation -like 'Program Files*') { 'OK' } else { 'MISSING' }; Detail = "install=$ZCodeSourceDir exists=$zcodeInstalled; location=$installLocation" })

# ---- existing cage state ----
$installStatePath = Join-Path $stateRoot 'install-state.json'
$existingState = $null
if (Test-Path -LiteralPath $installStatePath -PathType Leaf) {
    try { $existingState = Get-Content -LiteralPath $installStatePath -Raw | ConvertFrom-Json } catch { $existingState = $null }
}
$findings.Add([pscustomobject]@{
    Area = 'CageState'; State = if ($existingState) { 'INSTALLED' } else { 'NOT INSTALLED' }
    Detail = if ($existingState) { "installedAt=$($existingState.InstalledAtUtc); user=$($existingState.SandboxUserName); roots=$(@($existingState.WorkspaceRoots) -join ',')" }
             else { "no install-state.json under $stateRoot" }
})

# ---- sandbox account ----
$sandboxUser = Get-LocalUser -Name $SandboxUserName -ErrorAction SilentlyContinue
if ($sandboxUser) {
    $findings.Add([pscustomobject]@{ Area = 'SandboxAccount'; State = 'PRESENT'; Detail = "name=$SandboxUserName enabled=$($sandboxUser.Enabled) (created outside this audit if no cage state exists)" })
}

# ---- credentials exposure surface (existence only; NEVER read contents) ----
foreach ($item in @(
    @{ Name = 'ssh';     Path = Join-Path $home2 '..\.ssh' },
    @{ Name = 'aws';     Path = Join-Path $home2 '..\.aws' },
    @{ Name = 'azure';   Path = Join-Path $home2 '..\.azure' },
    @{ Name = 'gcloud';  Path = Join-Path $home2 '..\.config\gcloud' },
    @{ Name = 'zcode';   Path = Join-Path $home2 'v2\credentials.json' }
)) {
    $exists = Test-Path -LiteralPath $item.Path
    $findings.Add([pscustomobject]@{
        Area = "CredentialSurface/$($item.Name)"
        State = if ($exists) { 'EXPOSED-WITHOUT-CAGE' } else { 'ABSENT' }
        Detail = "$($item.Path) exists=$exists (existence check only; contents never read)"
    })
}

# ---- execution control posture (small temp artifact, always cleaned) ----
$userPathBlocked = Test-ZssUserPathExecutionBlocked
$findings.Add([pscustomobject]@{
    Area = 'ExecutionControl'
    State = if ($userPathBlocked) { 'ENFORCED' } else { 'NOT DETECTED' }
    Detail = if ($userPathBlocked) { 'user-writable paths cannot execute exes: the cage MUST run ZCode from an admin-controlled path; repo-local binaries will not run for the sandbox user' }
             else { 'exes from user paths execute: cage still REQUIRES a Program Files copy (hard requirement), but repo-local binaries may run for the sandbox user' }
})

# ---- tools ----
foreach ($tool in 'git', 'pwsh') {
    $command = Get-Command $tool -ErrorAction SilentlyContinue | Select-Object -First 1
    $findings.Add([pscustomobject]@{ Area = "Tool/$tool"; State = if ($command) { 'OK' } else { 'MISSING' }; Detail = if ($command) { $command.Source } else { 'not on PATH' } })
}

# ---- honest summary ----
$summary = @(
    'NOT CONTROLLED without the cage: any ZCode session running as the main user can read the credential locations listed above.',
    'NOT CONTROLLED even with the cage: network egress (Windows Firewall cannot scope by user for one exe path); secret files created after install inside granted roots; the sandbox user''s own ZCode credentials are readable by the main user (trusted root).',
    'Approval inside ZCode is a workflow choice, never the boundary itself.'
)

Write-Output 'ZCode Safe Setup - assessment (read-only)'
$findings | Format-Table -AutoSize | Out-String | Write-Output
Write-Output 'Summary:'
foreach ($line in $summary) { Write-Output "  - $line" }
return $findings
