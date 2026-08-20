[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [string]$Version,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repositoryRoot '.codex-plugin/plugin.json'
$manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = [string]$manifest.version
}
if ($Version -ne [string]$manifest.version) {
    throw "Requested version '$Version' does not match plugin manifest version '$($manifest.version)'."
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repositoryRoot 'dist'
}

[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$resolvedOutput = (Resolve-Path -LiteralPath $OutputDirectory).Path
$archivePath = Join-Path $resolvedOutput ("codex-safe-setup-v{0}.zip" -f $Version)
$checksumPath = $archivePath + '.sha256'
$existingOutputs = @(@($archivePath, $checksumPath) | Where-Object { Test-Path -LiteralPath $_ })
if ($existingOutputs.Count -gt 0) {
    if (-not $Force) {
        throw "Release output already exists: $($existingOutputs -join ', '). Use -Force to replace only these exact files."
    }
    foreach ($existingOutput in $existingOutputs) {
        Remove-Item -LiteralPath $existingOutput -Force
    }
}

$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$stagingPath = Join-Path $temporaryRoot ("codex-safe-setup-package-{0}" -f [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $stagingPath)

try {
    foreach ($directory in @('.codex-plugin', 'skills')) {
        Copy-Item -LiteralPath (Join-Path $repositoryRoot $directory) -Destination $stagingPath -Recurse -Force
    }
    foreach ($file in @('README.md', 'README.zh-CN.md', 'LICENSE', 'PRIVACY.md', 'SECURITY.md')) {
        Copy-Item -LiteralPath (Join-Path $repositoryRoot $file) -Destination $stagingPath -Force
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory(
        $stagingPath,
        $archivePath,
        [IO.Compression.CompressionLevel]::Optimal,
        $false
    )

    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $entryNames = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
        if ($entryNames -notcontains '.codex-plugin/plugin.json') {
            throw 'Built archive is missing .codex-plugin/plugin.json.'
        }
        if ($entryNames -notcontains 'skills/codex-safe-setup/SKILL.md') {
            throw 'Built archive is missing the codex-safe-setup skill.'
        }
        if ($entryNames -notcontains 'skills/secure-codex-setup/SKILL.md') {
            throw 'Built archive is missing the one-release compatibility alias.'
        }
        if ($entryNames -notcontains 'skills/codex-safe-setup/scripts/Upgrade-CodexSafety.ps1') {
            throw 'Built archive is missing the versioned upgrade entry point.'
        }
        if ($entryNames -notcontains 'skills/codex-safe-setup/scripts/Test-DesktopPermissionE2E.ps1') {
            throw 'Built archive is missing the real Desktop end-to-end verifier.'
        }
        foreach ($requiredEntry in @(
            'skills/codex-safe-setup/scripts/Install-DesktopPermissionSelectorFix.ps1',
            'skills/codex-safe-setup/scripts/Test-DesktopPermissionSelectorFix.ps1',
            'skills/codex-safe-setup/scripts/Rollback-DesktopPermissionSelectorFix.ps1',
            'skills/codex-safe-setup/assets/desktop-permission-selector/permission-selector-loader.cjs',
            'skills/codex-safe-setup/assets/desktop-permission-selector/permission-selector-preload.cjs',
            'skills/codex-safe-setup/assets/desktop-permission-selector/Start-CodexFixed.ps1',
            'skills/codex-safe-setup/assets/desktop-permission-selector/Watch-CodexDesktop.ps1',
            'skills/codex-safe-setup/assets/desktop-permission-selector/Recertify-CodexDesktop.ps1',
            'skills/codex-safe-setup/scripts/DesktopPermissionSelector.Common.ps1'
        )) {
            if ($entryNames -notcontains $requiredEntry) {
                throw "Built archive is missing Desktop compatibility source: $requiredEntry"
            }
        }
        $forbiddenClientEntries = @($entryNames | Where-Object {
            $_ -match '(?i)(?:^|/)(?:ChatGPT\.exe|codex\.exe|app\.asar)$' -or
            $_ -match '(?i)\.(?:asar|msix|msixbundle|exe|dll|node)$'
        })
        if ($forbiddenClientEntries.Count -gt 0) {
            throw "Built archive contains forbidden client binaries: $($forbiddenClientEntries -join ', ')"
        }
    }
    finally {
        $archive.Dispose()
    }
}
finally {
    $resolvedStaging = [IO.Path]::GetFullPath($stagingPath)
    if ($resolvedStaging.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedStaging).StartsWith('codex-safe-setup-package-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolvedStaging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$hash = Get-FileHash -LiteralPath $archivePath -Algorithm SHA256
[IO.File]::WriteAllText(
    $checksumPath,
    ("{0}  {1}{2}" -f $hash.Hash.ToLowerInvariant(), (Split-Path -Leaf $archivePath), [Environment]::NewLine),
    [Text.UTF8Encoding]::new($false)
)
Write-Output ("Built: {0}" -f $archivePath)
Write-Output ("SHA256: {0}" -f $hash.Hash)
Write-Output ("Checksum: {0}" -f $checksumPath)
