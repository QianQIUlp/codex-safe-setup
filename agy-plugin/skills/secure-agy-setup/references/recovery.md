# Checkpoint Recovery Guide for Antigravity

## How Checkpoints Work

The `New-AgyCheckpoint` bridge provides non-invasive, snapshot-based recovery without risking the user's active branch or working tree:

1. **Independent Temporary Index**:
   Uses an ephemeral `$env:GIT_INDEX_FILE` in the temp directory.
2. **Snapshot Creation**:
   - Reads current HEAD tree.
   - Stages all tracked and untracked project files (excluding `.gitignore` patterns).
   - Commits the tree with parent = HEAD into Git object storage.
   - Creates a dedicated ref: `refs/agy-safe/checkpoints/<timestamp>-<commit-sha>`.
3. **Zero Side Effects on Working Tree**:
   - Real Git index (`.git/index`), `HEAD`, active branch, and modified working files are 100% untouched.
4. **Secret Refusal**:
   - If sensitive-looking untracked files (`.env`, `*.pem`, `id_rsa`, etc.) exist, the checkpoint is **refused** so secrets never enter Git storage.

## How to Restore from a Checkpoint

Restoration is intentionally manual and user-controlled to prevent accidental overwrites:

### Option A: Restore into a Clean Worktree (Recommended)
```powershell
git worktree add ../recovered-workspace <checkpoint-commit-sha>
```

### Option B: Inspect Files in a Checkpoint
```powershell
git show <checkpoint-commit-sha>:path/to/file.js
```

### Option C: Restore Specific File to Current Tree
```powershell
git checkout <checkpoint-commit-sha> -- path/to/file.js
```
