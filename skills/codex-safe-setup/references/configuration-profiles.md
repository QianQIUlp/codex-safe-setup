# Configuration profiles

## Approval modes

| Installer value | Codex settings | Intended behavior |
|---|---|---|
| `BoundedAutonomy` | `approval_policy = "never"` | Work autonomously inside the boundary |
| `AskMe` | `on-request`, reviewer `user` | Ask the user for eligible crossings |
| `AutoReview` | `on-request`, reviewer `auto_review` | Route eligible crossings to a reviewer agent |

Auto-review is a reviewer substitution. It does not alter filesystem, network, protected-path, or workspace limits.

## Permission routing

| Installer value | Persisted configuration | Same-task UI switching | Read boundary |
|---|---|---|---|
| `DynamicUi` | `sandbox_mode` plus `sandbox_workspace_write`; no `default_permissions` or plugin-owned named profile | Full Access, Workspace, and Read-only apply to the next user message | Legacy workspace semantics: broad reads, workspace-scoped writes |
| `StrictProfile` | `default_permissions = "codex-safe-workspace"` and the named profile | Not the pure dynamic route | Root deny-read, minimal runtime reads, credential deny-globs |

DynamicUi is the 0.1.6 default and requires `-AcknowledgeDynamicUiReadScope`. After one fresh task loads a machine-configuration change, `thread/settings/updated` must report `sandboxPolicy.type = dangerFullAccess` after Full Access is selected, then `workspaceWrite` or `readOnly` after switching back. Do not infer permission scope from codexsandboxonline or codexsandboxoffline.

## Command-network modes

| Installer value | Permission network | Filtering proxy | Behavior | Requirement |
|---|---:|---:|---|---|
| `Off` | Disabled | Disabled | Commands cannot reach the network | None |
| `Allowlist` | Enabled | Enabled | Proxy permits only named public domains | Explicit domains |
| `Unrestricted` | Enabled | Disabled | Commands use direct, unrestricted networking, including native protocols such as SSH | Full disclosure, then high-risk acknowledgement |

A domain table without an active proxy is not an enforced allowlist.

The installer writes network switches for the selected route:

- DynamicUi `Off`: `sandbox_workspace_write.network_access = false` and proxy disabled.
- DynamicUi `Unrestricted`: network enabled and proxy disabled.
- StrictProfile `Off`, `Allowlist`, and `Unrestricted`: use the named profile plus the matching proxy state.

DynamicUi rejects Allowlist because the persistent proxy would contradict pure Full Access.

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

StrictProfile extends `:workspace`, denies `:root`, permits `:minimal` reads and workspace-root writes, and denies common credential-file globs. DynamicUi deliberately uses the older workspace sandbox so the Desktop can replace the sandbox for subsequent turns; it cannot claim StrictProfile's deny-read protection.

Permission profiles are Beta. Version 0.1.6 keeps the two routes mutually exclusive and backs up the original file before migration.

Base installation can proceed without Codex CLI, but exact version and rule behavior remain partially verified. A complete result requires a compatible CLI and successful `codex execpolicy check`.
