[CmdletBinding()]
param(
    [string]$DshHome,
    [switch]$AsJson
)

# Read-only safety assessment for a DeepSeek Harness (dsh) installation.
# Inspects configuration text and file existence only; never reads secret
# contents. Baseline: dsh 0.1.0-rc.5 (see docs/dsh/audit.md for evidence).

$resolvedHome = if ($DshHome) { $DshHome }
                elseif ($env:DSH_HOME) { $env:DSH_HOME }
                else { Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) '.dsh' }

function Get-DshCommandSnapshot {
    param([string]$Name, [string[]]$VersionArguments)
    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        return [pscustomobject]@{ Present = $false; Path = $null; Version = $null }
    }
    $versionText = $null
    try {
        $versionText = (& $command.Source @VersionArguments 2>$null | Select-Object -First 1)
        if ($null -ne $versionText) { $versionText = $versionText.ToString().Trim() }
    }
    catch { $versionText = $null }
    return [pscustomobject]@{ Present = $true; Path = $command.Source; Version = $versionText }
}

function Read-DshText {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop) }
    catch { return $null }
}

# A patch that rewrites a security-relevant entry id replaces that entry's
# entire config (docs/architecture.md: layering), so any hit is an override
# of the shipped sandbox or approval behavior.
$script:SecurityEntryIds = @('sandbox-policy', 'sandbox-local', 'approval', 'user-approval', 'fs-sandbox', 'bash-sandbox')

function Test-DshPatchText {
    param([string]$Text, [string]$Label)
    $hits = [Collections.Generic.List[string]]::new()
    if (-not $Text) { return $hits }
    foreach ($entryId in $script:SecurityEntryIds) {
        if ($Text -match ('(?m)^\s*-\s*id:\s*' + [regex]::Escape($entryId) + '\s*$')) {
            $hits.Add(("$Label replaces or inserts security entry '{0}'" -f $entryId))
        }
    }
    if ($Text -match '!!js') { $hits.Add("$Label contains '!!js' expressions (evaluated as JavaScript in the host process at load time)") }
    if ($Text -match 'danger-full-access') { $hits.Add("$Label mentions 'danger-full-access'") }
    return $hits
}

$dshCli = Get-DshCommandSnapshot -Name 'dsh' -VersionArguments @('--version')
$homeExists = Test-Path -LiteralPath $resolvedHome -PathType Container
$credentialsPath = Join-Path $resolvedHome '.credentials.yaml'
$credentialsExists = Test-Path -LiteralPath $credentialsPath -PathType Leaf
$homePatchPath = Join-Path $resolvedHome 'cordis.patch.yml'
$homePatchText = Read-DshText -Path $homePatchPath

$findings = [Collections.Generic.List[object]]::new()
$profiles = [Collections.Generic.List[object]]::new()
$profileSummaries = [Collections.Generic.List[object]]::new()

if ($homeExists) {
    $profilesDir = Join-Path $resolvedHome 'profiles'
    if (Test-Path -LiteralPath $profilesDir -PathType Container) {
        Get-ChildItem -LiteralPath $profilesDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'package.json') -PathType Leaf } |
            ForEach-Object { $profiles.Add($_) }
    }
}
else {
    $findings.Add([pscustomobject]@{ Severity = 'INFO'; Finding = 'dsh home not found; no installation to assess.' })
}

foreach ($homeFinding in (Test-DshPatchText -Text $homePatchText -Label 'Home-level cordis.patch.yml')) {
    $findings.Add([pscustomobject]@{ Severity = 'HIGH'; Finding = $homeFinding + '. Upper patch layers can replace sandbox and approval entries wholesale.' })
}

foreach ($profile in $profiles) {
    $manifestText = Read-DshText -Path (Join-Path $profile.FullName 'package.json')
    $workspaceText = Read-DshText -Path (Join-Path $profile.FullName 'pnpm-workspace.yaml')
    $patchText = Read-DshText -Path (Join-Path $profile.FullName 'cordis.patch.yml')

    $bundleNames = @()
    $floatingRefs = @()
    $allowedBuilds = @()
    if ($manifestText) {
        try {
            $manifest = $manifestText | ConvertFrom-Json
            if ($manifest.dsh -and $manifest.dsh.profile -and $manifest.dsh.profile.bundles) {
                $bundleNames = @($manifest.dsh.profile.bundles)
            }
            if ($manifest.dependencies) {
                foreach ($property in $manifest.dependencies.PSObject.Properties) {
                    $spec = [string]$property.Value
                    if ($spec -match '^(github:|git\+|git:|https?://)' -and $spec -notmatch '#[0-9a-f]{40}') {
                        $floatingRefs += ("{0} -> {1}" -f $property.Name, $spec)
                    }
                }
            }
        }
        catch { $findings.Add([pscustomobject]@{ Severity = 'MEDIUM'; Finding = ("Profile '{0}': package.json is not valid JSON; manual review required." -f $profile.Name) }) }
    }
    if ($workspaceText -match '(?m)^\s*allowBuilds\s*:') {
        $inSection = $false
        foreach ($line in ($workspaceText -split "`n")) {
            if ($line -match '(?m)^\s*allowBuilds\s*:') { $inSection = $true; continue }
            if ($inSection) {
                if ($line -match '^\S') { break }
                if ($line -match '^\s{2,}[''"]?([^''"#:\s]+)[''"]?\s*:\s*true') { $allowedBuilds += $Matches[1] }
            }
        }
    }
    foreach ($patchFinding in (Test-DshPatchText -Text $patchText -Label ("Profile '{0}' cordis.patch.yml" -f $profile.Name))) {
        $findings.Add([pscustomobject]@{ Severity = 'HIGH'; Finding = $patchFinding }) 
    }
    foreach ($ref in $floatingRefs) {
        $findings.Add([pscustomobject]@{ Severity = 'HIGH'; Finding = ("Profile '{0}' has a floating git dependency ({1}) without a pinned commit; 'dsh plugin update' can pull and activate new code without approval." -f $profile.Name, $ref) })
    }
    foreach ($build in $allowedBuilds) {
        $findings.Add([pscustomobject]@{ Severity = 'MEDIUM'; Finding = ("Profile '{0}' allows build scripts for '{1}'; build scripts run at install time outside any sandbox." -f $profile.Name, $build) })
    }

    $profileSummaries.Add([pscustomobject]@{
        Name = $profile.Name
        Bundles = $bundleNames
        FloatingGitDependencies = $floatingRefs
        AllowBuilds = $allowedBuilds
        HasPatch = [bool]$patchText
    })
}

if ($env:DSH_PERMISSION_MODE) {
    if ($env:DSH_PERMISSION_MODE -eq 'danger-full-access') {
        $findings.Add([pscustomobject]@{ Severity = 'HIGH'; Finding = 'DSH_PERMISSION_MODE=danger-full-access removes the file-write sandbox and simultaneously disables approval prompts.' })
    }
    else {
        $findings.Add([pscustomobject]@{ Severity = 'INFO'; Finding = ("DSH_PERMISSION_MODE is set to '{0}', overriding the shipped default tier." -f $env:DSH_PERMISSION_MODE) })
    }
}

if ($credentialsExists) {
    $findings.Add([pscustomobject]@{ Severity = 'MEDIUM'; Finding = 'Credentials file ~/.dsh/.credentials.yaml exists (existence checked, contents not read). Keys are stored in plaintext; every permission tier, including read-only, allows the agent to read this file.' })
}

$severityRank = @{ HIGH = 0; MEDIUM = 1; INFO = 2 }
$orderedFindings = @($findings | Sort-Object { $severityRank[$_.Severity] })

$report = [pscustomobject]@{
    TimestampUtc = [DateTime]::UtcNow.ToString('o')
    DshHome = $resolvedHome
    DshHomeExists = $homeExists
    DshCli = $dshCli
    CredentialsFilePresent = $credentialsExists
    HomePatchPresent = [bool]$homePatchText
    Profiles = $profileSummaries
    PermissionModeEnv = $env:DSH_PERMISSION_MODE
    NotControlled = @(
        'Outbound network is unrestricted in every tier (no kill switch, no domain allowlist).',
        'File reads are unrestricted in every tier, including read-only.',
        'Third-party plugins run inside the host process with no isolation; install-time build scripts run outside any sandbox.',
        'MCP server processes run with full host privileges.',
        'Dangerous-command content (e.g. curl | sh) has no static detection.'
    )
    Findings = $orderedFindings
}

if ($AsJson) {
    $report | ConvertTo-Json -Depth 7
    exit 0
}

Write-Output 'dsh Safe Setup - read-only assessment (prototype)'
Write-Output ("DshHome: {0} (exists: {1})" -f $resolvedHome, $homeExists)
Write-Output ("dsh CLI: present={0} version={1}" -f $dshCli.Present, $(if ($dshCli.Version) { $dshCli.Version } else { '<unknown>' }))
Write-Output ("Credentials file present: {0} (contents not read)" -f $credentialsExists)
Write-Output ("Profiles found: {0}" -f $profileSummaries.Count)
foreach ($summary in $profileSummaries) {
    Write-Output ("  - {0}: bundles=[{1}] floatingGitDeps={2} allowBuilds=[{3}]" -f $summary.Name, ($summary.Bundles -join ','), $summary.FloatingGitDependencies.Count, ($summary.AllowBuilds -join ','))
}
foreach ($finding in $orderedFindings) { Write-Output ("[{0}] {1}" -f $finding.Severity, $finding.Finding) }
Write-Output '[NOT CONTROLLED] Network egress, file reads, plugin code, MCP processes, and command content are outside the tier vocabulary in every mode.'
