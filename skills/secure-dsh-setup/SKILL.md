---
name: secure-dsh-setup
description: Assess the safety posture of a DeepSeek Harness (dsh) installation - permission tier and approval overrides in patch layers, plugin supply-chain exposure (floating git dependencies, allowed build scripts), plaintext credential exposure, and the surfaces no tier controls (network, reads, plugin code, MCP, command content). Use when a user runs dsh, asks whether dsh is safe, wants to check their dsh profiles or plugins, or was told to add a dsh plugin or cordis patch. Read-only assessment; never claim absolute safety.
---

# Secure dsh Setup (assessment prototype)

dsh's permission tiers (`read-only`, `workspace-write`, `danger-full-access`) govern **file-write effects only**. Network egress, file reads, plugin code, MCP processes, and command content are outside the tier vocabulary in every mode. Third-party plugins run inside the host process with no isolation, and a patch layer can replace the sandbox and approval entries wholesale.

## Safety contract

- This skill only reads configuration text and file existence. Never read credential file contents; report their presence only.
- Never claim the resulting setup is absolutely safe, and never present the permission tiers as a general security boundary.
- If a credential may already have been exposed, advise rotation and usage review; configuration checks cannot undo exposure.

## Workflow

### 1. Assess without changing state

Run:

```powershell
& <skill-dir>/scripts/Assess-DshSafety.ps1            # human-readable
& <skill-dir>/scripts/Assess-DshSafety.ps1 -AsJson    # machine-readable
```

Pass `-DshHome <path>` when `DSH_HOME` is non-default. The script locates `$DSH_HOME` (default `~/.dsh`), the home-level `cordis.patch.yml`, `.credentials.yaml`, and every profile under `profiles/` (manifest bundles, floating git dependencies, `allowBuilds`, profile patch).

### 2. Interpret findings

- **HIGH - patch replaces security entries / contains `!!js`**: an upper patch layer is overriding the shipped sandbox or approval behavior; `!!js` config values are JavaScript executed in the host process at load time. Ask the user where the patch came from before suggesting anything.
- **HIGH - floating git dependency**: `dsh plugin update` can pull and auto-activate new code (a package that newly declares `dsh.bundle` is appended to the load stack without approval). Recommend pinning a commit.
- **HIGH - `DSH_PERMISSION_MODE=danger-full-access`**: file-write sandbox removed and approval prompts disabled simultaneously.
- **MEDIUM - `allowBuilds` entries**: build scripts run at install time, outside any sandbox; only meaningful if the user remembers allowing them.
- **MEDIUM - credentials file present**: plaintext keys; readable by the agent in every tier, including `read-only`.

### 3. Advise within the actual boundary

When recommending changes, be explicit about what tiers do and do not control: choosing `workspace-write` bounds writes, but nothing in dsh bounds network egress, file reads, plugin behavior, or `curl | sh`. Advise that plugin trust decisions (source review + commit pinning) are the real control for the plugin axis. Full background with file-line evidence: `docs/dsh/audit.md` in the codex-safe-setup repository.

Do not modify or delete anything yourself in this prototype stage; report findings and recommendations only.
