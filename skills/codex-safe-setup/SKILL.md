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

For 0.1.4-or-earlier installations, version 0.1.5 records state schema 4 and removes the alternate normal-Git Status / Commit bridge. Upgrade rewrites any schema-2 workspace registry to the recovery-only Save/List schema and does not preserve commit authorizations. The user's safe default profile, networking choice, backups, rollback chain, and optional recovery checkpoints remain intact.

### 2. Explain the choices before asking

Lead with: **Do not treat approval as safety. Limit what the agent can change, read, and send.**

Offer these approval modes over the same least-privilege filesystem profile:

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

Run `Install-CodexSafety.ps1` with `-PlanOnly`. Include `-MigrateLegacySettings` only after explaining that the installer will replace conflicting legacy sandbox keys while retaining a full backup.

Show the configuration path, managed keys, chosen boundaries, checkpoint registration, backup location, rollback command, and controls that remain outside this skill.

Write the named profile as default_permissions only. This is the fallback when a task has no explicit permission selection; it must not be presented as a lock on the Codex UI. Do not create or modify managed allowed_permission_profiles restrictions, and do not reintroduce legacy sandbox_mode keys.

For a linked Git worktree, keep the parent repository's shared .git protected in the safe default. If the user temporarily selects Full Access for a task, use native Git normally in that task; Full Access must remove the sandbox restriction rather than route Git through a separate backend. Never add a parent-.git write exception or a commit bridge to compensate for a UI/runtime mismatch.

If direct Git reports surprising tracked deletions in the safe default, treat sandbox visibility or host ACL as hypotheses and verify them read-only. The codexsandboxonline and codexsandboxoffline account names identify Windows sandbox/network variants; neither name proves Full Access, filesystem scope, or effective task permissions.

### 5. Apply or upgrade only after confirmation

For an existing installation, apply the already previewed upgrade with:

```powershell
& <skill-dir>/scripts/Upgrade-CodexSafety.ps1 `
  -ConfirmUpgrade `
  -AcknowledgeRisk `
  -AcknowledgeAdminSetup `
  -NonInteractive
```

Omit acknowledgements that do not apply to the preserved selections. The upgrade writes a new transaction-scoped backup and immutable previous-state snapshot so rollback can traverse one configuration change at a time.

For a first installation, continue with the flow below.

After approval, rerun with `-ConfirmApply -NonInteractive`. For `Unrestricted`, also require `-AcknowledgeRisk`. For `Elevated`, require `-AcknowledgeAdminSetup`.

```powershell
& <skill-dir>/scripts/Install-CodexSafety.ps1 `
  -ApprovalMode BoundedAutonomy `
  -NetworkMode Off `
  -WindowsSandbox Elevated `
  -WorkspacePath <repo-root> `
  -MigrateLegacySettings `
  -AcknowledgeAdminSetup `
  -ConfirmApply `
  -NonInteractive
```

Never install :danger-full-access as the configured default. It remains a valid explicit, temporary task-level override when the user deliberately selects Full Access in the Codex UI.

### 6. Verify, activate, and report honestly

Run `Test-CodexSafety.ps1`. Treat static configuration and `execpolicy` checks as evidence, not runtime proof. Mark unavailable CLI rule checks as `PARTIAL`, not `PASS`.

After a successful apply, end with a visible activation block. Explain that Custom / 自定义 with codex-safe-workspace is the normal default. Also explain that an explicit UI selection of Full Access for a task must override that fallback and activate the built-in :danger-full-access profile for that task and subsequent turns.

Verify the effective runtime, not only the visible selector. Prefer the task response's activePermissionProfile.id; accept authoritative task metadata that explicitly says danger-full-access when the profile id is unavailable. The codexsandboxonline / codexsandboxoffline username is not proof of permission scope. If the UI says Full Access but runtime metadata still reports the custom/workspace profile, report FAIL: UI/runtime permission mismatch; do not claim Full Access and do not invent a Git backend. In a verified Full Access task, native Git must be able to update the repository's ordinary metadata, including a linked worktree's shared .git, subject only to normal OS ACLs.

On Windows, restart Codex and start a new task after installing or upgrading the machine configuration because an existing execution environment does not reload the new default, proxy, or sandbox setup from disk. A later UI permission change within a supported task is different: the Codex protocol defines it for subsequent turns and its returned runtime profile is the acceptance result. If administrator prompts repeat, require the user to fully quit every Codex desktop window and CLI process before one clean relaunch; alternating old and new loopback proxy port sets can invalidate the global elevated-firewall setup. On other platforms, start a new task or CLI session after configuration changes. Never imply that writing the file changed the current task's permissions.

When Windows `Elevated` is selected, explain that an administrator-approved sandbox setup prompt can appear after relaunch, but it is not expected for each command. Repeated administrator prompts are a failure signal. Run the read-only assessment and inspect only its `WindowsSandboxSetupHealth` result: `Allowlist` expects proxy ports 3128 and 8081, while `Off` and direct `Unrestricted` expect no proxy ports. Aligned latest ports mean historical changes are informational; `CONFLICT` means stale Codex processes should be closed before one clean relaunch. Preserve `Elevated` unless its setup genuinely fails and the user explicitly chooses the weaker fallback.

Report `PASS`, `PARTIAL`, `FAIL`, or `NOT CONTROLLED` for writes outside workspace, reads outside workspace, workspace secret files, protected metadata, deletion recovery, command egress, separate external tool surfaces, and rollback.

### 7. Roll back on request

Run `Rollback-CodexSafety.ps1` without confirmation first so it shows the target backup. Obtain confirmation immediately before restoring or removing configuration.

## Checkpoint rule

Allow only the installed `New-CodexCheckpoint.ps1` bridge through the exact PowerShell 7 executable and exact script path. Never allow a general `pwsh`, `powershell`, `git`, shell-wrapper, or arbitrary-script prefix.

The recovery bridge must accept only registered repositories and a pinned Git executable. Save creates a hidden checkpoint without changing the branch or real index, and List enumerates those checkpoints. It must not expose Status, Commit, general Git, or a shell escape. Normal status, add, commit, and branch operations remain native Git operations and require a task whose effective permissions actually permit them.
