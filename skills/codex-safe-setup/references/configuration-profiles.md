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
| `DynamicUi` | Built-in `:workspace` startup default plus two positive-only named profiles | `codex-safe-workspace`, Full Access, Workspace, and Read-only apply to the next user message | Custom follows the workspace sandbox's broader read scope |
| `StrictProfile` | `default_permissions = "codex-safe-workspace"` and the named profile | Not the pure dynamic route | Root deny-read, minimal runtime reads, credential deny-globs |

DynamicUi is the 0.2.0 default, requires Codex 0.138.0 or newer, and requires `-AcknowledgeDynamicUiReadScope`. It exposes `codex-safe-workspace` and a real offline choice, `codex-safe-workspace-offline`, without sticky filesystem denies. Generate the real Desktop probes with `<skill-dir>/scripts/Test-DesktopPermissionE2E.ps1 -ShowPrompts`. Complete the setup turn, then run `codex-safe-workspace` → Full Access → built-in Workspace in one task. Directly observe the selected label before send, during execution, and after completion; metadata cannot prove visual stability. Runtime PASS separately requires Codex Desktop `session_meta` with no replacement during the probes, the matching `turn_context`, exact unified-exec command and result, later `task_complete`, and outside-workspace canary. Do not infer permission scope from codexsandboxonline or codexsandboxoffline. If runtime passes while only the label oscillates on Windows, use the separately acknowledged and version-pinned Desktop compatibility layer; do not keep changing the runtime profile.

## Command-network modes

| Installer value | Permission network | Filtering proxy | Behavior | Requirement |
|---|---:|---:|---|---|
| `Off` | Disabled | Disabled | Commands cannot reach the network | None |
| `Allowlist` | Enabled | Enabled | Proxy permits only named public domains | Explicit domains |
| `Unrestricted` | Enabled | Disabled | Commands use direct, unrestricted networking, including native protocols such as SSH | Full disclosure, then high-risk acknowledgement |

A domain table without an active proxy is not an enforced allowlist.

The installer writes network switches for the selected route:

- DynamicUi `Off`: Custom network disabled and proxy disabled.
- DynamicUi `Unrestricted`: Custom network enabled and proxy disabled.
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

StrictProfile's `codex-safe-workspace` extends `:workspace`, denies `:root`, permits `:minimal` reads and workspace-root writes, and can deny common credential-file globs. DynamicUi also uses that visible name but installs only positive grants; its second offline profile differs by keeping command network disabled.

Permission profiles are Beta. Version 0.2.0 uses them for both routes. DynamicUi requires exactly the two plugin-owned positive-only profiles with built-in `default_permissions = ":workspace"`; legacy sandbox keys are a conflict. Every migration backs up the original file. The optional Desktop selector layer has its own plan, acknowledgement, schema-3 state, verifier, compatible-official-update recertification, and rollback; it is not part of config.toml.

StrictProfile installation can proceed without Codex CLI, but exact version and rule behavior remain partially verified. DynamicUi apply requires detected Codex CLI 0.138.0 or newer. A complete result also requires successful `codex execpolicy check` and the Desktop end-to-end probe.
