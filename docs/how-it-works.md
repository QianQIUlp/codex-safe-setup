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
    F --> G["Fresh task and runtime probes"]
    E --> H["Recorded backup and rollback"]
```

### 1. Assess

`Assess-CodexSafety.ps1` reads configuration, relevant path existence, and tool versions. It does not read secret contents. Its report separates the approval reviewer, filesystem policy, command-network policy, Windows sandbox implementation, prerequisite status, legacy conflicts, and external surfaces.

### 2. Select a routing mode

Version 0.2.0 separates permission routing from approval policy:

- `DynamicUi` exposes two positive-only named profiles on Codex 0.138.0 or newer and uses built-in `:workspace` only as the startup default. It has no sticky filesystem deny entries, and the user's last deliberate click governs the next message.
- `StrictProfile` uses `default_permissions = "codex-safe-workspace"` with root deny-read, credential deny-globs, and optional proxy allowlists. It is the stronger read boundary but is not the pure dynamic Full Access route.

All three approval modes work with either route:

- `BoundedAutonomy`: `approval_policy = "never"`; out-of-bound actions fail.
- `AskMe`: eligible requests use `on-request` with the user as reviewer.
- `AutoReview`: eligible requests use `on-request` with an agent reviewer.

Command networking is configured separately as offline with no proxy, proxy-enforced allowlist, or explicitly acknowledged direct unrestricted access with no proxy. DynamicUi supports Off and Unrestricted; it rejects Allowlist because a persistent proxy would keep constraining Full Access. StrictProfile supports all three modes.

Both DynamicUi Custom profiles extend Codex's Workspace sandbox and contain no explicit filesystem deny. Reads follow that sandbox's broader scope; workspace credential files remain readable while the workspace is writable. Applying DynamicUi requires an explicit read-scope acknowledgement.

### 3. Preview and apply

`Install-CodexSafety.ps1 -PlanOnly` shows the exact managed targets and decisions without changing them. Applying requires `-ConfirmApply -NonInteractive`. High-risk or administrator-backed choices require additional acknowledgements. Legacy sandbox migration is rejected unless `-MigrateLegacySettings` is present.

The installer preserves unrelated TOML content, backs up each managed target, writes the selected permission route and rule, registers authorized workspace roots, installs a synthetic outside-workspace canary, and records rollback state.

A machine-configuration change needs one fresh task. After that activation, DynamicUi changes are different: select Custom, Full Access, Workspace, or Read-only and send the next user message; the same task must adopt the corresponding policy without restarting Codex. If administrator prompts repeat on Windows, close every Codex desktop and CLI process before one clean relaunch.

The Windows sandbox stores firewall setup for the active network route. `Allowlist` expects loopback proxy ports 3128 and 8081; `Off` and direct `Unrestricted` expect no proxy ports. If an older task and a newly configured task use different port sets, each can invalidate the other's global setup and cause another administrator prompt. The read-only assessment retains only matching firewall port-change records from Codex's sandbox log and reports `WindowsSandboxSetupHealth`; it never includes logged command lines. A `CONFLICT` means the latest setup does not match the selected mode. `OSCILLATION_HISTORY` means a direct reversal occurred but the latest setup is aligned, so verification passes and no action is required unless prompts recur.

### 4. Upgrade an existing installation

`Upgrade-CodexSafety.ps1` reads the active install state and preserves its recorded selections by default. Running it without `-ConfirmUpgrade` is plan-only. A confirmed upgrade creates a unique transaction directory under `safe-setup/backups`, snapshots the previous active state under `safe-setup/state-history`, and then invokes the same deterministic installer in explicit upgrade mode.

Version 0.1.5 removed the alternate Status/Commit Git backend and rewrote old workspace registries to Save/List-only recovery. Version 0.1.6 migrated schema 4 to schema 5. The 0.1.7-0.1.9 development cycle tested several DynamicUi representations. Version 0.2.0 migrates to schema 9, keeps the verified positive-only runtime route, and handles affected Windows label oscillation through a separate optional compatibility layer. Plugin refresh, machine configuration, Desktop compatibility state, and already-running task remain separate layers.

### 5. Verify

`Test-CodexSafety.ps1` checks the generated configuration and, when a compatible CLI is available, calls `codex execpolicy check` against both allowed and deliberately broad command prefixes. Missing CLI verification produces `PARTIAL`, never a false `PASS`.

Runtime checks are route-specific and use a fresh task after machine-configuration changes. DynamicUi's Desktop verifier runs `codex-safe-workspace` → Full Access → built-in Workspace in one task. Runtime PASS correlates every probe with effective `turn_context`, actual unified-exec result, later `task_complete`, and an outside-workspace canary. UI PASS is separate and requires direct observation that the deliberately clicked label does not change before send, during execution, or after completion; rollout metadata cannot prove that visual condition. StrictProfile verification uses the effective managed policy. The codexsandboxonline/offline account name is never permission evidence.

When only the Windows Desktop label fails, `Install-DesktopPermissionSelectorFix.ps1` verifies that the signed installed build still ships the tested selector gate and selector structure, then installs a small project-owned main-process loader, Electron session preload, and update recertifier. The launcher sets `NODE_OPTIONS` only in the child Codex process, preserving any prior value without writing a persistent environment variable. The loader hash-checks the preload and registers it on the default session before the first BrowserWindow is created; the preload uses Electron's main-world bridge before the page's first script and overrides only that selector gate. Before any state changes, installation enumerates every Startup shortcut whose target is `wscript.exe` and whose normalized arguments point at the legacy `desktop-ui-fix\Watch-CodexDesktop.vbs`, archives each match into recovery history, and removes only those entries; unrelated shortcuts are untouched. The launcher never closes or force-terminates a running official Desktop: when an uninstrumented root already exists it records `MANUAL_ACTION_REQUIRED` with an audit PID list and fails closed, so you fully quit Codex yourself and start it from the dedicated shortcut. When official client bytes change, the hash-pinned recertifier runs through the recorded PowerShell 7 path and verifies the exact package family and publisher, valid signer subject, selector structural anchors, main-process hook, and document-start behavior. Only a complete pass atomically refreshes both state records; rejection leaves the old pins intact. It never extracts or modifies the client, writes WindowsApps, or exposes a debugging port.

### 6. Roll back

`Rollback-CodexSafety.ps1` first displays the recorded target backup. Restore or removal happens only after confirmation. The rollback implementation validates every target against its fixed Codex Home layout before writing. After an upgrade it also restores the previous active-state snapshot, so another rollback can continue to the preceding generation.

## Checkpoint bridge

The workspace sandbox intentionally protects `.git`. The optional bridge is copied to `CODEX_HOME/safe-setup/bin` and is the only PowerShell script allowed by the generated command rule. The rule matches the exact PowerShell 7 executable and exact bridge path; it does not allow a general `pwsh`, `powershell`, `git`, shell wrapper, or arbitrary script.

Every action resolves a canonical worktree root, checks authorized-workspaces.json, and verifies the pinned Git executable hash.

- Save refuses sensitive-looking untracked paths, builds a temporary index, and stores a hidden checkpoint under refs/codex-safe/checkpoints/*. The current branch, real index, and working tree remain unchanged.
- List enumerates checkpoint refs.
- Status and Commit are intentionally unavailable. Normal Git operations remain native Git and require a task whose effective permissions allow repository-metadata writes.

The bridge is not a general Git escape. Recovery from `Save` remains user-controlled and should normally use a separate worktree:

```powershell
git worktree add <new-empty-directory> <checkpoint-commit>
```

## Files managed on the user machine

Exact locations depend on `CODEX_HOME`, which defaults to the normal Codex user directory.

| Target | Purpose |
|---|---|
| `config.toml` | Active permission, approval, sandbox, and network selections |
| `rules/codex-safe-setup.rules` | Exact Save/List recovery bridge rule |
| `safe-setup/bin/New-CodexCheckpoint.ps1` | Installed narrow recovery bridge |
| `safe-setup/authorized-workspaces.json` | Canonical roots and pinned Git for recovery checkpoints |
| `safe-setup/backups/<transaction>/*` | Restore material isolated by install or upgrade transaction |
| `safe-setup/state-history/*` | Immutable prior-state snapshots and rolled-back state records |
| `safe-setup/outside-workspace-canary.txt` | Synthetic target for boundary testing |
| `desktop-selector-loader/*` | Optional process-scoped Desktop selector main loader, session preload, launcher, and watcher; no client copy |
| `safe-setup/desktop-selector-fix.json` | Active compatibility version pin and rollback pointer |
| `safe-setup/desktop-selector-fix-history/*` | Recoverable prior and rolled-back compatibility generations |

## Source layout

- `.codex-plugin/plugin.json`: plugin identity and install metadata.
- `.agents/plugins/marketplace.json`: Git-backed marketplace entry.
- `skills/codex-safe-setup/SKILL.md`: agent workflow and mandatory safety contract.
- `skills/codex-safe-setup/scripts/`: deterministic assessment, install, verify, checkpoint, and rollback code.
- `skills/codex-safe-setup/references/`: detailed profile, security, and recovery guidance loaded when needed.
- `tests/`: isolated integration and package checks.
- `tools/Build-Release.ps1`: install-ready ZIP builder.
