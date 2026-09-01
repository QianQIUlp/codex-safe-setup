Set-StrictMode -Version Latest

$script:AgyManagedStart = '// >>> agy-safe-setup managed >>>'
$script:AgyManagedEnd = '// <<< agy-safe-setup managed <<<'
$script:AgyProfileName = 'agy-safe-workspace'

function Get-AgyGeminiHome {
    param([string]$Override)

    if ($Override) {
        return [IO.Path]::GetFullPath($Override)
    }
    if ($env:GEMINI_HOME) {
        return [IO.Path]::GetFullPath($env:GEMINI_HOME)
    }
    $userProfilePath = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    if (-not $userProfilePath) {
        throw 'Cannot determine the user profile. Pass -GeminiHome explicitly.'
    }
    return Join-Path $userProfilePath '.gemini'
}

function Get-AgyConfigDir {
    param([string]$GeminiHome)
    return Join-Path (Get-AgyGeminiHome -Override $GeminiHome) 'config'
}

function Get-AgyCliSettingsPath {
    param([string]$GeminiHome, [string]$Override)
    if ($Override) { return [IO.Path]::GetFullPath($Override) }
    $cliDir = Join-Path (Get-AgyGeminiHome -Override $GeminiHome) 'antigravity-cli'
    return Join-Path $cliDir 'settings.json'
}

function Get-AgyGlobalSettingsPath {
    param([string]$GeminiHome, [string]$Override)
    if ($Override) { return [IO.Path]::GetFullPath($Override) }
    $configDir = Get-AgyConfigDir -GeminiHome $GeminiHome
    return Join-Path $configDir 'settings.json'
}

function Get-AgyStateRoot {
    param([string]$GeminiHome, [string]$Override)
    if ($Override) { return [IO.Path]::GetFullPath($Override) }
    return Join-Path (Get-AgyGeminiHome -Override $GeminiHome) 'safe-setup'
}

function Read-AgyJson {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    try {
        $content = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false))
        if (-not [string]::IsNullOrWhiteSpace($content)) {
            return ($content | ConvertFrom-Json)
        }
    }
    catch {
        return $null
    }
    return $null
}

function Write-AgyTextAtomic {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )

    $parentPath = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parentPath -PathType Container)) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }
    $temporaryPath = Join-Path $parentPath ('.agy-safe-setup-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporaryPath, $Text, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Write-AgyJsonAtomic {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Object,
        [int]$Depth = 10
    )
    $json = $Object | ConvertTo-Json -Depth $Depth
    Write-AgyTextAtomic -Path $Path -Text $json
}

function Test-AgySensitivePath {
    param([Parameter(Mandatory)][string]$Path)

    $normalized = ($Path -replace '\\', '/').ToLowerInvariant()
    $fileName = [IO.Path]::GetFileName($normalized)

    # 1. Exact sensitive file names
    $sensitiveNames = @(
        '.env', '.npmrc', '.pypirc', '.netrc', 'nuget.config',
        'credentials.json', 'service-account.json',
        'id_rsa', 'id_ed25519', 'id_ecdsa', 'id_dsa'
    )
    if ($sensitiveNames -contains $fileName) { return $true }

    # 2. Pattern matching
    if ($fileName.StartsWith('.env.') -or $fileName.StartsWith('.env_')) { return $true }
    if ($fileName.EndsWith('.pem') -or $fileName.EndsWith('.key') -or $fileName.EndsWith('.pfx') -or $fileName.EndsWith('.p12')) { return $true }

    # 3. Known sensitive directory segments
    $sensitiveDirs = @('/.ssh/', '/.aws/', '/.azure/', '/.config/gcloud/')
    foreach ($dir in $sensitiveDirs) {
        if ($normalized.Contains($dir) -or $normalized.EndsWith($dir.TrimEnd('/'))) {
            return $true
        }
    }

    return $false
}

function Get-AgyRepositoryRoot {
    param([Parameter(Mandatory)][string]$Path)

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $root = (& git -C $resolvedPath rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $root) {
        throw "Not a Git worktree: $resolvedPath"
    }
    return [IO.Path]::GetFullPath(($root | Select-Object -First 1).Trim())
}

function New-AgyCheckResult {
    param(
        [Parameter(Mandatory)][ValidateSet('PASS', 'PARTIAL', 'FAIL', 'NOT CONTROLLED')][string]$Status,
        [Parameter(Mandatory)][string]$Control,
        [Parameter(Mandatory)][string]$Evidence
    )
    return [pscustomobject]@{ Status = $Status; Control = $Control; Evidence = $Evidence }
}
