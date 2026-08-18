# Security contract

## Product claim

Codex Safe Setup reduces the consequences of human or agent mistakes by installing explicit, testable capability boundaries. It does not guarantee that the model, user, operating system, dependencies, or external services are trustworthy.

| Threat | Primary control | Remaining limitation |
|---|---|---|
| Wrong path outside the project | Deny filesystem access outside workspace roots | Sandbox implementation defects remain possible |
| Deletion inside the project | Hidden Git checkpoint ref | Ignored and refused sensitive files are not captured |
| Reading credentials outside the project | Root deny plus minimal runtime reads | The runtime-defined minimal set must be trusted |
| Task-level Full Access override | Explicit UI selection plus runtime profile verification | Full Access intentionally removes the local sandbox for that task; the safe profile remains only the default |
| Reading project secrets | Workspace-relative deny globs | Unknown filenames need custom deny entries |
| Shell-based exfiltration | Network off or enforced allowlist | Allowed domains can still receive data; direct unrestricted access removes destination containment |
| Network prompt injection | Keep command networking narrow and treat remote content as untrusted | Allowed remote content can still manipulate an agent |
| Malicious or vulnerable downloads | Restrict destinations and review dependency changes | An allowed source can still be compromised |
| Approval or reviewer error | Hard sandbox boundary | In-boundary actions do not receive extra review |
| Recovery rule abuse | Exact executable, script, and Save/List action prefix plus bridge-internal validation | Rules are experimental and need upgrade checks |

Web Search, Browser, Computer Use, apps, connectors, plugins, MCP, cloud tasks, source-control remotes, CI credentials, host malware, and credentials exposed before installation are outside the installed command profile. Report them as `NOT CONTROLLED`.

## Credential incident rule

Do not infer causation from timing alone. If a real token may have appeared in model context, terminal output, logs, repository history, or a readable file: revoke or rotate it, inspect provider usage, remove persistent copies, and only then rely on the new boundary for future work.

Never print, hash, upload, or otherwise process a real secret merely to prove that it exists.

## Verification vocabulary

- `PASS`: directly checked and matched the expected condition.
- `PARTIAL`: configuration evidence exists, but a required runtime or CLI check was unavailable.
- `FAIL`: a required condition is missing or contradictory.
- `NOT CONTROLLED`: the capability uses a separate control surface.
