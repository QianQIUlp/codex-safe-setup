// Generates the managed block for $DSH_HOME/cordis.patch.yml.
// dsh patch semantics: a layer entry addressed by id replaces that entry's
// entire config (docs/architecture). The home-level patch sits ABOVE shipped
// bundles, so locking `sandbox-policy` and `approval` here re-tightens the
// deployment default for every profile that does not override it further.
// The watcher hot-applies patch edits (watchUserPatches), so the lock takes
// effect without a restart; sessions already carrying a sandbox/mode event
// keep their explicit override.
//
// Managed content is wrapped in marker comments so re-runs replace only our
// block and rollback restores the pre-managed text byte-for-byte.

export const BEGIN = '# >>> managed by dsh-safe-setup >>>'
export const END = '# <<< managed by dsh-safe-setup <<<'

// Entry ids verified against packages/bundle/base/cordis.patch.yml.
export const SANDBOX_ENTRY_ID = 'sandbox-policy'
export const APPROVAL_ENTRY_ID = 'approval'

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function renderBody({ sandboxMode, approvalPolicy }) {
  return [
    `- id: ${SANDBOX_ENTRY_ID}`,
    '  config:',
    `    mode: ${sandboxMode}`,
    `- id: ${APPROVAL_ENTRY_ID}`,
    '  config:',
    `    policy: ${approvalPolicy}`,
  ].join('\n')
}

export function renderManagedBlock(choices) {
  return `${BEGIN}\n${renderBody(choices)}\n${END}`
}

// Replace an existing managed block, or append a fresh one. `text` is the
// current file content ('' when absent). Returns the new full file content.
export function applyManagedBlock(text, choices) {
  const block = renderManagedBlock(choices)
  if (text.includes(BEGIN) && text.includes(END)) {
    const pattern = new RegExp(`${escapeRegex(BEGIN)}[\\s\\S]*?${escapeRegex(END)}`)
    return text.replace(pattern, block)
  }
  const trimmed = text.replace(/\s*$/, '')
  return trimmed ? `${trimmed}\n${block}\n` : `${block}\n`
}

// True when the file carries a managed block whose choices equal `choices`.
export function managedBlockMatches(text, choices) {
  const match = text.match(new RegExp(`${escapeRegex(BEGIN)}\\n([\\s\\S]*?)\\n${escapeRegex(END)}`))
  if (!match) return false
  return match[1] === renderBody(choices)
}

// Remove the managed block entirely (rollback helper).
export function stripManagedBlock(text) {
  if (!(text.includes(BEGIN) && text.includes(END))) return text
  return text.replace(new RegExp(`${escapeRegex(BEGIN)}[\\s\\S]*?${escapeRegex(END)}\\n?`), '')
}
