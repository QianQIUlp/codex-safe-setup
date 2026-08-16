# Recovery (ZCode OS Cage)

Two independent recovery mechanisms exist. Neither ever performs an automatic restore.

## 1. Checkpoint bridge (opt-in at install)

`New-ZcodeCheckpoint.ps1` (installed under the cage state `bin\`) creates a snapshot of
the current work as a hidden commit on `refs/zcode-safe/checkpoints/<timestamp>-<sha8>`:

- Uses a temporary `GIT_INDEX_FILE`; the real index, the branch, and the working tree
  are never touched.
- Accepts only repositories registered in `authorized-workspaces.json`, with the Git
  executable pinned by SHA-256.
- Refuses to snapshot when sensitive-looking untracked files would enter Git object
  storage (`.env*`, `*.pem/.key/.pfx/.p12`, `credentials.json`, ...).

Restore stays user-controlled:

```powershell
git worktree add <dir> <checkpoint-commit>
```

Inspect first (`-Action List`), copy what is needed, remove the worktree. Never run
`git reset --hard`, `git clean`, or checkout as a "recovery" shortcut.

## 2. Full installation rollback

`Rollback-ZcodeSafety.ps1` reverses the entire cage exactly as recorded in
`install-state.json`: ACEs removed, Program Files copy deleted, shortcut removed,
sandbox account and profile deleted. It lists the targets first and requires `-Confirm`.
Workspace trees are never modified - only the sandbox ACEs disappear.

## Recommended rhythm

Create a checkpoint before asking the sandboxed agent for bulk edits, risky refactors,
or dependency surgery; verify with `Test-ZcodeSafety.ps1` after any machine change
(Windows updates, ZCode updates, new workspace roots).
