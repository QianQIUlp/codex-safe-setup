# Changelog

All notable changes are documented here. Releases follow semantic versioning.

## 0.1.2 - 2026-08-18

- Fix `Unrestricted` command networking to use direct networking with the filtering proxy disabled, so native protocols such as OpenSSH are not trapped behind the offline sandbox account's proxy route.
- Keep `Allowlist` proxy-filtered and `Off` fully offline; remove obsolete wildcard domain state from direct networking.
- Rename the canonical skill from `secure-codex-setup` to `codex-safe-setup` and retain the old name as an explicit-only compatibility alias for 0.1.1 users.
- Add a dedicated, plan-first upgrade command that preserves prior choices, requires security acknowledgements again when applicable, and refuses accidental first-installer overwrites.
- Add state schema 2, product and transaction versions, transaction-scoped backups, immutable previous-state snapshots, and chained rollback.
- Document and test the separate plugin-refresh, machine-configuration migration, and fresh-task activation phases.
- Mark the project accurately as a third-party GitHub marketplace plugin that is not listed in OpenAI's universal public directory.
- Required action for existing 0.1.1 `Unrestricted` users: refresh/reinstall the plugin, run the configuration upgrade, fully restart Codex, and verify direct TCP or native OpenSSH in a fresh task.

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
