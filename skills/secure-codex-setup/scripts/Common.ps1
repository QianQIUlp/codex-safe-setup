Set-StrictMode -Version Latest

$script:CssManagedStart = '# >>> codex-safe-setup managed >>>'
$script:CssManagedEnd = '# <<< codex-safe-setup managed <<<'
$script:CssProfileName = 'codex-safe-workspace'

function Get-CssCodexHome {
    param([string]$Override)

    if ($Override) {
        return [IO.Path]::GetFullPath($Override)
    }
    if ($env:CODEX_HOME) {
        return [IO.Path]::GetFullPath($env:CODEX_HOME)
    }
    $userProfilePath = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    if (-not $userProfilePath) {
        throw 'Cannot determine the user profile. Pass -CodexHome explicitly.'
    }
    return Join-Path $userProfilePath '.codex'
}

function Get-CssConfigPath {
    param([string]$CodexHome, [string]$Override)

    if ($Override) {
        return [IO.Path]::GetFullPath($Override)
    }
    return Join-Path (Get-CssCodexHome -Override $CodexHome) 'config.toml'
}

function Get-CssStateRoot {
    param([string]$CodexHome, [string]$Override)

    if ($Override) {
        return [IO.Path]::GetFullPath($Override)
    }
    return Join-Path (Get-CssCodexHome -Override $CodexHome) 'safe-setup'
}

function Read-CssText {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ''
    }
    return [IO.File]::ReadAllText($Path)
}

function Write-CssTextAtomic {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )

    $parentPath = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parentPath -PathType Container)) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }
    $temporaryPath = Join-Path $parentPath ('.codex-safe-setup-' + [guid]::NewGuid().ToString('N') + '.tmp')
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

function ConvertTo-CssTomlString {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    return '"' + $escaped + '"'
}

function ConvertTo-CssForwardSlashPath {
    param([Parameter(Mandatory)][string]$Path)
    return ([IO.Path]::GetFullPath($Path) -replace '\\', '/')
}

function ConvertTo-CssStarlarkString {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    $escaped = $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n')
    return '"' + $escaped + '"'
}

function Remove-CssManagedBlock {
    param([AllowEmptyString()][string]$Text)

    $start = [regex]::Escape($script:CssManagedStart)
    $end = [regex]::Escape($script:CssManagedEnd)
    $pattern = '(?ms)^[ \t]*' + $start + '.*?^[ \t]*' + $end + '[ \t]*(?:\r?\n)?'
    return [regex]::Replace($Text, $pattern, '')
}

function Get-CssTomlSectionName {
    param([string]$Line)

    if ($Line -match '^\s*\[([^\[\]]+)\]\s*(?:#.*)?$') {
        return $Matches[1].Trim()
    }
    return $null
}

function Get-CssTomlSectionText {
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Section
    )

    $capturing = $false
    $resultLines = [Collections.Generic.List[string]]::new()
    foreach ($line in [regex]::Split($Text, '\r?\n')) {
        $parsedSection = Get-CssTomlSectionName -Line $line
        if ($null -ne $parsedSection) {
            if ($capturing) { break }
            $capturing = $parsedSection -eq $Section
            continue
        }
        if ($capturing) { $resultLines.Add($line) }
    }
    return $resultLines -join [Environment]::NewLine
}

function Remove-CssTomlTopLevelKeys {
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string[]]$Keys
    )

    $keySet = @{}
    foreach ($key in $Keys) { $keySet[$key] = $true }
    $sectionName = ''
    $resultLines = [Collections.Generic.List[string]]::new()
    foreach ($line in [regex]::Split($Text, '\r?\n')) {
        $parsedSection = Get-CssTomlSectionName -Line $line
        if ($null -ne $parsedSection) {
            $sectionName = $parsedSection
            $resultLines.Add($line)
            continue
        }
        if (-not $sectionName -and $line -match '^\s*([A-Za-z0-9_.-]+)\s*=') {
            if ($keySet.ContainsKey($Matches[1])) { continue }
        }
        $resultLines.Add($line)
    }
    return ($resultLines -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine
}

function Remove-CssTomlSections {
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string[]]$SectionPrefixes
    )

    $resultLines = [Collections.Generic.List[string]]::new()
    $skip = $false
    foreach ($line in [regex]::Split($Text, '\r?\n')) {
        $parsedSection = Get-CssTomlSectionName -Line $line
        if ($null -ne $parsedSection) {
            $skip = $false
            foreach ($prefix in $SectionPrefixes) {
                if ($parsedSection -eq $prefix -or $parsedSection.StartsWith($prefix + '.', [StringComparison]::Ordinal)) {
                    $skip = $true
                    break
                }
            }
        }
        if (-not $skip) { $resultLines.Add($line) }
    }
    return ($resultLines -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine
}

function Set-CssTomlTopLevelValue {
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Literal
    )

    $cleanText = Remove-CssTomlTopLevelKeys -Text $Text -Keys @($Key)
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in [regex]::Split($cleanText.TrimEnd(), '\r?\n')) { $lines.Add($line) }
    $insertAt = $lines.Count
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($null -ne (Get-CssTomlSectionName -Line $lines[$index])) {
            $insertAt = $index
            break
        }
    }
    $lines.Insert($insertAt, "$Key = $Literal")
    return ($lines -join [Environment]::NewLine).Trim() + [Environment]::NewLine
}

function Set-CssTomlSectionValue {
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Literal
    )

    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in [regex]::Split($Text.TrimEnd(), '\r?\n')) { $lines.Add($line) }
    $sectionStart = -1
    $sectionEnd = $lines.Count
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $parsedSection = Get-CssTomlSectionName -Line $lines[$index]
        if ($parsedSection -eq $Section) {
            $sectionStart = $index
            for ($next = $index + 1; $next -lt $lines.Count; $next++) {
                if ($null -ne (Get-CssTomlSectionName -Line $lines[$next])) {
                    $sectionEnd = $next
                    break
                }
            }
            break
        }
    }
    if ($sectionStart -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim()) { $lines.Add('') }
        $lines.Add("[$Section]")
        $lines.Add("$Key = $Literal")
        return ($lines -join [Environment]::NewLine).Trim() + [Environment]::NewLine
    }

    $keyPattern = '^\s*' + [regex]::Escape($Key) + '\s*='
    for ($index = $sectionStart + 1; $index -lt $sectionEnd; $index++) {
        if ($lines[$index] -match $keyPattern) {
            $lines[$index] = "$Key = $Literal"
            return ($lines -join [Environment]::NewLine).Trim() + [Environment]::NewLine
        }
    }
    $lines.Insert($sectionStart + 1, "$Key = $Literal")
    return ($lines -join [Environment]::NewLine).Trim() + [Environment]::NewLine
}

function Test-CssLegacySettings {
    param([AllowEmptyString()][string]$Text)

    $withoutManaged = Remove-CssManagedBlock -Text $Text
    $hasSandboxMode = $withoutManaged -match '(?m)^\s*sandbox_mode\s*='
    $hasWorkspaceSection = $withoutManaged -match '(?m)^\s*\[sandbox_workspace_write\]'
    return [pscustomobject]@{
        Present = [bool]($hasSandboxMode -or $hasWorkspaceSection)
        SandboxMode = [bool]$hasSandboxMode
        WorkspaceSection = [bool]$hasWorkspaceSection
    }
}

function Get-CssRepositoryRoot {
    param([Parameter(Mandatory)][string]$Path)

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $root = (& git -C $resolvedPath rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $root) {
        throw "Not a Git worktree: $resolvedPath"
    }
    return [IO.Path]::GetFullPath(($root | Select-Object -First 1).Trim())
}

function Test-CssSensitiveRelativePath {
    param([Parameter(Mandatory)][string]$Path)

    $normalized = ($Path -replace '\\', '/').ToLowerInvariant()
    $fileName = [IO.Path]::GetFileName($normalized)
    $sensitiveNames = @('.env', '.npmrc', '.pypirc', '.netrc', 'nuget.config', 'credentials.json', 'service-account.json', 'id_rsa', 'id_ed25519')
    if ($sensitiveNames -contains $fileName) { return $true }
    if ($fileName.StartsWith('.env.')) { return $true }
    if ($fileName.EndsWith('.pem') -or $fileName.EndsWith('.key') -or $fileName.EndsWith('.pfx') -or $fileName.EndsWith('.p12')) { return $true }
    return $false
}

function New-CssCheck {
    param(
        [Parameter(Mandatory)][ValidateSet('PASS', 'PARTIAL', 'FAIL', 'NOT CONTROLLED')][string]$Status,
        [Parameter(Mandatory)][string]$Control,
        [Parameter(Mandatory)][string]$Evidence
    )
    return [pscustomobject]@{ Status = $Status; Control = $Control; Evidence = $Evidence }
}
