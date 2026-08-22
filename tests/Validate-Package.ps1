[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repositoryRoot '.codex-plugin/plugin.json'
$marketplacePath = Join-Path $repositoryRoot '.agents/plugins/marketplace.json'
$skillRoot = Join-Path $repositoryRoot 'skills/codex-safe-setup'
$skillPath = Join-Path $skillRoot 'SKILL.md'
$openAiYamlPath = Join-Path $skillRoot 'agents/openai.yaml'
$legacySkillRoot = Join-Path $repositoryRoot 'skills/secure-codex-setup'
$legacySkillPath = Join-Path $legacySkillRoot 'SKILL.md'
$upgradeScriptPath = Join-Path $skillRoot 'scripts/Upgrade-CodexSafety.ps1'
$desktopE2eScriptPath = Join-Path $skillRoot 'scripts/Test-DesktopPermissionE2E.ps1'
$desktopE2eWrapperPath = Join-Path $repositoryRoot 'tests/Test-DesktopPermissionE2E.ps1'
$legacyCleanupScriptPath = Join-Path $skillRoot 'scripts/Remove-LegacyDesktopSelectorArtifacts.ps1'
$tomlEditorScriptPath = Join-Path $skillRoot 'scripts/TomlConfigEditor.ps1'
$installScriptPath = Join-Path $skillRoot 'scripts/Install-CodexSafety.ps1'
$assessScriptPath = Join-Path $skillRoot 'scripts/Assess-CodexSafety.ps1'
$testScriptPath = Join-Path $skillRoot 'scripts/Test-CodexSafety.ps1'
$configurationProfilesPath = Join-Path $skillRoot 'references/configuration-profiles.md'
$securityContractPath = Join-Path $skillRoot 'references/security-contract.md'
$recoveryReferencePath = Join-Path $skillRoot 'references/recovery.md'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

$requiredFiles = @(
    $manifestPath,
    $marketplacePath,
    $skillPath,
    $openAiYamlPath,
    $legacySkillPath,
    $upgradeScriptPath,
    $desktopE2eScriptPath,
    $desktopE2eWrapperPath,
    $legacyCleanupScriptPath,
    $tomlEditorScriptPath,
    $installScriptPath,
    $assessScriptPath,
    $testScriptPath,
    $configurationProfilesPath,
    $securityContractPath,
    $recoveryReferencePath,
    (Join-Path $repositoryRoot 'README.md'),
    (Join-Path $repositoryRoot 'README.zh-CN.md'),
    (Join-Path $repositoryRoot 'LICENSE'),
    (Join-Path $repositoryRoot 'SECURITY.md'),
    (Join-Path $repositoryRoot 'PRIVACY.md'),
    (Join-Path $repositoryRoot 'CONTRIBUTING.md'),
    (Join-Path $repositoryRoot 'docs/threat-model.md'),
    (Join-Path $repositoryRoot 'docs/how-it-works.md')
)
foreach ($file in $requiredFiles) {
    Assert-True (Test-Path -LiteralPath $file -PathType Leaf) ("Required file is missing: {0}" -f $file)
}

$strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
$utf8Files = @($requiredFiles + (Join-Path $repositoryRoot 'CHANGELOG.md'))
foreach ($file in $utf8Files) {
    try {
        $text = [IO.File]::ReadAllText($file, $strictUtf8)
    }
    catch {
        throw ("File is not strict UTF-8: {0}" -f $file)
    }
    Assert-True (-not $text.Contains([char]0xFFFD)) ("File contains a Unicode replacement character: {0}" -f $file)
    Assert-True ($text -notmatch '\?\?\?') ("File contains a likely encoding replacement run: {0}" -f $file)
}

$utf8Sentinels = @{
    'README.md' = -join @([char]0x7B80, [char]0x4F53, [char]0x4E2D, [char]0x6587)
    'README.zh-CN.md' = -join @([char]0x5BA1, [char]0x6279, [char]0x4E0D, [char]0x662F, [char]0x5B89, [char]0x5168, [char]0x8FB9, [char]0x754C)
    'CHANGELOG.md' = -join @([char]0x81EA, [char]0x5B9A, [char]0x4E49)
    'skills/codex-safe-setup/SKILL.md' = -join @([char]0x81EA, [char]0x5B9A, [char]0x4E49)
}
foreach ($entry in $utf8Sentinels.GetEnumerator()) {
    $path = Join-Path $repositoryRoot $entry.Key
    $text = [IO.File]::ReadAllText($path, $strictUtf8)
    Assert-True ($text.Contains([string]$entry.Value)) ("UTF-8 sentinel is missing: {0}" -f $entry.Key)
}

$manifestText = [IO.File]::ReadAllText($manifestPath)
$manifest = $manifestText | ConvertFrom-Json
Assert-True ($manifest.name -eq 'codex-safe-setup') 'Plugin name must remain codex-safe-setup.'
Assert-True ($manifest.version -eq '0.3.0') 'Release package must use version 0.3.0.'
Assert-True ($manifest.version -match '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') 'Plugin version must be strict semver.'
Assert-True (-not [string]::IsNullOrWhiteSpace($manifest.description)) 'Plugin description is required.'
Assert-True (-not [string]::IsNullOrWhiteSpace($manifest.author.name)) 'Plugin author name is required.'
Assert-True ($manifest.skills -eq './skills/') 'Plugin skills path must be ./skills/.'
Assert-True ($manifest.license -eq 'Apache-2.0') 'Plugin license must match LICENSE.'
Assert-True ($manifest.repository -eq 'https://github.com/QianQIUlp/codex-safe-setup') 'Repository metadata is stale.'
Assert-True ($manifest.interface.defaultPrompt.Count -le 3) 'Plugin defaultPrompt accepts at most three entries.'
foreach ($prompt in $manifest.interface.defaultPrompt) {
    Assert-True ($prompt.Length -le 128) 'Plugin defaultPrompt entries must be at most 128 characters.'
}
Assert-True ($manifestText -notmatch '\[TODO:') 'Plugin manifest contains a TODO placeholder.'

$marketplace = [IO.File]::ReadAllText($marketplacePath) | ConvertFrom-Json
Assert-True ($marketplace.name -eq 'codex-safe-setup') 'Marketplace name must remain codex-safe-setup.'
Assert-True ($marketplace.plugins.Count -eq 1) 'Marketplace must expose exactly one plugin.'
$entry = $marketplace.plugins[0]
Assert-True ($entry.name -eq $manifest.name) 'Marketplace and manifest plugin names differ.'
Assert-True ($entry.source.source -eq 'url') 'Public marketplace entry must use a repository-root URL source.'
Assert-True ($entry.source.url -eq 'https://github.com/QianQIUlp/codex-safe-setup.git') 'Marketplace repository URL is stale.'
Assert-True ($entry.source.ref -eq ('v' + $manifest.version)) 'Marketplace ref must match the plugin release version.'
Assert-True ($entry.policy.installation -eq 'AVAILABLE') 'Marketplace installation policy must be AVAILABLE.'
Assert-True ($entry.policy.authentication -eq 'ON_INSTALL') 'Marketplace authentication policy must be explicit.'

$skillText = [IO.File]::ReadAllText($skillPath)
$frontmatter = [regex]::Match($skillText, '(?s)\A---\r?\n(?<yaml>.*?)\r?\n---\r?\n')
Assert-True $frontmatter.Success 'SKILL.md must begin with YAML frontmatter.'
Assert-True ($frontmatter.Groups['yaml'].Value -match '(?m)^name:\s*codex-safe-setup\s*$') 'Skill name is missing or stale.'
Assert-True ($frontmatter.Groups['yaml'].Value -match '(?m)^description:\s*\S') 'Skill description is required.'
Assert-True ($frontmatter.Groups['yaml'].Value -notmatch '(?m)^(?!name:|description:|\s*$)[A-Za-z0-9_-]+:') 'Skill frontmatter may contain only name and description.'
Assert-True ($skillText -notmatch '\[TODO:') 'SKILL.md contains a TODO placeholder.'
Assert-True ($skillText -match 'does not itself expand filesystem permissions or add deletion authority') 'Skill must distinguish network risk from filesystem authority.'
Assert-True ($skillText -match 'prompt injection') 'Skill must disclose prompt-injection risk before unrestricted networking.'
Assert-True ($skillText -match 'malware or vulnerable dependencies') 'Skill must disclose download and dependency risk before unrestricted networking.'
Assert-True ($skillText -match 'Allowlist.*filtering proxy') 'Skill must preserve proxy-enforced domain filtering for Allowlist mode.'
Assert-True ($skillText -match 'Unrestricted.*disables the proxy.*SSH') 'Skill must define Unrestricted as direct networking for native protocols.'
Assert-True ($skillText -match 'DynamicUi.*two positive-only named profiles.*default_permissions.*:workspace') 'Skill must define DynamicUi as the dual named-profile route with built-in Workspace startup default.'
Assert-True ($skillText -match 'next user message without restarting Codex') 'Skill must require same-task next-message permission routing.'
Assert-True ($skillText -match 'workspace credential files remain readable') 'Skill must disclose the DynamicUi workspace-secret read tradeoff.'
Assert-True ($skillText -match 'StrictProfile') 'Skill must retain the strict deny-read alternative.'
Assert-True ($skillText -match 'Full Access.*danger-full-access') 'Skill must require Full Access to produce the effective danger-full-access sandbox.'
Assert-True ($skillText -match 'Test-DesktopPermissionE2E') 'Skill must require the real Desktop turn/canary verifier.'
Assert-True ($skillText -notmatch 'AcknowledgeUnsupportedDesktopOverride|Install-DesktopPermissionSelectorFix') 'Skill must not offer the removed Desktop compatibility layer.'
Assert-True ($skillText -match 'must never modify WindowsApps or package any OpenAI executable, ASAR, renderer bundle') 'Skill must prohibit client modification and redistribution.'
Assert-True ($skillText -match 'Rollout records cannot prove what the selector displayed') 'Skill must separate visual stability from runtime permission evidence.'
Assert-True ($skillText -match 'codexsandboxonline.*codexsandboxoffline') 'Skill must reject sandbox account names as permission evidence.'
Assert-True ($skillText -match 'native Git') 'Skill must preserve ordinary Git in a true Full Access task.'
Assert-True ($skillText -notmatch 'EnableGitCommitBridge') 'Skill must not offer an alternate normal-commit backend.'
Assert-True ($skillText -match 'fully quit every Codex desktop window and CLI process') 'Skill must retain the Windows restart diagnostic for configuration activation.'
Assert-True ($skillText -match 'Repeated administrator prompts are a failure signal') 'Skill must treat repeated elevation prompts as a diagnosable failure.'

$openAiYaml = [IO.File]::ReadAllText($openAiYamlPath)
Assert-True ($openAiYaml -match '(?m)^\s*display_name:\s*"[^"]+"\s*$') 'openai.yaml display_name is required and must be quoted.'
Assert-True ($openAiYaml -match '(?m)^\s*short_description:\s*"[^"]{25,64}"\s*$') 'openai.yaml short_description must be quoted and 25-64 characters.'
$legacySkillText = [IO.File]::ReadAllText($legacySkillPath)
Assert-True ($legacySkillText -match '(?m)^name:\s*secure-codex-setup\s*$') 'Legacy compatibility alias must retain the old skill name.'
Assert-True ($legacySkillText -match '\$codex-safe-setup') 'Legacy compatibility alias must delegate to the canonical skill.'
$legacyOpenAiYaml = [IO.File]::ReadAllText((Join-Path $legacySkillRoot 'agents/openai.yaml'))
Assert-True ($legacyOpenAiYaml -match '(?m)^\s*allow_implicit_invocation:\s*false\s*$') 'Legacy compatibility alias must not be selected implicitly.'
$upgradeScriptText = [IO.File]::ReadAllText($upgradeScriptPath)
Assert-True ($upgradeScriptText -match 'ConfirmUpgrade') 'Dedicated upgrade flow must require explicit upgrade confirmation.'
Assert-True ($upgradeScriptText -match 'Upgrade\s*=\s*\$true') 'Dedicated upgrade flow must invoke installer upgrade mode.'

$desktopE2eScriptText = [IO.File]::ReadAllText($desktopE2eScriptPath)
Assert-True ($desktopE2eScriptText -match 'turn_context') 'Desktop E2E verifier must inspect the effective turn context.'
Assert-True ($desktopE2eScriptText -match 'unified_exec_startup') 'Desktop E2E verifier must inspect the real unified-exec command.'
Assert-True ($desktopE2eScriptText -match 'task_complete') 'Desktop E2E verifier must require same-turn task completion.'
Assert-True ($desktopE2eScriptText -match 'danger-full-access') 'Desktop E2E verifier must require effective Full Access.'
Assert-True ($desktopE2eScriptText -match 'codex-safe-workspace / 自定义') 'Desktop E2E verifier must exercise the primary named Custom route.'
Assert-True ($desktopE2eScriptText -match 'session_meta' -and $desktopE2eScriptText -match 'Codex Desktop') 'Desktop E2E verifier must prove a real Desktop session and reject restarts during the probe window.'
Assert-True ($desktopE2eScriptText -match '-ceq \$expectedCommand') 'Desktop E2E verifier must require the exact generated command, not marker text alone.'
Assert-True ($desktopE2eScriptText -match 'Get-DenySignatures') 'Desktop E2E verifier must reject every stale Custom deny entry in built-in Workspace.'
Assert-True ($desktopE2eScriptText -match 'VisualStabilityConfirmed' -and $desktopE2eScriptText -match 'Rollout metadata alone is insufficient') 'Desktop E2E verifier must require direct visual-stability confirmation separately from rollout evidence.'
$desktopE2eWrapperText = [IO.File]::ReadAllText($desktopE2eWrapperPath)
Assert-True ($desktopE2eWrapperText -match 'skills\\codex-safe-setup\\scripts\\Test-DesktopPermissionE2E\.ps1') 'Repository E2E wrapper must invoke the packaged canonical verifier.'

$removedCompatPaths = @(
    (Join-Path $skillRoot 'scripts/Install-DesktopPermissionSelectorFix.ps1'),
    (Join-Path $skillRoot 'scripts/Test-DesktopPermissionSelectorFix.ps1'),
    (Join-Path $skillRoot 'scripts/Rollback-DesktopPermissionSelectorFix.ps1'),
    (Join-Path $skillRoot 'scripts/DesktopPermissionSelector.Common.ps1'),
    (Join-Path $skillRoot 'assets/desktop-permission-selector')
)
foreach ($removedPath in $removedCompatPaths) {
    Assert-True (-not (Test-Path -LiteralPath $removedPath)) ("Removed Desktop compatibility source must stay absent: {0}" -f $removedPath)
}

$legacyCleanupText = [IO.File]::ReadAllText($legacyCleanupScriptPath)
Assert-True ($legacyCleanupText -match 'PlanOnly' -and $legacyCleanupText -match 'ConfirmApply') 'Legacy cleanup must be plan-first and require explicit confirmation.'
Assert-True ($legacyCleanupText -match 'Watch-CodexDesktop\.vbs|desktop-ui-fix|desktop-selector-loader') 'Legacy cleanup must target only the known retired artifact names.'
Assert-True ($legacyCleanupText -notmatch 'Stop-Process|CloseMainWindow|\bkill\b') 'Legacy cleanup must never close, kill, or restart any process.'
Assert-True ($legacyCleanupText -notmatch ('app\.asar|STATSIG|setPre' + 'loads|NODE_OPTIONS')) 'Legacy cleanup must not read client internals or set launcher environment overrides.'

$trackedFiles = @(git -C $repositoryRoot ls-files)
$scanExtensions = @('.ps1', '.md', '.json', '.cjs', '.ts', '.astro', '.yaml', '.yml', '.vbs')
$overrideScanFiles = @($trackedFiles | Where-Object {
    $_ -notlike 'dist/*' -and
    [IO.Path]::GetExtension($_) -in $scanExtensions
} | ForEach-Object { Join-Path $repositoryRoot $_ })
$forbiddenOverrideTokens = @(
    ('42262824' + '75'),
    ('__STAT' + 'SIG__'),
    ('executeInMain' + 'World'),
    ('setPre' + 'loads')
)
foreach ($file in $overrideScanFiles) {
    $text = [IO.File]::ReadAllText($file)
    foreach ($token in $forbiddenOverrideTokens) {
        Assert-True (-not $text.Contains($token)) ("Forbidden Desktop-override token '{0}' found in {1}" -f $token, (Split-Path -Leaf $file))
    }
}
Assert-True ($overrideScanFiles.Count -gt 0) 'Override-token scan must cover tracked text sources.'

$forbiddenClientFiles = @(Get-ChildItem -LiteralPath $skillRoot -Recurse -File | Where-Object {
    $_.Extension -in @('.asar', '.msix', '.msixbundle', '.exe', '.dll', '.node') -or
    $_.Name -in @('ChatGPT.exe', 'codex.exe', 'app.asar')
})
Assert-True ($forbiddenClientFiles.Count -eq 0) ('Release sources must not contain OpenAI client files: ' + (@($forbiddenClientFiles | ForEach-Object FullName) -join ', '))

Assert-True ($openAiYaml -match '(?m)^\s*default_prompt:\s*"[^"]*\$codex-safe-setup[^"]*"\s*$') 'openai.yaml default_prompt must mention $codex-safe-setup.'

$powerShellFiles = Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike (Join-Path $repositoryRoot 'dist*') }
foreach ($file in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        throw ("PowerShell parse error in {0}: {1}" -f $file.FullName, ($parseErrors.Message -join '; '))
    }
}

Write-Output 'PASS: strict UTF-8 package sources and sentinels'
Write-Output 'PASS: plugin manifest and release metadata'
Write-Output 'PASS: Git-backed marketplace metadata'
Write-Output 'PASS: canonical skill, compatibility alias, and UI metadata'
Write-Output 'PASS: unrestricted-network disclosure and task-level Full Access override contract'
Write-Output 'PASS: required community and security documentation'
Write-Output 'PASS: Desktop compatibility layer fully removed and override tokens absent from every tracked source'
Write-Output ("PASS: PowerShell syntax ({0} files)" -f $powerShellFiles.Count)
