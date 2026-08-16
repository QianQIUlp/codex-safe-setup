# Security Contract (ZCode OS Cage)

## Product claim

This skill installs operating-system boundaries: a dedicated standard Windows user whose
NTFS ACLs decide what a ZCode session can read, write, and execute. It does not install
approval prompts, soft rules, or model-side promises. It never claims absolute safety.

## Hard rules

1. **Approval is not a boundary.** Neither the user nor a reviewer agent reliably stops
   every dangerous action. Boundaries must make dangerous actions fail mechanically.
2. **Model behavior is not a control.** Instruction files, prompts, and habits are not
   enforcement. Nothing in this skill relies on the model "behaving".
3. **No silent changes.** Every account, ACL, copy, and shortcut is previewed in a plan,
   consented to explicitly, recorded in install-state.json, and reversible.
4. **Secrets are never read.** Assessment and verification check existence and ACLs only.
   Values are never displayed, logged, or transmitted.
5. **Honest vocabulary only.** Report `PASS` (verified), `PARTIAL` (evidence incomplete),
   `FAIL` (a required boundary is broken), or `NOT CONTROLLED` (outside this design).
   Never upgrade a PARTIAL to a PASS. Never describe a NOT CONTROLLED surface as bounded.
6. **Credential incident rule.** If exposure may already have happened, say so plainly
   and recommend rotation, revocation, and usage review. Boundaries cannot undo exposure.
7. **The cage protects only itself and the main user's data.** The main user is the
   trusted root and can read the sandbox user's data, including the sandbox ZCode login.

## The NOT CONTROLLED surface (must be disclosed, never hidden)

- **Network egress.** No per-user firewalling for one executable path exists on Windows.
  Everything inside the cage can reach the public Internet: consequence ceiling is high
  for prompt injection and exfiltration mistakes.
- **Secrets created after install.** Deny ACEs cover files that existed at install time.
- **Execution inside granted roots.** Repo-local executables may be blocked or allowed
  depending on machine execution-control policy; the cage reports, not guesses.
- **Main-user sessions.** Only sessions launched through the sandbox shortcut are caged.
