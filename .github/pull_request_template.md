## What changed

Describe the focused change and the user-visible result.

## Why

Describe the risk, failure mode, or user need.

## Security-boundary impact

State whether this changes filesystem access, network access, command rules, dependency installation, checkpoints, or rollback. Write "none" when it does not.

## Verification

- [ ] `pwsh -NoProfile -File ./tests/Validate-Package.ps1`
- [ ] `pwsh -NoProfile -File ./tests/Run-Tests.ps1`
- [ ] For DynamicUi changes: canonical Desktop E2E completed `codex-safe-workspace` → Full Access → built-in Workspace in one task with no new `session_meta`, and each clicked label stayed stable before, during, and after its turn.
- [ ] For Desktop compatibility changes: selector-gate, main-loader, document-start, tamper, upgrade, and rollback tests pass; no client binary, bundle, or derived copy is packaged.
- [ ] Tests use only temporary paths and synthetic data.
- [ ] Documentation is updated for changed behavior.
- [ ] No credentials, personal data, or private source code are included.
