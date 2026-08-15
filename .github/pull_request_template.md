## What changed

Describe the focused change and the user-visible result.

## Why

Describe the risk, failure mode, or user need.

## Security-boundary impact

State whether this changes filesystem access, network access, command rules, dependency installation, checkpoints, or rollback. Write "none" when it does not.

## Verification

- [ ] `pwsh -NoProfile -File ./tests/Validate-Package.ps1`
- [ ] `pwsh -NoProfile -File ./tests/Run-Tests.ps1`
- [ ] Tests use only temporary paths and synthetic data.
- [ ] Documentation is updated for changed behavior.
- [ ] No credentials, personal data, or private source code are included.
