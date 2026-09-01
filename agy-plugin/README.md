# Antigravity Safe Setup (`agy-safe-setup`)

[English](README.md) · [中文说明](README.zh-CN.md) · [威胁模型](skills/secure-agy-setup/references/threat-model.md) · [恢复指南](skills/secure-agy-setup/references/recovery.md)

**Approval is not a security boundary. What needs strict containment is what Antigravity can read, change, and send.**

`agy-safe-setup` is a least-privilege, bounded-autonomy, and recoverable safety plugin for Google Antigravity (AGY) spanning CLI (`agy`), Antigravity IDE, and Antigravity 2.0 Desktop.

## Core Capabilities

1. **Deterministic Lifecycle Hooks (`hooks.json`)**:
   - `PreToolUse` hook blocks `view_file` / `write_to_file` / `replace_file_content` from reading `.env`, private keys (`id_rsa`, `*.pem`), and cloud tokens even within the project.
   - Blocks opaque encoded commands (`powershell -EncodedCommand`) and commands targeting credential directories.
2. **Locked Capability Settings**:
   - `Non-Workspace File Access: deny` (Blocks tool access outside project root).
   - `Terminal Sandbox: true` (Runs commands in sandbox containers).
   - `Tool Execution Policy: proceed-in-sandbox` (Bounded Autonomy: works freely inside boundary; out-of-boundary actions fail without constant prompt fatigue).
3. **Safe Git Checkpoint Bridge (`New-AgyCheckpoint`)**:
   - Creates snapshots into hidden refs (`refs/agy-safe/checkpoints/*`) using an independent Git index.
   - Never changes your branch, index, or working tree. Refuses untracked secrets.
4. **Deterministic Staged Flow**:
   - Read-only Assessment $\to$ Risk Disclosure $\to$ Prerequisite Consent $\to$ Plan-Only Preview $\to$ Atomic Apply $\to$ Verification $\to$ Rollback Backup.

## Installation

Add this plugin to your Antigravity workspace or global configuration:

```powershell
# In your project root or global plugin folder (~/.gemini/config/plugins/agy-safe-setup)
```

In your Antigravity conversation, run:
```text
Use $secure-agy-setup to audit my current Antigravity permissions and install the recommended profile.
```
