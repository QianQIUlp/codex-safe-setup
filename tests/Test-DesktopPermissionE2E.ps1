#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RolloutPath,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{5,80}$')]
    [string]$RunId,
    [string]$CanaryRoot,
    [string]$CodexHome,
    [switch]$VisualStabilityConfirmed,
    [switch]$ShowPrompts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$canonicalScript = Join-Path $projectRoot 'skills\codex-safe-setup\scripts\Test-DesktopPermissionE2E.ps1'
& $canonicalScript @PSBoundParameters
