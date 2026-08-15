# How it works

## Installation flow

The skill executes a staged workflow so that assessment, consent, mutation, and verification cannot be confused:

```mermaid
flowchart LR
    A["Read-only assessment"] --> B["Explain boundaries and choices"]
    B --> C["Separate prerequisite consent"]
    C --> D["Plan-only configuration preview"]
    D --> E["Explicit apply confirmation"]
    E --> F["Static and execpolicy verification"]
    F --> G["Restart and runtime probes"]
    E --> H["Recorded backup and rollback"]
```

### 1. Assess

`Assess-CodexSafety.ps1` reads configuration, relevant path existence, and tool versions. It does not read secret contents. Its report separates the approval reviewer, filesystem policy, command-network policy, Windows sandbox implementation, prerequisite status, legacy conflicts, and external surfaces.

### 2. Select a profile

All three approval modes use the same least-privilege filesystem profile:

- `BoundedAutonomy`: `approval_policy = "never"`; out-of-bound actions fail.
- `AskMe`: eligible requests use `on-request` with the user as reviewer.
- `AutoReview`: eligible requests use `on-request` with an agent reviewer.

Command networking is configured separately as off, proxy-enforced allowlist, or explicitly acknowledged unrestricted access.

### 3. Preview and apply

`Install-CodexSafety.ps1 -PlanOnly` shows the exact managed targets and decisions without changing them. Applying requires `-ConfirmApply -NonInteractive`. High-risk or administrator-backed choices require additional acknowledgements. Legacy sandbox migration is rejected unless `-MigrateLegacySettings` is present.

The installer preserves unrelated TOML content, backs up each managed target, writes the permission profile and rule, registers authorized workspace roots, installs a synthetic outside-workspace canary, and records rollback state.

On Windows, writing the configuration is not the activation boundary. Restart Codex and use a new task because an existing execution environment retains its original sandbox and proxy state. If administrator prompts repeat, close every Codex desktop and CLI process before one clean relaunch. The preferred `Elevated` sandbox may request administrator-approved OS setup, but it does not elevate each workspace command.

The Windows sandbox stores firewall setup for the active loopback proxy ports. If an older task and a newly configured task use different port sets, each can invalidate the other's global setup and cause another administrator prompt. The read-only assessment retains only matching firewall port-change records from Codex's sandbox log and reports `WindowsSandboxSetupHealth`; it never includes logged command lines. A `CONFLICT` means the latest setup does not match the managed proxy defaults (`3128` and `8081`). `OSCILLATION_HISTORY` means a direct reversal occurred but the latest setup is aligned, so verification passes and no action is required unless prompts recur.

### 4. Verify

`Test-CodexSafety.ps1` checks the generated configuration and, when a compatible CLI is available, calls `codex execpolicy check` against both allowed and deliberately broad command prefixes. Missing CLI verification produces `PARTIAL`, never a false `PASS`.

### 5. Roll back

`Rollback-CodexSafety.ps1` first displays the recorded target backup. Restore or removal happens only after confirmation. The rollback implementation validates every target against its fixed Codex Home layout before writing.

## Checkpoint bridge

The workspace sandbox intentionally protects `.git`. The optional bridge is copied to `CODEX_HOME/safe-setup/bin` and is the only PowerShell script allowed by the generated command rule. The rule matches the exact PowerShell 7 executable and exact bridge path; it does not allow a general `pwsh`, `powershell`, `git`, shell wrapper, or arbitrary script.

For `Save`, the bridge:

1. Resolves the requested repository to a canonical path.
2. Confirms it is present in `authorized-workspaces.json`.
3. Confirms the configured Git executable still has its pinned SHA-256.
4. Refuses sensitive-looking untracked paths.
5. Uses a temporary Git index to build a tree and commit.
6. Stores the commit under `refs/codex-safe/checkpoints/*`.
7. Removes the temporary index.

The current branch, `HEAD`, real index, and working tree are unchanged. The bridge exposes only `Save` and `List`. Recovery stays user-controlled and should normally use a separate worktree:

```powershell
git worktree add <new-empty-directory> <checkpoint-commit>
```

## Files managed on the user machine

Exact locations depend on `CODEX_HOME`, which defaults to the normal Codex user directory.

| Target | Purpose |
|---|---|
| `config.toml` | Active permission, approval, sandbox, and network selections |
| `rules/codex-safe-setup.rules` | Exact checkpoint command rule |
| `safe-setup/bin/New-CodexCheckpoint.ps1` | Installed narrow checkpoint bridge |
| `safe-setup/authorized-workspaces.json` | Canonical workspace roots and pinned Git |
| `safe-setup/backups/*` | Restore material and installation state |
| `safe-setup/outside-workspace-canary.txt` | Synthetic target for boundary testing |

## Source layout

- `.codex-plugin/plugin.json`: plugin identity and install metadata.
- `.agents/plugins/marketplace.json`: Git-backed marketplace entry.
- `skills/secure-codex-setup/SKILL.md`: agent workflow and mandatory safety contract.
- `skills/secure-codex-setup/scripts/`: deterministic assessment, install, verify, checkpoint, and rollback code.
- `skills/secure-codex-setup/references/`: detailed profile, security, and recovery guidance loaded when needed.
- `tests/`: isolated integration and package checks.
- `tools/Build-Release.ps1`: install-ready ZIP builder.
