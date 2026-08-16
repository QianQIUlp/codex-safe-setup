---
name: secure-zcode-setup
description: Audit, explain, install, verify, or roll back an OS-enforced ZCode boundary on Windows: a dedicated low-privilege local user with NTFS ACL grants, secret deny ACEs, a Program Files launcher copy, and recoverable Git checkpoints. Use when a user wants hard limits on what a ZCode agent can read, write, or reach, an alternative to trusting approval prompts, or credential-exposure protection. Do not use for ordinary project permissions unrelated to ZCode.
when_to_use: The user asks to sandbox, cage, limit, or harden ZCode; wants boundaries instead of approval; mentions credential exposure, a dedicated Windows user, or ZCode checkpoints.
---

# Secure ZCode Setup (OS Cage)

Approval is a workflow choice, not a security boundary. ZCode has no configuration-file
equivalent of Codex permission profiles, so the boundary is enforced by the operating
system itself: ZCode runs as a dedicated standard Windows user whose NTFS ACLs decide
what can be read, written, and executed - regardless of what any model attempts.

## Required safety contract

Read [references/security-contract.md](references/security-contract.md) before assessing
or changing a machine. Read [references/os-boundary-model.md](references/os-boundary-model.md)
before presenting choices. Read [references/recovery.md](references/recovery.md) before
enabling checkpoints or discussing recovery.

Never claim the resulting machine is absolutely safe. If a real credential may already
have been exposed, advise rotation, revocation, and usage review; boundaries cannot undo
prior exposure.

Do not read secret contents during assessment. Inspect only configuration text, account
existence, ACL text, and the existence of known sensitive locations.

## Workflow

### 1. Assess without changing state

```powershell
& <skill-dir>/scripts/Assess-ZcodeSafety.ps1
```

Report: ZCode install location (user-profile vs admin-controlled), existing cage state,
credential-location existence (never contents), execution-control posture, tool
availability, and the NOT CONTROLLED surface.

### 2. Explain the boundary model before asking

Lead with: **Do not treat approval as safety. The cage limits what the agent can read,
write, and execute - enforced by Windows, not by the model's good behavior.**

Explain the boundary set (see references/os-boundary-model.md):
- Main user profile, credentials, SSH keys: **unreadable** by the sandbox user.
- Authorized workspace roots: writable; everything else outside them: **not writable**.
- Existing secret-like files in those roots: **deny ACEs** for the sandbox user.
- ZCode runs from an admin-controlled Program Files copy (required on hardened machines).
- Recovery: Git checkpoints and exact rollback of the whole installation.

Then state the honest limits - network egress is NOT CONTROLLED (Windows Firewall cannot
scope by user for one executable path; WebFetch, WebSearch, MCP, and curl inside the cage
can reach any destination), secret files created after install are not covered, and the
sandbox user's own ZCode credentials remain readable by the main user (the trusted root).
Never compress this into "basically safe".

### 3. Obtain consents separately

- **Administrator setup (one UAC prompt)**: creating the sandbox account and copying
  ZCode into Program Files require an administrator token. Nothing installs silently.
- **PowerShell 7** is optional (script fidelity only; not a boundary). Offer
  `Install-Prerequisites.ps1 -PowerShell7 Install` only after an explicit yes.
- **Checkpoints** (`-InstallCheckpoints`) are a separate opt-in.

### 4. Preview the exact plan

```powershell
& <skill-dir>/scripts/Install-ZcodeSafety.ps1 -WorkspacePath <repo-root> -PlanOnly
```

Show: account name, install copy location, granted roots, the exact secret files that
will receive deny ACEs, the canary, the shortcut, the recorded state for rollback, and
what stays NOT CONTROLLED.

### 5. Apply only after confirmation

```powershell
& <skill-dir>/scripts/Install-ZcodeSafety.ps1 `
  -WorkspacePath <repo-root> `
  -InstallCheckpoints `
  -AcknowledgeAdminSetup `
  -ConfirmApply `
  -NonInteractive
```

One UAC prompt appears. A failure mid-apply undoes its own partial changes and never
writes install-state.json.

### 6. Verify, activate, and report honestly

```powershell
& <skill-dir>/scripts/Test-ZcodeSafety.ps1
```

Structural checks are evidence, not proof; the live probe phase runs as the sandbox user
and asserts that forbidden reads fail and allowed writes succeed. Anything unprovable is
PARTIAL or NOT CONTROLLED - never PASS.

End every successful install with a visible activation block: launch ZCode through the
new "ZCode (Sandboxed)" shortcut, log in once inside that window, and start a NEW session
there. State explicitly that main-user ZCode windows are NOT inside the cage and that an
already-running main-user session does not become protected.

Report PASS / PARTIAL / FAIL / NOT CONTROLLED for: reads outside the cage, writes outside
granted roots, workspace secret files, install-copy integrity, self-protection of the cage
state, deletion recovery, network egress, and rollback readiness.

### 7. Roll back on request

```powershell
& <skill-dir>/scripts/Rollback-ZcodeSafety.ps1
```

It lists the exact recorded targets first and needs `-Confirm` before touching anything.
Workspace trees themselves are never modified - only the sandbox ACEs are removed.

## Checkpoint rule

Checkpoints go only through the installed `New-ZcodeCheckpoint.ps1` bridge (PowerShell 7,
exact installed path), which accepts only registered repositories, refuses
sensitive-looking untracked files, creates a hidden commit on `refs/zcode-safe/checkpoints/*`
without touching branch or index, and leaves restoration user-controlled
(`git worktree add <dir> <checkpoint-commit>`). Never run ad-hoc `git reset`, `git clean`,
or `git checkout` as a "recovery" mechanism.
