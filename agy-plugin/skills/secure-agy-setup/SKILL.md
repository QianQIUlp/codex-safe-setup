---
name: secure-agy-setup
description: Audit, explain, install, verify, or roll back a least-privilege local Antigravity (AGY) configuration. Use when a user wants safer Antigravity permissions, bounded autonomy without approval fatigue, protection against credential reads or unrestricted networking, or recoverable Git checkpoints.
---

# Secure Antigravity Setup

Treat approval as a workflow choice, not a security boundary. Limit what Antigravity can write, read, and send; preserve recovery; then distinguish configuration checks from runtime proof.

## Required Safety Contract

Read [references/security-contract.md](references/security-contract.md) before assessing or changing a machine. Read [references/configuration-profiles.md](references/configuration-profiles.md) before presenting choices. Read [references/recovery.md](references/recovery.md) before enabling checkpoints or discussing recovery.

Never claim the resulting setup is absolutely safe. Do not read secret contents during assessment. Inspect only configuration text, tool versions, and the existence of known sensitive locations.

## Workflow

### 1. Assess without changing state
Run:
```powershell
& <skill-dir>/scripts/Assess-AgySafety.ps1
```
Report effective evidence:
- Non-Workspace file access setting
- Tool execution policy
- Terminal sandbox enablement
- Internet access policy
- Presence of sensitive directories (`.ssh`, `.aws`, etc.)
- Tool prerequisites (`pwsh`, `agy`, `git`, `node`)

### 2. Explain the choices before asking
Lead with: **Do not treat approval as safety. Limit what the agent can change, read, and send.**

Offer these approval modes over the same least-privilege filesystem profile:
- `BoundedAutonomy` (recommended): `proceed-in-sandbox`, out-of-boundary actions fail closed without approval prompts.
- `AskMe`: `request-review`, eligible boundary crossings prompt the user.
- `Strict`: `strict`, high friction for all tool actions.

Offer command-network modes separately: `Off` (recommended), `Allowlist` with explicit domains, or `Unrestricted` (only after full risk disclosure and explicit acknowledgement).

### 3. Obtain prerequisite consent separately
Recommend PowerShell 7 and Git. Never install either without explicit confirmation:
```powershell
& <skill-dir>/scripts/Install-Prerequisites.ps1 -PowerShell7 Install -Git Install
```

### 4. Preview the exact configuration
Run:
```powershell
& <skill-dir>/scripts/Install-AgySafety.ps1 -ApprovalMode BoundedAutonomy -NetworkMode Off -WorkspacePath <workspace-root> -PlanOnly
```

### 5. Apply only after confirmation
After user approval:
```powershell
& <skill-dir>/scripts/Install-AgySafety.ps1 `
  -ApprovalMode BoundedAutonomy `
  -NetworkMode Off `
  -WorkspacePath <workspace-root> `
  -ConfirmApply `
  -NonInteractive
```

### 6. Verify and report honestly
Run:
```powershell
& <skill-dir>/scripts/Test-AgySafety.ps1
```
Report `PASS`, `PARTIAL`, `FAIL`, or `NOT CONTROLLED` for:
- Non-Workspace file access
- Terminal sandbox
- Workspace credential protection (via PreToolUse lifecycle hook)
- Checkpoint bridge
- Rollback backups
- External surfaces (Web Search, MCP servers, host OS)

### 7. Rollback on request
Run:
```powershell
& <skill-dir>/scripts/Rollback-AgySafety.ps1
```
