Set-StrictMode -Version Latest

$script:ZssStateDirName = 'safe-setup'
$script:ZssSandboxDefaultName = 'ZCode-Sandbox'

function Get-ZssZcodeHome {
    param([string]$Override)

    if ($Override) { return [IO.Path]::GetFullPath($Override) }
    $userProfilePath = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    if (-not $userProfilePath) { throw 'Cannot determine the user profile. Pass -ZcodeHome explicitly.' }
    return (Join-Path $userProfilePath '.zcode')
}

function Get-ZssStateRoot {
    param([string]$ZcodeHome, [string]$Override)

    $resolvedHome = Get-ZssZcodeHome -Override $ZcodeHome
    if ($Override) {
        $resolved = [IO.Path]::GetFullPath($Override)
        Assert-ZssNotFilesystemRoot -Path $resolved -Label 'StateRoot'
        return $resolved
    }
    return (Join-Path $resolvedHome $script:ZssStateDirName)
}

function Assert-ZssNotFilesystemRoot {
    param([Parameter(Mandatory)][string]$Path, [string]$Label = 'Path')

    $filesystemRoot = [IO.Path]::GetPathRoot($Path)
    $trimCharacters = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $comparison = if ($env:OS -eq 'Windows_NT') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if ([string]::Equals($Path.TrimEnd($trimCharacters), $filesystemRoot.TrimEnd($trimCharacters), $comparison)) {
        throw "Refusing to use a filesystem root as ${Label}: $Path"
    }
}

function Read-ZssText {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return [IO.File]::ReadAllText($Path)
}

function Write-ZssTextAtomic {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )
    $parentPath = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parentPath -PathType Container)) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }
    $temporaryPath = Join-Path $parentPath ('.zcode-safe-setup-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporaryPath, $Text, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
}

function Test-ZssSensitiveRelativePath {
    param([Parameter(Mandatory)][string]$Path)
    $normalized = ($Path -replace '\\', '/').ToLowerInvariant()
    $fileName = [IO.Path]::GetFileName($normalized)
    $sensitiveNames = @('.env', '.npmrc', '.pypirc', '.netrc', 'nuget.config', 'credentials.json', 'service-account.json', 'id_rsa', 'id_ed25519')
    if ($sensitiveNames -contains $fileName) { return $true }
    if ($fileName.StartsWith('.env.')) { return $true }
    return $fileName.EndsWith('.pem') -or $fileName.EndsWith('.key') -or $fileName.EndsWith('.pfx') -or $fileName.EndsWith('.p12')
}

$script:ZssSecretFilePatterns = @('.env', '.env.*', '.npmrc', '.pypirc', '.netrc', 'credentials.json', 'service-account.json', '*.pem', '*.key', '*.pfx', '*.p12')

function Find-ZssSecretFiles {
    param([Parameter(Mandatory)][string[]]$Roots, [int]$MaxDepth = 6)
    $found = [Collections.Generic.List[string]]::new()
    foreach ($root in $Roots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        foreach ($pattern in $script:ZssSecretFilePatterns) {
            Get-ChildItem -LiteralPath $root -Filter $pattern -File -Recurse -Depth ($MaxDepth - 1) -Force -ErrorAction SilentlyContinue |
                ForEach-Object { $found.Add($_.FullName) }
        }
    }
    return @($found | Sort-Object -Unique)
}

function New-ZssCheck {
    param(
        [Parameter(Mandatory)][ValidateSet('PASS', 'PARTIAL', 'FAIL', 'NOT CONTROLLED')][string]$Status,
        [Parameter(Mandatory)][string]$Control,
        [Parameter(Mandatory)][string]$Evidence
    )
    return [pscustomobject]@{ Status = $Status; Control = $Control; Evidence = $Evidence }
}

function Get-ZssRepositoryRoot {
    param([Parameter(Mandatory)][string]$Path)
    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $root = (& git -C $resolvedPath rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $root) { throw "Not a Git worktree: $resolvedPath" }
    return [IO.Path]::GetFullPath(($root | Select-Object -First 1).Trim())
}

# ---- DPAPI credential storage (CurrentUser scope; the main user is the trusted root) ----

function Protect-ZssSecret {
    param([Parameter(Mandatory)][string]$PlainText, [Parameter(Mandatory)][string]$Path)
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $bytes = [Text.Encoding]::UTF8.GetBytes($PlainText)
    $encrypted = [Security.Cryptography.ProtectedData]::Protect($bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    [IO.File]::WriteAllBytes($Path, $encrypted)
}

function Unprotect-ZssSecret {
    param([Parameter(Mandatory)][string]$Path)
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Credential blob is missing: $Path" }
    $encrypted = [IO.File]::ReadAllBytes($Path)
    $bytes = [Security.Cryptography.ProtectedData]::Unprotect($encrypted, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    return [Text.Encoding]::UTF8.GetString($bytes)
}

function New-ZssRandomPassword {
    param([int]$Length = 32)
    $ranges = (48..57) + (65..90) + (97..122) + (33..43)
    return (-join ($ranges | Get-Random -Count $Length | ForEach-Object { [char]$_ }))
}

# ---- elevation / ownership helpers ----

function Test-ZssIsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ZssProcsOwnedBy {
    param([Parameter(Mandatory)][string]$UserName)
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
        $owner = Invoke-CimMethod -InputObject $_ -MethodName GetOwner -ErrorAction SilentlyContinue
        if ($owner -and $owner.User -eq $UserName) { $_ }
    }
}

<#
.SYNOPSIS
  Launch a probe script as the sandbox user and wait for its result file.
.NOTES
  Start-Process -Credential is incompatible with -Wait and -WindowStyle Hidden
  (both throw 'access denied' even when the launch succeeds - verified on the
  reference machine; see docs/zcode-probe/PROBE-REPORT.md). Synchronize via a
  result file instead. The working directory must be readable by the target user.
#>
function Invoke-ZssAsSandboxUser {
    param(
        [Parameter(Mandatory)][pscredential]$Credential,
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$WorkDir,
        [string]$ResultFileName = 'probe-result.txt',
        [int]$TimeoutSec = 90
    )
    $resultPath = Join-Path $WorkDir $ResultFileName
    Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
    Start-Process powershell.exe -Credential $Credential -WorkingDirectory $WorkDir `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while (-not (Test-Path -LiteralPath $resultPath) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
    if (-not (Test-Path -LiteralPath $resultPath)) { throw "Sandbox probe did not produce a result within $TimeoutSec seconds: $resultPath" }
    Start-Sleep -Milliseconds 500
    return (Get-Content -LiteralPath $resultPath)
}

function Test-ZssIcaclsGrantPresent {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$UserName)
    $output = @(icacls $Path 2>$null)
    foreach ($line in $output) {
        if ($line -match [regex]::Escape($UserName)) { return $true }
    }
    return $false
}

<#
.SYNOPSIS
  Detect machine-level path-based execution control (see PROBE-REPORT.md).
.DESCRIPTION
  Copies a signed System32 console binary to the user's temp and executes it.
  Machines with path-based execution control block it (no output). The temp
  copy is always removed. Purely local, no network, no elevation.
#>
function Test-ZssUserPathExecutionBlocked {
    $probeExe = Join-Path ([IO.Path]::GetTempPath()) ('zss-exec-probe-' + [guid]::NewGuid().ToString('N') + '.exe')
    try {
        Copy-Item "$env:SystemRoot\System32\where.exe" $probeExe -Force
        $output = & $probeExe 2>&1 | Out-String
        return ($output.Trim().Length -eq 0)
    }
    finally {
        Remove-Item -LiteralPath $probeExe -Force -ErrorAction SilentlyContinue
    }
}
