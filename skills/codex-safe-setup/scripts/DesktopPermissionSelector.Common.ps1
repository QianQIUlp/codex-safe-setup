Set-StrictMode -Version Latest

$script:CssDesktopSelectorGate = '4226282475'
$script:CssDesktopSelectorStateFile = 'desktop-selector-fix.json'
$script:CssDesktopSelectorLocalStateFile = 'desktop-selector-state.json'
$script:CssDesktopSelectorLoaderFile = 'permission-selector-loader.cjs'
$script:CssDesktopSelectorPreloadFile = 'permission-selector-preload.cjs'
$script:CssDesktopSelectorLaunchMarkerPrefix = '--codex-safe-setup-selector-loader='
$script:CssDesktopSelectorStructureVersion = 1
$script:CssDesktopSelectorStructureAnchors = @(
    'useAppServerPermissionDefault',
    'permissionProfileId',
    'disableDefaultPermissions',
    'disableCustomPermissions'
)

function Test-CssPathWithin {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    $resolvedPath = [IO.Path]::GetFullPath($Path)
    $resolvedRoot = [IO.Path]::GetFullPath($Root)
    if ($resolvedPath.Equals($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $rootPrefix = $resolvedRoot.TrimEnd([char[]]@(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )) + [IO.Path]::DirectorySeparatorChar
    return $resolvedPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)
}

function Get-CssDesktopPackageInfo {
    param(
        [string]$InstallLocation,
        [string]$PackageVersion
    )

    $packageName = $null
    $packageFamilyName = $null
    $publisherId = $null
    $publisher = $null
    if ($InstallLocation) {
        $resolvedLocation = [IO.Path]::GetFullPath($InstallLocation)
        $manifestPath = Join-Path $resolvedLocation 'AppxManifest.xml'
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            [xml]$manifest = [IO.File]::ReadAllText($manifestPath)
            if (-not $PackageVersion) { $PackageVersion = [string]$manifest.Package.Identity.Version }
            $packageName = [string]$manifest.Package.Identity.Name
            $publisher = [string]$manifest.Package.Identity.Publisher
            $publisherIdProperty = $manifest.Package.Identity.PSObject.Properties['PublisherId']
            $publisherId = if ($null -ne $publisherIdProperty) { [string]$publisherIdProperty.Value } else { '' }
            $packageFamilyProperty = $manifest.Package.Identity.PSObject.Properties['PackageFamilyName']
            $packageFamilyName = if ($null -ne $packageFamilyProperty) { [string]$packageFamilyProperty.Value } else { '' }
            if (-not $publisherId -and $resolvedLocation -match '__([^\\]+)$') {
                $publisherId = $Matches[1]
            }
            if (-not $publisherId -and $packageFamilyName -match '_([^_]+)$') {
                $publisherId = $Matches[1]
            }
            if (-not $packageFamilyName -and $packageName -and $publisherId) {
                $packageFamilyName = $packageName + '_' + $publisherId
            }
        }
        if (-not $PackageVersion) {
            throw 'Pass -PackageVersion when -InstallLocation does not contain a readable AppxManifest.xml.'
        }
    }
    else {
        if ($env:OS -ne 'Windows_NT') {
            throw 'The Desktop permission-selector compatibility fix is Windows-only.'
        }
        $package = Get-AppxPackage -Name OpenAI.Codex -ErrorAction Stop |
            Sort-Object Version -Descending |
            Select-Object -First 1
        if ($null -eq $package) {
            throw 'The signed OpenAI.Codex Desktop package is not installed.'
        }
        if ($package.PackageFamilyName -notlike 'OpenAI.Codex_*') {
            throw "Unexpected Codex package family: $($package.PackageFamilyName)"
        }
        $resolvedLocation = [IO.Path]::GetFullPath([string]$package.InstallLocation)
        $PackageVersion = [string]$package.Version
        $packageName = [string]$package.Name
        $packageFamilyName = [string]$package.PackageFamilyName
        $publisherIdProperty = $package.PSObject.Properties['PublisherId']
        $publisherId = if ($null -ne $publisherIdProperty) { [string]$publisherIdProperty.Value } else { '' }
        if (-not $publisherId -and $packageFamilyName -match '_([^_]+)$') {
            $publisherId = $Matches[1]
        }
        $publisher = [string]$package.Publisher
    }

    $executable = Join-Path $resolvedLocation 'app\ChatGPT.exe'
    $codexCli = Join-Path $resolvedLocation 'app\resources\codex.exe'
    $asarPath = Join-Path $resolvedLocation 'app\resources\app.asar'
    foreach ($requiredPath in @($executable, $codexCli, $asarPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "The installed Codex package is missing a required file: $requiredPath"
        }
    }

    return [pscustomobject]@{
        Version = $PackageVersion
        InstallLocation = $resolvedLocation
        ExecutablePath = $executable
        CodexCliPath = $codexCli
        AsarPath = $asarPath
        AsarUnpackedPath = $asarPath + '.unpacked'
        PackageName = $packageName
        PackageFamilyName = $packageFamilyName
        PublisherId = $publisherId
        Publisher = $publisher
    }
}

function Read-CssAsarHeader {
    param([Parameter(Mandatory)][string]$ArchivePath)

    $resolvedArchive = (Resolve-Path -LiteralPath $ArchivePath -ErrorAction Stop).Path
    $stream = [IO.File]::OpenRead($resolvedArchive)
    try {
        if ($stream.Length -lt 16) { throw 'ASAR archive is too short.' }
        $prefix = New-Object byte[] 16
        if ($stream.Read($prefix, 0, $prefix.Length) -ne $prefix.Length) {
            throw 'Could not read the ASAR header.'
        }
        $sizePayloadLength = [BitConverter]::ToUInt32($prefix, 0)
        $headerPickleSize = [BitConverter]::ToUInt32($prefix, 4)
        $headerPayloadSize = [BitConverter]::ToUInt32($prefix, 8)
        $jsonLength = [BitConverter]::ToUInt32($prefix, 12)
        if ($sizePayloadLength -ne 4 -or $headerPickleSize -lt 8 -or $headerPayloadSize + 4 -ne $headerPickleSize) {
            throw 'Unsupported ASAR pickle header.'
        }
        if ($jsonLength -eq 0 -or $jsonLength -gt ($headerPayloadSize - 4)) {
            throw 'Invalid ASAR JSON header length.'
        }
        $contentOffset = [long]8 + [long]$headerPickleSize
        if ($contentOffset -gt $stream.Length) {
            throw 'ASAR content offset is outside the archive.'
        }
        $jsonBytes = New-Object byte[] ([int]$jsonLength)
        if ($stream.Read($jsonBytes, 0, $jsonBytes.Length) -ne $jsonBytes.Length) {
            throw 'Could not read the complete ASAR JSON header.'
        }
        $header = [Text.Encoding]::UTF8.GetString($jsonBytes) | ConvertFrom-Json -Depth 200
        if ($null -eq $header.PSObject.Properties['files']) {
            throw 'ASAR header does not contain a files tree.'
        }
        return [pscustomobject]@{
            ArchivePath = $resolvedArchive
            ArchiveLength = $stream.Length
            ContentOffset = $contentOffset
            Header = $header
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Test-CssAsarEntryName {
    param([Parameter(Mandatory)][string]$Name)

    if (-not $Name -or $Name -eq '.' -or $Name -eq '..' -or $Name.Contains('/') -or $Name.Contains('\')) {
        return $false
    }
    if ($Name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
        $Name.TrimEnd([char[]]@(' ', '.')).Length -ne $Name.Length) {
        return $false
    }
    $baseName = ($Name -split '\.', 2)[0].ToUpperInvariant()
    if ($baseName -in @('CON', 'PRN', 'AUX', 'NUL') -or $baseName -match '^(?:COM|LPT)[1-9]$') {
        return $false
    }
    return $true
}

function Get-CssFileSha256 {
    param([Parameter(Mandatory)][string]$Path)

    $stream = [IO.File]::OpenRead($Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}

function Get-CssNodeRequirePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if ($resolved -notmatch '\s') { return $resolved }
    if ($env:OS -ne 'Windows_NT') {
        throw 'The Desktop loader path contains whitespace and cannot be represented in NODE_OPTIONS.'
    }
    if ($null -eq ('CssDesktopNativePath' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Text;
using System.Runtime.InteropServices;
public static class CssDesktopNativePath {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint GetShortPathName(string longPath, StringBuilder shortPath, uint bufferLength);
}
'@
    }
    $buffer = [Text.StringBuilder]::new(32768)
    $length = [CssDesktopNativePath]::GetShortPathName($resolved, $buffer, [uint32]$buffer.Capacity)
    $shortPath = $buffer.ToString()
    if ($length -eq 0 -or -not $shortPath -or $shortPath -match '\s' -or
        -not (Test-Path -LiteralPath $shortPath -PathType Leaf)) {
        throw 'The Desktop loader path contains whitespace and Windows did not provide a usable short path. Choose a DestinationRoot without whitespace.'
    }
    return $shortPath
}

function Test-CssStreamRangeContainsText {
    param(
        [Parameter(Mandatory)][IO.Stream]$Stream,
        [Parameter(Mandatory)][long]$Offset,
        [Parameter(Mandatory)][long]$Length,
        [Parameter(Mandatory)][string]$Needle
    )

    if ($Length -lt 0 -or $Offset -lt 0 -or $Offset + $Length -gt $Stream.Length) {
        throw 'Requested stream range is invalid.'
    }
    if (-not $Needle) { throw 'Search text must not be empty.' }
    $Stream.Position = $Offset
    $buffer = New-Object byte[] (1024 * 1024)
    $carry = ''
    [long]$remaining = $Length
    while ($remaining -gt 0) {
        $requested = [int][Math]::Min([long]$buffer.Length, $remaining)
        $read = $Stream.Read($buffer, 0, $requested)
        if ($read -le 0) { throw 'Unexpected end of ASAR entry data.' }
        $text = $carry + [Text.Encoding]::ASCII.GetString($buffer, 0, $read)
        if ($text.IndexOf($Needle, [StringComparison]::Ordinal) -ge 0) { return $true }
        $carryLength = [Math]::Min([Math]::Max(0, $Needle.Length - 1), $text.Length)
        $carry = if ($carryLength -gt 0) { $text.Substring($text.Length - $carryLength) } else { '' }
        $remaining -= $read
    }
    return $false
}

function Find-CssAsarText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$Needle,
        [string]$PathPattern = '^webview/assets/.+\.js$',
        [int]$MaxMatches = 8
    )

    $archive = Read-CssAsarHeader -ArchivePath $ArchivePath
    $archiveStream = [IO.File]::OpenRead($archive.ArchivePath)
    $unpackedRoot = [IO.Path]::GetFullPath($archive.ArchivePath + '.unpacked')
    $unpackedPrefix = $unpackedRoot.TrimEnd([char[]]@(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )) + [IO.Path]::DirectorySeparatorChar
    $found = [Collections.Generic.List[object]]::new()

    function Search-CssAsarNode {
        param($Node, [string]$RelativePath)

        foreach ($property in $Node.files.PSObject.Properties) {
            if ($found.Count -ge $MaxMatches) { return }
            if (-not (Test-CssAsarEntryName -Name $property.Name)) {
                throw "Unsafe ASAR entry name: $($property.Name)"
            }
            $entryRelativePath = if ($RelativePath) { "$RelativePath/$($property.Name)" } else { $property.Name }
            $entry = $property.Value
            if ($null -ne $entry.PSObject.Properties['files']) {
                Search-CssAsarNode -Node $entry -RelativePath $entryRelativePath
                continue
            }
            if ($null -ne $entry.PSObject.Properties['link']) {
                throw "ASAR links are not supported by the selector verifier: $entryRelativePath"
            }
            if ($entryRelativePath -notmatch $PathPattern) { continue }
            if ($null -eq $entry.PSObject.Properties['size']) {
                throw "ASAR file entry has no size: $entryRelativePath"
            }
            [long]$size = $entry.size
            $isUnpacked = $null -ne $entry.PSObject.Properties['unpacked'] -and [bool]$entry.unpacked
            $matched = $false
            if ($isUnpacked) {
                $sourcePath = [IO.Path]::GetFullPath((Join-Path $unpackedRoot ($entryRelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)))
                if (-not $sourcePath.StartsWith($unpackedPrefix, [StringComparison]::OrdinalIgnoreCase) -or
                    -not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                    throw "ASAR unpacked file is missing or unsafe: $entryRelativePath"
                }
                $sourceStream = [IO.File]::OpenRead($sourcePath)
                try { $matched = Test-CssStreamRangeContainsText -Stream $sourceStream -Offset 0 -Length $sourceStream.Length -Needle $Needle }
                finally { $sourceStream.Dispose() }
            }
            else {
                if ($null -eq $entry.PSObject.Properties['offset']) {
                    throw "Packed ASAR file entry has no offset: $entryRelativePath"
                }
                [long]$absoluteOffset = $archive.ContentOffset + [long]$entry.offset
                if ($size -lt 0 -or $absoluteOffset -lt $archive.ContentOffset -or $absoluteOffset + $size -gt $archive.ArchiveLength) {
                    throw "Packed ASAR file range is invalid: $entryRelativePath"
                }
                $matched = Test-CssStreamRangeContainsText -Stream $archiveStream -Offset $absoluteOffset -Length $size -Needle $Needle
            }
            if (-not $matched) { continue }
            if ($null -eq $entry.PSObject.Properties['integrity'] -or
                [string]$entry.integrity.algorithm -ne 'SHA256' -or
                -not [string]$entry.integrity.hash) {
                throw "Matched selector asset has no supported SHA-256 integrity record: $entryRelativePath"
            }
            $found.Add([pscustomobject]@{
                RelativePath = $entryRelativePath
                Size = $size
                Unpacked = $isUnpacked
                IntegritySha256 = ([string]$entry.integrity.hash).ToLowerInvariant()
            })
        }
    }

    try { Search-CssAsarNode -Node $archive.Header -RelativePath '' }
    finally { $archiveStream.Dispose() }
    return @($found)
}

function Get-CssDesktopSelectorSourceEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ArchivePath)

    $matches = @(Find-CssAsarText -ArchivePath $ArchivePath -Needle $script:CssDesktopSelectorGate)
    if ($matches.Count -eq 0) {
        throw "This Desktop build does not contain the tested selector gate $($script:CssDesktopSelectorGate). Refusing to install the loader."
    }
    $anchorEvidence = [Collections.Generic.List[object]]::new()
    foreach ($anchor in $script:CssDesktopSelectorStructureAnchors) {
        $anchorMatches = @(Find-CssAsarText -ArchivePath $ArchivePath -Needle $anchor)
        if ($anchorMatches.Count -eq 0) {
            throw "This Desktop build is missing selector structure anchor '$anchor'. Refusing to install or recertify the loader."
        }
        $anchorEvidence.Add([pscustomobject]@{
            Anchor = $anchor
            MatchCount = $anchorMatches.Count
            Assets = @($anchorMatches | ForEach-Object RelativePath | Sort-Object -Unique)
        })
    }
    return [pscustomobject]@{
        SelectorGate = $script:CssDesktopSelectorGate
        MatchCount = $matches.Count
        Assets = $matches
        StructureVersion = $script:CssDesktopSelectorStructureVersion
        StructureAnchors = @($anchorEvidence)
    }
}

function Write-CssFileTextAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Text
    )

    $resolvedPath = [IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $resolvedPath
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporaryPath = Join-Path $directory ('.' + [IO.Path]::GetFileName($resolvedPath) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $backupPath = Join-Path $directory ('.' + [IO.Path]::GetFileName($resolvedPath) + '.' + [guid]::NewGuid().ToString('N') + '.bak')
    try {
        [IO.File]::WriteAllText($temporaryPath, $Text, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
            [IO.File]::Replace($temporaryPath, $resolvedPath, $backupPath)
        }
        else {
            [IO.File]::Move($temporaryPath, $resolvedPath)
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-CssDesktopRootProcesses {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ExecutablePath)

    if ($env:OS -ne 'Windows_NT') { return @() }
    $resolvedExecutable = [IO.Path]::GetFullPath($ExecutablePath)
    $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $_.ExecutablePath -and
        [IO.Path]::GetFullPath([string]$_.ExecutablePath).Equals($resolvedExecutable, [StringComparison]::OrdinalIgnoreCase)
    })
    $processIds = @($processes | ForEach-Object { [int]$_.ProcessId })
    return @($processes | Where-Object { $_.ParentProcessId -notin $processIds })
}

function Test-CssDesktopProcessRecord {
    param(
        [Parameter(Mandatory)]$Process,
        [Parameter(Mandatory)]$Record
    )

    return [int]$Process.ProcessId -eq [int]$Record.processId -and
        [string]$Process.CreationDate -eq [string]$Record.creationDate
}

function Stop-CssDesktopSelectorWatcher {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DestinationRoot)

    if ($env:OS -ne 'Windows_NT') { return 0 }
    $watcherPath = [IO.Path]::GetFullPath((Join-Path $DestinationRoot 'Watch-CodexDesktop.ps1'))
    $matches = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -in @('powershell.exe', 'pwsh.exe') -and
        ([string]$_.CommandLine).IndexOf($watcherPath, [StringComparison]::OrdinalIgnoreCase) -ge 0
    })
    foreach ($process in $matches) {
        Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction Stop
    }
    return $matches.Count
}

function Get-CssDesktopSelectorLegacyShortcuts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LegacyRoot,
        [string[]]$StartupDirectories
    )

    if ($env:OS -ne 'Windows_NT') { return @() }
    $legacyVbs = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath($LegacyRoot)) 'Watch-CodexDesktop.vbs'))
    $normalizedNeedle = $legacyVbs.Replace('/', '\').ToLowerInvariant()
    $folders = if ($StartupDirectories) {
        @($StartupDirectories | Where-Object { $_ })
    }
    else {
        @(
            [Environment]::GetFolderPath('Startup'),
            [Environment]::GetFolderPath('CommonStartup')
        ) | Where-Object { $_ }
    }
    $folders = @($folders | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | Select-Object -Unique)
    $shell = New-Object -ComObject WScript.Shell
    $entries = [Collections.Generic.List[object]]::new()
    foreach ($folder in $folders) {
        $shortcutFiles = @(Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -File -ErrorAction SilentlyContinue)
        foreach ($file in $shortcutFiles) {
            try { $shortcut = $shell.CreateShortcut($file.FullName) } catch { continue }
            $target = [string]$shortcut.TargetPath
            if (-not $target) { continue }
            $targetName = [IO.Path]::GetFileName($target)
            if (-not $targetName.Equals('wscript.exe', [StringComparison]::OrdinalIgnoreCase)) { continue }
            $flatArguments = ([string]$shortcut.Arguments).Replace('"', '').Replace('/', '\').ToLowerInvariant()
            if (-not $flatArguments.Contains($normalizedNeedle)) { continue }
            $entries.Add([pscustomobject]@{
                Path = $file.FullName
                TargetPath = $target
                Arguments = [string]$shortcut.Arguments
                WorkingDirectory = [string]$shortcut.WorkingDirectory
                Description = [string]$shortcut.Description
                CreationTimeUtc = $file.CreationTimeUtc.ToString('o')
                LastWriteTimeUtc = $file.LastWriteTimeUtc.ToString('o')
            })
        }
    }
    return @($entries)
}

function Protect-CssDesktopSelectorLegacyShortcutArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Entry,
        [Parameter(Mandatory)][string]$HistoryRoot,
        [Parameter(Mandatory)][string]$TimestampUtc
    )

    $archiveDir = Join-Path ([IO.Path]::GetFullPath($HistoryRoot)) ($TimestampUtc + '-legacy-autostart')
    New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
    $sourceItem = Get-Item -LiteralPath ([string]$Entry.Path) -Force
    Copy-Item -LiteralPath $sourceItem.FullName -Destination (Join-Path $archiveDir $sourceItem.Name) -Force
    $metadata = [ordered]@{
        archivedUtc = (Get-Date).ToUniversalTime().ToString('o')
        originalPath = [string]$Entry.Path
        targetPath = [string]$Entry.TargetPath
        arguments = [string]$Entry.Arguments
        workingDirectory = [string]$Entry.WorkingDirectory
        description = [string]$Entry.Description
        creationTimeUtc = [string]$Entry.CreationTimeUtc
        lastWriteTimeUtc = [string]$Entry.LastWriteTimeUtc
        sha256 = (Get-CssFileSha256 -Path $sourceItem.FullName)
    }
    [IO.File]::WriteAllText(
        (Join-Path $archiveDir ($sourceItem.BaseName + '.metadata.json')),
        ($metadata | ConvertTo-Json -Depth 6),
        [Text.UTF8Encoding]::new($false)
    )
    return $archiveDir
}

function Remove-CssDesktopSelectorLegacyShortcuts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LegacyRoot,
        [Parameter(Mandatory)][string]$HistoryRoot,
        [string[]]$StartupDirectories
    )

    $timestampUtc = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
    $removed = [Collections.Generic.List[string]]::new()
    foreach ($entry in @(Get-CssDesktopSelectorLegacyShortcuts -LegacyRoot $LegacyRoot -StartupDirectories $StartupDirectories)) {
        Protect-CssDesktopSelectorLegacyShortcutArchive -Entry $entry -HistoryRoot $HistoryRoot -TimestampUtc $timestampUtc | Out-Null
        Remove-Item -LiteralPath ([string]$entry.Path) -Force -ErrorAction Stop
        $removed.Add([string]$entry.Path)
    }
    return @($removed)
}

function Invoke-CssDesktopSelectorNodeOptionsProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ExecutablePath,
        [Parameter(Mandatory)][string]$LoaderPath,
        [Parameter(Mandatory)][string]$PreloadPath,
        [Parameter(Mandatory)][string]$PreloadSha256,
        [int]$TimeoutSeconds = 12
    )

    $probeRoot = Join-Path ([IO.Path]::GetTempPath()) ('css-desktop-loader-probe-' + [guid]::NewGuid().ToString('N'))
    $statusPath = Join-Path $probeRoot 'probe-status.json'
    New-Item -ItemType Directory -Path $probeRoot -Force | Out-Null
    try {
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = [IO.Path]::GetFullPath($ExecutablePath)
        $startInfo.Arguments = '--user-data-dir="' + $probeRoot + '"'
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
        $startInfo.EnvironmentVariables['NODE_OPTIONS'] = '--require=' + (Get-CssNodeRequirePath -Path $LoaderPath)
        $startInfo.EnvironmentVariables['CSS_DESKTOP_SELECTOR_PRELOAD'] = [IO.Path]::GetFullPath($PreloadPath)
        $startInfo.EnvironmentVariables['CSS_DESKTOP_SELECTOR_PRELOAD_SHA256'] = $PreloadSha256
        $startInfo.EnvironmentVariables['CSS_DESKTOP_SELECTOR_STATUS_PATH'] = $statusPath
        $startInfo.EnvironmentVariables['CSS_DESKTOP_SELECTOR_PROBE_MODE'] = 'electron-hook'
        $process = [Diagnostics.Process]::Start($startInfo)
        if ($null -eq $process) { throw 'Could not start the Desktop loader probe.' }
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $completed) {
            try { $process.Kill() } catch { }
            throw 'Desktop loader probe timed out.'
        }
        if (-not (Test-Path -LiteralPath $statusPath -PathType Leaf)) {
            throw "Desktop loader probe produced no status (exit $($process.ExitCode))."
        }
        $status = [IO.File]::ReadAllText($statusPath) | ConvertFrom-Json -Depth 10
        if ($process.ExitCode -ne 0 -or [string]$status.status -ne 'PROBE_PASS') {
            throw "Desktop loader probe failed (exit $($process.ExitCode), status $($status.status))."
        }
        return $status
    }
    finally {
        if (Test-Path -LiteralPath $probeRoot) {
            $resolvedProbe = [IO.Path]::GetFullPath($probeRoot)
            $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
            if (-not (Test-CssPathWithin -Path $resolvedProbe -Root $resolvedTemp) -or
                $resolvedProbe.Equals($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to remove unexpected loader probe path: $resolvedProbe"
            }
            Remove-Item -LiteralPath $resolvedProbe -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
