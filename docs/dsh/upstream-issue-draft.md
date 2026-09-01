# Upstream issue drafts — deepseek-ai/deepseek-harness

> **These are drafts for review.** Nothing here has been posted. Each section below is a self-contained GitHub issue, ready to split and submit once reviewed. All file:line references are against `0.1.0-rc.5` / commit `47f9438` (2026-08-13). Full background: [audit.md](audit.md) / [audit.zh-CN.md](audit.zh-CN.md).

---

## Draft 1 — Plugin supply-chain hardening: pin by default, confirm bundle changes on update, ship an audit inventory

**Type:** feature request / security hardening

First: the care in this repo is noticed and appreciated — `strictDepBuilds` with a reviewed `allowBuilds` list, `minimumReleaseAge` against latency attacks, patched `node-pty`, a fail-closed approval ladder with a closed result set, and the browser-trust fence are all done better than in most comparable tools. This issue is about extending that same care from the repo itself to what users install *into* dsh.

dsh is reaching an audience that includes many first-time users (the ecosystem of beginner tutorials in Chinese is already large). For that audience, the current plugin flow asks them to make trust decisions they cannot yet evaluate:

1. **Floating refs are treated the same as pinned installs.** `dsh plugin add github:owner/repo` and a commit-pinned spec are handled identically; nothing surfaces the difference, even though the docs themselves say "Only allow packages whose source you trust, and pin a commit" (`docs/user/develop/basic/publish.md:173`).

2. **`dsh plugin update` can silently activate new code.** A dependency that gains a `dsh.bundle` declaration in a newer version is appended to the load stack without confirmation (`apps/cli/src/plugin.ts:59-91`). A user who reviewed version A is running arbitrary new host-process code after a routine update — the code comment describes this as intended behavior, so this is a proposal to add a confirmation step, not a bug report.

3. **There is no way to inspect what is actually loaded and where it came from.** `plugin-inventory` intentionally has "no cache, history, provenance model" (`packages/host/plugin-inventory/src/index.ts:56-69` and README), and community tutorials already reference audit tooling (`audit_plugin` / `audit_installed`) that doesn't exist in-tree — the demand is ahead of the supply.

Concrete proposals, in rough order of value:

- **Warn on unpinned git/https specs at install time**, with the pin command in the message. (Docs already prescribe pinning; the tool should too.)
- **Prompt on bundle-set changes during `update`** when a package newly declares `dsh.bundle` — "this package now wants to load as a plugin; its code will run in the dsh process; view diff / allow / skip."
- **A `dsh plugin audit` read-only report**: installed bundles per profile, source spec, pinned-or-floating, `allowBuilds` entries, last-updated. `plugin-inventory` plus provenance is exactly what third-party tutorials are trying to fake today.

Happy to turn any of these into a PR if the direction is welcome.

---

## Draft 2 — Credentials: prioritize the OS-keychain provider; document the read path for novice users

**Type:** feature request (echoing your own deferred work)

The honesty in `packages/credentials/credentials-local/README.md` ("stops other OS users — **not** the model… That is discretion, not a boundary", and the OS-keychain provider listed as deferred work) is exactly right, and this issue is mainly a request to raise its priority, for one reason: **the audience**.

Because every sandbox tier permits whole-disk reads (`packages/fs/fs-sandbox/src/index.ts:6-7` — "every mode permits reading"), a single successful prompt injection that reaches `cat ~/.dsh/.credentials.yaml` exfiltrates every stored provider key. The harness never hands the model the path, which is good discretion — but a one-liner in any injected tutorial page defeats it, and first-time users are the most likely to be running unfamiliar plugins (which execute in-process and can read the file directly, path or no path).

Two smaller asks alongside the keychain work:

- On first write of a key, print one line stating plainly that the file is readable by the agent and by any installed plugin in every permission mode.
- Consider a "did the session read the credentials file" tripwire in the session log (the file path is known; the log already records tool activity), so users have a forensic answer after a suspected injection.

---

## Draft 3 — Discussion: a network axis in the sandbox vocabulary

**Type:** discussion / long-term direction

`SandboxMode` today governs file-write effects only, and says so clearly (`packages/sandbox/sandbox/src/index.ts:23-28`: "Network and process visibility are outside this vocabulary"). That is a coherent, well-documented boundary — this is not a bug report. But for the novice audience, the gap between "I set read-only mode" and "the agent can still POST anything it can read to any destination" is where real losses will happen, because:

- `web_fetch` / `web_search` choose their own targets (`apps/web/tests/shipped-composition.e2e.ts:30-33` says so verbatim in the test comments),
- no backend has network rules (Landlock ABI 4 TCP bits unused, `native/landlock-run/packages/entry/src/main.c:71-88`; bwrap runs without `--unshare-net`; Seatbelt uses `(allow default)`),
- and exfiltration is the end-to-end goal of essentially every prompt-injection payload.

Even a coarse first step — e.g. a `workspace-write` companion flag that applies `--unshare-net` on bwrap and the Landlock TCP bits where the ABI allows, defaulting off — would give cautious users a real egress boundary instead of none. Would a contribution along those lines be considered, or is network policy deliberately out of scope for the seam's design?

---

### Posting notes (for internal review, do not post)

- Drafts 1 and 2 are safe to post as-is; verify the line numbers still match `master` at posting time (repo moves fast, rc.6+ may have shifted lines).
- Draft 3 invites a design debate — expect maintainer opinions about scope; the closing question is deliberately open.
- Consider posting Draft 1 first alone; 2 and 3 land better after a good-faith interaction exists on 1.
- All three avoid disclosing anything not already public in the repo/docs; the "potential approval-answerer bypass" from the audit (`approval/request` exposed to plugins) is intentionally **not** in these drafts — if you want to report it, do it privately first (GitHub security advisory / security@ contact if available) rather than in a public issue.
