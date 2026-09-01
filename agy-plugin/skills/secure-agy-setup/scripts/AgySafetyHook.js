#!/usr/bin/env node
/**
 * Antigravity Safe Setup — Lifecycle Hook Guard (PreToolUse)
 * Intercepts tool calls and deterministically blocks unauthorized access or credential leaks.
 */

const fs = require('fs');
const path = require('path');

function isSensitiveFileName(filePath) {
  if (!filePath || typeof filePath !== 'string') return false;
  const normalized = filePath.replace(/\\/g, '/').toLowerCase();
  const baseName = path.basename(normalized);

  const exactSensitive = [
    '.env', '.npmrc', '.pypirc', '.netrc', 'nuget.config',
    'credentials.json', 'service-account.json',
    'id_rsa', 'id_ed25519', 'id_ecdsa', 'id_dsa'
  ];
  if (exactSensitive.includes(baseName)) return true;
  if (baseName.startsWith('.env.') || baseName.startsWith('.env_')) return true;
  if (baseName.endsWith('.pem') || baseName.endsWith('.key') || baseName.endsWith('.pfx') || baseName.endsWith('.p12')) return true;

  const sensitiveDirs = ['/.ssh/', '/.aws/', '/.azure/', '/.config/gcloud/'];
  for (const dir of sensitiveDirs) {
    if (normalized.includes(dir)) return true;
  }
  return false;
}

function isPathInsideAny(targetPath, allowedRoots) {
  if (!targetPath || !allowedRoots || allowedRoots.length === 0) return false;
  const resolvedTarget = path.resolve(targetPath).toLowerCase();
  for (const root of allowedRoots) {
    if (!root) continue;
    const resolvedRoot = path.resolve(root).toLowerCase();
    if (resolvedTarget === resolvedRoot || resolvedTarget.startsWith(resolvedRoot + path.sep) || resolvedTarget.startsWith(resolvedRoot + '/')) {
      return true;
    }
  }
  return false;
}

function evaluateToolCall(payload) {
  const toolCall = payload.toolCall || {};
  const toolName = (toolCall.name || '').toLowerCase();
  const args = toolCall.args || {};
  const workspacePaths = payload.workspacePaths || [];
  const artifactDir = payload.artifactDirectoryPath ? [payload.artifactDirectoryPath] : [];
  const allowedReadRoots = [...workspacePaths, ...artifactDir];

  // 1. Filesystem Tools: view_file, write_to_file, replace_file_content, multi_replace_file_content
  const targetFilePath = args.AbsolutePath || args.TargetFile;
  if (targetFilePath) {
    if (isSensitiveFileName(targetFilePath)) {
      return {
        decision: 'deny',
        reason: `Blocked by agy-safe-setup: Access to sensitive credential file (${path.basename(targetFilePath)}) is prohibited.`
      };
    }

    const isWriteOperation = ['write_to_file', 'replace_file_content', 'multi_replace_file_content'].includes(toolName);
    if (isWriteOperation && workspacePaths.length > 0) {
      if (!isPathInsideAny(targetFilePath, allowedReadRoots)) {
        return {
          decision: 'deny',
          reason: `Blocked by agy-safe-setup: Out-of-workspace file modification is prohibited (${targetFilePath}).`
        };
      }
    }
  }

  // 2. Command Execution: run_command
  if (toolName === 'run_command') {
    const cmd = args.CommandLine || '';

    // Check for obfuscated encoded commands
    if (/\b(?:powershell|pwsh)\b.*-(?:e|enc|encodedcommand)\b/i.test(cmd)) {
      return {
        decision: 'deny',
        reason: 'Blocked by agy-safe-setup: Opaque encoded PowerShell commands (-EncodedCommand) are prohibited.'
      };
    }

    // Check for direct access to user credential directories
    if (/\.(?:ssh|aws|azure|config[\\/]gcloud)\b/i.test(cmd)) {
      return {
        decision: 'deny',
        reason: 'Blocked by agy-safe-setup: Commands targeting user credential directories are prohibited.'
      };
    }

    // Check for suspicious root-level deletions
    if (/\b(?:rm\s+-rf\s+\/|Remove-Item\s+-Path\s+["']?[a-zA-Z]:\\?["']?\s+-Recurse)/i.test(cmd)) {
      return {
        decision: 'deny',
        reason: 'Blocked by agy-safe-setup: Recursive deletion targeting filesystem root is prohibited.'
      };
    }
  }

  return { decision: 'allow' };
}

// Read payload from stdin
let inputData = '';
process.stdin.setEncoding('utf8');

process.stdin.on('data', (chunk) => {
  inputData += chunk;
});

process.stdin.on('end', () => {
  try {
    if (!inputData.trim()) {
      process.stdout.write(JSON.stringify({ decision: 'allow' }));
      return;
    }
    const payload = JSON.parse(inputData);
    const result = evaluateToolCall(payload);
    process.stdout.write(JSON.stringify(result));
  } catch (err) {
    // Fail-safe default
    process.stdout.write(JSON.stringify({ decision: 'allow', reason: 'Hook evaluation error: ' + err.message }));
  }
});
