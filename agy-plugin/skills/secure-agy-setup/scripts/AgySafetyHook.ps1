[CmdletBinding()]
param()

$rawInput = [Console]::In.ReadToEnd()
if (-not $rawInput.Trim()) {
    @{ decision = 'allow' } | ConvertTo-Json -Compress
    return
}

try {
    $payload = $rawInput | ConvertFrom-Json
}
catch {
    @{ decision = 'allow'; reason = 'Failed to parse JSON input' } | ConvertTo-Json -Compress
    return
}

$toolCall = $payload.toolCall
$toolName = if ($toolCall -and $toolCall.name) { $toolCall.name.ToLowerInvariant() } else { '' }
$args = if ($toolCall -and $toolCall.args) { $toolCall.args } else { $null }
$workspacePaths = if ($payload.workspacePaths) { @($payload.workspacePaths) } else { @() }

# 1. Filesystem Tools
$targetFilePath = $null
if ($args) {
    if ($args.PSObject.Properties['AbsolutePath']) { $targetFilePath = $args.AbsolutePath }
    elseif ($args.PSObject.Properties['TargetFile']) { $targetFilePath = $args.TargetFile }
}

if ($targetFilePath) {
    $normalized = ($targetFilePath -replace '\\', '/').ToLowerInvariant()
    $fileName = [IO.Path]::GetFileName($normalized)

    $sensitiveNames = @(
        '.env', '.npmrc', '.pypirc', '.netrc', 'nuget.config',
        'credentials.json', 'service-account.json',
        'id_rsa', 'id_ed25519', 'id_ecdsa', 'id_dsa'
    )
    if ($sensitiveNames -contains $fileName -or $fileName.StartsWith('.env.') -or $fileName.EndsWith('.pem') -or $fileName.EndsWith('.key')) {
        @{
            decision = 'deny'
            reason = "Blocked by agy-safe-setup: Access to sensitive credential file ($fileName) is prohibited."
        } | ConvertTo-Json -Compress
        return
    }

    $isWrite = @('write_to_file', 'replace_file_content', 'multi_replace_file_content') -contains $toolName
    if ($isWrite -and $workspacePaths.Count -gt 0) {
        $inside = $false
        $resolvedTarget = [IO.Path]::GetFullPath($targetFilePath).ToLowerInvariant()
        foreach ($root in $workspacePaths) {
            $resolvedRoot = [IO.Path]::GetFullPath($root).ToLowerInvariant()
            if ($resolvedTarget.StartsWith($resolvedRoot)) {
                $inside = $true; break
            }
        }
        if (-not $inside) {
            @{
                decision = 'deny'
                reason = "Blocked by agy-safe-setup: Out-of-workspace file modification is prohibited ($targetFilePath)."
            } | ConvertTo-Json -Compress
            return
        }
    }
}

# 2. Command Execution
if ($toolName -eq 'run_command' -and $args -and $args.CommandLine) {
    $cmd = $args.CommandLine
    if ($cmd -match '\b(?:powershell|pwsh)\b.*-(?:e|enc|encodedcommand)\b') {
        @{
            decision = 'deny'
            reason = 'Blocked by agy-safe-setup: Opaque encoded PowerShell commands (-EncodedCommand) are prohibited.'
        } | ConvertTo-Json -Compress
        return
    }
    if ($cmd -match '\.(?:ssh|aws|azure|config[\\/]gcloud)\b') {
        @{
            decision = 'deny'
            reason = 'Blocked by agy-safe-setup: Commands targeting user credential directories are prohibited.'
        } | ConvertTo-Json -Compress
        return
    }
}

@{ decision = 'allow' } | ConvertTo-Json -Compress
