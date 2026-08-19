# Antigravity Safety Contract

## Mandatory Contract for Safety Operations

1. **Non-destructive Audit**:
   - The assessment phase must be purely read-only.
   - Never read, display, or transmit secret contents during audit. Inspect only path existence, tool versions, and configuration keys.
2. **Explicit Consent & Tradeoff Disclosure**:
   - Explain boundaries and tradeoffs clearly before requesting user consent.
   - If unrestricted network egress is requested, provide full risk disclosures regarding prompt injection, data exfiltration, and supply chain contamination. Require explicit risk acknowledgement.
3. **Atomic Backup & Verification**:
   - Every file modified or replaced must be backed up before write.
   - Configuration writes must be atomic.
   - An exact rollback recipe must be saved and verified.
4. **Honest Reporting**:
   - Report `PASS`, `PARTIAL`, `FAIL`, or `NOT CONTROLLED`.
   - External tool surfaces (Web Search, Browser, Computer Use, Third-party MCPs, host OS compromise) must be reported as `NOT CONTROLLED`, never assumed secure.
5. **Safe Checkpoints**:
   - Checkpoints must commit to isolated hidden refs (`refs/agy-safe/checkpoints/*`).
   - Never alter the user's active branch, HEAD, index, or working tree.
   - Refuse untracked secrets from entering checkpoints.
