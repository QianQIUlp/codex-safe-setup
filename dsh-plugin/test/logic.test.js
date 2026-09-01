import test from 'node:test'
import assert from 'node:assert/strict'

import { checkWebFetch, checkFsRead, globToRegex } from '../lib/guards.js'
import { applyManagedBlock, managedBlockMatches, stripManagedBlock } from '../lib/patch.js'
import { validateChoices, buildPlan } from '../lib/wizard.js'
import { APPROVAL_MODES, NETWORK_MODES } from '../lib/modes.js'

test('web_fetch guard: off blocks everything with a reason', () => {
  const verdict = checkWebFetch('https://example.com/x', NETWORK_MODES.off)
  assert.equal(verdict.allowed, false)
  assert.match(verdict.reason, /联网已关闭/)
})

test('web_fetch guard: allowlist matches host and subdomain, rejects others', () => {
  const mode = { key: 'allowlist', allowlist: ['Example.com', 'api.deepseek.com'] }
  assert.equal(checkWebFetch('https://example.com/a', mode).allowed, true)
  assert.equal(checkWebFetch('https://cdn.example.com/a', mode).allowed, true)
  assert.equal(checkWebFetch('https://api.deepseek.com/v1', mode).allowed, true)
  const denied = checkWebFetch('https://evil.com/a', mode)
  assert.equal(denied.allowed, false)
  assert.match(denied.reason, /不在联网白名单/)
  // Subdomain matching must not be a suffix trick: notevil-example.com must fail.
  assert.equal(checkWebFetch('https://notevil-example.com/a', mode).allowed, false)
})

test('web_fetch guard: unrestricted passes, unparseable URL fails closed', () => {
  assert.equal(checkWebFetch('https://x.example', NETWORK_MODES.unrestricted).allowed, true)
  assert.equal(checkWebFetch('not a url', NETWORK_MODES.off).allowed, false)
})

test('fs guard: deny globs match credentials across separators and case', () => {
  const globs = ['**/.env', '**/*.pem', '**/.dsh/.credentials.yaml']
  assert.equal(checkFsRead('C:\\Users\\q\\project\\.ENV', globs).allowed, false)
  assert.equal(checkFsRead('/home/u/.dsh/.credentials.yaml', globs).allowed, false)
  assert.equal(checkFsRead('/home/u/keys/server.pem', globs).allowed, false)
  assert.equal(checkFsRead('/home/u/project/src/main.ts', globs).allowed, true)
  assert.match(checkFsRead('/home/u/.dsh/.credentials.yaml', globs).reason, /不覆盖 bash/)
})

test('fs guard: dotfile inside a nested directory still matches **/ pattern', () => {
  assert.equal(globToRegex('**/.env').test('a/b/c/.env'), true)
  assert.equal(globToRegex('**/.env').test('a/b/c/env'), false)
})

test('patch: managed block applies, is idempotent, matches choices, and strips cleanly', () => {
  const choices = { sandboxMode: 'workspace-write', approvalPolicy: 'never' }
  const first = applyManagedBlock('existing: content\n', choices)
  assert.match(first, /existing: content/)
  assert.match(first, /id: sandbox-policy/)
  assert.match(first, /mode: workspace-write/)
  assert.match(first, /id: approval/)
  assert.match(first, /policy: never/)

  const rerun = applyManagedBlock(first, choices)
  assert.equal(rerun, first)
  assert.equal(managedBlockMatches(rerun, choices), true)

  const changed = applyManagedBlock(first, { sandboxMode: 'workspace-write', approvalPolicy: 'ask' })
  assert.equal(managedBlockMatches(changed, choices), false)
  assert.equal(managedBlockMatches(changed, { sandboxMode: 'workspace-write', approvalPolicy: 'ask' }), true)

  const stripped = stripManagedBlock(changed)
  assert.equal(stripped, 'existing: content\n')
})

test('patch: empty file gains a managed block', () => {
  const out = applyManagedBlock('', { sandboxMode: 'read-only', approvalPolicy: 'ask' })
  assert.ok(out.startsWith('# >>> managed by dsh-safe-setup >>>'))
  assert.ok(out.trimEnd().endsWith('# <<< managed by dsh-safe-setup <<<'))
})

test('wizard: allowlist requires domains; unrestricted requires exact acknowledgement', () => {
  assert.equal(validateChoices({ network: 'allowlist', approval: 'bounded', allowlist: [] }).ok, false)
  assert.equal(
    validateChoices({ network: 'allowlist', approval: 'bounded', allowlist: ['docs.example.com'] }).ok,
    true
  )
  const missing = validateChoices({ network: 'unrestricted', approval: 'bounded' })
  assert.equal(missing.ok, false)
  assert.match(missing.errors[0], /不限联网/)
  const acked = validateChoices({
    network: 'unrestricted',
    approval: 'bounded',
    unrestrictedAcknowledgement: '我理解并接受不限联网的风险',
  })
  assert.equal(acked.ok, true)
  assert.equal(validateChoices({ network: 'off', approval: 'ask' }).ok, true)
  assert.equal(validateChoices({ network: 'off', approval: 'nope' }).ok, false)
})

test('wizard: plan is preview-only text naming every managed target', () => {
  const plan = buildPlan({ network: 'allowlist', approval: 'bounded', allowlist: ['a.com'] })
  assert.match(plan, /计划（未写入任何内容）/)
  assert.match(plan, /sandbox-policy mode=workspace-write/)
  assert.match(plan, /approval policy=never/)
  assert.match(plan, /a\.com/)
  assert.match(plan, /备份/)
})

test('modes: every approval mode maps to real dsh policy values', () => {
  for (const mode of Object.values(APPROVAL_MODES)) {
    assert.ok(['ask', 'never'].includes(mode.dshApprovalPolicy))
    assert.ok(['read-only', 'workspace-write', 'danger-full-access'].includes(mode.dshSandboxMode))
  }
})
