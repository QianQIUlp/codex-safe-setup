# dsh (DeepSeek Harness) extension materials

Security-audit foundation for extending codex-safe-setup to the DeepSeek Harness ecosystem. Everything here is a working draft pending review — nothing is committed to a release or posted upstream.

| File | What it is |
|---|---|
| [audit.zh-CN.md](audit.zh-CN.md) / [audit.md](audit.md) | Source-level security audit of dsh `0.1.0-rc.5` (commit `47f9438`): permission tiers, approval, sandbox backends, plugin system, web surface, credentials, session log — with a file:line evidence index. Bilingual. |
| [upstream-issue-draft.md](upstream-issue-draft.md) | Three ready-to-review GitHub issue drafts for deepseek-ai/deepseek-harness (plugin supply-chain hardening, credentials keychain priority, network-axis discussion). Not posted. |
| ../../skills/secure-dsh-setup/ | Assessment-skill prototype: `Assess-DshSafety.ps1` (read-only sweep of `$DSH_HOME` — patch-layer security overrides, floating git dependencies, `allowBuilds`, credentials presence) plus its SKILL.md. |
| ../../dsh-plugin/ | **dsh-safe-setup** — the wizard plugin itself: interactive safe configuration (`/safe-setup`), tool-layer guards (web_fetch allowlist, credential-path denial), managed-block lock of sandbox tier + approval, backup/rollback. Logic tests 10/10; verified end-to-end against a real dsh 0.1.0-rc.6 boot (plugin load + managed-block effect on the composed tree). |

## Key findings in one minute

- dsh's permission tiers (`read-only` / `workspace-write` / `danger-full-access`) govern **file-write effects only**. Network egress, file reads, plugin code, MCP processes, and command content are outside the vocabulary in every tier — the code says so itself.
- Third-party plugins install and load with **zero isolation, zero verification, zero approval gate** (in-host import; no worker/vm anywhere on the load path), and `dsh plugin update` auto-activates packages that newly declare `dsh.bundle` — update is a privilege-escalation path.
- Credentials are plaintext in `~/.dsh/.credentials.yaml` and readable by the agent under every tier; the official README states this is "discretion, not a boundary".
- Done well: fail-closed approval design, the browser-trust fence on the web API, append-only session logging, and the repo's own internal supply-chain hygiene.

## Local dsh checkout

The audit was performed against a shallow clone at `C:\Codes\deepseek-harness` (kept for follow-up work; safe to delete).
