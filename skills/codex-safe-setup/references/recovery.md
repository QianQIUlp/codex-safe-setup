# Recovery checkpoints

The workspace sandbox keeps .git read-only. The optional recovery bridge is copied outside workspace roots and exposed through one exact command rule. Authorized canonical worktree roots and the installer-pinned Git executable live in CODEX_HOME/safe-setup/authorized-workspaces.json.

- Save uses a temporary index to snapshot tracked changes and ordinary untracked files under refs/codex-safe/checkpoints/* without changing HEAD, the real index, or the working tree.
- List enumerates those hidden checkpoint refs.
- The bridge does not expose Status, Commit, general Git, or a shell escape. Normal Git remains native Git and requires an effective task permission profile that permits its metadata writes.

Save refuses sensitive-looking untracked paths such as .env, private keys, .npmrc, and cloud credential files. Tracked credential-style fixtures can still collide with workspace deny globs; review those files and use only exact read exceptions for known public fixtures. Never disable the deny globs wholesale.

Inspect a checkpoint with git show --stat <commit>. Recover without overwriting the current tree by creating a separate worktree after confirmation: git worktree add <new-empty-directory> <commit>. Never automatically run reset --hard, clean, branch replacement, or in-place checkout.

## Versioned install state

Version 0.1.5 stores state schema 4, 0.1.6 stores schema 5, the unreleased 0.1.7-0.1.9 development builds store schemas 6-8, and 0.2.0 stores schema 9. Upgrading from 0.1.3 or 0.1.4 removes any normal-commit authorization from the workspace registry and installs the recovery-only Save/List bridge. The 0.2.0 migration uses two positive-only DynamicUi profiles and built-in Workspace as the startup default. Transaction-scoped backups and immutable prior-state snapshots remain under CODEX_HOME/safe-setup/state-history, so rollback can restore the exact prior state.

The optional Windows Desktop selector layer uses separate schema-3 state at `CODEX_HOME/safe-setup/desktop-selector-fix.json`. Compatible official package updates are automatically recertified and atomically refresh both the pointer and loader-local state; an incompatible update preserves the prior pins and fails closed. Replacement first moves the active loader generation into `desktop-selector-fix-history`; an older derived-client generation is left untouched while its task runs and moved into the same recoverable history on the next launch. Rollback moves the deactivated loader into history and restores the immediately previous loader or preserved legacy generation when present. It removes only shortcuts that still point at the recorded installation and never deletes or restores files in WindowsApps.

Plugin cache state and already-running Codex task state are not part of this chain. Refresh the plugin first, run the configuration upgrade explicitly, then start one fresh task to load the machine configuration. Later UI permission selections are task-scoped and must take effect on the next message without a restart; verify runtime from real `turn_context`, exact unified-exec behavior, completion, and the outside-workspace canary, and verify label stability by direct observation across the turn lifecycle. Fully restart Codex only as a diagnostic when Windows administrator prompts repeat.
