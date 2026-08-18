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

$manifestText = [IO.File]::ReadAllText($manifestPath)
$manifest = $manifestText | ConvertFrom-Json
Assert-True ($manifest.name -eq 'codex-safe-setup') 'Plugin name must remain codex-safe-setup.'
Assert-True ($manifest.version -eq '0.1.2') 'Release package must use version 0.1.2.'
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
Assert-True ($skillText -match 'choose `Custom`') 'Skill must require the Custom permission selection after installation.'
Assert-True ($skillText -match '`codex-safe-workspace` is the selected profile') 'Skill must name the profile the user should activate.'
Assert-True ($skillText -match 'fully quit every Codex desktop window and CLI process') 'Skill must require a complete Windows process shutdown after installation.'
Assert-True ($skillText -match 'Repeated administrator prompts are a failure signal') 'Skill must treat repeated elevation prompts as a diagnosable failure.'

$openAiYaml = [IO.File]::ReadAllText($openAiYamlPath)
Assert-True ($openAiYaml -match '(?m)^\s*display_name:\s*"[^"]+"\s*$') 'openai.yaml display_name is required and must be quoted.'
Assert-True ($openAiYaml -match '(?m)^\s*short_description:\s*"[^"]{25,64}"\s*$') 'openai.yaml short_description must be quoted and 25-64 characters.'
$legacySkillText = [IO.File]::ReadAllText($legacySkillPath)
Assert-True ($legacySkillText -match '(?m)^name:\s*secure-codex-setup\s*\s*"[^"]*\$codex-safe-setup[^"]*"\s*$') 'openai.yaml default_prompt must mention $codex-safe-setup.'

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

Write-Output 'PASS: plugin manifest and release metadata'
Write-Output 'PASS: Git-backed marketplace metadata'
Write-Output 'PASS: canonical skill, compatibility alias, and UI metadata'
Write-Output 'PASS: unrestricted-network disclosure and Windows Custom activation handoff'
Write-Output 'PASS: required community and security documentation'
Write-Output ("PASS: PowerShell syntax ({0} files)" -f $powerShellFiles.Count)

) 'Legacy compatibility alias must retain the old skill name.'
Assert-True ($legacySkillText -match '\$codex-safe-setup') 'Legacy compatibility alias must delegate to the canonical skill.'
$legacyOpenAiYaml = [IO.File]::ReadAllText((Join-Path $legacySkillRoot 'agents/openai.yaml'))
Assert-True ($legacyOpenAiYaml -match '(?m)^\s*allow_implicit_invocation:\s*false\s*\s*"[^"]*\$codex-safe-setup[^"]*"\s*$') 'openai.yaml default_prompt must mention $codex-safe-setup.'

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

Write-Output 'PASS: plugin manifest and release metadata'
Write-Output 'PASS: Git-backed marketplace metadata'
Write-Output 'PASS: skill frontmatter and UI metadata'
Write-Output 'PASS: unrestricted-network disclosure and Windows Custom activation handoff'
Write-Output 'PASS: required community and security documentation'
Write-Output ("PASS: PowerShell syntax ({0} files)" -f $powerShellFiles.Count)

) 'Legacy compatibility alias must not be selected implicitly.'
$upgradeScriptText = [IO.File]::ReadAllText($upgradeScriptPath)
Assert-True ($upgradeScriptText -match 'ConfirmUpgrade') 'Dedicated upgrade flow must require explicit upgrade confirmation.'
Assert-True ($upgradeScriptText -match 'Upgrade\s*=\s*\$true') 'Dedicated upgrade flow must invoke installer upgrade mode.'

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

Write-Output 'PASS: plugin manifest and release metadata'
Write-Output 'PASS: Git-backed marketplace metadata'
Write-Output 'PASS: skill frontmatter and UI metadata'
Write-Output 'PASS: unrestricted-network disclosure and Windows Custom activation handoff'
Write-Output 'PASS: required community and security documentation'
Write-Output ("PASS: PowerShell syntax ({0} files)" -f $powerShellFiles.Count)

