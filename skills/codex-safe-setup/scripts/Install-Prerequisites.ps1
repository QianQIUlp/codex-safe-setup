[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Ask', 'Install', 'Skip')][string]$PowerShell7 = 'Ask',
    [ValidateSet('Ask', 'Install', 'Skip')][string]$CodexCli = 'Ask',
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Confirm-InstallChoice {
    param([string]$Prompt)
    if ($NonInteractive) { throw "Cannot use Ask in non-interactive mode: $Prompt" }
    $answer = Read-Host "$Prompt [y/N]"
    return $answer -match '^(?i:y|yes)$'
}

$results = [Collections.Generic.List[object]]::new()
$pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pwshCommand) {
    $results.Add([pscustomobject]@{ Component = 'PowerShell 7'; Status = 'Present'; Detail = $pwshCommand.Source })
}
else {
    $installPowerShell = $PowerShell7 -eq 'Install'
    if ($PowerShell7 -eq 'Ask') {
        Write-Output 'PowerShell 7 is recommended for modern encoding, quoting, error handling, and compatibility. It is not a security boundary.'
        $installPowerShell = Confirm-InstallChoice -Prompt 'Install PowerShell 7 with Windows Package Manager?'
    }
    if (-not $installPowerShell) {
        $results.Add([pscustomobject]@{ Component = 'PowerShell 7'; Status = 'Skipped'; Detail = 'Declined or disabled' })
    }
    else {
        $wingetCommand = Get-Command winget -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $wingetCommand) { throw 'PowerShell 7 installation requires winget. Install Windows Package Manager manually, or rerun with -PowerShell7 Skip.' }
        if ($PSCmdlet.ShouldProcess('Microsoft.PowerShell', 'Install PowerShell 7 with winget')) {
            & $wingetCommand.Source install --id Microsoft.PowerShell --exact --source winget --accept-package-agreements --accept-source-agreements
            if ($LASTEXITCODE -ne 0) { throw "winget failed with exit code $LASTEXITCODE" }
        }
        $results.Add([pscustomobject]@{ Component = 'PowerShell 7'; Status = 'Installed'; Detail = 'Restart the terminal before using pwsh.' })
    }
}

$codexCommand = Get-Command codex -ErrorAction SilentlyContinue | Select-Object -First 1
if ($codexCommand) {
    $version = (& $codexCommand.Source --version 2>$null | Select-Object -First 1)
    $results.Add([pscustomobject]@{ Component = 'Codex CLI'; Status = 'Present'; Detail = $version })
}
else {
    $installCodex = $CodexCli -eq 'Install'
    if ($CodexCli -eq 'Ask') {
        Write-Output 'Codex CLI is recommended for version checks and execpolicy rule verification. Base configuration can continue without it.'
        $installCodex = Confirm-InstallChoice -Prompt 'Install Codex CLI globally with npm?'
    }
    if (-not $installCodex) {
        $results.Add([pscustomobject]@{ Component = 'Codex CLI'; Status = 'Skipped'; Detail = 'Verification will be partial' })
    }
    else {
        $npmCommand = Get-Command npm -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $npmCommand) { throw 'Codex CLI installation requires npm. Node.js will not be installed silently; install it separately or rerun with -CodexCli Skip.' }
        if ($PSCmdlet.ShouldProcess('@openai/codex', 'Install Codex CLI globally with npm')) {
            & $npmCommand.Source install --global '@openai/codex'
            if ($LASTEXITCODE -ne 0) { throw "npm failed with exit code $LASTEXITCODE" }
        }
        $results.Add([pscustomobject]@{ Component = 'Codex CLI'; Status = 'Installed'; Detail = 'Open a new terminal if codex is not yet on PATH.' })
    }
}

$results
