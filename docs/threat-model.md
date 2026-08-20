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
| Codex permission route | Enforcing the selected DynamicUi or StrictProfile boundary | Absence of implementation defects or client/runtime mismatch |
| Operating system sandbox | Isolating local command execution | Protection after host compromise |
| User approval | Expressing intent for a specific crossing | Perfect review or complete context |
| Auto-review agent | Applying review policy | Stronger isolation or infallible judgment |
| PowerShell 7 | More consistent shell behavior | Prevention of semantic mistakes |
| Codex CLI and execpolicy | Parsing and checking active rule behavior | Proof of every future runtime path |
| Recovery bridge | Creating narrow Save/List recovery snapshots | General Git, status, commit, or shell authority |

## Threats and controls

| Threat | Primary control | Residual risk |
|---|---|---|
| Wrong-path writes outside the project | DynamicUi workspace-write sandbox or StrictProfile workspace roots | Built-in selections use their own scopes; sandbox defects or separate tools remain |
| Accidental deletion inside the project | Hidden Git checkpoint ref | Ignored files and sensitive refused files are absent |
| Reading credentials outside the project | StrictProfile adds explicit root deny | DynamicUi and built-in Workspace use broader read scopes; Full Access is unrestricted |
| Permission label changes without another click | DynamicUi disables the sole named-profile and generic Custom fallbacks, then directly observes the label before, during, and after a turn | Rollout metadata cannot prove visual stability; a future Desktop regression remains possible |
| UI Full Access selection does not match runtime | DynamicUi separately verifies same-task `sandbox_policy.type = danger-full-access` and a disabled permission profile; StrictProfile verifies profile metadata | A verified Full Access task intentionally removes the local sandbox boundary |
| Reading credentials inside the project | StrictProfile deny globs for common sensitive names | DynamicUi cannot use sticky deny-globs; unusual filenames require more rules |
| Shell-based data exfiltration | Network off or active proxy allowlist | An allowed domain can still receive data; direct unrestricted access removes destination containment |
| Prompt injection from network content | Minimize allowed destinations and treat remote instructions as untrusted | Allowed pages, issues, and dependency documentation can still manipulate the agent |
| Malicious, vulnerable, or restricted downloads | Narrow network access and review dependency/content changes | An allowed source can still be compromised or carry restricted content |
| Human or reviewer error | Hard capability boundaries | In-boundary actions can still be harmful |
| Broad rule becoming a shell escape | Exact executable, recovery script, and Save/List action prefix plus registered-root validation | Rules are evolving and need upgrade verification |
| Checkpoint bridge used in another repository | Canonical authorized-root registry | Registry and bridge integrity depend on the host |
| Git executable replacement | Pinned path and SHA-256 verification | Legitimate Git upgrades require reinstall |
| Rollback redirected to arbitrary paths | Fixed layout and recorded-target validation | Backups still need filesystem protection |

## Credential exposure

Reading a credential can be an exposure event even when the agent never prints it intentionally. StrictProfile blocks common credential paths. DynamicUi Custom follows the workspace-write sandbox's broader read scope and does not block credential files inside a writable workspace with explicit deny-globs. Built-in Workspace and Full Access retain their documented read scopes.

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

Configuration parsing, file inspection, `permissionProfile/list`, and `codex execpolicy check` show that generated policy matches expected structure. They do not prove a Desktop turn or what its selector visibly showed. The 0.2.0 end-to-end verifier requires `codex-safe-workspace` → Full Access → built-in Workspace in one real rollout, correlating effective `turn_context`, unified-exec result, later completion, and an outside-workspace canary. It separately requires direct observation of the label before, during, and after each turn. Re-run after Codex upgrades and never infer scope from the Windows sandbox account name.

The optional Windows Desktop compatibility layer is outside the signed package and relies on an undocumented selector gate. Its controls are an explicit acknowledgement; exact package-family, publisher, executable, ASAR, signer identity, gate, structural-anchor, loader, recertifier, and preload pins; a process-only environment override; real Windows PowerShell launch-chain validation with a deliberately invalid inherited module path and live routing discovery; a liveness-checked startup watcher that records redirect failures without exiting; isolated main-process and document-start probes; no client extraction or modification; no debugging port; no WindowsApps write; tamper checks; and recoverable rollback. Its release package contains no OpenAI client file. Changed official bytes are accepted automatically only when identity, signature, structure, and both runtime probes pass; the two state records are then atomically refreshed. A missing gate, changed structure or identity, unavailable Electron preload API, failed launch validation, failed probe, or state mismatch preserves the prior accepted pins and disables launch rather than guessing.

## Security non-goals

- Promising absolute safety.
- Deciding that Full Access is safe because prompts are enabled.
- Treating auto-review as stronger sandboxing.
- Capturing secrets in checkpoints.
- Automatically restoring or overwriting a working tree.
- Weakening other security controls to make installation easier.
