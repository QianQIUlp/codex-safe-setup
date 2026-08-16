# Changelog

All notable changes are documented here. Releases follow semantic versioning.

## 0.2.0 - Unreleased (feat/zcode-safe-setup branch)

- Add the ZCode edition as a native plugin (zcode/): an OS-enforced cage for ZCode on Windows - dedicated standard user, NTFS workspace grants, secret deny ACEs, admin-controlled Program Files install copy, DPAPI launcher credential, Start Menu shortcut, and exact rollback.
- Optional branch/index-neutral Git checkpoints under refs/zcode-safe/* with repository authorization, sensitive-file refusal, and pinned Git verification.
- Honest verification vocabulary retained: network egress, post-install secrets, and main-user sessions are reported NOT CONTROLLED.
- Add the ZCode marketplace files (.claude-plugin/ and .zcode-plugin/), package validation, headless test coverage, release packaging, and the machine-verified feasibility probe report under docs/zcode-probe/.
- Codex edition unchanged.

## 0.1.1 - 2026-08-16

- Explain the concrete consequences of unrestricted command networking before acknowledgement: destination-unbounded exfiltration, prompt injection, unsafe downloads, and license risk.
- Clarify that command networking does not itself widen filesystem or deletion authority, while existing workspace write/delete capability remains.
- Require the completion handoff to select `Custom` / `自定义`, confirm `codex-safe-workspace`, and start a new task or session.
- Move new marketplace installs to a `main`-tracked catalog so subsequent released versions can be discovered, with a one-time migration path for `v0.1.0` users.
- Add regression coverage for the risk disclosure, acknowledgement guard, and activation handoff.
- Diagnose repeated Windows elevated-sandbox administrator prompts by reporting proxy-port setup conflicts while treating recovered, aligned history as informational.
- Clarify that normal activation needs a Codex restart and new task, while repeated prompts require a full desktop/CLI process shutdown before one clean relaunch.

## 0.1.0 - 2026-08-15

Initial public release.

- Read-only assessment of current Codex permissions and prerequisites.
- Consent-driven least-privilege configuration for Windows, macOS, Linux, and WSL.
- Independent approval and command-network choices.
- Legacy-setting migration guard with exact backup and rollback.
- Optional branch/index-neutral Git checkpoints with repository authorization, sensitive-file refusal, and pinned Git executable verification.
- Static, TOML, and Codex execpolicy verification with honest PASS/PARTIAL/FAIL/NOT CONTROLLED reporting.
- GitHub marketplace metadata, install-ready release packaging, CI, and community contribution files.
