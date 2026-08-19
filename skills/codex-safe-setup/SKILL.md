---
name: codex-safe-setup
description: Audit, explain, install, verify, or roll back a least-privilege local Codex configuration on Windows, macOS, Linux, or WSL. Use when a user wants safer Codex permissions, an alternative to Full Access, bounded autonomy without approval fatigue, protection against credential reads or unrestricted command networking, PowerShell 7 or Codex CLI prerequisite guidance, or recoverable Git checkpoints. Do not use for ordinary project permissions unrelated to Codex.
---

# Codex Safe Setup

Treat approval as a workflow choice, not a security boundary. Limit what Codex can write, read, and send; preserve recovery; then distinguish configuration checks from runtime proof.

## Required safety contract

Read [references/security-contract.md](references/security-contract.md) before assessing or changing a machine. Read [references/configuration-profiles.md](references/configuration-profiles.md) before presenting choices. Read [references/recovery.md](references/recovery.md) before enabling checkpoints or discussing recovery.

Never claim the resulting machine is absolutely safe. Never use an anecdotal credential theft report as proof of causation. If a real credential may already have been exposed, advise rotation, revocation, and usage review; configuration changes cannot undo prior exposure.

Do not read secret contents during assessment. Inspect only configuration text, tool versions, and the existence of known sensitive locations. Redact values in all reports.

## Workflow

### 1. Assess without changing state

Select `pwsh` when available; otherwise use Windows PowerShell only for assessment and bootstrap work.

Run:

```powershell
& <skill-dir>/scripts/Assess-CodexSafety.ps1
```

Report the effective evidence, including Full Access or legacy/new profile state, approval policy and reviewer, filesystem and command-network boundaries, Windows sandbox implementation, prerequisite versions, configuration conflicts, and unverified external tool surfaces.

### Existing installations and plugin updates

Plugin bundle updates and applied machine configuration are separate state layers. Updating or reinstalling the plugin does not silently rewrite `config.toml`, rules, checkpoints, or an already-running task.

If `CODEX_HOME/safe-setup/install-state.json` exists, do not rerun the first-install path. Run `Upgrade-CodexSafety.ps1` without confirmation first. It must preserve the recorded approval, network, Windows sandbox, workspace, backup, and rollback choices; show the previous and requested values; and make no changes until the user confirms the upgrade. Security broadening still requires the same acknowledgement as a new install.

For a 0.1.1-or-earlier `Unrestricted` installation, explain that the old wildcard proxy representation did not provide native direct networking. The 0.1.2 migration disables the filtering proxy, removes the wildcard domain table, records state schema 2, and requires a full Codex restart plus a fresh task. Never claim the plugin update alone activated this migration.

For 0.1.4-or-earlier installations, version 0.1.5 records state schema 4 and removes the alternate normal-Git Status / Commit bridge. Upgrade rewrites any schema-2 workspace registry to the recovery-only Save/List schema and does not preserve commit authorizations.

For 0.1.5 installations, version 0.1.6 records state schema 5 and fixes the Desktop routing conflict. The default DynamicUi migration removes the plugin-owned `default_permissions` pin and `[permissions.codex-safe-workspace]` table, preserves an existing UI-selected `sandbox_mode`, and otherwise installs a workspace fallback. Preview first; apply only after the DynamicUi read-scope disclosure is accepted.

### 2. Explain the choices before asking

Lead with: **Do not treat approval as safety. Limit what the agent can change, read, and send.**

Choose the permission-routing mode before approval or network settings:

- `DynamicUi` (default for 0.1.6): do not write `default_permissions` or a named profile. Use the legacy `sandbox_mode` / `sandbox_workspace_write` route so Full Access, Workspace, and Read-only changes apply to the next user message without restarting Codex. Disclose that legacy workspace semantics allow broad filesystem reads and cannot enforce the StrictProfile credential deny-globs. Require `-AcknowledgeDynamicUiReadScope` before apply. DynamicUi supports `Off` and `Unrestricted`; it rejects `Allowlist` because a persistent proxy would keep constraining Full Access.
- `StrictProfile`: retain the named root-deny, minimal-read, credential-deny, and proxy-allowlist profile. Use it when those boundaries matter more than pure same-task Full Access switching.

Offer these approval modes over the selected filesystem route:

- `BoundedAutonomy` (recommended): no approval prompts; attempts outside the boundary fail.
- `AskMe`: eligible boundary crossings go to the user.
- `AutoReview`: eligible boundary crossings go to a reviewer agent. Explain that this replaces the reviewer and does not strengthen the sandbox.

Offer command-network modes separately: `Off` (recommended) disables both command networking and the proxy; `Allowlist` enables the filtering proxy with explicit domains; `Unrestricted` disables the proxy and enables direct command networking for ordinary protocols such as SSH, only after a high-risk acknowledgement. Explain that command-network settings do not control Web Search, Browser, Computer Use, apps, plugins, MCP, or cloud tasks.

Before accepting `Unrestricted`, give the complete disclosure below in the user's language. Do not reduce it to "high risk" or ask for acknowledgement before explaining it:

- Enabling unrestricted command networking does not itself expand filesystem permissions or add deletion authority. The active filesystem profile still applies, and files that are already writable inside the workspace can still be changed or deleted.
- Disabling the filtering proxy removes the public-destination boundary and permits direct protocols such as SSH: any data a sandboxed command can already read or generate may be sent to any public Internet destination. That can include source, configuration, command output, private data, and credentials whose filenames were not covered by deny rules.
- Untrusted web pages, issues, or dependency documentation can contain prompt injection that induces exfiltration or unsafe commands. Networked commands can also download malware or vulnerable dependencies and introduce license-restricted content.
- This does not mean disclosure will automatically occur. It means a human, model, or prompt-injection mistake has a much larger possible consequence, and no domain rule is enforced in direct mode. Recommend `Allowlist` for normal proxy-compatible work and `Unrestricted` only when direct protocols are required or destinations cannot be enumerated.

Only after this disclosure, require an explicit acknowledgement equivalent to "I understand and accept unrestricted command-network risk."

### 3. Obtain dependency consent separately

Recommend PowerShell 7 on Windows because it reduces legacy shell, encoding, quoting, and compatibility surprises. State that it is not a security boundary and cannot prevent semantic path mistakes.

Recommend Codex CLI for version detection, `execpolicy` rule validation, and a complete verification result. Allow base configuration without it, but label that outcome `PARTIALLY VERIFIED`.

Never install either dependency without an explicit yes. After consent, run:

```powershell
& <skill-dir>/scripts/Install-Prerequisites.ps1 -PowerShell7 Install -CodexCli Install
```

Use `Skip` for each declined dependency. Do not silently install Node.js when npm is unavailable.

### 4. Preview the exact configuration

Choose Windows `Elevated` when the user accepts its administrator-approved setup; otherwise use `Unelevated` or `Keep` and explain the weaker boundary.

Run `Install-CodexSafety.ps1` with `-PlanOnly`. For StrictProfile, include `-MigrateLegacySettings` only after explaining that legacy sandbox keys will be replaced after backup. For DynamicUi, use the flag only when removing a user-owned non-plugin `default_permissions` value after explicit review.

Show the configuration path, managed keys, chosen boundaries, checkpoint registration, backup location, rollback command, and controls that remain outside this skill.

DynamicUi must remove the plugin-owned named profile and must not write `default_permissions`; `sandbox_mode` is only the persisted fallback and the task UI owns subsequent-turn routing. StrictProfile writes `default_permissions = "codex-safe-workspace"` and the named profile. Do not create or modify managed `allowed_permission_profiles` restrictions.

For a linked Git worktree, keep the parent repository's shared .git protected in the safe default. If the user temporarily selects Full Access for a task, use native Git normally in that task; Full Access must remove the sandbox restriction rather than route Git through a separate backend. Never add a parent-.git write exception or a commit bridge to compensate for a UI/runtime mismatch.

If direct Git reports surprising tracked deletions in the safe default, treat sandbox visibility or host ACL as hypotheses and verify them read-only. The codexsandboxonline and codexsandboxoffline account names identify Windows sandbox/network variants; neither name proves Full Access, filesystem scope, or effective task permissions.

### 5. Apply or upgrade only after confirmation

For an existing installation, apply the already previewed upgrade with:

```powershell
& <skill-dir>/scripts/Upgrade-CodexSafety.ps1 `
  -ConfirmUpgrade `
  -AcknowledgeDynamicUiReadScope `
  -AcknowledgeRisk `
  -AcknowledgeAdminSetup `
  -NonInteractive
```

Omit acknowledgements that do not apply to the selected route and network mode. DynamicUi always requires its read-scope acknowledgement. The upgrade writes a new transaction-scoped backup and immutable previous-state snapshot so rollback can traverse one configuration change at a time.

For a first installation, continue with the flow below.

After approval, rerun with `-ConfirmApply -NonInteractive`. DynamicUi also requires `-AcknowledgeDynamicUiReadScope`; `Unrestricted` requires `-AcknowledgeRisk`; `Elevated` requires `-AcknowledgeAdminSetup`.

```powershell
& <skill-dir>/scripts/Install-CodexSafety.ps1 `
  -ApprovalMode BoundedAutonomy `
  -PermissionRouting DynamicUi `
  -NetworkMode Off `
  -WindowsSandbox Elevated `
  -WorkspacePath <repo-root> `
  -MigrateLegacySettings `
  -AcknowledgeDynamicUiReadScope `
  -AcknowledgeAdminSetup `
  -ConfirmApply `
  -NonInteractive
```

Never install danger-full-access as the configured fallback. In DynamicUi, a deliberate Full Access selection must produce `sandboxPolicy.type = dangerFullAccess` for the next user message and subsequent turns in the same task.

### 6. Verify, activate, and report honestly

Run `Test-CodexSafety.ps1`. Treat static configuration and `execpolicy` checks as evidence, not runtime proof. Mark unavailable CLI rule checks as `PARTIAL`, not `PASS`.

After a successful DynamicUi apply, start one fresh task to load the machine-configuration change. Then prove both directions in that same task: select Full Access, send a new message, and require `sandboxPolicy.type = dangerFullAccess`; select Workspace or Read-only, send another message, and require the corresponding sandbox on the following turn. Those later UI changes must take effect on the next user message without restarting Codex.

Verify the effective runtime, not only the visible selector. For DynamicUi, prefer `sandboxPolicy.type`; for StrictProfile, prefer `activePermissionProfile.id`. The codexsandboxonline / codexsandboxoffline username is not proof of permission scope. If the UI says Full Access but runtime metadata does not report dangerFullAccess, report FAIL: UI/runtime permission mismatch; do not invent a Git backend. In a verified Full Access task, native Git must be able to update ordinary repository metadata, including a linked worktree's shared .git, subject only to normal OS ACLs.

A machine-configuration install or upgrade still needs one fresh task because the already-running environment does not reload the file. That is separate from routine DynamicUi changes: after activation, Full Access, Workspace, and Read-only changes must apply on the next message in the same task without a Codex restart. If administrator prompts repeat on Windows, require the user to fully quit every Codex desktop window and CLI process before one clean relaunch.

When Windows `Elevated` is selected, explain that an administrator-approved sandbox setup prompt can appear after relaunch, but it is not expected for each command. Repeated administrator prompts are a failure signal. Run the read-only assessment and inspect only its `WindowsSandboxSetupHealth` result: `Allowlist` expects proxy ports 3128 and 8081, while `Off` and direct `Unrestricted` expect no proxy ports. Aligned latest ports mean historical changes are informational; `CONFLICT` means stale Codex processes should be closed before one clean relaunch. Preserve `Elevated` unless its setup genuinely fails and the user explicitly chooses the weaker fallback.

Report `PASS`, `PARTIAL`, `FAIL`, or `NOT CONTROLLED` for writes outside workspace, reads outside workspace, workspace secret files, protected metadata, deletion recovery, command egress, separate external tool surfaces, and rollback.

### 7. Roll back on request

Run `Rollback-CodexSafety.ps1` without confirmation first so it shows the target backup. Obtain confirmation immediately before restoring or removing configuration.

## Checkpoint rule

Allow only the installed `New-CodexCheckpoint.ps1` bridge through the exact PowerShell 7 executable and exact script path. Never allow a general `pwsh`, `powershell`, `git`, shell-wrapper, or arbitrary-script prefix.

The recovery bridge must accept only registered repositories and a pinned Git executable. Save creates a hidden checkpoint without changing the branch or real index, and List enumerates those checkpoints. It must not expose Status, Commit, general Git, or a shell escape. Normal status, add, commit, and branch operations remain native Git operations and require a task whose effective permissions actually permit them.
