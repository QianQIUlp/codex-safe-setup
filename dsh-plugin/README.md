# dsh-safe-setup

English | [中文](README.zh.md)

An interactive safe-configuration wizard plugin for DeepSeek Harness (dsh). Same core philosophy as [codex-safe-setup](https://safercodex.qiu.works):

> **Approval is not a security boundary.** Commands grow too complex to review line-by-line; approval fatigue guarantees skim-reading; and "every line reasonable, the combination catastrophic" accidents exist. The key is not review — it is **locking the scope**: out-of-bound actions simply fail, and approval becomes a workflow choice inside the boundary.

## What it does (model axis)

The wizard asks a few questions, then:

1. Writes a **marked managed block** into `$DSH_HOME/cordis.patch.yml` (hot-applied by dsh's patch watcher; fully rollback-able): locks `sandbox-policy` to `workspace-write` and locks the `approval` policy to your chosen mode;
2. Enables tool-layer guards:
   - **web_fetch domain allowlist** (dsh has no network axis of its own — this fills that seat): Off / Allowlist / Unrestricted (requires a verbatim acknowledgement);
   - **credential-path read denial**: `.env`, `*.pem`, `id_rsa`, `~/.dsh/.credentials.yaml`-shaped paths are denied at the filesystem-tool layer;
3. Follows the staged flow end to end: **read-only assessment → disclosure → plan-only preview → explicit apply confirmation → verification → rollback record**.

Approval modes (all sharing the same least-privilege filesystem tier):

| Mode | dsh mapping | Behavior |
|---|---|---|
| BoundedAutonomy (recommended) | approval `never` | No prompts; escalations fail closed |
| AskMe | approval `ask` | Sandbox-escalation retries ask per call (strictly single-use grants) |

AutoReview is not offered: dsh has no reviewer-agent channel for approvals, and silently mapping it would misrepresent what it does.

## What it does NOT control (honest list)

A trustworthy security tool says what it does not control:

- **Third-party plugins**: dsh plugins run in-process with no isolation — no plugin (this one included) can constrain other plugins. Review source and pin a commit before installing anything.
- **Bash-initiated network**: dsh has no network sandbox; the allowlist covers the `web_fetch` tool only.
- **Bash `cat` on sensitive files**: the fs guard sits at the filesystem-tool layer (PARTIAL).
- **MCP subprocesses** and **dangerous command content** (e.g. `curl | sh`): outside dsh's tier vocabulary.

Full source-level evidence: the [dsh audit in codex-safe-setup](../docs/dsh/audit.md).

## Install and use

```sh
dsh plugin --profile web add github:<you>/dsh-safe-setup#<commit-sha>
```

Then run `/safe-setup` in a dsh Web UI session (commands dispatch without a model turn). `/safe-setup-rollback` shows the recorded backup and restores on confirmation.

## Status

Prototype, on a developer-preview harness. Logic-layer tests 10/10; pipeline wiring needs one real model turn to fully verify and is reported as PARTIAL until then. Guards stay inert until the wizard has run once. Apache-2.0; not affiliated with DeepSeek.
