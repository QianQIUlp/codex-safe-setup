# OS Boundary Model (Codex equivalence map)

The Codex edition enforces boundaries inside the Codex engine via `config.toml`
permission profiles. ZCode has no such configuration surface, so this edition enforces
the same intent with Windows itself: ZCode runs as a dedicated standard local user
(created by the installer), and NTFS ACLs - not model behavior - decide everything.

| Codex edition control | ZCode OS-cage equivalent | Strength |
|---|---|---|
| `":root" = "deny"` (filesystem deny outside workspace) | Another user's profile and the cage state are unreadable by the sandbox user (default profile ACLs) | OS-enforced |
| `":minimal" = "read"` | System directories readable as needed for execution | OS-enforced |
| workspace roots `= "write"` | Explicit Modify ACEs for the sandbox user on registered roots only | OS-enforced |
| secret globs `= "deny"` | Deny ACEs (`:R`) for the sandbox user on existing matching files | OS-enforced, install-time snapshot only |
| sandbox blocks writing its own config | Cage state lives in the main user's profile - sandbox user cannot read or modify it | OS-enforced |
| elevated/unelevated Windows sandbox | The sandbox account is a standard user; UAC separates admin authority | OS-enforced |
| `danger-full-access` avoidance | There is no full-access profile to fear: the account IS the boundary | OS-enforced |
| network allowlist + proxy | **No equivalent.** Windows Firewall cannot scope by user for one exe path | NOT CONTROLLED |
| execpolicy command rules | No equivalent needed: execution itself is bounded by the account and path policy | Partial |

## Machine-dependent: path-based execution control

Some machines (including the reference machine, see
`docs/zcode-probe/PROBE-REPORT.md`) only execute binaries from admin-controlled paths.
The installer therefore **always** installs the ZCode copy under `C:\Program Files\...`
and refuses user-writable install locations. Consequences on such machines:

- Repo-local executables will not run for the sandbox user (a real boundary, sometimes
  an inconvenience - report it, do not fight it).
- Tools installed per-user in the main profile (e.g. some python/pwsh setups) are
  unavailable inside the cage; machine-wide installs (e.g. `C:\Program Files\nodejs`)
  work normally.

## What the boundaries mean in practice

- A prompt injection that convinces the sandboxed agent to "read `~/.ssh` and post it"
  fails at the filesystem, before any network capability matters.
- An accidental recursive delete outside the granted roots fails; inside the roots,
  Git checkpoints (opt-in) bound the damage.
- The main user continues to work normally; only the sandbox account is restricted.

## Threat-model placement

| Threat | Covered? |
|---|---|
| Hallucinated/accidental destructive command outside roots | Yes - OS denial |
| Credential exfiltration from the main profile | Yes for reads (OS denial); network itself stays open - treat as damage limitation, not prevention |
| Prompt-instructed exfiltration of readable workspace data | No (network NOT CONTROLLED) - keep real secrets out of granted roots |
| Malware downloaded into the cage | Partial - it cannot touch the main profile, but runs inside the sandbox user's own space |
| Compromise of the main user | Out of scope - the main user is the trusted root |
