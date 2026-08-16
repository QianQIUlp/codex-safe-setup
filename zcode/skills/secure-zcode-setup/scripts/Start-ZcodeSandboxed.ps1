#requires -Version 5.1
<#
.SYNOPSIS
  Launch ZCode inside the OS cage (as the dedicated sandbox user).
.DESCRIPTION
  Runs from the main user account. Decrypts the DPAPI-protected sandbox
  credential (CurrentUser scope - only the main user can) and starts the
  Program Files copy of ZCode via CreateProcessWithLogonW. The window appears
  on the current desktop. Work inside that instance is bounded by NTFS ACLs;
  main-user ZCode sessions remain outside the cage.
.NOTES
  Start-Process -Credential cannot be combined with -Wait or -WindowStyle
  Hidden (both throw; see docs/zcode-probe/PROBE-REPORT.md).
#>
[CmdletBinding()]
param(
    [string]$ZcodeHome,
    [string]$StateRoot,
    [string[]]$Argument
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$ErrorActionPreference = 'Stop'

$home2 = Get-ZssZcodeHome -Override $ZcodeHome
# bin\Start-ZcodeSandboxed.ps1 -> state root is the parent of bin
$stateRoot = if ($StateRoot) { [IO.Path]::GetFullPath($StateRoot) } else { Split-Path -Parent $PSScriptRoot }
$installStatePath = Join-Path $stateRoot 'install-state.json'
if (-not (Test-Path -LiteralPath $installStatePath -PathType Leaf)) {
    throw "No cage installation found at $stateRoot. Run Install-ZcodeSafety.ps1 first."
}
$state = Get-Content -LiteralPath $installStatePath -Raw | ConvertFrom-Json

$zcodeExe = Join-Path $state.SandboxInstallDir 'ZCode.exe'
if (-not (Test-Path -LiteralPath $zcodeExe -PathType Leaf)) {
    throw "Sandboxed ZCode copy is missing: $zcodeExe. Re-run the installer or roll back."
}

$password = Unprotect-ZssSecret -Path $state.CredentialPath
$credential = [pscredential]::new("$env:COMPUTERNAME\$($state.SandboxUserName)", (ConvertTo-SecureString $password -AsPlainText -Force))
Remove-Variable password

# the working directory must be readable by the sandbox user
$workDir = $env:PUBLIC
if (-not (Test-Path -LiteralPath $workDir -PathType Container)) { $workDir = 'C:\Windows' }

if ($Argument) {
    Start-Process -FilePath $zcodeExe -Credential $credential -WorkingDirectory $workDir -ArgumentList $Argument
}
else {
    Start-Process -FilePath $zcodeExe -Credential $credential -WorkingDirectory $workDir
}
Write-Output "ZCode launched as $($state.SandboxUserName). Sessions in this window are inside the cage; main-user ZCode windows are not."
