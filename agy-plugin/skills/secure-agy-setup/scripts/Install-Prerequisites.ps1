[CmdletBinding()]
param(
    [ValidateSet('Skip', 'Install')][string]$PowerShell7 = 'Skip',
    [ValidateSet('Skip', 'Install')][string]$Git = 'Skip'
)

$ErrorActionPreference = 'Stop'

if ($PowerShell7 -eq 'Install') {
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        Write-Output 'PowerShell 7 is already installed.'
    }
    elseif (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Output 'Installing PowerShell 7 via winget...'
        winget install --id Microsoft.PowerShell --exact --source winget --accept-source-agreements --accept-package-agreements
    }
    else {
        Write-Warning 'winget is unavailable. Please install PowerShell 7 from https://github.com/PowerShell/PowerShell/releases.'
    }
}

if ($Git -eq 'Install') {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Output 'Git is already installed.'
    }
    elseif (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Output 'Installing Git via winget...'
        winget install --id Git.Git --exact --source winget --accept-source-agreements --accept-package-agreements
    }
    else {
        Write-Warning 'winget is unavailable. Please install Git from https://git-scm.com/downloads.'
    }
}
