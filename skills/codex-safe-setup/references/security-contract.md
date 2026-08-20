# Security contract

## Product claim

Codex Safe Setup offers two explicit configuration tradeoffs. DynamicUi prioritizes same-task permission switching through two positive-only named profiles; StrictProfile prioritizes persistent deny-read boundaries through a fixed named profile. On affected Windows builds, selector display stability is handled by a separate optional compatibility layer, not claimed as an inherent property of config.toml. Neither route guarantees that the model, user, operating system, dependencies, or external services are trustworthy.

| Threat | Primary control | Remaining limitation |
|---|---|---|
| Wrong-path writes outside the project | DynamicUi workspace-write sandbox or StrictProfile workspace roots | Built-in profiles have their own scopes; sandbox defects remain possible |
| Deletion inside the project | Hidden Git checkpoint ref | Ignored and refused sensitive files are not captured |
| Reading credentials outside the project | StrictProfile adds explicit root deny | DynamicUi and built-in Workspace use broader read scopes; Full Access is unrestricted |
| Selector label jumps without a click | Direct visual observation plus the optional recertified Windows compatibility layer | It relies on an undocumented Desktop implementation detail; rollout metadata cannot prove visible label stability |
| Task-level Full Access override | DynamicUi plus real Desktop `turn_context`, completion, exact command, and outside-workspace canary | Full Access intentionally removes the local sandbox for that task |
| Reading project secrets | StrictProfile workspace-relative deny globs | DynamicUi cannot install sticky deny-globs; unknown filenames need custom rules |
| Shell-based exfiltration | Network off or enforced allowlist | Allowed domains can still receive data; direct unrestricted access removes destination containment |
| Network prompt injection | Keep command networking narrow and treat remote content as untrusted | Allowed remote content can still manipulate an agent |
| Malicious or vulnerable downloads | Restrict destinations and review dependency changes | An allowed source can still be compromised |
| Approval or reviewer error | Hard sandbox boundary | In-boundary actions do not receive extra review |
| Recovery rule abuse | Exact executable, script, and Save/List action prefix plus bridge-internal validation | Rules are experimental and need upgrade checks |

DynamicUi Custom follows the workspace sandbox's broader read scope and does not protect credential files inside a writable workspace. Full Access is unrestricted. StrictProfile is the route for persistent root and credential denies. Web Search, Browser, Computer Use, apps, connectors, plugins, MCP, cloud tasks, source-control remotes, CI credentials, host malware, and credentials exposed before installation are also outside the installed command route. Report them as `NOT CONTROLLED`.

The Desktop selector compatibility layer runs the original signed executable with a project-owned main-process loader and Electron session preload. It creates no derivative client copy and distributes no OpenAI executable, ASAR, renderer bundle, or other client file. `NODE_OPTIONS` is set only in the launched Codex process; no user or machine environment value is written. Installation pins the exact official package identity, executable hash, ASAR hash, signer identity, shipped selector gate and structural anchors, loader hash, and preload hash. When an official update changes the version or bytes, a hash-pinned recertifier executed by the recorded PowerShell 7 path requires the same package family and publisher, a valid signer with the pinned subject, compatible selector structure, an isolated main-process hook probe, and an isolated document-start/non-interference probe before atomically refreshing both state records. A failed check preserves the prior accepted pins and disables launch. Verification must execute the installed launcher's non-mutating validation path—including live process-routing discovery—under real Windows PowerShell and prove that no extracted app tree exists. Installation must also prove that the matching startup watcher remains alive; a redirect failure is recorded but cannot terminate that watcher. The layer opens no debugging port, modifies no WindowsApps path, requires explicit acknowledgement, exempts the task running during migration from redirection, and preserves recoverable rollback history. It changes display behavior and launch routing; it does not grant additional filesystem or command-network authority.

## Credential incident rule

Do not infer causation from timing alone. If a real token may have appeared in model context, terminal output, logs, repository history, or a readable file: revoke or rotate it, inspect provider usage, remove persistent copies, and only then rely on the new boundary for future work.

Never print, hash, upload, or otherwise process a real secret merely to prove that it exists.

## Verification vocabulary

- `PASS`: directly checked and matched the expected condition.
- `PARTIAL`: configuration evidence exists, but a required runtime or CLI check was unavailable.
- `FAIL`: a required condition is missing or contradictory.
- `NOT CONTROLLED`: the capability uses a separate control surface.
