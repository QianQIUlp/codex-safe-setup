# Threat model

## Security objective

Codex Safe Setup reduces the consequences of a mistaken, manipulated, or overconfident agent action by making authority explicit and testable. It is designed around three questions:

1. What can a local command change?
2. What can the agent read?
3. Where can command output be sent?

Approval is deliberately treated as a separate workflow decision. A person or reviewer model can misunderstand a command, miss an indirect effect, or approve an action without seeing the sensitive data already present in context. The permission boundary must remain useful even when review is imperfect.

## Assets

- Source code and project files in the active workspace.
- Credentials, tokens, private keys, personal files, and machine configuration outside the workspace.
- Sensitive files accidentally stored inside a workspace.
- Git history, branch state, index state, and recoverability of uncommitted work.
- Network destinations reachable by local commands.
- The integrity of Codex configuration, rule files, checkpoint authorization, and rollback state.

## Trust boundaries

| Boundary | Trusted for | Not assumed |
|---|---|---|
| Codex permission profile | Enforcing declared filesystem and command-network limits | Absence of implementation defects |
| Operating system sandbox | Isolating local command execution | Protection after host compromise |
| User approval | Expressing intent for a specific crossing | Perfect review or complete context |
| Auto-review agent | Applying review policy | Stronger isolation or infallible judgment |
| PowerShell 7 | More consistent shell behavior | Prevention of semantic mistakes |
| Codex CLI and execpolicy | Parsing and checking active rule behavior | Proof of every future runtime path |
| Git checkpoint bridge | Creating narrow recovery snapshots | Backing up ignored or refused secrets |

## Threats and controls

| Threat | Primary control | Residual risk |
|---|---|---|
| Wrong path outside the project | Deny root; allow writes only to registered workspace roots | Sandbox defects or separately authorized tools |
| Accidental deletion inside the project | Hidden Git checkpoint ref | Ignored files and sensitive refused files are absent |
| Reading credentials outside the project | Root deny plus minimal runtime reads | The runtime-defined minimal set must be trusted |
| Reading credentials inside the project | Deny globs for common sensitive names | Unusual filenames require additional deny rules |
| Shell-based data exfiltration | Network off or active proxy allowlist | An allowed domain can still receive data; direct unrestricted access removes destination containment |
| Prompt injection from network content | Minimize allowed destinations and treat remote instructions as untrusted | Allowed pages, issues, and dependency documentation can still manipulate the agent |
| Malicious, vulnerable, or restricted downloads | Narrow network access and review dependency/content changes | An allowed source can still be compromised or carry restricted content |
| Human or reviewer error | Hard capability boundaries | In-boundary actions can still be harmful |
| Broad rule becoming a shell escape | Exact executable and checkpoint-script prefix | Rules are evolving and need upgrade verification |
| Checkpoint bridge used in another repository | Canonical authorized-root registry | Registry and bridge integrity depend on the host |
| Git executable replacement | Pinned path and SHA-256 verification | Legitimate Git upgrades require reinstall |
| Rollback redirected to arbitrary paths | Fixed layout and recorded-target validation | Backups still need filesystem protection |

## Credential exposure

Reading a credential can be an exposure event even when the agent never prints it intentionally. A value may enter model context, command output, logs, repository history, or another tool invocation. This project therefore blocks common credential paths instead of relying only on a promise not to use their contents.

Enabling unrestricted command networking does not change the filesystem profile or add deletion authority. It disables the filtering proxy and domain enforcement so direct protocols such as SSH can work. This removes the public-destination boundary: data already readable by a sandboxed command can be transmitted to any public destination. Files that are writable inside the workspace remain changeable or deletable regardless of the network choice.

Timing alone does not prove that a later account compromise was caused by an agent run. If a real credential may have been exposed:

1. Revoke or rotate it immediately.
2. Inspect the provider's usage, sessions, and billing records.
3. Remove it from files, logs, shell history, and repository history where applicable.
4. Apply a narrower permission boundary for future work.

Never paste a real secret into an issue or use it as test data.

## Explicitly out of scope

The installed command profile does not govern Web Search, Browser, Computer Use, apps, connectors, other plugins, MCP servers, cloud tasks, source-control remotes, CI systems, or credentials already disclosed before installation. Host malware, kernel compromise, physical access, and defects in Codex or operating-system isolation are also out of scope.

These surfaces must be evaluated separately. The verifier reports them as `NOT CONTROLLED`.

## Verification limits

Configuration parsing, file inspection, and `codex execpolicy check` show that the generated policy matches expected structure and decisions. They do not prove that every command, tool, product surface, or future Codex version will enforce it identically. Re-run verification after upgrades and perform runtime probes in a new Codex execution environment.

## Security non-goals

- Promising absolute safety.
- Deciding that Full Access is safe because prompts are enabled.
- Treating auto-review as stronger sandboxing.
- Capturing secrets in checkpoints.
- Automatically restoring or overwriting a working tree.
- Weakening other security controls to make installation easier.

