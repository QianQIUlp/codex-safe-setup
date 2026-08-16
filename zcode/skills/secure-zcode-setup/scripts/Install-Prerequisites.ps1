#requires -Version 5.1
<#
.SYNOPSIS
  Consent-gated prerequisite installer for the ZCode cage.
.DESCRIPTION
  PowerShell 7 via winget is optional (better shell fidelity for the scripts;
  it is NOT a security boundary and cannot prevent semantic path mistakes).
  ZCode itself is assumed present - the audit reports it. Nothing is ever
  installed silently: every component requires an explicit Install choice.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Install', 'Skip')][string]$PowerShell7
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$ErrorActionPreference = 'Stop'

if ($PowerShell7 -eq 'Skip') {
    Write-Output 'PowerShell 7: skipped by user choice (Windows PowerShell 5.1 will run the scripts).'
    return
}

$existing = Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existing) {
    Write-Output "PowerShell 7 already available: $($existing.Source)"
    return
}

$winget = Get-Command winget -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $winget) {
    Write-Warning 'winget is unavailable. Install PowerShell 7 manually from https://aka.ms/powershell and re-run.'
    return
}

Write-Output 'Installing PowerShell 7 via winget (consent already given via -PowerShell7 Install)...'
& $winget.Source install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements
if ($LASTEXITCODE -ne 0) { throw "winget install failed with exit code $LASTEXITCODE. Install PowerShell 7 manually and re-run." }
Write-Output 'PowerShell 7 installed. Open a new shell so PATH refreshes.'
