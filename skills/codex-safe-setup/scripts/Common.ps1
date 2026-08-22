Set-StrictMode -Version Latest

$script:CssStateSchemaVersion = 9
$script:CssProductVersion = '0.3.0'
$script:CssManagedStart = '# >>> codex-safe-setup managed >>>'
$script:CssManagedEnd = '# <<< codex-safe-setup managed <<<'
$script:CssProfileName = 'codex-safe-workspace'
$script:CssOfflineProfileName = 'codex-safe-workspace-offline'

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

function Get-CssFileTextSha256 {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Invoke-CssGuardedConfigWrite {
    <#
    Replaces a configuration file only when the on-disk bytes still match the
    content the plan was generated from, and verifies the written bytes
    afterwards. Any mismatch aborts without touching the file, or restores the
    exact previous bytes when the verification fails after writing.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ExpectedOriginalSha256,
        [Parameter(Mandatory)][AllowEmptyString()][string]$NewText
    )

    $originalBytes = $null
    $fileExists = Test-Path -LiteralPath $Path -PathType Leaf
    if ($fileExists) {
        $currentBytes = [IO.File]::ReadAllBytes($Path)
        $originalBytes = $currentBytes
        $currentText = [Text.UTF8Encoding]::new($false, $true).GetString($currentBytes)
        if ((Get-CssFileTextSha256 -Text $currentText) -ne $ExpectedOriginalSha256.ToLowerInvariant()) {
            throw ("CONCURRENT_MODIFICATION: '{0}' changed since the plan was generated. Re-run the plan against the current content." -f $Path)
        }
    }

    Write-CssTextAtomic -Path $Path -Text $NewText

    try {
        $writtenBytes = [IO.File]::ReadAllBytes($Path)
        $writtenText = [Text.UTF8Encoding]::new($false, $true).GetString($writtenBytes)
        if ((Get-CssFileTextSha256 -Text $writtenText) -ne (Get-CssFileTextSha256 -Text $NewText)) {
            throw 'POST_WRITE_VERIFICATION_FAILED'
        }
    }
    catch {
        if ($null -ne $originalBytes) {
            [IO.File]::WriteAllBytes($Path, $originalBytes)
        }
        elseif (Test-Path -LiteralPath $Path -PathType Leaf) {
            Remove-Item -LiteralPath $Path -Force
        }
        throw
    }
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

    if ($Line -match '^\s*\[\[([^\[\]]+)\]\]\s*(?:#.*)?$') {
        return '__array__:' + $Matches[1].Trim()
    }
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
    $nl = Get-CssTomlNewlineStyle -Text $Text
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
    return ($resultLines -join $nl).TrimEnd() + $nl
}

function Remove-CssTomlSectionKeys {
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string[]]$Keys
    )

    $keySet = @{}
    foreach ($key in $Keys) { $keySet[$key] = $true }
    $currentSection = ''
    $resultLines = [Collections.Generic.List[string]]::new()
    $nl = Get-CssTomlNewlineStyle -Text $Text
    foreach ($line in [regex]::Split($Text, '\r?\n')) {
        $parsedSection = Get-CssTomlSectionName -Line $line
        if ($null -ne $parsedSection) {
            $currentSection = $parsedSection
            $resultLines.Add($line)
            continue
        }
        if ($currentSection -eq $Section -and $line -match '^\s*([A-Za-z0-9_.-]+)\s*=') {
            if ($keySet.ContainsKey($Matches[1])) { continue }
        }
        $resultLines.Add($line)
    }
    return ($resultLines -join $nl).TrimEnd() + $nl
}

function Get-CssTomlTopLevelStringValue {
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Key
    )

    $topLevel = $true
    $keyPattern = '^\s*' + [regex]::Escape($Key) + '\s*=\s*(?<quote>["''])(?<value>[^"'']*)\k<quote>\s*(?:#.*)?$'
    foreach ($line in [regex]::Split($Text, '\r?\n')) {
        $parsedSection = Get-CssTomlSectionName -Line $line
        if ($null -ne $parsedSection) {
            $topLevel = $false
            continue
        }
        if (-not $topLevel) { continue }

        $match = [regex]::Match($line, $keyPattern)
        if ($match.Success) {
            return [pscustomobject]@{ Present = $true; Value = $match.Groups['value'].Value }
        }
    }
    return [pscustomobject]@{ Present = $false; Value = $null }
}

function Get-CssPermissionProfileSettings {
    param([AllowEmptyString()][string]$Text)

    $defaultSetting = Get-CssTomlTopLevelStringValue -Text $Text -Key 'default_permissions'
    $managedProfilePresent = $Text -match '(?m)^\s*\[permissions\.codex-safe-workspace(?:\.|\])'
    $offlineProfilePresent = $Text -match '(?m)^\s*\[permissions\.codex-safe-workspace-offline(?:\.|\])'
    return [pscustomobject]@{
        DefaultPresent = [bool]$defaultSetting.Present
        DefaultProfile = $defaultSetting.Value
        ManagedProfilePresent = [bool]$managedProfilePresent
        OfflineProfilePresent = [bool]$offlineProfilePresent
    }
}

function Remove-CssTomlSections {
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string[]]$SectionPrefixes
    )

    $resultLines = [Collections.Generic.List[string]]::new()
    $skip = $false
    $nl = Get-CssTomlNewlineStyle -Text $Text
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
    return ($resultLines -join $nl).TrimEnd() + $nl
}

function Set-CssTomlTopLevelValue {
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Literal
    )

    $cleanText = Remove-CssTomlTopLevelKeys -Text $Text -Keys @($Key)
    $nl = Get-CssTomlNewlineStyle -Text $cleanText
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
    return ($lines -join $nl).Trim() + $nl
}

function Set-CssTomlSectionValue {
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Literal
    )

    $nl = Get-CssTomlNewlineStyle -Text $Text
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
        return ($lines -join $nl).Trim() + $nl
    }

    $keyPattern = '^\s*' + [regex]::Escape($Key) + '\s*='
    for ($index = $sectionStart + 1; $index -lt $sectionEnd; $index++) {
        if ($lines[$index] -match $keyPattern) {
            $lines[$index] = "$Key = $Literal"
            return ($lines -join $nl).Trim() + $nl
        }
    }
    $lines.Insert($sectionStart + 1, "$Key = $Literal")
    return ($lines -join $nl).Trim() + $nl
}

function Test-CssLegacySettings {
    param([AllowEmptyString()][string]$Text)

    $sandboxModeSetting = Get-CssTomlTopLevelStringValue -Text $Text -Key 'sandbox_mode'
    $hasWorkspaceSection = $false
    foreach ($line in [regex]::Split($Text, '\r?\n')) {
        if ((Get-CssTomlSectionName -Line $line) -eq 'sandbox_workspace_write') {
            $hasWorkspaceSection = $true
            break
        }
    }
    return [pscustomobject]@{
        Present = [bool]($sandboxModeSetting.Present -or $hasWorkspaceSection)
        SandboxMode = [bool]$sandboxModeSetting.Present
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

function ConvertTo-CssNormalizedPortSet {
    param([AllowEmptyString()][string]$Ports)

    if (-not $Ports) { return '' }
    $normalized = @(
        $Ports -split ',' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^\d+$' } |
            ForEach-Object { [int]$_ } |
            Sort-Object -Unique
    )
    return $normalized -join ','
}

function Get-CssWindowsSandboxSetupHealth {
    param(
        [Parameter(Mandatory)][string]$CodexHome,
        [int[]]$ExpectedProxyPort = @()
    )

    $expected = ConvertTo-CssNormalizedPortSet -Ports ($ExpectedProxyPort -join ',')
    $expectedLabel = if ($expected) { $expected } else { '<none>' }
    $emptyResult = [ordered]@{
        Available = $false
        Status = 'UNAVAILABLE'
        EventCount = 0
        PortOscillationDetected = $false
        LatestStoredPorts = $null
        LatestDesiredPorts = $null
        ExpectedProxyPorts = $expectedLabel
        LatestDesiredMatchesExpected = $null
        Evidence = 'No readable Windows sandbox setup log was found.'
    }
    if ($env:OS -ne 'Windows_NT') {
        $emptyResult.Status = 'NOT_APPLICABLE'
        $emptyResult.Evidence = 'Windows sandbox setup telemetry is not applicable on this platform.'
        return [pscustomobject]$emptyResult
    }

    $sandboxRoot = Join-Path $CodexHome '.sandbox'
    try {
        $logFiles = @(Get-ChildItem -LiteralPath $sandboxRoot -Filter 'sandbox*.log' -File -ErrorAction Stop | Sort-Object LastWriteTimeUtc, FullName)
    }
    catch {
        return [pscustomobject]$emptyResult
    }
    if ($logFiles.Count -eq 0) { return [pscustomobject]$emptyResult }

    $events = [Collections.Generic.List[object]]::new()
    $pattern = '^\[(?<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?) [^\]]+\] sandbox setup required: offline firewall settings changed \(stored_ports=\[(?<stored>[^\]]*)\], desired_ports=\[(?<desired>[^\]]*)\],'
    foreach ($logFile in $logFiles) {
        try {
            foreach ($line in [IO.File]::ReadLines($logFile.FullName)) {
                $match = [regex]::Match($line, $pattern)
                if (-not $match.Success) { continue }
                $events.Add([pscustomobject]@{
                    Timestamp = $match.Groups['timestamp'].Value
                    StoredPorts = ConvertTo-CssNormalizedPortSet -Ports $match.Groups['stored'].Value
                    DesiredPorts = ConvertTo-CssNormalizedPortSet -Ports $match.Groups['desired'].Value
                })
            }
        }
        catch {
            # Keep any safely extracted setup events from other readable logs.
        }
    }

    if ($events.Count -eq 0) {
        $emptyResult.Available = $true
        $emptyResult.Status = 'NO_EVENTS'
        $emptyResult.Evidence = 'Sandbox logs are readable, but no firewall port-change setup event was found.'
        return [pscustomobject]$emptyResult
    }

    $oscillation = $false
    for ($index = 1; $index -lt $events.Count; $index++) {
        $previous = $events[$index - 1]
        $current = $events[$index]
        if ($previous.StoredPorts -eq $current.DesiredPorts -and $previous.DesiredPorts -eq $current.StoredPorts -and $previous.StoredPorts -ne $previous.DesiredPorts) {
            $oscillation = $true
            break
        }
    }

    $latest = $events[$events.Count - 1]
    $matchesExpected = $latest.DesiredPorts -eq $expected
    $status = if (-not $matchesExpected) { 'CONFLICT' } elseif ($oscillation) { 'OSCILLATION_HISTORY' } else { 'ALIGNED' }
    $evidence = "Observed $($events.Count) firewall port-change setup event(s); latest stored [$($latest.StoredPorts)] -> desired [$($latest.DesiredPorts)]."
    $evidence += " Managed proxy expectation: [$expectedLabel]."
    if ($oscillation) { $evidence += ' A direct port-set reversal was detected; stale or concurrent Codex processes can repeatedly invalidate elevated setup.' }

    return [pscustomobject]@{
        Available = $true
        Status = $status
        EventCount = $events.Count
        PortOscillationDetected = $oscillation
        LatestStoredPorts = $latest.StoredPorts
        LatestDesiredPorts = $latest.DesiredPorts
        ExpectedProxyPorts = $expectedLabel
        LatestDesiredMatchesExpected = $matchesExpected
        Evidence = $evidence
    }
}

function New-CssCheck {
    param(
        [Parameter(Mandatory)][ValidateSet('PASS', 'PARTIAL', 'FAIL', 'NOT CONTROLLED')][string]$Status,
        [Parameter(Mandatory)][string]$Control,
        [Parameter(Mandatory)][string]$Evidence
    )
    return [pscustomobject]@{ Status = $Status; Control = $Control; Evidence = $Evidence }
}

# Structural TOML editing and managed-region ownership (v0.3.0+).
$tomlEditorScript = Join-Path $PSScriptRoot 'TomlConfigEditor.ps1'
if (Test-Path -LiteralPath $tomlEditorScript -PathType Leaf) {
    . $tomlEditorScript
}
