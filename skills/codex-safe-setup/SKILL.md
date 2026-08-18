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

For 0.1.2 installations, version 0.1.3 records state schema 3 and upgrades the registered-workspace bridge without making shared Git metadata writable. Preserve the prior Git commit-bridge choice. Enabling normal branch commits is a separate capability choice: preview it first and require the user to explicitly select it for an exact registered worktree.

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

For a linked Git worktree, keep the parent repository's shared `.git` protected. If the user needs normal commits, offer `-EnableGitCommitBridge $true` only after explaining that the bridge will update the real index and current branch for explicit paths. The default branch prefix is `codex/`; use `-CommitBranchPrefix` only when the user explicitly chooses another prefix. Do not replace this with a broad filesystem write exception for the parent `.git`.

Use bridge `Status` when direct `git status` reports surprising tracked deletions. A difference means the sandbox profile or host ACL is hiding files from the direct Git process; it is not evidence that the project deleted them. Credential-style tracked fixtures such as public test certificates still require exact, reviewed read exceptions; never disable the workspace secret globs wholesale.

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

Never select or preserve `danger-full-access` as a verified safe profile.

### 6. Verify, activate, and report honestly

Run `Test-CodexSafety.ps1`. Treat static configuration and `execpolicy` checks as evidence, not runtime proof. Mark unavailable CLI rule checks as `PARTIAL`, not `PASS`.

After a successful apply, end with a visible activation block. Tell the user to open the Codex permission selector, choose `Custom` / `???`, and confirm that `codex-safe-workspace` is the selected profile; explicitly say not to choose Full Access. On Windows, tell the user to restart Codex and start a new task rather than resume a pre-install task because existing execution environments retain their old proxy and sandbox state. If administrator prompts repeat, then require the user to fully quit every Codex desktop window and CLI process before one clean relaunch; alternating old and new loopback proxy port sets can invalidate the global elevated-firewall setup. On other platforms, start a new Codex task or CLI session because an existing execution environment does not retroactively adopt the new profile. Never imply that writing the file changed the current task's permissions.

When Windows `Elevated` is selected, explain that an administrator-approved sandbox setup prompt can appear after relaunch, but it is not expected for each command. Repeated administrator prompts are a failure signal. Run the read-only assessment and inspect only its `WindowsSandboxSetupHealth` result: `Allowlist` expects proxy ports 3128 and 8081, while `Off` and direct `Unrestricted` expect no proxy ports. Aligned latest ports mean historical changes are informational; `CONFLICT` means stale Codex processes should be closed before one clean relaunch. Preserve `Elevated` unless its setup genuinely fails and the user explicitly chooses the weaker fallback.

Report `PASS`, `PARTIAL`, `FAIL`, or `NOT CONTROLLED` for writes outside workspace, reads outside workspace, workspace secret files, protected metadata, deletion recovery, command egress, separate external tool surfaces, and rollback.

### 7. Roll back on request

Run `Rollback-CodexSafety.ps1` without confirmation first so it shows the target backup. Obtain confirmation immediately before restoring or removing configuration.

## Checkpoint rule

Allow only the installed `New-CodexCheckpoint.ps1` bridge through the exact PowerShell 7 executable and exact script path. Never allow a general `pwsh`, `powershell`, `git`, shell-wrapper, or arbitrary-script prefix.

The bridge must accept only registered repositories and a pinned Git executable. `Save` creates a hidden checkpoint without changing the branch or real index; `Status` reports the repository state outside protected metadata. `Commit` is opt-in, accepts explicit literal paths only, requires an allowed branch prefix and an initially clean index, refuses in-progress Git operations and repository-local clean/process filters, suppresses hooks and signing, and leaves unselected changes untouched. Never use it as a general Git or shell escape.
