# Antigravity Threat Model

## Security Objective
Antigravity Safe Setup limits the consequences of an unexpected, manipulated, or hallucinated agent action by enforcing capability limits on:
1. What local commands and tools can change.
2. What the agent can read and ingest into LLM context/logs.
3. Where command output or telemetry can be transmitted.

## Trust Boundaries & Controls

| Threat | Primary Control | Residual Risk |
| :--- | :--- | :--- |
| **Accidental file deletion / overwrite outside workspace** | `Non-Workspace File Access: deny` + Hook gate | External tools with root permissions or OS bypasses |
| **Accidental file deletion inside project** (`git clean -fdx`) | Git Checkpoints (`refs/agy-safe/checkpoints/*`) | Unsaved / ignored files outside checkpoint scope |
| **Credential exfiltration via file reading** | Hook-based block on `.env*`, `*.pem`, `id_rsa`, `credentials.json` | Non-standard credential filenames not covered in pattern list |
| **Exfiltration via network requests** | `Internet Access Policy: deny` / domain allowlist | Network destinations explicitly allowed in the allowlist |
| **Prompt injection from web content** | Network isolation / domain allowlist | Malicious prompt content present within allowed repositories or domains |
| **Obfuscated script execution** (`EncodedCommand`) | PreToolUse Hook inspection | Highly subtle or split-command obfuscation |

## Surfaces NOT Controlled
The installed plugin controls tool invocations and Antigravity core permissions. It does NOT control:
- External LLM training data or hosted API compromises.
- Third-party MCP servers running out-of-process with unrestricted system permissions.
- Pre-existing malware or compromised host OS binaries.
- Credentials already leaked prior to installation.

These surfaces are explicitly reported as `NOT CONTROLLED`.
