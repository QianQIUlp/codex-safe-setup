# Configuration profiles

## Approval modes

| Installer value | Codex settings | Intended behavior |
|---|---|---|
| `BoundedAutonomy` | `approval_policy = "never"` | Work autonomously inside the boundary |
| `AskMe` | `on-request`, reviewer `user` | Ask the user for eligible crossings |
| `AutoReview` | `on-request`, reviewer `auto_review` | Route eligible crossings to a reviewer agent |

Auto-review is a reviewer substitution. It does not alter filesystem, network, protected-path, or workspace limits.

## Default and task-level selection

default_permissions selects the fallback profile for tasks that do not make an explicit selection. It is not a managed restriction on the Codex UI. An explicit Full Access selection must activate the built-in :danger-full-access profile for that task; verify activePermissionProfile.id or authoritative danger-full-access task metadata.

Do not infer permission scope from the Windows sandbox username. codexsandboxonline and codexsandboxoffline distinguish sandbox/network variants, not Full Access versus workspace access. If the UI and runtime metadata disagree, report an activation failure instead of widening workspace roots or adding a Git backend.

## Command-network modes

| Installer value | Permission network | Filtering proxy | Behavior | Requirement |
|---|---:|---:|---|---|
| `Off` | Disabled | Disabled | Commands cannot reach the network | None |
| `Allowlist` | Enabled | Enabled | Proxy permits only named public domains | Explicit domains |
| `Unrestricted` | Enabled | Disabled | Commands use direct, unrestricted networking, including native protocols such as SSH | Full disclosure, then high-risk acknowledgement |

A domain table without an active proxy is not an enforced allowlist.

The installer must write both network switches explicitly:

- `Off`: `permissions.codex-safe-workspace.network.enabled = false` and `features.network_proxy = false`.
- `Allowlist`: network enabled, proxy enabled, and explicit domain rules.
- `Unrestricted`: network enabled, proxy disabled, and no domain table.

This distinction is functional, not cosmetic. A wildcard rule still routes commands through the proxy, and proxy-unaware native clients such as OpenSSH do not thereby gain direct connectivity.

### Required unrestricted-network disclosure

Explain all of the following before asking the user to acknowledge `Unrestricted`:

1. The network choice does not widen the filesystem profile and does not grant a new deletion capability. Existing workspace write access still permits changes and deletions inside that boundary.
2. Disabling the filtering proxy removes the public-destination restriction and permits direct protocols such as SSH. Anything a command can already read or generate can be sent to any public destination, including source, configuration, command output, private information, and credentials with names that evade the deny globs.
3. Untrusted pages, issue text, and dependency documentation can carry prompt injection. A manipulated agent can exfiltrate data or execute unsafe networked steps.
4. Internet access can download malware or vulnerable dependencies and can pull license-restricted content into the workspace.
5. These are possible consequences, not a claim that enabling network automatically deletes or leaks data. `Allowlist` materially limits destinations for proxy-compatible traffic and remains the normal recommendation.

This matches OpenAI's documented internet-access risks and its recommendation to allow only necessary domains and methods: [Agent internet access](https://learn.chatgpt.com/docs/cloud/internet-access). The local command proxy covers sandboxed scripts, programs, and child processes only; separate tools require separate controls: [Agent approvals and security](https://learn.chatgpt.com/docs/agent-approvals-security).

## Filesystem policy

The managed profile extends `:workspace`, denies `:root`, permits `:minimal` reads, permits workspace-root writes, optionally denies temp directories, and denies common credential-file globs. It inherits Codex protections for `.git`, `.codex`, and `.agents`.

Permission profiles are Beta. The installer refuses to combine them silently with legacy `sandbox_mode` or `[sandbox_workspace_write]`. Use `-MigrateLegacySettings` only after review; the original file is backed up first.

Base installation can proceed without Codex CLI, but exact version and rule behavior remain partially verified. A complete result requires a compatible CLI and successful `codex execpolicy check`.
