# Contributing

Thank you for helping improve Codex Safe Setup. Security-boundary code benefits from small, reviewable changes and explicit evidence.

## Before opening an issue

- Search existing issues.
- Remove all real credentials, personal paths, account identifiers, and private repository names.
- Include the operating system, PowerShell version, Codex CLI version, chosen profile, expected behavior, actual behavior, and the smallest safe reproduction.
- Use GitHub Security Advisories instead of a public issue when a report could enable unauthorized access, secret exposure, policy bypass, or destructive behavior.

## Development setup

Install Git, PowerShell 7, and Codex CLI 0.138.0 or newer. Fork and clone the repository, then run:

```powershell
pwsh -NoProfile -File ./tests/Validate-Package.ps1
pwsh -NoProfile -File ./tests/Run-Tests.ps1
```

Tests must use temporary Codex homes and repositories. Never point tests at a real `CODEX_HOME`, real credentials, or an irreplaceable working tree.

## Pull requests

1. Keep the change focused on one coherent problem.
2. Explain the threat, failure mode, or user need being addressed.
3. Add or update a regression test for behavior changes.
4. Preserve unrelated TOML and existing user configuration.
5. Keep assessment read-only and never inspect secret contents.
6. Require explicit consent for dependency installation, elevated setup, unrestricted networking, migration, and configuration writes.
7. Run both validation commands and include their output summary.
8. Update user-facing and agent-facing documentation when behavior changes.

Changes that widen filesystem access, enable networking, broaden a command prefix, bypass a refusal, automatically restore Git state, or weaken rollback validation will not be accepted without a narrowly justified design and tests demonstrating the boundary.

## Style

- Use strict PowerShell mode and terminating errors for unsafe or ambiguous states.
- Prefer literal paths and canonical path validation.
- Do not build shell command strings from untrusted data.
- Keep `SKILL.md` concise; put detailed material in its directly linked references.
- Report verification as `PASS`, `PARTIAL`, `FAIL`, or `NOT CONTROLLED`.

By submitting a contribution, you agree that it is licensed under Apache-2.0.
