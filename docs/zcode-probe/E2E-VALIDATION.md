# ZCode Safe Setup E2E Validation

**Date:** 2026-08-16  
**Machine:** Windows 11 build 10.0.26100 (VM)  
**Repository branch:** `feat/zcode-safe-setup`  
**ZCode:** 3.7.7 (user install under `%LOCALAPPDATA%\Programs\ZCode`)  
**Primary user:** `telecaster\qiu`  
**Sandbox user:** `telecaster\ZCode-Sandbox`  
**Result:** **PASS after four small fixes found by real execution**

## Scope and safety notes

This was a real-machine acceptance run of the formal installer, verifier,
launcher, checkpoint bridge, and rollback scripts. The VM snapshot was **not**
used; the operator explicitly chose to proceed without one. The rollback script
was tested independently and completed successfully.

No secret contents were read. Assessment and verification checked only the
existence of credential locations and ACL behavior. The workspace used for the
run was a synthetic Git repository at `C:\ZCode-E2E\demo-workspace`; its `.env`
contained a fake value created solely to exercise the deny-ACE path.

The machine's current process was already running with an administrator token,
so neither the install nor rollback path displayed a UAC prompt. This is an
environment difference from the normal filtered-token flow, not a bypass of the
installer's consent flags. The plan still reported the required one-UAC setup.

## Step 0: Environment preflight — PASS

- Windows: confirmed.
- Administrator token: confirmed (`IsInRole(Administrator) = True`).
- ZCode executable: `%LOCALAPPDATA%\Programs\ZCode\ZCode.exe` exists.
- Main-user login: `%USERPROFILE%\.zcode\v2\credentials.json` exists (existence only;
  contents were never read).
- Git: 2.55.0.windows.3.
- PowerShell 7: 7.6.4.
- Remote branch: `feat/zcode-safe-setup` exists at the time of cloning.
- No previous `ZCode-Sandbox` user, Program Files copy, state directory, or
  sandbox shortcut existed before installation.
- VM snapshot: **not taken**, by operator choice.

## Step 1: Read-only assessment — PASS

`Assess-ZcodeSafety.ps1` made no changes and reported:

- ZCode location: user-profile path; a Program Files copy is required.
- Cage state: `NOT INSTALLED`.
- Existing credential surface: `.zcode\v2\credentials.json` and `.ssh` exist;
  contents were not inspected.
- Execution control: `ENFORCED`; a copied `where.exe` in a user-writable path
  did not execute. This VM therefore has the same path-based execution
  constraint documented in `PROBE-REPORT.md`.
- `git` and `pwsh`: available.
- Honest limits: network egress, secrets created after installation, and the
  sandbox user's own credentials remain **NOT CONTROLLED**.

## Step 2: PlanOnly preview — PASS

Command shape:

```powershell
Install-ZcodeSafety.ps1 `
  -WorkspacePath C:\ZCode-E2E\demo-workspace `
  -InstallCheckpoints `
  -PlanOnly
```

The plan showed the exact targets before any change:

- Account: `ZCode-Sandbox`, standard local user with a random password.
- Install copy: `C:\Program Files\ZCodeSandbox`, recursive RX grant.
- Authorized root: `C:\ZCode-E2E\demo-workspace`, recursive Modify grant.
- Secret deny ACE: `C:\ZCode-E2E\demo-workspace\.env` (one synthetic file).
- Canary: `C:\Users\qiu\.zcode\safe-setup\outside-workspace-canary.txt`.
- Launcher and shortcut paths.
- Checkpoint bridge and pinned Git SHA-256.
- State path and rollback command.
- Network and other NOT CONTROLLED disclosures.

The plan ended with `No changes made (PlanOnly).`

## Step 3: Formal installation — PASS

The installer was run with:

```powershell
Install-ZcodeSafety.ps1 `
  -WorkspacePath C:\ZCode-E2E\demo-workspace `
  -InstallCheckpoints `
  -AcknowledgeAdminSetup -ConfirmApply -NonInteractive
```

The installer returned `INSTALLED_ACTIVATION_REQUIRED`. Independent checks
confirmed:

- `ZCode-Sandbox` exists, is enabled, and is not in the Administrators group.
- `C:\Program Files\ZCodeSandbox\ZCode.exe` exists; copied tree was about 619 MB.
- `install-state.json` exists with the expected recorded targets.
- `ZCode (Sandboxed).lnk` exists in the user's Start Menu Programs folder.
- Workspace root has `ZCode-Sandbox:(OI)(CI)(M)`.
- `.env` has an explicit `ZCode-Sandbox:(DENY)(R)` ACE above its inherited Modify
  grant.
- Program Files copy has `ZCode-Sandbox:(OI)(CI)(RX)`.
- Checkpoint bridge, launcher, DPAPI credential blob, and workspace registry exist.

## Step 4: Structural and live verification — PASS

The first run exposed a verifier bug; after the fix, the formal run returned:

```text
Result: PASS (fail=0 partial=0 notControlled=4)
```

All structural checks and all live probes passed:

| Control | Result |
|---|---|
| Sandbox account is a standard user | PASS |
| ZCode copy is admin-controlled and RX-readable | PASS |
| Authorized workspace Modify grant | PASS |
| Recorded secret deny ACE | PASS |
| Launcher, `Common.ps1`, and shortcut | PASS |
| Checkpoint bridge and registry | PASS |
| Sandbox token is not administrator | PASS (`isAdmin=False`) |
| Main-profile canary cannot be read | PASS / DENIED |
| Main user profile cannot be listed | PASS / DENIED |
| Cage state cannot be read | PASS / DENIED |
| Install directory cannot be written | PASS / DENIED |
| Authorized workspace can be written | PASS / ALLOWED |
| `C:\Windows` cannot be written | PASS / DENIED |
| Deny-ACE `.env` cannot be read | PASS / DENIED |
| Network egress | NOT CONTROLLED (expected) |
| Secrets created after install | NOT CONTROLLED (expected) |
| Sandbox user's own ZCode credentials | NOT CONTROLLED (expected) |
| Main-user ZCode sessions | NOT CONTROLLED (expected) |

The verifier left `zss-writetest.txt` in the authorized workspace as an
intentional probe artifact. It was not removed before the checkpoint test so the
checkpoint behavior included a real untracked file.

## Step 5: GUI activation and boundary test — PASS

The initial shortcut click exposed a missing launcher dependency (see bugs
below). After copying the fixed `Common.ps1` into the live state, the launcher
started the Program Files copy successfully. Process inspection confirmed the
sandbox ZCode process tree was owned by `telecaster\ZCode-Sandbox` and executed
from `C:\Program Files\ZCodeSandbox\ZCode.exe`; the main user's existing ZCode
processes remained separate.

Inside the sandbox ZCode window, the operator logged in once and ran the four
requested checks in a new session while the client was set to **Full Access**:

| Check | Result |
|---|---|
| `whoami` | PASS — `ZCode-Sandbox` |
| Read `C:\Users\qiu\.zcode\v2\credentials.json` | PASS boundary — denied |
| Create `gui-write-test.txt` in authorized workspace | PASS — created |
| Create `gui-write-test.txt` in `C:\Windows` | PASS boundary — denied |

This is strong evidence that the OS boundary remains effective even when the
ZCode approval mode is Full Access. The approval setting is not the boundary.

**Screenshot placeholder:** shortcut failure before the `Common.ps1` fix (the
operator-provided screenshot shows the exact `CommandNotFoundException` at
`Start-ZcodeSandboxed.ps1:22`).  
**Screenshot placeholder:** successful sandbox ZCode window and the four GUI
results.

## Step 6: Git checkpoint — PASS

The installed bridge was exercised through PowerShell 7. The first execution
exposed a pwsh 7.6 compatibility bug; after the fix, Save returned:

```text
Status: SAVED
Ref: refs/zcode-safe/checkpoints/20260816T065308857Z-12b7abf8
Commit: 12b7abf83052b0304082f1296e685234c931e4a2
BranchAndIndexChanged: False
```

Evidence:

- `git for-each-ref refs/zcode-safe/checkpoints/` listed the new ref.
- Branch remained `main`.
- `HEAD` remained `135283c`.
- Real index tree remained `ecad1e5dc9ae5dd80fae48301b29998855420f11`.
- The checkpoint commit contained the modified README and ordinary untracked
  files without changing the real index or branch.
- `List` returned the saved ref.
- A synthetic untracked `.env.local` was refused with exit code 1 and an
  explicit sensitive-file message.

Operational note: this checkpoint test was run while waiting for the GUI step,
so it occurred before the GUI step rather than after it. It used the same
installed state and did not alter the GUI or rollback results. This ordering
deviation is recorded rather than hidden.

## Step 7: Rollback rehearsal — PASS

`Rollback-ZcodeSafety.ps1 -Confirm -NonInteractive` first printed the exact
recorded targets, then completed:

```text
Rollback completed: account 'ZCode-Sandbox', install copy, ACEs, shortcut, and state removed.
```

Post-rollback checks:

| Target | Result |
|---|---|
| `ZCode-Sandbox` local user | Absent |
| `C:\Users\ZCode-Sandbox` profile | Removed by rollback |
| `C:\Program Files\ZCodeSandbox` | Absent |
| `C:\Users\qiu\.zcode\safe-setup` | Absent |
| DPAPI credential blob | Absent |
| Start Menu shortcut | Absent |
| Sandbox ZCode processes | 0 |
| Sandbox ACE on workspace root | Absent |
| Sandbox deny ACE on `.env` | Absent |

The workspace itself was not removed or reset:

- Branch remained `main`.
- `HEAD` remained `135283c`.
- Index tree remained `ecad1e5dc9ae5dd80fae48301b29998855420f11`.
- `README.md` modification, `gui-write-test.txt`, `untracked-ordinary.txt`,
  and `zss-writetest.txt` remained present.
- A post-rollback assessment reported `CageState: NOT INSTALLED`.

## Bugs found and fixed by real execution

All four were small, localized fixes and were re-tested after each change.
They are committed on this branch:

1. **Single-secret StrictMode crash** (`Test-ZcodeSafety.ps1`). With one
   `SecretFilesDenied` entry, `ConvertFrom-Json` returns a scalar and direct
   `.Count` fails under Windows PowerShell 5.1 StrictMode. Fixed by wrapping
   the value in `@()`.
2. **Probe placeholder collision** (`Test-ZcodeSafety.ps1`). Case-insensitive
   `-replace` changed placeholders inside lowercase probe names such as
   `read-canary` and `read-installdir-write`, yielding silent PARTIAL results.
   Fixed with ordinal `.Replace()` calls. The repaired live probes all passed.
3. **pwsh 7.6 checkpoint crash** (`New-ZcodeCheckpoint.ps1`). Piping native Git
   output through `Select-Object -First 1` left `$LASTEXITCODE` unset under
   StrictMode. Fixed by capturing native output fully before checking the exit
   code. Save/List and sensitive refusal passed on pwsh 7.6.4.
4. **Launcher missing `Common.ps1`** (`Install-ZcodeSafety.ps1`). The installer
   copied `Start-ZcodeSandboxed.ps1` but not the `Common.ps1` it dot-sources.
   The shortcut therefore failed before launching ZCode. Fixed by copying the
   dependency into `bin\`; Test now requires both files. The repaired launcher
   started a real Program Files ZCode process as the sandbox user.

Commits:

- `616f534` — verifier fixes.
- `c6d340c` — checkpoint pwsh 7.6 fix.
- `130c22b` — installer launcher dependency fix.

The repository's `tests/Run-Tests.ps1` was run after all fixes on pwsh 7.6.4;
all 15 checks passed.

## Final assessment

| Area | Result |
|---|---|
| Reads outside the cage | PASS for the tested main profile, credentials, and cage state |
| Writes outside authorized roots | PASS for Program Files, `C:\Windows`, and the live GUI test |
| Authorized workspace writes | PASS |
| Existing workspace secret files | PASS; deny ACE enforced for `.env` |
| Program Files install-copy integrity | PASS |
| Cage-state self-protection | PASS |
| Git checkpoint recovery readiness | PASS |
| GUI activation and sandbox identity | PASS |
| Exact installation rollback | PASS; zero cage residue |
| Network egress | NOT CONTROLLED |
| Secrets created after installation | NOT CONTROLLED |
| Sandbox user's own credentials | NOT CONTROLLED (main user is trusted root) |

The OS cage is not an absolute-safety claim. Network traffic remains
unfiltered, and deny ACEs are an install-time snapshot of matching files. Keep
real secrets out of authorized roots and treat the main user as the trusted
root.
