# Security policy

## Supported versions

Security fixes are applied to the latest published release. Older releases may not receive backports.

## Report a vulnerability

Use [GitHub's private vulnerability reporting](https://github.com/QianQIUlp/codex-safe-setup/security/advisories/new). Do not open a public issue for a sandbox bypass, secret exposure, command-rule escape, checkpoint authorization flaw, rollback path flaw, or other security-sensitive report.

Include:

- affected version and platform;
- prerequisites and configuration mode;
- a minimal reproduction using synthetic data only;
- expected and observed boundaries;
- potential impact;
- any suggested remediation.

Do not include real credentials, personal data, private source code, or destructive proof-of-concept payloads. The maintainer will acknowledge the report, reproduce it when possible, coordinate a fix and release, and credit the reporter if requested.

## If a credential may already be exposed

Do not wait for a software fix. Revoke or rotate the credential, inspect provider usage and billing, terminate unknown sessions, and remove persistent copies from files, logs, shell history, and repository history. A later configuration change cannot undo prior exposure.

Timing alone is not proof of how a credential was compromised. Preserve relevant non-secret evidence for investigation.
