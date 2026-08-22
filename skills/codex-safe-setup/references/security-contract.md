# Security contract

## Product claim

Codex Safe Setup offers two explicit configuration tradeoffs. DynamicUi prioritizes same-task permission switching through two positive-only named profiles; StrictProfile prioritizes persistent deny-read boundaries through a fixed named profile. Windows Desktop selector display stability is an upstream product concern: this project observes and reports it but does not modify the Desktop client. Neither route guarantees that the model, user, operating system, dependencies, or external services are trustworthy.

| Threat | Primary control | Remaining limitation |
|---|---|---|
| Wrong-path writes outside the project | DynamicUi workspace-write sandbox or StrictProfile workspace roots | Built-in profiles have their own scopes; sandbox defects remain possible |
| Deletion inside the project | Hidden Git checkpoint ref | Ignored and refused sensitive files are not captured |
| Reading credentials outside the project | StrictProfile adds explicit root deny | DynamicUi and built-in Workspace use broader read scopes; Full Access is unrestricted |
| Selector label jumps without a click | Direct visual observation plus an upstream bug report to OpenAI | Rollout metadata cannot prove visible label stability; no local compatibility layer exists since v0.2.1 |
| Task-level Full Access override | DynamicUi plus real Desktop `turn_context`, completion, exact command, and outside-workspace canary | Full Access intentionally removes the local sandbox for that task |
| Reading project secrets | StrictProfile workspace-relative deny globs | DynamicUi cannot install sticky deny-globs; unknown filenames need custom rules |
| Shell-based exfiltration | Network off or enforced allowlist | Allowed domains can still receive data; direct unrestricted access removes destination containment |
| Network prompt injection | Keep command networking narrow and treat remote content as untrusted | Allowed remote content can still manipulate an agent |
| Malicious or vulnerable downloads | Restrict destinations and review dependency changes | An allowed source can still be compromised |
| Approval or reviewer error | Hard sandbox boundary | In-boundary actions do not receive extra review |
| Recovery rule abuse | Exact executable, script, and Save/List action prefix plus bridge-internal validation | Rules are experimental and need upgrade checks |

DynamicUi Custom follows the workspace sandbox's broader read scope and does not protect credential files inside a writable workspace. Full Access is unrestricted. StrictProfile is the route for persistent root and credential denies. Web Search, Browser, Computer Use, apps, connectors, plugins, MCP, cloud tasks, source-control remotes, CI credentials, host malware, and credentials exposed before installation are also outside the installed command route. Report them as `NOT CONTROLLED`.

The Desktop selector compatibility layer shipped in version 0.2.0 was removed in 0.2.1 and is no longer part of this contract. It launched the signed official client with a process-scoped loader and session preload pinned to undocumented internals; that approach depended on proprietary implementation details that change without notice and operated outside the supported configuration surface. Installations of the retired layer are cleaned by `Remove-LegacyDesktopSelectorArtifacts.ps1`, which archives exact-match shortcuts, removes listed user-scope environment variables, and quarantines retired state folders without starting, stopping, or inspecting any process or any client file.

## Credential incident rule

Do not infer causation from timing alone. If a real token may have appeared in model context, terminal output, logs, repository history, or a readable file: revoke or rotate it, inspect provider usage, remove persistent copies, and only then rely on the new boundary for future work.

Never print, hash, upload, or otherwise process a real secret merely to prove that it exists.

## Verification vocabulary

- `PASS`: directly checked and matched the expected condition.
- `PARTIAL`: configuration evidence exists, but a required runtime or CLI check was unavailable.
- `FAIL`: a required condition is missing or contradictory.
- `NOT CONTROLLED`: the capability uses a separate control surface.
