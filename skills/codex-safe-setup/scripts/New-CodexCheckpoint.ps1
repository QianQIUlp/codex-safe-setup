#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Save', 'List', 'Status', 'Commit')][string]$Action,
    [Parameter(Mandatory)][string]$Repository,
    [ValidateLength(0, 120)][string]$Message = 'Codex safety checkpoint',
    [string[]]$Path = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CanonicalRepositoryRoot {
    param([string]$Path, [string]$GitExecutable)
    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $root = (& $GitExecutable -C $resolvedPath rev-parse --show-toplevel 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or -not $root) { throw "Not a Git worktree: $resolvedPath" }
    return [IO.Path]::GetFullPath($root.Trim())
}

function Invoke-GitChecked {
    param([string]$GitExecutable, [string]$Root, [string[]]$GitArguments)
    $output = @(& $GitExecutable -C $Root @GitArguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArguments -join ' ') failed: $($output -join [Environment]::NewLine)" }
    return $output
}

function Invoke-GitProbe {
    param([string]$GitExecutable, [string]$Root, [string[]]$GitArguments)
    $output = @(& $GitExecutable -C $Root @GitArguments 2>&1)
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

function Get-NormalizedRelativePath {
    param([string]$Root, [string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value) -or [IO.Path]::IsPathRooted($Value) -or $Value -match '[\x00-\x1f]') {
        throw "Commit paths must be non-empty repository-relative file paths: '$Value'"
    }
    $normalized = $Value.Replace('\', '/')
    if ($normalized.StartsWith('./', [StringComparison]::Ordinal)) { $normalized = $normalized.Substring(2) }
    $segments = @($normalized -split '/')
    if (-not $normalized -or $normalized.StartsWith(':', [StringComparison]::Ordinal) -or $segments -contains '.' -or $segments -contains '..') {
        throw "Commit path is not a literal repository-relative path: '$Value'"
    }
    $candidate = [IO.Path]::GetFullPath((Join-Path $Root $normalized))
    $comparison = if ($env:OS -eq 'Windows_NT') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $rootPrefix = $Root.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)) + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($rootPrefix, $comparison)) { throw "Commit path escapes the registered repository: '$Value'" }
    return $normalized
}

function Assert-NoExternalGitFilters {
    param([string]$GitExecutable, [string]$Root)
    $filterProbe = Invoke-GitProbe -GitExecutable $GitExecutable -Root $Root -GitArguments @('config', '--local', '--get-regexp', '^filter\..*\.(clean|process)$')
    if ($filterProbe.ExitCode -eq 0 -and $filterProbe.Output.Count -gt 0) {
        throw 'The bridge refuses repositories with configured Git clean/process filters because they could execute outside the sandbox.'
    }
    if ($filterProbe.ExitCode -notin @(0, 1)) { throw 'Unable to inspect Git filter configuration safely.' }
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
if (-not (Test-Path -LiteralPath $authorizedPath -PathType Leaf)) { throw 'No authorized workspace registry exists. Re-run the installer with -WorkspacePath.' }
$registry = Get-Content -LiteralPath $authorizedPath -Raw | ConvertFrom-Json
if ($registry.schemaVersion -notin @(1, 2) -or -not $registry.gitExecutable -or -not $registry.gitExecutableSha256) { throw 'The workspace registry is missing a pinned Git executable. Re-run the installer.' }
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
    $rows = Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('for-each-ref', '--sort=-creatordate', '--format=%(refname)|%(objectname)|%(creatordate:iso8601)', 'refs/codex-safe/checkpoints/')
    foreach ($row in $rows) {
        if (-not $row) { continue }
        $parts = $row -split '\|', 3
        [pscustomobject]@{ Ref = $parts[0]; Commit = $parts[1]; Created = $parts[2] }
    }
    return
}

if ($Action -eq 'Status') {
    $rows = @(Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('-c', 'core.fsmonitor=false', 'status', '--short', '--untracked-files=all'))
    [pscustomobject]@{
        Status = $(if ($rows.Count -eq 0) { 'CLEAN' } else { 'CHANGED' })
        Repository = $repositoryRoot
        Entries = @($rows)
    }
    return
}

if ($Action -eq 'Commit') {
    $commitRoots = if ($registry.PSObject.Properties['commitRoots']) { @($registry.commitRoots) } else { @() }
    $commitAuthorized = $false
    foreach ($root in $commitRoots) {
        if ([string]::Equals([IO.Path]::GetFullPath($root), $repositoryRoot, $comparison)) { $commitAuthorized = $true; break }
    }
    if (-not $commitAuthorized) { throw "Normal branch commits are not enabled for this registered repository: $repositoryRoot" }
    if ($Path.Count -eq 0) { throw 'Commit requires one or more explicit -Path values.' }
    if ([string]::IsNullOrWhiteSpace($Message)) { throw 'Commit requires a non-empty message.' }

    $branch = (Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('symbolic-ref', '--quiet', '--short', 'HEAD') | Select-Object -First 1).Trim()
    $branchPrefixes = if ($registry.PSObject.Properties['commitBranchPrefixes']) { @($registry.commitBranchPrefixes) } else { @('codex/') }
    $branchAllowed = $false
    foreach ($prefix in $branchPrefixes) {
        if ($prefix -and $branch.StartsWith([string]$prefix, [StringComparison]::Ordinal)) { $branchAllowed = $true; break }
    }
    if (-not $branchAllowed) { throw "Commit bridge is limited to registered branch prefixes ($($branchPrefixes -join ', ')); current branch is '$branch'." }

    $headBefore = (Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('rev-parse', '--verify', 'HEAD') | Select-Object -First 1).Trim()
    foreach ($marker in @('MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge', 'rebase-apply', 'BISECT_LOG')) {
        $gitPath = (Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('rev-parse', '--git-path', $marker) | Select-Object -First 1).Trim()
        if (-not [IO.Path]::IsPathRooted($gitPath)) { $gitPath = Join-Path $repositoryRoot $gitPath }
        if (Test-Path -LiteralPath $gitPath) { throw "Commit bridge refuses a repository with an in-progress Git operation: $marker" }
    }
    $stagedProbe = Invoke-GitProbe -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('-c', 'core.fsmonitor=false', 'diff', '--cached', '--quiet', '--')
    if ($stagedProbe.ExitCode -eq 1) { throw 'Commit bridge refuses to mix with pre-existing staged changes. Commit or unstage them first.' }
    if ($stagedProbe.ExitCode -ne 0) { throw 'Unable to verify that the real Git index is clean.' }
    Assert-NoExternalGitFilters -GitExecutable $gitExecutable -Root $repositoryRoot

    $selectedPaths = [Collections.Generic.List[string]]::new()
    foreach ($requestedPath in $Path) {
        $relativePath = Get-NormalizedRelativePath -Root $repositoryRoot -Value $requestedPath
        if ($selectedPaths -contains $relativePath) { continue }
        $trackedProbe = Invoke-GitProbe -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('ls-files', '--error-unmatch', '--', $relativePath)
        $isTracked = $trackedProbe.ExitCode -eq 0
        if (-not $isTracked -and $trackedProbe.ExitCode -notin @(0, 1)) { throw "Unable to inspect commit path: $relativePath" }
        $untrackedProbe = Invoke-GitProbe -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('ls-files', '--others', '--exclude-standard', '--', $relativePath)
        if ($untrackedProbe.ExitCode -ne 0) { throw "Unable to inspect commit path: $relativePath" }
        $isUntracked = @($untrackedProbe.Output) -contains $relativePath
        if (-not $isTracked -and -not $isUntracked) { throw "Commit path is not a changed tracked file or exact untracked file: $relativePath" }
        if ($isUntracked -and (Test-SensitiveName -Path $relativePath)) {
            throw "Commit refused because an untracked path looks sensitive: $relativePath"
        }
        if ($isTracked) {
            $changedProbe = Invoke-GitProbe -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('-c', 'core.fsmonitor=false', 'diff', '--quiet', '--', $relativePath)
            if ($changedProbe.ExitCode -eq 0) { throw "Tracked commit path has no working-tree change: $relativePath" }
            if ($changedProbe.ExitCode -ne 1) { throw "Unable to inspect tracked commit path: $relativePath" }
        }
        $selectedPaths.Add($relativePath)
    }

    $emptyHooks = Join-Path ([IO.Path]::GetTempPath()) ('codex-safe-empty-hooks-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $emptyHooks)
    $stagingStarted = $false
    $commitCompleted = $false
    try {
        $stagingStarted = $true
        Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments (@('-c', 'core.fsmonitor=false', '-c', "core.hooksPath=$emptyHooks", 'add', '-A', '--') + @($selectedPaths)) | Out-Null
        $headAfterStage = (Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('rev-parse', '--verify', 'HEAD') | Select-Object -First 1).Trim()
        if ($headAfterStage -ne $headBefore) { throw 'HEAD changed concurrently while preparing the commit.' }
        $stagedPaths = @(Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('diff', '--cached', '--name-only', '--no-renames', '--'))
        $expected = @($selectedPaths | Sort-Object -Unique)
        $actual = @($stagedPaths | Where-Object { $_ } | Sort-Object -Unique)
        if (($expected -join "`n") -ne ($actual -join "`n")) { throw 'Staged paths differ from the explicit commit path set; refusing the commit.' }
        Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('-c', 'core.fsmonitor=false', '-c', "core.hooksPath=$emptyHooks", '-c', 'commit.gpgSign=false', 'commit', '--no-verify', '--no-gpg-sign', '-m', $Message) | Out-Null
        $commitCompleted = $true
        $commitId = (Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('rev-parse', '--verify', 'HEAD') | Select-Object -First 1).Trim()
        [pscustomobject]@{ Status = 'COMMITTED'; Repository = $repositoryRoot; Branch = $branch; Commit = $commitId; Paths = @($selectedPaths) }
        return
    }
    catch {
        if ($stagingStarted -and -not $commitCompleted) {
            & $gitExecutable -C $repositoryRoot reset $headBefore -- @($selectedPaths) 2>$null | Out-Null
        }
        throw
    }
    finally {
        if (Test-Path -LiteralPath $emptyHooks -PathType Container) { Remove-Item -LiteralPath $emptyHooks -Recurse -Force }
    }
}
$untrackedPaths = @(Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('ls-files', '--others', '--exclude-standard'))
$sensitiveUntracked = @($untrackedPaths | Where-Object { $_ -and (Test-SensitiveName -Path $_) })
if ($sensitiveUntracked.Count -gt 0) {
    throw "Checkpoint refused because sensitive-looking untracked files would enter Git object storage: $($sensitiveUntracked -join ', '). Add them to .gitignore or move them outside the repository."
}

$temporaryIndex = Join-Path ([IO.Path]::GetTempPath()) ('codex-safe-index-' + [guid]::NewGuid().ToString('N'))
$previousIndex = [Environment]::GetEnvironmentVariable('GIT_INDEX_FILE', 'Process')
try {
    $env:GIT_INDEX_FILE = $temporaryIndex
    $head = @(& $gitExecutable -C $repositoryRoot rev-parse --verify HEAD 2>$null)
    $hasHead = $LASTEXITCODE -eq 0 -and $head.Count -gt 0
    if ($hasHead) { Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('read-tree', $head[0].Trim()) | Out-Null }
    else { Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('read-tree', '--empty') | Out-Null }
    Assert-NoExternalGitFilters -GitExecutable $gitExecutable -Root $repositoryRoot
    Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('add', '-A', '--', '.') | Out-Null
    $tree = (Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments @('write-tree') | Select-Object -First 1).Trim()
    $commitArguments = @('-c', 'user.name=Codex Safe Setup', '-c', 'user.email=checkpoint@local.invalid', 'commit-tree', $tree, '-m', $Message)
    if ($hasHead) { $commitArguments += @('-p', $head[0].Trim()) }
    $commit = (Invoke-GitChecked -GitExecutable $gitExecutable -Root $repositoryRoot -GitArguments $commitArguments | Select-Object -First 1).Trim()
    $refName = 'refs/codex-safe/checkpoints/' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + $commit.Substring(0, 8)
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
