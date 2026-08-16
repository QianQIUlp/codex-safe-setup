#requires -Version 7.0
<#
.SYNOPSIS
  Checkpoint bridge: hidden Git commit on a dedicated ref, branch and index untouched.
.DESCRIPTION
  Port of New-CodexCheckpoint.ps1 for the ZCode cage (refs/zcode-safe/*).
  Accepts only repositories registered in authorized-workspaces.json, refuses
  sensitive-looking untracked files, verifies the pinned Git executable, and
  uses a temporary GIT_INDEX_FILE so the real index, branch, and working tree
  are never modified. Restoration stays user-controlled (git worktree add).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Save', 'List')][string]$Action,
    [Parameter(Mandatory)][string]$Repository,
    [ValidateLength(0, 120)][string]$Message = 'ZCode safety checkpoint'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CanonicalRepositoryRoot {
    param([string]$Path, [string]$GitExecutable)
    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    # Piping a native command into Select-Object -First stops the pipeline early
    # and leaves $LASTEXITCODE unset (pwsh 7.6 StrictMode throws); capture fully first.
    $output = @(& $GitExecutable -C $resolvedPath rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $output) { throw "Not a Git worktree: $resolvedPath" }
    return [IO.Path]::GetFullPath(($output | Select-Object -First 1).Trim())
}

function Invoke-GitChecked {
    param([string]$GitExecutable, [string]$Root, [string[]]$GitArguments)
    $output = @(& $GitExecutable -C $Root @GitArguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArguments -join ' ') failed: $($output -join [Environment]::NewLine)" }
    return $output
}

function Test-SensitiveName {
    param([string]$Path)
    $fileName = [IO.Path]::GetFileName(($Path -replace '\\', '/')).ToLowerInvariant()
    if (@('.env', '.npmrc', '.pypirc', '.netrc', 'nuget.config', 'credentials.json', 'service-account.json', 'id_rsa', 'id_ed25519') -contains $fileName) { return $true }
    if ($fileName.StartsWith('.env.')) { return $true }
    return $fileName.EndsWith('.pem') -or $fileName.EndsWith('.key') -or $fileName.EndsWith('.pfx') -or $fileName.EndsWith('.p12')
}

$effectiveStateRoot = Split-Path -Parent $PSScriptRoot
$authorizedPath = Join-Path $effectiveStateRoot 'authorized-workspaces.json'
if (-not (Test-Path -LiteralPath $authorizedPath -PathType Leaf)) { throw 'No authorized workspace registry exists. Re-run the installer with -InstallCheckpoints.' }
$registry = Get-Content -LiteralPath $authorizedPath -Raw | ConvertFrom-Json
if ($registry.schemaVersion -ne 1 -or -not $registry.gitExecutable -or -not $registry.gitExecutableSha256) { throw 'The workspace registry is missing a pinned Git executable. Re-run the installer.' }
$gitExecutable = [IO.Path]::GetFullPath($registry.gitExecutable)
if (-not (Test-Path -LiteralPath $gitExecutable -PathType Leaf)) { throw "Pinned Git executable is missing: $gitExecutable" }
$currentGitHash = (Get-FileHash -LiteralPath $gitExecutable -Algorithm SHA256).Hash
if (-not [string]::Equals($currentGitHash, $registry.gitExecutableSha256, [StringComparison]::OrdinalIgnoreCase)) { throw 'Pinned Git executable changed after installation. Re-run the installer before creating checkpoints.' }
$repositoryRoot = Get-CanonicalRepositoryRoot -Path $Repository -GitExecutable $gitExecutable
$comparison = if ($env:OS -eq 'Windows_NT') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
$authorized = $false
foreach ($root in @($registry.roots)) {
    if ([string]::Equals([IO.Path]::GetFullPath($root), $repositoryRoot, $comparison)) { $authorized = $true; break }
}
if (-not $authorized) { throw "Repository is not registered for checkpoint access: $repositoryRoot" }

if ($Action -eq 'List') {
    $rows = Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('for-each-ref', '--sort=-creatordate', '--format=%(refname)|%(objectname)|%(creatordate:iso8601)', 'refs/zcode-safe/checkpoints/')
    foreach ($row in $rows) {
        if (-not $row) { continue }
        $parts = $row -split '\|', 3
        [pscustomobject]@{ Ref = $parts[0]; Commit = $parts[1]; Created = $parts[2] }
    }
    return
}

$untrackedPaths = @(Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('ls-files', '--others', '--exclude-standard'))
$sensitiveUntracked = @($untrackedPaths | Where-Object { $_ -and (Test-SensitiveName -Path $_) })
if ($sensitiveUntracked.Count -gt 0) {
    throw "Checkpoint refused because sensitive-looking untracked files would enter Git object storage: $($sensitiveUntracked -join ', '). Add them to .gitignore or move them outside the repository."
}

$temporaryIndex = Join-Path ([IO.Path]::GetTempPath()) ('zcode-safe-index-' + [guid]::NewGuid().ToString('N'))
$previousIndex = [Environment]::GetEnvironmentVariable('GIT_INDEX_FILE', 'Process')
try {
    $env:GIT_INDEX_FILE = $temporaryIndex
    $head = @(& $gitExecutable -C $repositoryRoot rev-parse --verify HEAD 2>$null)
    $hasHead = $LASTEXITCODE -eq 0 -and $head.Count -gt 0
    if ($hasHead) { Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('read-tree', $head[0].Trim()) | Out-Null }
    else { Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('read-tree', '--empty') | Out-Null }
    Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('add', '-A', '--', '.') | Out-Null
    $tree = (Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('write-tree') | Select-Object -First 1).Trim()
    $commitArguments = @('-c', 'user.name=ZCode Safe Setup', '-c', 'user.email=checkpoint@local.invalid', 'commit-tree', $tree, '-m', $Message)
    if ($hasHead) { $commitArguments += @('-p', $head[0].Trim()) }
    $commit = (Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments $commitArguments | Select-Object -First 1).Trim()
    $refName = 'refs/zcode-safe/checkpoints/' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + $commit.Substring(0, 8)
    Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('update-ref', $refName, $commit) | Out-Null
    [pscustomobject]@{ Status = 'SAVED'; Repository = $repositoryRoot; Ref = $refName; Commit = $commit; BranchAndIndexChanged = $false }
}
finally {
    if ([string]::IsNullOrEmpty($previousIndex)) {
        Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue
    }
    else {
        $env:GIT_INDEX_FILE = $previousIndex
    }
    if (Test-Path -LiteralPath $temporaryIndex -PathType Leaf) { Remove-Item -LiteralPath $temporaryIndex -Force }
}
