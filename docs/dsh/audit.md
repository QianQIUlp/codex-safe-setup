# DeepSeek Harness (dsh) Plugin Loading & Permission Model Security Audit

| | |
|---|---|
| Subject | [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) |
| Baseline | `0.1.0-rc.5`, commit `47f9438` (2026-08-13, shallow clone) |
| Date | 2026-08-16 |
| Method | Source reading + targeted greps (including absence proofs) + cross-checks against official docs/postmortems; every claim carries a `file:line` reference, marked **code-verified** or **documented claim** |
| Purpose | Factual foundation for extending codex-safe-setup into the dsh ecosystem |

> 中文版：[audit.zh-CN.md](audit.zh-CN.md)

---

## Executive summary

dsh's security architecture defends the **model → tools** axis well: the three-tier file-write policy is clearly defined, fail-closed discipline is strict, the approval escalation ladder only ever widens, and audit logging is thorough. The web server's browser-trust fence is implemented better than in most comparable local tools.

But the **plugin → host** axis is wide open: third-party plugins are installed and loaded with zero isolation, zero verification, and zero approval gate — and the official documentation knows it (it literally calls allowing a build script "permission to execute the package's code on your machine at install time, outside any sandbox"). Combined with dsh's large audience of users without a computing background, **the plugin supply chain is the most realistic and highest-severity attack surface today** — and no plugin auditing tooling exists in the official repository.

One-line verdict: **dsh's permission model is an honest, well-engineered *file-write-effects* policy system, not a general security boundary — and it says so itself** (`packages/sandbox/sandbox/src/index.ts:23-28`).

---

## 1. Architectural background (prerequisite for the attack surface)

dsh is built on Cordis with "everything is a plugin": model adapters, the tool registry, the session log, **the sandbox and approval policy themselves**, and even the agent loop are plugins (`docs/architecture.md:11`). A running instance is a plugin tree assembled by stacking four layers (`docs/architecture.md:17-27`):

1. bundles (composition packages) listed by the profile, applied in order
2. the profile's `cordis.patch.yml`
3. the home-level (`$DSH_HOME`) `cordis.patch.yml`
4. any `--patch` CLI overlay

**Security implication**: any upper layer can **replace whole entries** by id — including the sandbox provider and the approval policy themselves. Convincing a user to "add this patch to enable a feature" is equivalent to replacing their security configuration.

**Configuration is code**: `!!js` expressions in any patch layer are evaluated at load time via `with(ctx){eval(expr)}` inside the host process (`vendor/loader/src/config/utils.ts:5-9`). YAML config files are a genuine JavaScript execution surface.

## 2. Permission model: three tiers + approval

### 2.1 Tier definitions (code-verified)

```ts
// packages/sandbox/sandbox/src/index.ts:29
export type SandboxMode = 'read-only' | 'workspace-write' | 'danger-full-access'
```

The third tier is internally named **`danger-full-access`**. The vocabulary comment (`index.ts:23-28`) states the scope explicitly: **file-write effects only; network and process visibility are outside the vocabulary**.

| Tier | File reads | File writes | Outbound network |
|---|---|---|---|
| `read-only` | **unrestricted, whole disk** | denied (only sinks such as `/dev/null`) | unrestricted |
| `workspace-write` | **unrestricted, whole disk** | workspace root + `/tmp` + `os.tmpdir()` | unrestricted |
| `danger-full-access` | whole disk | whole disk | unrestricted |

Code evidence: `packages/fs/fs-sandbox/src/index.ts:6-7` ("Reads pass through untouched: every mode permits reading"); `packages/sandbox/sandbox-local/src/profiles.ts:31,35,52` (Landlock `readOnly: ['/']`, bwrap `--ro-bind / /`, Seatbelt `(allow default) (deny file-write*)` — all three backends deny writes only).

### 2.2 Shipped defaults

- Package-level fail-safe default is `read-only` (`packages/sandbox/sandbox-policy/src/index.ts:94`).
- The shipped composition overrides this to `workspace-write` + approval `ask`: `packages/bundle/base/cordis.patch.yml:172-191`, controlled by the `DSH_PERMISSION_MODE` environment variable; an end-to-end test asserts the default (`apps/web/tests/shipped-composition.e2e.ts:109-111`).
- Note that `DSH_PERMISSION_MODE=danger-full-access` **simultaneously** sets approval to `never` — under the fully-open tier there is no confirmation gate at all.

### 2.3 Approval mechanism (what is done well)

Approval is not a general gate over "dangerous operations"; it covers exactly one action: **escalation retry after a sandbox denial**. The design discipline deserves credit:

- Strict monotonic widening (`packages/sandbox/sandbox/src/escalation.ts:28-31`); a non-widening escalation request is rejected without a prompt (`:162-164`);
- Results form a closed set of 4 values (`allowed-once | rejected | cancelled | unavailable`, `:93`); **there is no "always allow"** — grants are strictly per-call;
- Fail-closed: no answerer or a failing answerer settles as `unavailable` (`packages/interaction/user-approval/src/index.ts:304-344`); `never` means **auto-reject**, not auto-approve (`:100`) — an auto-approve tier does not exist;
- Every ask and decision is persisted to the session log (`user-approval/src/index.ts:44-59,257-276`);
- The agent cannot switch tiers through any model-visible tool: switching comes only from the user-facing `/permission` command, and the model merely receives a "changed by the user" notice (`user-approval/src/index.ts:230-236`).

**Gaps**:
- **The TUI (terminal) has no approval answerer** — escalation requests fail closed, and terminal users must switch tiers manually via `/permission` (`.agents/notes/implemented/feature/2026-07-31-workspace-write-surface-default.md`; grep of `apps/cli/src` for `approval` returns nothing).
- **Potential bypass vector found by this audit**: the plugin API catalog exposes the `approval/request` event to plugin authors (`packages/extensions/tool-cordis/src/api-catalog.ts:2273-2275`), and the dynamic-plugin ctx facade whitelist includes `on` (`packages/extensions/cordis-host-runner/src/guard.ts:632-636`) — an activated plugin can register an approval answerer returning `allowed-once` (the waterfall is first-come-first-served). This is a code-level inference; no test coverage was observed.

## 3. Sandbox implementation

Backends are chosen per platform (`packages/sandbox/sandbox-local/src/index.ts:159-166`):

| Platform | Backend | Notes |
|---|---|---|
| Linux | bwrap → Landlock (probe fallback) | Landlock is a native C launcher (`native/landlock-run`) handling `LL_FS_*` file bits only — **the ABI 4 TCP bits are not included** (`packages/entry/src/main.c:71-88`) |
| macOS | Seatbelt (`sandbox-exec`) | `(allow default) (deny file-write*)` — everything except file writes is allowed by default |
| Windows | restricted token + DACL | **Self-rated `partial` enforcement**: the Everyone-ACE gap plus NTFS hard links can alias workspace files outside the workspace (`sandbox-local/src/index.ts:177-187`); the workspace ACE is standing, reused across sessions, and deliberately never revoked (`packages/sandbox/sandbox-windows-acl/src/index.ts:10-15`) |

What it covers: one-shot bash/pwsh subprocesses, file tools (write/edit — an **in-process** policy fence that self-describes as "NOT a kernel boundary … residual TOCTOU … accepted", `packages/fs/fs-sandbox/src/index.ts:10-18`), and PTY terminals. All three share the same writable-roots to prevent drift.

**Outside the sandbox**: MCP server subprocesses (spawned by the SDK stdio transport, not via `ctx.shell`/`ctx.sandbox`, `packages/mcp/mcp-client/src/transport.ts:10,18`), the bundled ripgrep, and E2B remote execution.

## 4. What the permission model does not govern (under any tier)

1. **Outbound network** — no network kill switch, no domain allowlist; `web_fetch`/`web_search` targets are model-chosen (stated verbatim in the official test comment, `shipped-composition.e2e.ts:30-33`).
2. **Unrestricted reads** — even `read-only` permits reading the whole disk; secret exfiltration is unguarded.
3. **Process visibility and inter-process operations** (self-documented for Windows ACL, `sandbox-windows-acl/src/index.ts:23-25`).
4. **MCP subprocesses** — run with full host privileges.
5. **Dynamic Cordis plugin host code** — see §5.3.
6. **Dangerous command content** — no static analysis or denylist; `bash -c` passes commands through verbatim (official TODO self-admission, `packages/shell/tool-bash/src/index.ts:6-7`); `curl | sh` runs under every tier.
7. **The system temp directory** — `workspace-write` always includes `/tmp` and `os.tmpdir()`, shared across sessions (`packages/sandbox/sandbox/src/roots.ts:54`).
8. **Config-layer replacement** — an upper patch layer can replace sandbox/approval entries wholesale (§1).
9. **Plugins themselves** — the largest gap; see below.

## 5. Plugin system attack surface (core findings)

### 5.1 Installation: a thin pnpm forwarder with no argument allowlist

`dsh plugin --profile <name> <args...>` spawns `pnpm` verbatim (`apps/cli/src/plugin.ts:120-133`). Two code-execution-at-install paths:

- **npm lifecycle scripts**: pnpm ≥10 blocks build scripts by default, but dsh **actively guides users** to add the package's key to the profile's `allowBuilds` and re-run (`plugin.ts:149-155`);
- **Load-time execution** (unconditional): prebuilt packages "require no build allowance" — the first boot after install executes module code inside the host process (`docs/user/develop/basic/publish.md:175-178`).

Official documentation, verbatim (`publish.md:173` — hard evidence, quotable):

> "Treat that allowance as what it is: **permission to execute the package's code on your machine at install time, outside any sandbox the agent runs under**. Only allow packages whose source you trust, and pin a commit…"

**No signatures, no verification, no provenance checks**: a full grep of `packages/boot/` and `apps/cli/src/` for `signature|integrity|checksum|attestation|verify` yields no security-relevant hits; a floating ref (`github:you/hello-plugin`) and a pinned-commit install are treated identically by dsh.

### 5.2 Loading: in-host import, zero isolation

The loading chain is same-process throughout: `loadProfile` reads bundle manifests (`packages/boot/app-boot/src/profile.ts:371-403`) → `boot` → import via the Node ESM loader (`packages/boot/app-boot/src/index.ts:492-503`) → each entry is dynamically imported and its `apply(ctx, config)` invoked (`vendor/loader/src/config/entry.ts:280-282`).

**Isolation survey (absence proof)**: grepping `packages/bundle/` and `apps/cli/src/bin.ts` for `worker_threads|new Worker|fork|vm` returns zero hits. Cordis's `isolate` is symbol-realm service-visibility isolation, not execution isolation (`vendor/loader/src/config/isolate.ts:26-40`). After boot, all enabled entries are **forced** to activate; failure exits the process (`app-boot/src/index.ts:692-725`) — there is no approval gate.

A plugin can `import node:fs / node:child_process / node:net` directly; in-process code is untouched by fs-sandbox/approval/Landlock — **capability trimming lives entirely in the "model tool call" layer, not the "plugin code" layer**. Postmortem 0002 admits it officially: "permission presets … cannot mount, unmount, or confine the filesystem stack" (`docs/postmortem/0002-js-expression-disabled-filesystem-tools.md:21`).

### 5.3 Update-as-privilege-escalation + model-authored plugins

- **Update escalates**: on `dsh plugin update`, an installed package that newly declares `dsh.bundle` in a newer version is **automatically appended** to the load stack with no approval (`apps/cli/src/plugin.ts:59-91`; the code comment confirms: "an `update` activates a package that gained its `dsh.bundle` declaration in a newer version").
- **The model can author plugins**: the `cordis_define` tool family lets the model write dynamic packages executed in `node:vm` — a vm the project itself describes as "not containment: host-realm helper functions remain an escape route" (`cordis-host-runner/src/sandbox.ts:6-7`). Dynamic packages with only a host half **activate without user approval** (`cordis-host-runner/src/index.ts:270-274`); declaring `inject` yields the **real** `ctx.fs / ctx.web / ctx.bash` services, which run reads/writes/network silently at the default tier and **bypass the tool-layer approval path entirely**. Activation approval offers "double-check to authorize future versions" (`approveFutureVersions`) — **one double-check and subsequent arbitrary code versions of the same plugin run automatically** (`tool-cordis/src/prompt.ts:45`). This is a realistic prompt-injection → host-process path; the shipped-composition test comment says it outright: "the `cordis_*` toolset executes model-written JavaScript **that no sandbox row confines**" (`shipped-composition.e2e.ts:30-33`).

### 5.4 Manifests and inventory

A bundle declares itself via `package.json`'s `"dsh": { "bundle": { "patch": "./cordis.patch.yml" } }` (`profile.ts:41-51`). **There is no permission-declaration field** (no permissions/capabilities key anywhere in the boot/loader path). `plugin-inventory` is a read-only status projection — its README says "no cache, history, provenance model, event stream", and it cannot tell which bundle/profile introduced an entry (`packages/host/plugin-inventory/src/index.ts:56-69`).

### 5.5 Official audit tooling: nonexistent

The `audit_plugin` / `audit_installed` commands mentioned in community articles have **zero hits** in the repository (full-tree grep); the CLI registers only `plugin` and `web` subcommands. The third-party-plugin audit niche is currently **empty**.

## 6. Web attack surface: something done right

The low-level webserver is an unauthenticated raw route table (`packages/host/webserver/src/index.ts`, bind-capable to `0.0.0.0`), but the layer above has a carefully designed browser-trust fence (`packages/client/connection/src/api-request-trust.ts:96-123`):

- The **Host fence** applies to every request (DNS-rebinding defense — the browser's inability to forge Host is the core argument; the plain-HTTP read case that carries neither Origin nor Fetch-Metadata is reasoned through);
- `Sec-Fetch-Site: cross-site` is always refused; an Origin, when present, must match the Host exactly; the `null` origin is refused;
- The comment is explicit that "this fence is not an auth layer" — any local process can call the API (normal for local tools), and a malicious web page cannot get in under modern browsers.

**Boundary**: binding `0.0.0.0` plus `--trusted-host` extends the trust boundary to the LAN; older browsers without `Sec-Fetch-Site` rely on the Host fence alone.

## 7. Credentials and session log

- **Credentials are stored in plaintext**: API keys live in `~/.dsh/.credentials.yaml` (0600/0700; POSIX permission bits are validated, the check is skipped on Windows). The README's security-boundary section, verbatim (`packages/credentials/credentials-local/README.md:54`): it "stops other OS users — **not the model**… That is discretion, not a boundary". workspace-write confines writes but not reads, and tool processes share the user's identity: **a prompt injection that steers the agent to read that file exfiltrates every API key** (the harness never hands the model the path — but a `cat ~/.dsh/.credentials.yaml` suffices). An OS keychain provider is the officially deferred answer.
- **Session log**: "model-visible is recorded" is a runtime invariant (`docs/architecture.md:96-100`) — a strong forensic base; but `packages/core/session/src` contains **no hash chain / integrity check** — append-only is a design discipline, not tamper evidence.

## 8. Realistic attack scripts against novice users

The findings above, translated into victim terms (this is also the skeleton for safe-setup content):

1. **Malicious plugin** (highest severity): a tutorial saying "run `dsh plugin add github:xxx/yyy`" — install is arbitrary code execution outside any sandbox; even if the first version is clean, a later `update` that adds a bundle declaration silently escalates. A novice cannot tell the difference.
2. **Induced patch**: a "unlock full access" recipe circulating in group chats — one `cordis.patch.yml` entry, or the environment variable `DSH_PERMISSION_MODE=danger-full-access`, removes every guardrail (the latter also disables approval).
3. **Prompt injection → self-authored plugin**: injected content while browsing/reading repos leads the model to write code via `cordis_define` in an "escapable vm"; users faced with the activation prompt will click approve — possibly double-clicking through to future versions.
4. **API key theft**: an injection makes the agent `cat ~/.dsh/.credentials.yaml` — not stopped even under read-only (which bans writes, not reads); the stolen key leaves over the always-open network.
5. **Downloader attacks**: network is unrestricted under every tier; `curl | sh` faces no content inspection and no domain allowlist.

## 9. Comparison with Codex CLI (migration view)

| Dimension | Codex CLI | dsh |
|---|---|---|
| Permission vocabulary | Read/write/network axes; sandbox tiers include network isolation | **file-write effects only**; network, reads, processes are outside the vocabulary |
| Sandbox | Platform mechanisms + network isolation (per config) | file-write ACL/Landlock/Seatbelt; Windows self-rated partial; **no network isolation** |
| Extension model | config files + MCP; MCP processes are separate | **in-process plugins, zero isolation**; configuration is code (`!!js`→eval) |
| Supply chain | npm packages + official registry | pnpm forwarding + GitHub ecosystem, no review, no signatures, update escalates |
| Local service | — | Web UI + triple browser fence (well done) |
| Credentials | — | plaintext yaml; officially acknowledged as not model-proof |
| Audit | session records | strong session log (model-visible-is-recorded), but no tamper evidence |

Conclusion: codex-safe-setup's core methodology (threat model → safe config profiles → one-click install/rollback → assessment script) **transfers wholesale**, but the dsh edition's emphasis shifts from "unrestricted network risk disclosure" (the v0.1.1 theme) to **plugin supply chain and config-layer replacement** — because that is where dsh's door actually stands open.

## 10. Recommendations for codex-safe-setup

1. **Ship "assessment + guide" first; plugin-ify later**: the counterpart of `Assess-CodexSafety` (a `dsh --dump-config` sweep over tiers/approval/installed bundles/allowBuilds/credential permissions) plus a hand-holding Chinese tutorial reaches novices better than a third-party security plugin (trust-bootstrap problem: distributing a security plugin through an unreviewed channel is itself the attack surface we warn about).
2. **Use dsh's own mechanisms for defense**: the `tools/pre-execute` waterfall is a ready-made interception point (the official deployment-policy TODO is still vacant, `packages/shell/tool-bash/src/index.ts:6-7`); a home-level `cordis.patch.yml` can tighten the default tier; the plugin API allows an approval-answerer UI — but all of these should ship as **recommended configuration**, not merely as yet another plugin.
3. **The best play is upstream**: propose default locked/pinned installs, confirmation when `dsh bundle` declarations change (closing update-escalation), and an OS keychain for credentials (already semantically on the roadmap). A merged PR beats a fork on the road to "the default safe option on a novice's path".
4. **Windows users need special care**: the Windows sandbox is partial and its ACEs are standing — and dsh's novice audience is heavily on Windows, which is exactly codex-safe-setup's home turf (PowerShell, Windows-first).

---

## Appendix: evidence index (main entries)

| Conclusion | Evidence (relative to the dsh repo root) |
|---|---|
| Three-tier definition; "network outside the vocabulary" | `packages/sandbox/sandbox/src/index.ts:23-29` |
| Shipped default workspace-write + ask | `packages/bundle/base/cordis.patch.yml:172-191` |
| Closed approval result set / per-call grant / fail-closed | `packages/sandbox/sandbox/src/escalation.ts:93,157-189`; `packages/interaction/user-approval/src/index.ts:304-344` |
| TUI has no approval answerer | `.agents/notes/implemented/feature/2026-07-31-workspace-write-surface-default.md` |
| All tiers allow whole-disk reads | `packages/fs/fs-sandbox/src/index.ts:6-7` |
| No network isolation (all platforms) | `packages/sandbox/sandbox-local/src/profiles.ts:16-58`; `native/landlock-run/packages/entry/src/main.c:71-88`; `sandbox-windows-acl/src/index.ts:23-25` |
| Windows partial enforcement / standing ACE | `packages/sandbox/sandbox-local/src/index.ts:177-187`; `sandbox-windows-acl/src/index.ts:10-15` |
| No dangerous-command static analysis (official TODO) | `packages/shell/tool-bash/src/index.ts:6-7` |
| dsh plugin = pnpm forwarder | `apps/cli/src/plugin.ts:120-133` |
| "Execute at install, outside any sandbox" (official admission) | `docs/user/develop/basic/publish.md:173-178` |
| Plugin loading has zero isolation | `packages/boot/app-boot/src/index.ts:492-503,692-725`; `vendor/loader/src/config/entry.ts:280-282` (grep: no worker/vm) |
| Update-as-escalation | `apps/cli/src/plugin.ts:59-91` |
| Configuration is code | `vendor/loader/src/config/utils.ts:5-9` |
| vm not containment / double-check future versions / host-only packages skip approval | `packages/extensions/cordis-host-runner/src/sandbox.ts:6-7`; `tool-cordis/src/prompt.ts:45`; `cordis-host-runner/src/index.ts:270-274` |
| "no sandbox row confines" (official test comment) | `apps/web/tests/shipped-composition.e2e.ts:30-33` |
| Permissions cannot confine the in-process stack (official postmortem) | `docs/postmortem/0002-js-expression-disabled-filesystem-tools.md:21,47` |
| Browser-trust fence | `packages/client/connection/src/api-request-trust.ts:96-123` |
| Plaintext credentials / not model-proof (official admission) | `packages/credentials/credentials-local/README.md:44-56` |
| MCP processes outside the sandbox | `packages/mcp/mcp-client/src/transport.ts:10,18` |
| plugin-inventory has no provenance tracking | `packages/host/plugin-inventory/src/index.ts:56-69` |
| audit_* tools do not exist | full-repo grep, zero hits; CLI registers only `plugin`/`web` |
