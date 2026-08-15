# Codex Safe Setup

[简体中文](README.zh-CN.md) · [Threat model](docs/threat-model.md) · [How it works](docs/how-it-works.md) · [Contributing](CONTRIBUTING.md)

[![CI](https://github.com/QianQIUlp/codex-safe-setup/actions/workflows/ci.yml/badge.svg)](https://github.com/QianQIUlp/codex-safe-setup/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/QianQIUlp/codex-safe-setup)](https://github.com/QianQIUlp/codex-safe-setup/releases)
[![License](https://img.shields.io/github/license/QianQIUlp/codex-safe-setup)](LICENSE)

**Approval is not a security boundary. Limit what an agent can change, read, and send.**

Codex Safe Setup is a community-built Codex plugin for installing a least-privilege, recoverable local configuration. It begins with a read-only audit, explains the actual tradeoffs, asks before every consequential choice, writes a backed-up configuration only after confirmation, and verifies the result.

The project exists because “I will review every command” and “another AI will review every command” are both fallible strategies. Full Access can also expose credentials and private files to an agent run even when no destructive command is executed. Hard capability boundaries reduce the impact of mistakes; approval remains a workflow choice inside and around those boundaries.

This project is not an absolute-safety guarantee and is not an official OpenAI project.

## Install

Requires Codex CLI 0.138.0 or newer. The plugin recommends PowerShell 7 on Windows and can install prerequisites only after explicit consent.

```powershell
codex plugin marketplace add QianQIUlp/codex-safe-setup --ref main
codex plugin add codex-safe-setup@codex-safe-setup
```

Start a new Codex task or CLI session, then ask:

```text
Use $secure-codex-setup to audit my current permissions and install the recommended profile.
```

The marketplace follows `main`, whose catalog pins the plugin to the latest released tag. You can also download the install-ready ZIP from [Releases](https://github.com/QianQIUlp/codex-safe-setup/releases).

If you installed `v0.1.0` using the old version-pinned marketplace command, switch that marketplace to the updateable channel once:

```powershell
codex plugin remove codex-safe-setup@codex-safe-setup
codex plugin marketplace remove codex-safe-setup
codex plugin marketplace add QianQIUlp/codex-safe-setup --ref main
codex plugin add codex-safe-setup@codex-safe-setup
```

Each release includes a `.sha256` file. Verify the downloaded archive on PowerShell with `Get-FileHash -Algorithm SHA256 <archive>`.

## What the setup asks you to choose

Approval mode and command networking are separate decisions:

| Choice | Recommended default | Meaning |
|---|---:|---|
| `BoundedAutonomy` | Yes | No approval prompts; out-of-bound actions fail at the permission boundary. |
| `AskMe` | Optional | Eligible crossings are sent to you for review. |
| `AutoReview` | Optional | Eligible crossings are sent to a reviewer agent; the sandbox does not become stronger. |
| Network `Off` | Yes | Commands cannot access the network. |
| Network `Allowlist` | Optional | The command proxy permits only explicitly named public domains. |
| Network `Unrestricted` | High risk | All public destinations are allowed, but only after the concrete risks are explained and separately acknowledged. |

`Unrestricted` networking does not by itself expand filesystem permissions or grant a new ability to delete files. The filesystem profile still applies, including its existing ability to change or delete writable workspace files. The added risk is loss of destination containment: anything a command can already read or generate could be sent to any public Internet destination, including source, configuration, output, private data, or credentials that use an unexpected filename. Untrusted pages, issues, and dependency documentation can also carry prompt injection; networked commands can download malware or vulnerable dependencies and introduce license-restricted content. OpenAI recommends limiting internet access to the domains and methods actually needed. See [Agent internet access](https://learn.chatgpt.com/docs/cloud/internet-access) and [Agent approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security).

On Windows, the setup separately asks whether to install PowerShell 7 and Codex CLI, and whether to use the administrator-backed elevated sandbox. Declining a prerequisite never silently installs it. PowerShell 7 reduces legacy shell, quoting, encoding, and compatibility mistakes; it is useful, but it is not itself a security boundary.

## What it changes

- Creates a named permission profile that denies filesystem root access, allows only minimal runtime reads, and limits writes to registered workspace roots.
- Denies common credential-bearing files such as `.env`, private keys, npm credentials, and cloud credential files inside the workspace.
- Keeps command networking off or routes it through an enforced allowlist proxy.
- Preserves Codex protections for `.git`, `.codex`, and `.agents`.
- Optionally installs a narrow, pinned Git checkpoint bridge that can save or list recovery checkpoints without changing the current branch, real index, or working tree.
- Backs up every managed file and provides an exact rollback command.

The installer refuses to mix modern permission profiles silently with legacy sandbox settings. Migration requires explicit consent and a backup is taken first.

## What it does not control

Web Search, Browser, Computer Use, apps, connectors, plugins, MCP servers, cloud tasks, source-control remotes, CI credentials, credentials exposed before installation, host malware, and operating-system compromise use separate control surfaces. Verification reports these as `NOT CONTROLLED` instead of implying protection.

Read the complete [threat model](docs/threat-model.md) before treating the result as a security control.

## Verification and recovery

The skill reports each control as:

- `PASS`: directly checked and matched.
- `PARTIAL`: configuration evidence exists, but a required runtime or CLI check was unavailable.
- `FAIL`: a required condition is missing or contradictory.
- `NOT CONTROLLED`: the capability belongs to another control surface.

Static configuration and `codex execpolicy check` are evidence, not proof of every future runtime behavior. After installation, open the Codex permission selector, choose **Custom**, confirm that `codex-safe-workspace` is selected, and start a new task or CLI session before runtime probes. Do not switch back to Full Access.

The optional checkpoint bridge snapshots tracked and ordinary untracked files to hidden refs under `refs/codex-safe/checkpoints/*`. It refuses sensitive-looking untracked files and never performs automatic `reset --hard`, `clean`, branch replacement, or in-place checkout. See [How it works](docs/how-it-works.md).

## Develop and test

Run from the repository root with PowerShell 7:

```powershell
pwsh -NoProfile -File ./tests/Validate-Package.ps1
pwsh -NoProfile -File ./tests/Run-Tests.ps1
pwsh -NoProfile -File ./tools/Build-Release.ps1 -Force
```

Tests use temporary Codex homes and Git repositories. They do not change the real Codex configuration. The suite covers configuration migration and preservation, injection guards, least-privilege generation, `execpolicy` validation, branch/index-neutral checkpoints, sensitive-file refusals, pinned Git, authorized repositories, target-locked rollback, and exact restoration.

## Community

- Use [Issues](https://github.com/QianQIUlp/codex-safe-setup/issues) for reproducible bugs and proposals.
- Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.
- Report vulnerabilities privately through [GitHub Security Advisories](https://github.com/QianQIUlp/codex-safe-setup/security/advisories/new), never in a public issue.
- See [SECURITY.md](SECURITY.md) for credential-incident guidance.

The project is licensed under [Apache-2.0](LICENSE).

## References

The implementation follows current OpenAI documentation for [plugins and marketplace distribution](https://developers.openai.com/plugins/build/plugins), [skills](https://learn.chatgpt.com/docs/build-skills), [permission profiles](https://learn.chatgpt.com/docs/permissions), [sandboxing and approvals](https://learn.chatgpt.com/docs/agent-approvals-security), [Windows sandboxing](https://learn.chatgpt.com/docs/windows/windows-sandbox), and [command rules](https://learn.chatgpt.com/docs/agent-configuration/rules). These surfaces evolve; rerun verification after Codex upgrades.
