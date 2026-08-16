---
description: Audit ZCode exposure and install or roll back the OS-level sandbox boundary (Windows cage).
argument-hint: "[assess|plan|apply|verify|rollback]"
skills: secure-zcode-setup
---

Run the `secure-zcode-setup` skill workflow for this request:

$ARGUMENTS

Follow the staged flow in the skill exactly: read-only assessment first, explain the
boundary model and the NOT CONTROLLED surface, obtain separate consents, preview with
`-PlanOnly`, apply only after explicit confirmation, verify, and hand off activation
(launch ZCode through the sandbox shortcut, log in once, start a new session inside the
sandboxed instance).
