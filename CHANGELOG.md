# Changelog

All notable changes are documented here. Releases follow semantic versioning.

## 0.2.0 - 2026-08-20

- Preserve the verified runtime rule that the last deliberate selector click governs the next turn. DynamicUi uses built-in Workspace as its startup default plus two positive-only named profiles, with no sticky filesystem deny entries.
- Add a real Desktop end-to-end verifier that separates runtime evidence from direct before/during/after observation of the selector label.
- Add an optional, explicitly acknowledged Windows Desktop compatibility layer for affected builds whose selector label changes without a click. It launches the original signed executable with a process-scoped main loader and a hash-pinned Electron session preload that runs before the first renderer script; it creates no derived client copy and opens no debugging port.
- Pin the compatibility layer to the exact package version, executable, ASAR, signer, and shipped selector gate. Add isolated main-process and document-start probes, startup redirection that preserves the task running during migration, tamper detection, generation history, and recoverable rollback. Release archives contain no OpenAI executable, ASAR, renderer bundle, or other client file.
- Validate the installed launch chain under real Windows PowerShell and use module-independent SHA-256 hashing, preventing a missing `Get-FileHash` command from disabling startup redirection while renderer-only probes still pass.
- Validate the live process-routing branch as part of that hidden launch check, normalize scalar Windows PowerShell query results, require a live startup watcher before installation can pass, and keep the watcher running after a failed redirect attempt so a later launch can recover.
- Automatically recertify compatible official Desktop updates by requiring the same package family and publisher, a valid pinned signer identity, tested selector structural anchors, and fresh isolated main-process and document-start probes. Refresh schema-3 version and byte pins atomically only after every check passes; preserve the prior accepted state and fail closed for incompatible updates.
- Preserve StrictProfile for fixed deny-read boundaries, record the main configuration as state schema 9, and retain migrations from the unreleased 0.1.7-0.1.9 development states.

## 0.1.6 - 2026-08-19

- Add `DynamicUi` routing, which removes the plugin-owned named-profile/default pin and uses the Desktop-compatible sandbox route so Full Access, Workspace, and Read-only changes apply on the next user message in the same task.
- Preserve an existing UI-selected `sandbox_mode` during the 0.1.5 upgrade; when none exists, install a workspace fallback. Record routing state as schema 5.
- Retain `StrictProfile` as the explicit alternative for root deny-read, credential deny-globs, and proxy allowlists. DynamicUi discloses its broader legacy read scope and requires acknowledgement.
- Add the exact deleted-default/mixed-profile regression and an app-server integration test that switches one live thread from Workspace to Full Access and back.
- Align plugin, marketplace, tests, documentation, tag, archive, checksum, and release metadata at 0.1.6.

## 0.1.5 - 2026-08-18

- Keep codex-safe-workspace as the normal default while preserving explicit task-level UI overrides; Full Access is accepted only when the effective runtime is :danger-full-access.
- Stop treating codexsandboxonline or codexsandboxoffline as permission evidence; those names describe Windows sandbox/network variants.
- Remove the alternate Status/Commit Git backend and restore native Git as the only normal status/add/commit/branch path.
- Migrate install state to schema 4 and rewrite old workspace registries to the recovery-only Save/List format without changing the user's network, approval, Windows sandbox, backup, or rollback choices.
- Add package and behavioral assertions for UI/runtime profile provenance and for the absence of normal-commit bridge actions.

## 0.1.4 - 2026-08-18

- Rebuild release artifacts from byte-preserved UTF-8 source after withdrawing the encoding-damaged v0.1.3 package.
- Fix automatic publication by explicitly dispatching the Release workflow after an aligned version tag is validated or created.
- Add package validation for strict UTF-8 decoding and required Chinese text sentinels so encoding regressions fail CI.

## 0.1.3 - 2026-08-18

> Withdrawn: GitHub release artifacts for this version were encoding-damaged. Use 0.1.4 or later.

- Fix linked-worktree Git workflows without granting raw write access to the parent repository's shared `.git`.
- Add bridge `Status` so real Git state can be compared with sandbox/ACL visibility artifacts instead of treating inaccessible tracked files as deletions.
- Add an explicit opt-in `Commit` action for registered worktrees. It accepts literal paths only, defaults to `codex/` branches, requires a clean index and no in-progress Git operation, suppresses hooks/signing, refuses repository-local clean/process filters, verifies the staged path set, and preserves unselected changes.
- Upgrade install state to schema 3 and registry schema 2 while preserving prior choices and rollback generations. Existing installations keep normal commits disabled until the user explicitly enables them.
- Add guarded automatic release tagging when an aligned manifest and marketplace version reaches `main`; the existing tag workflow still validates, packages, checksums, and publishes the release.
- Add isolated linked-worktree coverage for shared Git metadata, exact-path commits, branch isolation, and untouched unselected changes.

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
