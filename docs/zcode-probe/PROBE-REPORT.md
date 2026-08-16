# ZCode OS-Cage Feasibility Probe Report

**Date:** 2026-08-16 · **Machine:** QiuQian (Windows 11, main user `qianq` = admin with UAC filtered token) · **ZCode:** 3.7.7.4926 (per-user install at `%LOCALAPPDATA%\Programs\ZCode`)

## Verdict: GO (with one mandatory design constraint)

The OS-level cage — running ZCode as a dedicated low-privilege local Windows user — is
feasible and delivers genuinely hard, model-independent boundaries. One machine-dependent
constraint discovered during probing **must** shape the installer design:

> **ZCode must execute from an admin-controlled path (`C:\Program Files\...`).**
> This machine enforces path-based execution control: Win32 exes only run from protected
> paths (System32, Program Files) or per-binary allowlist entries; anything user-writable
> is blocked for **all non-elevated processes** (main user included). A per-user
> `%LOCALAPPDATA%` install therefore cannot execute under the sandbox user. Copying the
> install (619 MB, robocopy) into `C:\Program Files\ZCodeSandbox` + an RX ACE for the
> sandbox user **works**: ZCode started as the sandbox user with a normal GUI window,
> writing only to its own profile.

## Proven boundaries (all enforced by Windows itself, not by model behavior)

Probe executed as `zcode_probe` (standard user, created via `New-LocalUser`, launched
through `Start-Process -Credential` = `CreateProcessWithLogonW` + profile load):

| Probe | Result | Meaning |
|---|---|---|
| read canary in main profile | **DENIED** | `:root`-deny equivalent holds |
| list `C:\Users\qianq` | **DENIED** | main profile invisible |
| read `~\.zcode\v2\credentials.json` | **DENIED** | ZCode credentials unreachable |
| list `~\.ssh` | **DENIED** | SSH keys unreachable |
| write authorized root (granted `M`) | **ALLOWED** | workspace-write equivalent |
| write `C:\Windows` | **DENIED** | system protected |
| mkdir `C:\` root | **DENIED** | (this box is stricter than default Windows) |
| read `.env` in authorized root (deny ACE `:R`) | **DENIED** | `ProtectWorkspaceSecrets` equivalent |
| read ZCode.exe (no grant) | **DENIED** | default closed |
| read ZCode.exe after RX grant on dir only | **ALLOWED** | traverse-bypass: only leaf grant needed |
| `isAdmin` check | **False** | standard token confirmed |
| notepad + charmap GUI same-desktop | **window visible** | interactive desktop works cross-user |
| `git.exe` from Program Files | **runs** | PF execution OK for sandbox user |

## Root-cause trail for the "Electron won't start as sandbox user" mystery

1. ZCode/VS Code launched as sandbox user from their `%LOCALAPPDATA%` install dirs:
   instant silent exit (code 1), zero profile writes, no WER crash reports.
2. `where.exe` copied from System32 to any user-writable path (Public, `C:\Codes`,
   sandbox user's own profile, main user's own TEMP, even *inside* the ZCode install dir):
   **blocked, rc=2, zero output** — for main user non-elevated too.
3. Same `where.exe` from System32 or Program Files: runs fine as sandbox user.
4. `ZCode.exe` runs daily for the main user from `%LOCALAPPDATA%` → the machine allowlists
   specific installed binaries (per-binary hash/publisher), not directories.
5. Full install copied to `C:\Program Files\ZCodeSandbox` + RX grant → **plain launch as
   sandbox user works** (window title 'ZCode', 5 processes, settings written to
   `C:\Users\zcode_probe\.zcode\v2\setting.json`). No flags needed.
6. Second-instance delegation as main user exits code 0 (clean); sandbox failures were
   exit 1 — different path; irrelevant now that (5) resolves the blocker.

The policy mechanism was not identified precisely (SRP registry tree looked empty,
AppIDSvc stopped, `Get-AppLockerPolicy` unavailable, no WDAC class data) — behavior is
what matters and is documented above. **Assess must detect this empirically on each
machine** rather than assume it.

## PowerShell / Windows launch mechanics learned (load-bearing for the installer)

- `Start-Process -Credential -WindowStyle Hidden` → **always throws** "access denied"
  (known bug: temp `.lnk` + credential launch). Use plain launches.
- `Start-Process -Credential -Wait` → **throws "access denied" even though the launch
  succeeds**. Never use; synchronize via result files + polling instead.
- `-WorkingDirectory` must be readable by the target user (else ERROR_ACCESS_DENIED).
- GUI apps launched with credentials appear on the caller's desktop normally.
- New-LocalUser `-Description` max 48 chars.
- Profile of another user is unreadable to a non-elevated admin (filtered token) —
  elevated helpers are needed to inspect sandbox-side artifacts.
- `robocopy` exit codes ≤ 7 are success for scripting purposes.

## NOT CONTROLLED (must be documented honestly in the plugin)

- **Network**: Windows Firewall cannot scope rules by user for the same exe path.
  WebFetch/WebSearch/MCP/Bash-curl traffic is unfiltered. Optional cooperative local
  allowlist proxy = mitigation, not a boundary.
- **New secret files**: deny ACEs apply to files existing at install time. Secrets
  created later inside granted roots (e.g., by the sandbox user itself) are not covered;
  verify re-scans and reports.
- **Sandbox user's own ZCode credentials** are readable by the main user (main user is
  the trusted root).
- **Execution from workspace roots**: this machine blocks exes in user-writable paths —
  repo-local binaries won't run for the sandbox user (node.exe in Program Files is fine;
  per-user python/pwsh installs are not). Other machines may differ; Assess reports it.
- **In-session approval UX**: permission mode is the user's choice in the client; not a
  config-file boundary.

## Probe inventory (scripts preserved under `probes/`)

Consolidated, cleaned-up versions of the t1–t18 probe scripts live next to this report.
Original one-off artifacts ran from `%TEMP%\zcode-probe` and were fully cleaned up
(temp user `zcode_probe`, `C:\Program Files\ZCodeSandbox` copy, ACEs on the real ZCode
dir, Public scratch, authorized-root sample, canary, leftover GUI processes).
