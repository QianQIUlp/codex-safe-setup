# Recovery and checkpoint bridge

The workspace sandbox keeps `.git` read-only. The optional bridge is copied outside workspace roots and exposed through one exact command rule; it is not a general Git, PowerShell, or shell escape.

It uses a temporary Git index to snapshot tracked changes and ordinary untracked files into a commit under `refs/codex-safe/checkpoints/*`. It does not change the checked-out branch, `HEAD`, the real index, or the working tree.

The bridge refuses sensitive-looking untracked paths such as `.env`, private keys, `.npmrc`, and cloud credential files. Add those paths to `.gitignore` or manage them outside the repository instead of bypassing the refusal.

Authorized canonical roots and the installer-pinned Git executable live in `CODEX_HOME/safe-setup/authorized-workspaces.json`. The bridge rejects any other repository and refuses to run if that Git executable's SHA-256 changes. A legitimate Git upgrade therefore requires rerunning the installer.

Inspect a checkpoint with `git show --stat <commit>`. Recover without overwriting the current tree by creating a separate worktree after confirmation: `git worktree add <new-empty-directory> <commit>`.

Never automatically run `reset --hard`, `clean`, branch replacement, or in-place checkout.
