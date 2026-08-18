# Recovery and checkpoint bridge

The workspace sandbox keeps `.git` read-only. In a linked worktree, the worktree administration directory, object database, branch refs, and reflogs all live under the parent repository's shared `.git`; granting raw write access to that tree would defeat the protected-metadata boundary.

The optional bridge is copied outside workspace roots and exposed through one exact command rule. Authorized canonical worktree roots and the installer-pinned Git executable live in `CODEX_HOME/safe-setup/authorized-workspaces.json`. The bridge rejects other repositories and a changed Git executable.

- `Save` uses a temporary index to snapshot tracked changes and ordinary untracked files under `refs/codex-safe/checkpoints/*` without changing `HEAD`, the real index, or the working tree.
- `List` enumerates those hidden checkpoint refs.
- `Status` obtains the actual repository status outside the protected metadata boundary. Use it to distinguish real deletions from files hidden from direct Git by sandbox or host ACL rules.
- `Commit` is disabled unless the user explicitly enables it for the registered worktree. It accepts exact literal paths, requires an allowed branch prefix (default `codex/`), an initially clean index, and no merge/rebase/cherry-pick/revert/bisect operation. It suppresses hooks and signing, refuses repository-local clean/process filters, verifies that only the selected paths were staged, and leaves unselected changes untouched.

`Save` and `Commit` refuse sensitive-looking untracked paths such as `.env`, private keys, `.npmrc`, and cloud credential files. Tracked credential-style fixtures can still collide with workspace deny globs; review those files and use only exact read exceptions for known public fixtures. Never disable the deny globs wholesale.

Inspect a checkpoint with `git show --stat <commit>`. Recover without overwriting the current tree by creating a separate worktree after confirmation: `git worktree add <new-empty-directory> <commit>`. Never automatically run `reset --hard`, `clean`, branch replacement, or in-place checkout.


## Versioned install state

Version 0.1.3 stores state schema 3, including the explicit Git commit-bridge choice and allowed branch prefixes. Transaction-scoped backups and immutable prior-state snapshots remain under `CODEX_HOME/safe-setup/state-history`. A configuration upgrade never deletes the prior state; one rollback restores both the prior managed files and its active state.

Plugin cache state and already-running Codex task state are not part of this chain. Refresh the plugin first, run the configuration upgrade explicitly, then restart Codex and use a new task.
