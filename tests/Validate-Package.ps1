[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repositoryRoot '.codex-plugin/plugin.json'
$marketplacePath = Join-Path $repositoryRoot '.agents/plugins/marketplace.json'
$skillRoot = Join-Path $repositoryRoot 'skills/secure-codex-setup'
$skillPath = Join-Path $skillRoot 'SKILL.md'
$openAiYamlPath = Join-Path $skillRoot 'agents/openai.yaml'

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
Assert-True ($frontmatter.Groups['yaml'].Value -match '(?m)^name:\s*secure-codex-setup\s*$') 'Skill name is missing or stale.'
Assert-True ($frontmatter.Groups['yaml'].Value -match '(?m)^description:\s*\S') 'Skill description is required.'
Assert-True ($frontmatter.Groups['yaml'].Value -notmatch '(?m)^(?!name:|description:|\s*$)[A-Za-z0-9_-]+:') 'Skill frontmatter may contain only name and description.'
Assert-True ($skillText -notmatch '\[TODO:') 'SKILL.md contains a TODO placeholder.'
Assert-True ($skillText -match 'does not itself expand filesystem permissions or add deletion authority') 'Skill must distinguish network risk from filesystem authority.'
Assert-True ($skillText -match 'prompt injection') 'Skill must disclose prompt-injection risk before unrestricted networking.'
Assert-True ($skillText -match 'malware or vulnerable dependencies') 'Skill must disclose download and dependency risk before unrestricted networking.'
Assert-True ($skillText -match 'choose `Custom`') 'Skill must require the Custom permission selection after installation.'
Assert-True ($skillText -match '`codex-safe-workspace` is the selected profile') 'Skill must name the profile the user should activate.'
Assert-True ($skillText -match 'fully quit every Codex desktop window and CLI process') 'Skill must require a complete Windows process shutdown after installation.'
Assert-True ($skillText -match 'Repeated administrator prompts are a failure signal') 'Skill must treat repeated elevation prompts as a diagnosable failure.'

$openAiYaml = [IO.File]::ReadAllText($openAiYamlPath)
Assert-True ($openAiYaml -match '(?m)^\s*display_name:\s*"[^"]+"\s*$') 'openai.yaml display_name is required and must be quoted.'
Assert-True ($openAiYaml -match '(?m)^\s*short_description:\s*"[^"]{25,64}"\s*$') 'openai.yaml short_description must be quoted and 25-64 characters.'
Assert-True ($openAiYaml -match '(?m)^\s*default_prompt:\s*"[^"]*\$secure-codex-setup[^"]*"\s*$') 'openai.yaml default_prompt must mention $secure-codex-setup.'

$powerShellFiles = Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File -Filter '*.ps1' |
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

# ---------- ZCode edition (OS cage) ----------

$zcodePluginRoot = Join-Path $repositoryRoot 'zcode'
$zcodeManifestPath = Join-Path $zcodePluginRoot '.zcode-plugin/plugin.json'
$zcodeSkillRoot = Join-Path $zcodePluginRoot 'skills/secure-zcode-setup'
$zcodeSkillPath = Join-Path $zcodeSkillRoot 'SKILL.md'
$zcodeCommandPath = Join-Path $zcodePluginRoot 'commands/zcode-safe-setup.md'
foreach ($file in @($zcodeManifestPath, $zcodeSkillPath, $zcodeCommandPath,
    (Join-Path $zcodeSkillRoot 'references/os-boundary-model.md'),
    (Join-Path $zcodeSkillRoot 'references/recovery.md'),
    (Join-Path $zcodeSkillRoot 'references/security-contract.md'),
    (Join-Path $zcodeSkillRoot 'scripts/Common.ps1'),
    (Join-Path $zcodeSkillRoot 'scripts/Assess-ZcodeSafety.ps1'),
    (Join-Path $zcodeSkillRoot 'scripts/Install-ZcodeSafety.ps1'),
    (Join-Path $zcodeSkillRoot 'scripts/Test-ZcodeSafety.ps1'),
    (Join-Path $zcodeSkillRoot 'scripts/Rollback-ZcodeSafety.ps1'),
    (Join-Path $zcodeSkillRoot 'scripts/Start-ZcodeSandboxed.ps1'),
    (Join-Path $zcodeSkillRoot 'scripts/New-ZcodeCheckpoint.ps1'))) {
    Assert-True (Test-Path -LiteralPath $file -PathType Leaf) ("ZCode edition file is missing: {0}" -f $file)
}

$zcodeManifest = [IO.File]::ReadAllText($zcodeManifestPath) | ConvertFrom-Json
Assert-True ($zcodeManifest.name -eq 'zcode-safe-setup') 'ZCode plugin name must be zcode-safe-setup.'
Assert-True ($zcodeManifest.version -match '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') 'ZCode plugin version must be semver.'
Assert-True ($zcodeManifest.skills -eq 'skills') 'ZCode plugin skills path must be skills.'
Assert-True ($zcodeManifest.commands -eq 'commands') 'ZCode plugin commands path must be commands.'
Assert-True ($zcodeManifest.license -eq 'Apache-2.0') 'ZCode plugin license must match LICENSE.'

foreach ($marketplaceFile in @('.claude-plugin/marketplace.json', '.zcode-plugin/marketplace.json')) {
    $marketplacePathZ = Join-Path $repositoryRoot $marketplaceFile
    Assert-True (Test-Path -LiteralPath $marketplacePathZ -PathType Leaf) ("ZCode marketplace file is missing: {0}" -f $marketplaceFile)
    $marketplaceZ = [IO.File]::ReadAllText($marketplacePathZ) | ConvertFrom-Json
    Assert-True ($marketplaceZ.plugins.Count -eq 1) "ZCode marketplace ($marketplaceFile) must expose exactly one plugin."
    $entryZ = $marketplaceZ.plugins[0]
    Assert-True ($entryZ.name -eq $zcodeManifest.name) "ZCode marketplace ($marketplaceFile) name must match the plugin manifest."
    Assert-True ($entryZ.source -eq './zcode') "ZCode marketplace ($marketplaceFile) source must be ./zcode."
    Assert-True ($entryZ.version -eq $zcodeManifest.version) "ZCode marketplace ($marketplaceFile) version must match the plugin manifest."
}

$zcodeSkillText = [IO.File]::ReadAllText($zcodeSkillPath)
$zcodeFrontmatter = [regex]::Match($zcodeSkillText, '(?s)\A---\r?\n(?<yaml>.*?)\r?\n---\r?\n')
Assert-True $zcodeFrontmatter.Success 'ZCode SKILL.md must begin with YAML frontmatter.'
Assert-True ($zcodeFrontmatter.Groups['yaml'].Value -match '(?m)^name:\s*secure-zcode-setup\s*$') 'ZCode skill name is missing or stale.'
Assert-True ($zcodeFrontmatter.Groups['yaml'].Value -match '(?m)^description:\s*\S') 'ZCode skill description is required.'
Assert-True ($zcodeFrontmatter.Groups['yaml'].Value -notmatch '(?m)^(?!name:|description:|when_to_use:|license:|metadata:|\s*$)[A-Za-z0-9_-]+:') 'ZCode skill frontmatter uses unsupported keys.'
Assert-True ($zcodeSkillText -notmatch '\[TODO:') 'ZCode SKILL.md contains a TODO placeholder.'
Assert-True ($zcodeSkillText -match 'Approval is a workflow choice, not a security boundary') 'ZCode skill must reject approval-as-boundary.'
Assert-True ($zcodeSkillText -match 'NOT CONTROLLED') 'ZCode skill must keep the honest-reporting vocabulary.'
Assert-True ($zcodeSkillText -match 'network') 'ZCode skill must disclose the network limitation.'
Assert-True ($zcodeSkillText -match 'ZCode \(Sandboxed\)') 'ZCode skill must name the sandbox shortcut activation handoff.'
Assert-True ($zcodeSkillText -match 'main-user ZCode windows are NOT inside the cage') 'ZCode skill must state the unprotected-session limit.'

$zcodeCommandText = [IO.File]::ReadAllText($zcodeCommandPath)
Assert-True ($zcodeCommandText -match '(?m)^description:\s*\S') 'ZCode command description is required.'
Assert-True ($zcodeCommandText -match '(?m)^skills:\s*secure-zcode-setup\s*$') 'ZCode command must mount the secure-zcode-setup skill.'

Write-Output 'PASS: ZCode edition plugin manifest and marketplace metadata (dual file)'
Write-Output 'PASS: ZCode edition skill frontmatter, command, and references'
Write-Output 'PASS: ZCode edition disclosure and activation handoff'
Write-Output 'PASS: plugin manifest and release metadata'
Write-Output 'PASS: Git-backed marketplace metadata'
Write-Output 'PASS: skill frontmatter and UI metadata'
Write-Output 'PASS: unrestricted-network disclosure and Windows Custom activation handoff'
Write-Output 'PASS: required community and security documentation'
Write-Output ("PASS: PowerShell syntax ({0} files)" -f $powerShellFiles.Count)
