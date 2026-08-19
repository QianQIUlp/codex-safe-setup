# Recovery checkpoints

The workspace sandbox keeps .git read-only. The optional recovery bridge is copied outside workspace roots and exposed through one exact command rule. Authorized canonical worktree roots and the installer-pinned Git executable live in CODEX_HOME/safe-setup/authorized-workspaces.json.

- Save uses a temporary index to snapshot tracked changes and ordinary untracked files under refs/codex-safe/checkpoints/* without changing HEAD, the real index, or the working tree.
- List enumerates those hidden checkpoint refs.
- The bridge does not expose Status, Commit, general Git, or a shell escape. Normal Git remains native Git and requires an effective task permission profile that permits its metadata writes.

Save refuses sensitive-looking untracked paths such as .env, private keys, .npmrc, and cloud credential files. Tracked credential-style fixtures can still collide with workspace deny globs; review those files and use only exact read exceptions for known public fixtures. Never disable the deny globs wholesale.

Inspect a checkpoint with git show --stat <commit>. Recover without overwriting the current tree by creating a separate worktree after confirmation: git worktree add <new-empty-directory> <commit>. Never automatically run reset --hard, clean, branch replacement, or in-place checkout.

## Versioned install state

Version 0.1.6 stores state schema 5. Upgrading removes the plugin-owned global default permission pin while retaining the selectable profile, legacy UI sandbox route, network and approval choices, transaction-scoped backups, and immutable prior-state snapshots under CODEX_HOME/safe-setup/state-history.

Plugin cache state and already-running Codex task state are not part of this chain. Refresh the plugin first, run the configuration upgrade explicitly, then use one new task to load the unpinned layout. Later UI permission changes are task-scoped, must apply on the next user message without restarting Codex, and must be verified from the returned runtime profile.
