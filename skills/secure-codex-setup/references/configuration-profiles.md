# Configuration profiles

## Approval modes

| Installer value | Codex settings | Intended behavior |
|---|---|---|
| `BoundedAutonomy` | `approval_policy = "never"` | Work autonomously inside the boundary |
| `AskMe` | `on-request`, reviewer `user` | Ask the user for eligible crossings |
| `AutoReview` | `on-request`, reviewer `auto_review` | Route eligible crossings to a reviewer agent |

Auto-review is a reviewer substitution. It does not alter filesystem, network, protected-path, or workspace limits.

## Command-network modes

| Installer value | Behavior | Requirement |
|---|---|---|
| `Off` | Commands cannot reach the network | None |
| `Allowlist` | Proxy permits only named public domains | Explicit domains |
| `Unrestricted` | Commands have direct outbound access | High-risk acknowledgement |

A domain table without an active proxy is not an enforced allowlist.

## Filesystem policy

The managed profile extends `:workspace`, denies `:root`, permits `:minimal` reads, permits workspace-root writes, optionally denies temp directories, and denies common credential-file globs. It inherits Codex protections for `.git`, `.codex`, and `.agents`.

Permission profiles are Beta. The installer refuses to combine them silently with legacy `sandbox_mode` or `[sandbox_workspace_write]`. Use `-MigrateLegacySettings` only after review; the original file is backed up first.

Base installation can proceed without Codex CLI, but exact version and rule behavior remain partially verified. A complete result requires a compatible CLI and successful `codex execpolicy check`.
