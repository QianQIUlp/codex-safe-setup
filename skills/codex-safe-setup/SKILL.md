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

For 0.1.5 installations, version 0.1.6 records state schema 5 and introduced the legacy DynamicUi route. That migration removed the plugin-owned permission profile and restored built-in UI switching, but it also removed Custom from the menu.

For 0.1.6 installations, version 0.1.7 records state schema 6 and restores the Custom menu through one permission-profile family. DynamicUi removes legacy `sandbox_mode` / `sandbox_workspace_write`, maps a deliberate legacy startup choice to the corresponding built-in `default_permissions` ID, and writes `codex-safe-workspace` with positive grants only. It requires Codex CLI 0.147.0 or newer. Never put an explicit filesystem `deny` in the DynamicUi Custom profile: Codex preserves deny entries across profile changes, which can make a later Full Access selection remain managed and restricted.

For 0.1.7 installations, version 0.1.8 records state schema 7 and removes the sole named DynamicUi profile plus `default_permissions`. The old Desktop selector temporarily displayed that sole name while a running turn stopped sending permission overrides, even though the user's last deliberate click still governed the next turn. DynamicUi now always writes a distinct `Custom (config.toml)` workspace-write fallback. This is an intentional backed-up migration; use `-MigrateLegacySettings` after explaining it. StrictProfile keeps the named profile.

For 0.1.8 or 0.1.9 development installations, version 0.2.0 records state schema 9. DynamicUi removes legacy sandbox and top-level approval keys, sets built-in `:workspace` only as the startup default, and installs two positive-only named profiles: `codex-safe-workspace` and `codex-safe-workspace-offline`. Runtime semantics remain last-manual-click wins. Do not claim this config shape alone fixes visible label oscillation on every Desktop build; the optional Windows compatibility layer below is a separate installation and state boundary.

### 2. Explain the choices before asking

Lead with: **Do not treat approval as safety. Limit what the agent can change, read, and send.**

Choose the permission-routing mode before approval or network settings:

- `DynamicUi` (default for 0.2.0): install two positive-only named profiles, `codex-safe-workspace` and `codex-safe-workspace-offline`, with top-level `default_permissions = ":workspace"`. Remove top-level `sandbox_mode`, `approval_policy`, `approvals_reviewer`, and `[sandbox_workspace_write]` so the dynamic route has one authoritative permission family and no sticky filesystem denies. Custom / 自定义, Full Access, Workspace, and Read-only must replace one another on the next user message without restarting Codex. Disclose that Custom follows the broader workspace sandbox read scope and cannot install credential deny-globs; workspace credential files remain readable while the workspace is writable. Require Codex CLI 0.138.0 or newer and `-AcknowledgeDynamicUiReadScope`. DynamicUi supports `Off` and `Unrestricted`; the offline profile always disables command network. It rejects `Allowlist` because a persistent proxy would keep constraining Full Access.
- `StrictProfile`: write `default_permissions = "codex-safe-workspace"` so the same named root-deny, minimal-read, credential-deny, and proxy-allowlist profile is the fixed default. Use it only when that fixed boundary matters more than same-task Full Access switching.

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

Recommend Codex CLI for version detection, `execpolicy` rule validation, and a complete verification result. StrictProfile can be configured without it but remains `PARTIALLY VERIFIED`; DynamicUi must refuse apply unless a detected CLI is version 0.138.0 or newer because its config.toml Custom catalog behavior is version-specific.

Never install either dependency without an explicit yes. After consent, run:

```powershell
& <skill-dir>/scripts/Install-Prerequisites.ps1 -PowerShell7 Install -CodexCli Install
```

Use `Skip` for each declined dependency. Do not silently install Node.js when npm is unavailable.

### 4. Preview the exact configuration

Choose Windows `Elevated` when the user accepts its administrator-approved setup; otherwise use `Unelevated` or `Keep` and explain the weaker boundary.

Run `Install-CodexSafety.ps1` with `-PlanOnly`. For StrictProfile, include `-MigrateLegacySettings` only after explaining that legacy sandbox keys will be replaced after backup. For DynamicUi, use it when replacing an older generic Custom or single-profile shape after explicit review; the resulting dual named-profile route is the intended DynamicUi representation.

Show the configuration path, managed keys, chosen boundaries, checkpoint registration, backup location, rollback command, and controls that remain outside this skill.

DynamicUi must write built-in `default_permissions = ":workspace"`, both plugin-owned positive-only named profiles, and no legacy sandbox or top-level approval keys. StrictProfile writes `default_permissions = "codex-safe-workspace"` with explicit root and credential denies and removes the DynamicUi compatibility profile. Never mix the two configuration families. Do not create or modify managed `allowed_permission_profiles` restrictions.

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

Never treat the config fallback or a rollout echo as evidence of what the user last deliberately clicked. In DynamicUi, selecting Full Access must produce `sandbox_policy.type = danger-full-access`, `permission_profile.type = disabled`, and a successful outside-workspace canary on the next user message.

### 6. Verify, activate, and report honestly

Run `Test-CodexSafety.ps1`. Treat static configuration and `execpolicy` checks as evidence, not runtime proof. Mark unavailable CLI rule checks as `PARTIAL`, not `PASS`.

After a successful DynamicUi apply, start one fresh task to load the machine-configuration change. Use `<skill-dir>/scripts/Test-DesktopPermissionE2E.ps1 -ShowPrompts`, complete its setup turn, then run all three probes in that same task in order: `codex-safe-workspace`, Full Access, built-in Workspace. For each probe, directly observe that the deliberately clicked label is identical before sending, while the turn runs, and after it finishes. The verifier must require that explicit visual confirmation plus a real Codex Desktop `session_meta` with no replacement during the probe window, and correlate each exact generated command with its preceding `turn_context`, later `task_complete`, exit status, and outside-workspace canary. Those UI changes must take effect on the next user message without restarting Codex.

Verify visual state and effective runtime as separate conditions. Rollout records cannot prove what the selector displayed, while the selector cannot prove runtime scope. Full Access requires effective `danger-full-access`, a disabled permission profile, and active `:danger-full-access`. Custom requires active `codex-safe-workspace`, managed workspace-write, a failed outside-workspace canary, and zero explicit deny entries. Built-in Workspace requires active `:workspace` with no stale deny entries. The codexsandboxonline / codexsandboxoffline username is not proof of permission scope. On any mismatch, report FAIL and do not invent a Git backend. In verified Full Access, native Git must be able to update ordinary repository metadata, including a linked worktree's shared .git, subject only to normal OS ACLs.

If runtime routing passes but direct observation still shows a Windows Desktop label change without a click, treat it as an upstream Desktop defect: record the observation, help the user file a report with OpenAI, and do not attempt to patch, relaunch, or redirect the signed client. This project never modifies or redistributes client files, never scans proprietary application bundles for private feature gates, never injects code into the Desktop process, and must never modify WindowsApps or package any OpenAI executable, ASAR, renderer bundle, or other client file. If a legacy installation from version 0.2.0 or earlier left launcher shortcuts, watchers, environment variables, or state folders behind, offer `Remove-LegacyDesktopSelectorArtifacts.ps1 -PlanOnly` first and apply only after explicit confirmation; it archives every shortcut before deletion and never closes any process.

A machine-configuration install or upgrade still needs one fresh task because the already-running environment does not reload the file. That is separate from routine DynamicUi changes: after activation, Full Access, Workspace, and Read-only changes must apply on the next message in the same task without a Codex restart. If administrator prompts repeat on Windows, require the user to fully quit every Codex desktop window and CLI process before one clean relaunch.

When Windows `Elevated` is selected, explain that an administrator-approved sandbox setup prompt can appear after relaunch, but it is not expected for each command. Repeated administrator prompts are a failure signal. Run the read-only assessment and inspect only its `WindowsSandboxSetupHealth` result: `Allowlist` expects proxy ports 3128 and 8081, while `Off` and direct `Unrestricted` expect no proxy ports. Aligned latest ports mean historical changes are informational; `CONFLICT` means stale Codex processes should be closed before one clean relaunch. Preserve `Elevated` unless its setup genuinely fails and the user explicitly chooses the weaker fallback.

Report `PASS`, `PARTIAL`, `FAIL`, or `NOT CONTROLLED` for writes outside workspace, reads outside workspace, workspace secret files, protected metadata, deletion recovery, command egress, separate external tool surfaces, and rollback.

### 7. Roll back on request

Run `Rollback-CodexSafety.ps1` without confirmation first so it shows the target backup. Obtain confirmation immediately before restoring or removing configuration.

A retired Desktop selector installation from version 0.2.0 or earlier keeps its own state under `CODEX_HOME/safe-setup/desktop-selector-fix.json` and `desktop-selector-fix-history`. Preview `Remove-LegacyDesktopSelectorArtifacts.ps1 -PlanOnly`, then require `-ConfirmApply`. The cleanup removes only exact-match retired shortcuts (archiving each one first), listed user-scope `CSS_DESKTOP_SELECTOR_*` environment variables, and those retired state paths into a quarantine folder; it never touches processes or the official client.

## Checkpoint rule

Allow only the installed `New-CodexCheckpoint.ps1` bridge through the exact PowerShell 7 executable and exact script path. Never allow a general `pwsh`, `powershell`, `git`, shell-wrapper, or arbitrary-script prefix.

The recovery bridge must accept only registered repositories and a pinned Git executable. Save creates a hidden checkpoint without changing the branch or real index, and List enumerates those checkpoints. It must not expose Status, Commit, general Git, or a shell escape. Normal status, add, commit, and branch operations remain native Git operations and require a task whose effective permissions actually permit them.
