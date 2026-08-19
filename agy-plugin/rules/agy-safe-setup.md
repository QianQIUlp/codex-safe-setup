# Antigravity Safe Setup — Security Guidelines & Rules

## 1. Core Principle: Bounded Autonomy
- **Approval is not a security boundary**: Security is maintained by capability containment (what you can read, write, and send).
- Always operate strictly within the registered workspace paths. Never attempt to read, modify, or delete files outside the current project workspace.

## 2. Credential & Secret Protection
- **Never read or inspect secrets**: Do not view, display, parse, or embed contents of sensitive files such as:
  - `.env`, `.env.*` (environment secrets)
  - `id_rsa`, `id_ed25519`, `*.pem`, `*.key`, `*.pfx`, `*.p12` (private keys & certificates)
  - `.npmrc`, `.pypirc`, `.netrc`, `nuget.config` (package manager credentials)
  - `credentials.json`, `service-account.json`, `~/.aws/*`, `~/.azure/*`, `~/.config/gcloud/*` (cloud tokens)
- If a task requires environment variables, ask the user to provide dummy/test variables or verify variable existence without reading secret values.

## 3. Command & Filesystem Safety
- **No Uncontrolled Deletions**: Do not run arbitrary `rm -rf`, `Remove-Item -Recurse -Force`, `git clean -fdx`, or `git reset --hard` that could wipe untracked or uncommitted work.
- **Path Resolution Checks**: Before performing cleanup or build operations, verify that destination directories are not null, empty, or resolving to drive roots (such as `C:\` or `/`).
- **No Persistence or Concealment**: Never configure startup items, registry autoruns, or execute hidden/encoded scripts (`powershell -EncodedCommand`).

## 4. Recovery & Checkpoints
- Prior to major refactorings or risky changes, recommend or create a safe Git checkpoint using `$secure-agy-setup` (which commits snapshots to `refs/agy-safe/checkpoints/*` without altering working branch or index).
