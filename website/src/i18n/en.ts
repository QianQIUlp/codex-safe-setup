import type { UiContent } from './types';

export const en: UiContent = {
  lang: 'en',
  altLang: 'zh-CN',
  altLangLabel: '中文',
  altLangHref: '/zh-CN/',
  path: '/',
  meta: {
    title: 'Codex Safe Setup — Safer Codex on Windows',
    description:
      'Install least-privilege, recoverable Codex permissions on Windows. Limit what Codex can read, change, and send — then verify the setup and recover from mistakes.',
    ogTitle: 'Codex Safe Setup — Safer Codex on Windows',
    ogDescription:
      'Limit what Codex can read, change, and send — then verify the setup and recover from mistakes. A community-built Codex plugin for Windows.',
  },
  nav: {
    howItWorks: { label: 'How it works', href: '/#limits' },
    install: { label: 'Install', href: '/#install' },
    threatModel: {
      label: 'Threat model',
      href: 'https://github.com/QianQIUlp/codex-safe-setup/blob/main/docs/threat-model.md',
      external: true,
    },
    github: {
      label: 'GitHub',
      href: 'https://github.com/QianQIUlp/codex-safe-setup',
      external: true,
    },
  },
  hero: {
    eyebrow: 'Codex security · Windows',
    title: 'Safer Codex on Windows.',
    lead: 'Limit what Codex can read, change, and send — then verify the setup and recover from mistakes.',
    primaryCta: { label: 'Install Codex Safe Setup', href: '/#install' },
    secondaryCta: {
      label: 'View on GitHub',
      href: 'https://github.com/QianQIUlp/codex-safe-setup',
      external: true,
    },
    tertiaryCta: { label: 'How it works', href: '/#limits' },
    disclaimer: 'Community project · Not affiliated with OpenAI',
    visual: {
      agentLabel: 'Agent',
      agentName: 'Codex',
      insideLabel: 'Inside bounded profiles',
      outsideLabel: 'Outside the boundary',
      allowed: ['workspace write', 'workspace sandbox reads', 'explicit network policy'],
      denied: ['outside-workspace writes', 'StrictProfile credentials', 'unrestricted network'],
      deniedCrossing: 'out-of-profile read',
      crossingDetail: 'blocked at the boundary',
      ariaLabel:
        'A bounded-profile diagram: DynamicUi uses two positive-only named Workspace profiles; StrictProfile adds persistent root and credential denies.',
    },
  },
  principle: {
    eyebrow: 'Why this exists',
    title: 'Approval is not a security boundary.',
    body: [
      'Faced with a destructive command, most people\u2019s first instinct is: \u201cI\u2019ll write clear instructions and approve everything important myself.\u201d But approval only protects you if you can actually read every command \u2014 and on Windows, with its quoting rules, encodings, registry entries, and endless parameters, that is far harder than it sounds.',
      'Commands get longer, approvals repeat dozens of times a day, and sooner or later you skim, misread, or only see the first half. Reviewer agents misjudge too. When approval is the only line of defense, one wrong click hands over full authority.',
    ],
    semantic: {
      label: 'Test yourself \u00b7 The scariest kind: semantic errors',
      intro:
        'Read the whole script once before looking at the answer below. There is no malicious line in sight \u2014 but it deletes a folder you never meant to touch.',
      code: [
        'Set-Location "C:\\Users\\you\\projects\\webapp"',
        '$ErrorActionPreference = "SilentlyContinue"',
        'if (-not (Test-Path "C:\\Users\\you\\projects\\webapp\\node_modules")) {',
        '  npm ci --no-audit --no-fund --loglevel=error',
        '}',
        '$config = Get-Content "C:\\Users\\you\\projects\\webapp\\tools\\build-config.json" -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json',
        '$base = $config.outputDirectory',
        'npm run build -- --outDir "$base" --minify',
        'Copy-Item -Path "$base\\*" -Destination "C:\\Users\\you\\projects\\webapp\\release\\latest" -Recurse -Force -Confirm:$false',
        'Remove-Item -Path "$base\\data" -Recurse -Force -Confirm:$false',
        'git add -A; git commit -m "sync build output"; git push origin main',
      ],
      looksLike: 'A routine build-and-release script.',
      actually:
        'By the time you reach the final lines, line 7 looks completely innocent: $base takes its value from the config. But the config read failed quietly \u2014 $base is $null. Not one line in this script was written to cause the accident.',
      answer: {
        caption: 'Answer',
        keyLines: [
          '$config = Get-Content "C:\\Users\\you\\projects\\webapp\\tools\\build-config.json" -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json',
          '$base = $config.outputDirectory',
          'Remove-Item -Path "$base\\data" -Recurse -Force -Confirm:$false',
        ],
        explanation:
          'PowerShell resolves paths starting with \\ from the root of the current drive \u2014 here, C:. The config file is missing, so the read fails quietly and $base is $null: "$base\\data" becomes \\data, and "$base\\*" becomes \\*. Copy-Item first copies whatever it can read from C:\\* into release\\latest; Remove-Item targets C:\\data. Whether the deletion actually lands depends on C:\\data existing and on your permissions. Danger did not come from a dangerous line \u2014 two locally reasonable choices combined into a path you never meant.',
      },
    },
    accidents: {
      label: 'Risk one \u00b7 Agent accidents \u2014 no malice required',
      intro:
        'Completing the task correctly is not the same as completing it safely. Nothing in these commands is evil; the outcome is simply wrong.',
      examples: [
        {
          label: 'Sync that erases',
          code: [
            'git fetch origin main --quiet',
            'git reset --hard origin/main',
            'git clean -fdx -e ".env.local" -e "node_modules"',
          ],
          looksLike: 'An ordinary request: bring the repo back to a clean state of remote main.',
          actually:
            'It never checks whether the working tree holds your only copy of anything. reset --hard discards tracked changes; clean -fdx wipes even ignored files. The task is correct \u2014 the completion is unsafe.',
        },
      ],
    },
    boundary: {
      label: 'Risk two \u00b7 More permission than the task needs',
      intro:
        'These are not reasoning accidents \u2014 they are what granted permissions allow: code you cannot audit, and one-time approvals that keep executing later.',
      examples: [
        {
          label: 'Opaque execution',
          code: [
            'powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand JABFAHIAcgBvAHIAQQBjAHQAaQBvAG4AUAByAGUAZgBlAHIAZQBuAGMAZQA9ACcAUwBpAGwAZQBuAHQAbAB5AEMAbwBuAHQAaQBuAHUAZQAnADsAIABHAGUAdAAtAEMAaABpAGwAZABJAHQAZQBtACAAIgAkAGUAbgB2ADoAVQBTAEUAUgBQAFIATwBGAEkATABFAFwALgBhAHcAcwAiACwAIgAkAGUAbgB2ADoAVQBTAEUAUgBQAFIATwBGAEkATABFAFwALgBzAHMAaAAiACAALQBSAGUAYwB1AHIAcwBlACAALQBGAG8AcgBjAGUAIAAtAEUAcgByAG8AcgBBAGMAdABpAG8AbgAgAFMAaQBsAGUAbgB0AGwAeQBDAG8AbgB0AGkAbgB1AGUAIAB8ACAARgBvAHIARQBhAGMAaAAtAE8AYgBqAGUAYwB0ACAAewAgAEMAbwBwAHkALQBJAHQAZQBtACAAJABfAC4ARgB1AGwAbABOAGEAbQBlACAAIgBDADoAXABVAHMAZQByAHMAXAB5AG8AdQBcAHAAcgBvAGoAZQBjAHQAcwBcAHcAZQBiAGEAcABwAFwALgBzAGMAYQBuAC0AbwB1AHQAcAB1AHQAIgAgAC0ARgBvAHIAYwBlACAAfQA=',
          ],
          looksLike: 'A common workaround for Windows quoting problems \u2014 or a way to hide what actually runs.',
          actually:
            'Prompt injection and malicious repo instructions look exactly like this under Full Access: Hidden, NonInteractive, ExecutionPolicy Bypass, and a payload no one can audit.',
          decodedLabel: 'Decoded, it reads:',
          decoded: [
            '$ErrorActionPreference = \'SilentlyContinue\'',
            'Get-ChildItem "$env:USERPROFILE\\.aws", "$env:USERPROFILE\\.ssh" -Recurse -Force |',
            'ForEach-Object { Copy-Item $_.FullName "C:\\Users\\you\\projects\\webapp\\.scan-output" -Force }',
          ],
        },
        {
          label: 'Persistence across logins',
          code: [
            'New-ItemProperty -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run" -Name "WebAppUpdater" -Value "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\\Users\\you\\AppData\\Local\\Temp\\upd.ps1" -PropertyType String -Force | Out-Null',
          ],
          looksLike: 'Register an updater that starts at login.',
          actually:
            'The Run entry points at a mutable file: upd.ps1. You reviewed version A today; a replaced version B runs at your next login. One approval becomes a standing execution path that outlives this review.',
        },
      ],
      incident: {
        label: 'One case, reported from the community',
        story:
          'A user running Full Access discovered that their relay service had injected a script into the execution flow, disguised as \u201cenvironment monitoring\u201d. They only spotted it because the executed code was visible in the chain of thought \u2014 SSH keys and API keys were one step away from being bundled out of the machine.',
        lesson:
          'The script looked harmless, so approval was never the question. With the Custom or StrictProfile read boundary active, disguised code could not have read SSH keys or API keys outside the project.',
      },
    },
    closer:
      'Every new command is another exam that must be passed perfectly, and a single failure hands over full authority. Codex Safe Setup flips this: approval becomes an optional workflow inside the boundary, and the boundary itself becomes the thing that cannot be crossed.',
    cta: 'See how the boundary actually works',
  },
  limits: {
    eyebrow: 'What it limits',
    title: 'What it limits',
    lead: 'Three capability boundaries, with an explicit choice between dynamic UI control and a pinned strict profile.',
    modules: [
      {
        id: 'files',
        number: 'A',
        eyebrow: 'Files',
        title: 'Codex shouldn\u2019t own your whole filesystem.',
        lead: 'DynamicUi keeps runtime switching free of sticky denies. StrictProfile pins persistent root and credential denies.',
        inside: [
          {
            icon: 'allow',
            label: 'Workspace write',
            detail: 'Writes allowed only under registered workspace roots.',
          },
          {
            icon: 'allow',
            label: 'Workspace sandbox reads',
            detail: 'DynamicUi follows the workspace sandbox read scope; StrictProfile narrows reads with explicit rules.',
          },
        ],
        outside: [
          {
            icon: 'deny',
            label: 'Filesystem root',
            detail: 'Writes are blocked by DynamicUi outside the workspace and explicitly bounded by StrictProfile; Full Access permits them.',
          },
          {
            icon: 'deny',
            label: 'Common credentials',
            detail: 'Explicitly denied only by StrictProfile. DynamicUi cannot use sticky deny-globs inside a writable workspace.',
          },
        ],
        note: 'DynamicUi installs two positive-only runtime profiles. Workspace credential files remain readable; use StrictProfile for persistent explicit denies.',
      },
      {
        id: 'network',
        number: 'B',
        eyebrow: 'Network',
        title: 'Command networking is a separate boundary.',
        lead: 'Approving commands is not the same as deciding what can leave your machine. Egress is an explicit, independent choice.',
        inside: [
          {
            icon: 'allow',
            label: 'Off',
            detail: 'Default. Commands cannot reach the network.',
          },
          {
            icon: 'allow',
            label: 'Allowlist',
            detail: 'Only explicitly named public domains pass through the command proxy.',
          },
        ],
        outside: [
          {
            icon: 'deny',
            label: 'Unrestricted',
            detail: 'High risk. Direct command egress, installed only after a separate acknowledgement.',
          },
        ],
        note: 'A domain table without an active proxy is not an enforced allowlist.',
      },
      {
        id: 'recovery',
        number: 'C',
        eyebrow: 'Recovery',
        title: 'Safety includes being able to undo.',
        lead: 'Containment prevents mistakes; recovery survives them. Every managed file is backed up, and the optional checkpoint bridge snapshots work without touching your branch.',
        inside: [
          {
            icon: 'allow',
            label: 'Backup before write',
            detail: 'Every file the installer touches is backed up first, with an exact rollback command.',
          },
          {
            icon: 'allow',
            label: 'Git checkpoints',
            detail: 'Optional hidden refs under refs/codex-safe/checkpoints/*. Branch, real index, and working tree stay untouched.',
          },
        ],
        outside: [
          {
            icon: 'deny',
            label: 'Sensitive untracked files',
            detail: 'Refused from checkpoints: .env, private keys, .npmrc, cloud credential files.',
          },
          {
            icon: 'deny',
            label: 'Automatic destructive recovery',
            detail: 'Never runs reset --hard, clean, branch replacement, or in-place checkout.',
          },
          {
            icon: 'deny',
            label: 'Replaced Git executable',
            detail: 'The bridge refuses to run if the pinned Git SHA-256 changes.',
          },
        ],
        note: 'Checkpoints do not capture ignored or refused files. Restore with a separate worktree: git worktree add <new-empty-directory> <commit>.',
      },
    ],
  },
  beforeAfter: {
    eyebrow: 'Before & after',
    title: 'Autonomy and containment are not opposites.',
    lead: 'A good boundary lets the agent work freely inside it — you don\u2019t become the gatekeeper.',
    before: {
      title: 'Full Access',
      tagline: 'Every read, write, and send starts allowed.',
      items: ['Workspace', 'Home directory', 'Credentials', 'Whole filesystem', 'Network'],
    },
    after: {
      title: 'Bounded autonomy',
      tagline: 'Writes and command egress stay bounded; the selected UI route controls the read boundary.',
      items: ['Workspace writes', 'Zero-deny Custom profile', 'Explicit network policy'],
    },
    afterDenied: 'Out-of-bound writes and command egress \u2192 denied',
    bottomLine:
      'With the recommended BoundedAutonomy mode, there are no approval prompts inside the boundary — limits do the work approvals were doing.',
    modes: {
      label: 'Three ways to handle a boundary crossing',
      intro:
        'Approval and command networking are separate decisions. The reviewer choice does not change whichever DynamicUi or StrictProfile filesystem route is active.',
      recommendedTag: 'Recommended',
      rows: [
        {
          name: 'BoundedAutonomy',
          recommended: true,
          detail: 'No approval prompts. Out-of-bound actions fail at the boundary.',
        },
        {
          name: 'AskMe',
          detail: 'Eligible boundary crossings are sent to you for review.',
        },
        {
          name: 'AutoReview',
          detail:
            'Eligible crossings go to a reviewer agent — the sandbox does not become stronger.',
        },
      ],
    },
  },
  verification: {
    eyebrow: 'Verification',
    title: 'Installed is not verified.',
    lead: 'Installing a config is not the same as proving it holds. Verification reports what was actually checked — and what it could not check.',
    rows: [
      {
        status: 'pass',
        label: 'PASS',
        detail: 'Directly checked and matched the expected condition.',
      },
      {
        status: 'partial',
        label: 'PARTIAL',
        detail: 'Configuration evidence exists, but a required runtime or CLI check was unavailable.',
      },
      {
        status: 'fail',
        label: 'FAIL',
        detail: 'A required condition is missing or contradictory.',
      },
      {
        status: 'not-controlled',
        label: 'NOT CONTROLLED',
        detail: 'The capability belongs to another control surface — reported, never implied as protected.',
      },
    ],
    caveat: 'Static configuration and codex execpolicy check are evidence, not proof of every future runtime behavior. Re-run verification after Codex upgrades.',
    restart: 'Start one fresh task after a machine-configuration change. Same-task UI permission changes must then apply on the next message without restarting.',
    checks: {
      label: 'What verification actually checks',
      items: [
        'writes outside the workspace',
        'reads outside the workspace',
        'workspace secret files',
        'protected metadata (.git, .codex, .agents)',
        'deletion recovery (checkpoints)',
        'command network egress',
        'rollback and backups',
        'external surfaces — reported, never implied',
      ],
    },
    canary:
      'A synthetic file placed outside the workspace is used to probe the boundary before any claim is made.',
  },
  install: {
    eyebrow: 'Install',
    title: 'Install Codex Safe Setup',
    lead: 'Two commands, one prompt — then the skill audits, explains the tradeoffs, and writes configuration only after you confirm.',
    requires: 'DynamicUi and StrictProfile require Codex CLI 0.138.0 or newer · PowerShell 7 recommended on Windows',
    commands: [
      'codex plugin marketplace add QianQIUlp/codex-safe-setup --ref main',
      'codex plugin add codex-safe-setup@codex-safe-setup',
    ],
    promptLabel: 'Start a new Codex task or CLI session, then ask:',
    promptText:
      'Use $codex-safe-setup to audit my current permissions and install the recommended profile.',
    releaseNote:
      'Version 0.2.1 removes the retired Windows selector compatibility layer from 0.2.0 and ships a cleanup script for legacy autostart remnants. The GitHub marketplace follows main, whose catalog pins the latest release.',
    shaNote:
      'Each release also ships an install-ready ZIP with a .sha256 file. Verify the archive in PowerShell with Get-FileHash -Algorithm SHA256 <archive>.',
    detailsCta: {
      label: 'View installation details',
      href: 'https://github.com/QianQIUlp/codex-safe-setup#install',
      external: true,
    },
    copyButton: 'Copy',
    copied: 'Copied',
    flow: {
      label: 'What happens after the two commands',
      steps: [
        'Read-only assessment — nothing changes yet.',
        'Boundaries and tradeoffs explained, not hidden.',
        'Separate consent for prerequisites (PowerShell 7, Codex CLI).',
        'Plan-only preview of the exact configuration.',
        'Applied only after your explicit confirmation.',
        'Static and execpolicy checks, then a fresh task for real Desktop end-to-end probes.',
        'Backups recorded — exact rollback stays available.',
      ],
    },
  },
  notProtected: {
    eyebrow: 'The boundary',
    title: 'Know the boundary.',
    lead: 'A trustworthy security tool states what it does not control. These surfaces use separate control surfaces — each is reported as NOT CONTROLLED, never implied as protected.',
    items: [
      'Web Search',
      'Browser',
      'Computer Use',
      'Apps & connectors',
      'Other plugins',
      'MCP servers',
      'Cloud tasks',
      'Source-control remotes',
      'CI credentials',
      'Credentials exposed before installation',
      'Host malware',
      'Operating-system compromise',
    ],
    reportedAs: 'Each appears as NOT CONTROLLED in the verification report.',
    cta: {
      label: 'Read the threat model',
      href: 'https://github.com/QianQIUlp/codex-safe-setup/blob/main/docs/threat-model.md',
      external: true,
    },
    exposed: {
      label: 'If a credential may already be exposed',
      items: [
        'Revoke or rotate it immediately.',
        'Inspect the provider\u2019s usage, sessions, and billing.',
        'Remove copies from files, logs, shell history, and repository history.',
        'Timing alone is not proof of causation.',
      ],
    },
  },
  openSource: {
    eyebrow: 'Open source',
    title: 'Built in the open.',
    lead: 'Community-built and Apache-2.0 licensed. Source, reproducible builds, and private security reporting on GitHub.',
    items: [
      { label: 'Issues', href: 'https://github.com/QianQIUlp/codex-safe-setup/issues' },
      {
        label: 'Security advisories',
        href: 'https://github.com/QianQIUlp/codex-safe-setup/security/advisories/new',
      },
      {
        label: 'Contributing',
        href: 'https://github.com/QianQIUlp/codex-safe-setup/blob/main/CONTRIBUTING.md',
      },
      { label: 'License', href: 'https://github.com/QianQIUlp/codex-safe-setup/blob/main/LICENSE' },
    ],
    cta: {
      label: 'View source on GitHub',
      href: 'https://github.com/QianQIUlp/codex-safe-setup',
      external: true,
    },
    facts: [
      'CI runs isolated integration tests and package validation on Windows.',
      'Releases are built from validated tags and ship with SHA-256 checksums.',
      'Each release passed the official Skill and Plugin validators.',
      'Private vulnerability reporting through GitHub Security Advisories.',
    ],
  },
  footer: {
    tagline: 'Safer Codex on Windows.',
    disclaimer: 'Community project. Not affiliated with OpenAI.',
    links: [
      { label: 'GitHub', href: 'https://github.com/QianQIUlp/codex-safe-setup' },
      {
        label: 'License',
        href: 'https://github.com/QianQIUlp/codex-safe-setup/blob/main/LICENSE',
      },
      {
        label: 'Security',
        href: 'https://github.com/QianQIUlp/codex-safe-setup/blob/main/SECURITY.md',
      },
      {
        label: 'Contributing',
        href: 'https://github.com/QianQIUlp/codex-safe-setup/blob/main/CONTRIBUTING.md',
      },
    ],
    languageLabel: 'Language',
  },
};
