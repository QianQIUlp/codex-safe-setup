# Configuration Profiles for Antigravity

## Approval & Execution Modes

All approval modes share the exact same least-privilege capability boundaries (denying filesystem root, restricting writes to registered workspaces, blocking secrets). The mode only changes how out-of-boundary requests or sensitive operations are handled:

| Approval Mode | Antigravity Setting Mapping | Behavior |
| :--- | :--- | :--- |
| **`BoundedAutonomy`** (Recommended) | `Tool Execution Policy: proceed-in-sandbox` | Agent works autonomously within the sandbox boundary. Out-of-boundary actions fail closed without annoying prompts. |
| **`AskMe`** | `Tool Execution Policy: request-review` | Eligible boundary-crossing actions prompt the user for individual confirmation. |
| **`Strict`** | `Tool Execution Policy: strict` | High friction; requires explicit user approval for virtually all side-effecting operations. |

## Network Egress Modes

Command networking is an independent boundary:

| Network Mode | Policy | Meaning |
| :--- | :--- | :--- |
| **`Off`** (Recommended) | `deny` | Terminal commands and web tools cannot access the public internet. |
| **`Allowlist`** | `allowlist` | Commands / browser tools may only access explicitly permitted domain names. |
| **`Unrestricted`** (High Risk) | `allow` | Commands may reach arbitrary public Internet endpoints. Requires explicit risk disclosure & acknowledgement. |

## Filesystem Boundaries

| Boundary | Setting | Meaning |
| :--- | :--- | :--- |
| **Non-Workspace File Access** | `deny` | Agent tools (`view_file`, `write_to_file`, etc.) are blocked from accessing paths outside registered workspace roots. |
| **Workspace Secret Protection** | Hook Enforced | `.env*`, `*.pem`, `id_rsa`, etc., are denied even if located inside the workspace. |
| **Terminal Sandbox** | `true` | Executes CLI commands in isolated sandbox container where available. |
