// dsh-safe-setup — interactive safe-configuration wizard for DeepSeek Harness.
// Locks the model axis: sandbox tier + approval policy via a marked managed
// block in $DSH_HOME/cordis.patch.yml (hot-applied by the patch watcher), plus
// tool-layer guards (web_fetch allowlist, credential-path denial).
// Staged flow per safercodex.qiu.works: assess → explain → disclose → plan →
// confirm → write → verify → rollback record. Guards stay INERT until the
// wizard has run once.

import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'
import {
  APPROVAL_MODES,
  NETWORK_MODES,
  UNRESTRICTED_DISCLOSURE,
  UNRESTRICTED_ACKNOWLEDGEMENT,
  DEFAULT_DENY_GLOBS,
} from './lib/modes.js'
import { checkWebFetch, checkFsRead } from './lib/guards.js'
import { applyManagedBlock, managedBlockMatches } from './lib/patch.js'
import { PHILOSOPHY, NOT_CONTROLLED_DISCLOSURE, validateChoices, buildPlan } from './lib/wizard.js'

export const name = 'dsh-safe-setup'

const HOME_PATCH = 'cordis.patch.yml'
const STATE_FILE = '.safe-setup-state.json'
const BACKUP_FILE = 'cordis.patch.yml.safe-setup-backup'
const FS_TOOLS = new Set(['read', 'read_image', 'write', 'edit', 'glob', 'grep'])

function dshHome() {
  return process.env.DSH_HOME || path.join(os.homedir(), '.dsh')
}

function readText(file) {
  try { return fs.readFileSync(file, 'utf8') } catch { return null }
}

function writeText(file, text) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, text)
}

function loadState(home) {
  try { return JSON.parse(fs.readFileSync(path.join(home, STATE_FILE), 'utf8')) } catch { return null }
}

let active = null

async function ask(ctx, invocation, questions) {
  if (!ctx.userQuestions) {
    throw new Error('此环境没有问答界面（userQuestions 无 provider）。请在 dsh Web UI 中运行本命令。')
  }
  const { answers } = await ctx.userQuestions.ask({
    questions,
    agent: invocation.agent,
    signal: invocation.signal,
  })
  return answers || []
}

function firstSelection(answer) {
  const selected = answer?.selected?.[0]
  if (selected) return { kind: 'option', value: selected }
  const custom = answer?.custom
  if (custom && String(custom).trim()) return { kind: 'text', value: String(custom).trim() }
  return { kind: 'none', value: null }
}

function parseDomains(text) {
  return String(text || '')
    .split(/[,，\s]+/)
    .map((d) => d.trim().toLowerCase())
    .filter(Boolean)
}

async function runWizard(ctx, invocation) {
  const home = dshHome()
  const patchPath = path.join(home, HOME_PATCH)
  const backupPath = path.join(home, BACKUP_FILE)
  const currentPatch = readText(patchPath) ?? ''

  const begin = firstSelection(
    (await ask(ctx, invocation, [{
      id: 'begin',
      question: '开始安全配置？先看两段说明。',
      header: '安全配置',
      detail: `${PHILOSOPHY}\n\n${NOT_CONTROLLED_DISCLOSURE}`,
      options: [
        { label: '开始配置', description: '只读评估并进入选择，随时可取消，不会写入任何内容' },
        { label: '取消' },
      ],
    }]))[0]
  )
  if (begin.value !== '开始配置') return { kind: 'success', text: '已取消，未做任何更改。' }

  const currentManaged = currentPatch.includes('# >>> managed by dsh-safe-setup >>>')
  const networkAnswer = firstSelection(
    (await ask(ctx, invocation, [{
      id: 'network',
      question: 'web_fetch 联网模式？',
      header: '联网',
      detail: `当前托管块：${currentManaged ? '已存在（本次为更新）' : '不存在（首次配置）'}。\n${NETWORK_MODES.off.summary}`,
      options: Object.values(NETWORK_MODES).map((mode) => ({
        label: mode.label,
        description: mode.summary,
      })),
    }]))[0]
  )
  const networkKeyByLabel = Object.values(NETWORK_MODES).find((m) => m.label === networkAnswer.value)?.key
  const networkMode = NETWORK_MODES[networkKeyByLabel]
  if (!networkMode) return { kind: 'error', text: `无法识别的联网选择：${networkAnswer.value ?? '<未作答>'}` }

  const choices = { network: networkMode.key, allowlist: [], unrestrictedAcknowledgement: null }

  if (networkMode.key === 'allowlist') {
    const domainsAnswer = firstSelection(
      (await ask(ctx, invocation, [{
        id: 'domains',
        question: '允许哪些域名？用逗号或空格分隔（例如 api.deepseek.com docs.example.com）',
        header: '白名单',
      }]))[0]
    )
    choices.allowlist = parseDomains(domainsAnswer.value)
  } else if (networkMode.requiresAcknowledgement) {
    const ackAnswer = firstSelection(
      (await ask(ctx, invocation, [{
        id: 'ack',
        question: `不限联网需要逐字确认。请输入："${UNRESTRICTED_ACKNOWLEDGEMENT}"`,
        header: '高风险确认',
        detail: UNRESTRICTED_DISCLOSURE.join('\n'),
      }]))[0]
    )
    choices.unrestrictedAcknowledgement = ackAnswer.value
  }

  const approvalAnswer = firstSelection(
    (await ask(ctx, invocation, [{
      id: 'approval',
      question: '审批模式？（两种模式共享同一最小权限文件档位 workspace-write）',
      header: '审批',
      detail: 'dsh 的审批只覆盖"沙箱拒绝后的升级重试"，且授权严格单次、无 always-allow。',
      options: Object.values(APPROVAL_MODES).map((mode) => ({
        label: mode.label,
        description: mode.summary,
      })),
    }]))[0]
  )
  const approval = Object.values(APPROVAL_MODES).find((m) => m.label === approvalAnswer.value)
  if (!approval) return { kind: 'error', text: `无法识别的审批选择：${approvalAnswer.value ?? '<未作答>'}` }
  choices.approval = approval.key

  const validation = validateChoices(choices)
  if (!validation.ok) {
    return { kind: 'error', text: `选择未通过校验，未写入任何内容：\n- ${validation.errors.join('\n- ')}` }
  }

  const plan = buildPlan(choices)
  const confirmed = firstSelection(
    (await ask(ctx, invocation, [{
      id: 'apply',
      question: '按以上计划写入？',
      header: '确认写入',
      detail: plan,
      options: [
        { label: '确认写入', description: '先备份原文件，再写入托管块与守卫状态' },
        { label: '取消' },
      ],
    }]))[0]
  )
  if (confirmed.value !== '确认写入') return { kind: 'success', text: '已取消，未做任何更改。' }

  // Apply: first-write backup, managed block, guard state.
  if (!fs.existsSync(backupPath)) writeText(backupPath, currentPatch)
  writeText(patchPath, applyManagedBlock(readText(patchPath) ?? '', {
    sandboxMode: approval.dshSandboxMode,
    approvalPolicy: approval.dshApprovalPolicy,
  }))
  const state = {
    appliedAt: new Date().toISOString(),
    networkMode: { key: choices.network, allowlist: choices.allowlist },
    denyGlobs: DEFAULT_DENY_GLOBS,
  }
  writeText(path.join(home, STATE_FILE), JSON.stringify(state, null, 2) + '\n')
  active = state

  // Verify (安装 ≠ 验证): file round-trip, state round-trip, guard probes.
  const checks = []
  const reread = readText(patchPath) ?? ''
  checks.push(['托管块与所选档位一致',
    managedBlockMatches(reread, { sandboxMode: approval.dshSandboxMode, approvalPolicy: approval.dshApprovalPolicy })])
  checks.push(['守卫状态可回读', loadState(home)?.networkMode?.key === choices.network])
  const webProbe = checkWebFetch('https://boundary-probe.invalid/x', state.networkMode)
  checks.push(['web_fetch 边界探测被拒', !webProbe.allowed])
  const fsProbe = checkFsRead(path.join(home, '.credentials.yaml'), state.denyGlobs)
  checks.push(['凭据路径探测被拒', !fsProbe.allowed])
  const failed = checks.filter(([, ok]) => !ok)
  const verdict = failed.length === 0 ? 'PASS（文件/状态/守卫逻辑）' : `FAIL：${failed.map(([n]) => n).join('；')}`

  return {
    kind: 'success',
    text: [
      '写入完成。',
      `验证：${verdict}。守卫在工具流水线的接线需一次真实模型轮次验证，标注为 PARTIAL。`,
      '新会话起生效；当前会话可用 /permission 立即切换档位。',
      `回滚：运行 /safe-setup-rollback（首次写入前的原文件已备份于 ${BACKUP_FILE}）。`,
    ].join('\n'),
  }
}

async function runRollback(ctx, invocation) {
  const home = dshHome()
  const patchPath = path.join(home, HOME_PATCH)
  const backupPath = path.join(home, BACKUP_FILE)
  const backup = readText(backupPath)
  if (backup === null) {
    return { kind: 'error', text: `未找到备份文件（${BACKUP_FILE}）。没有可回滚的安装记录。` }
  }
  const confirmed = firstSelection(
    (await ask(ctx, invocation, [{
      id: 'rollback',
      question: '恢复首次写入前的原文件并停用守卫？',
      header: '回滚',
      detail: `备份内容（${backup.length} 字符）：\n${backup.slice(0, 400)}${backup.length > 400 ? '\n…' : ''}`,
      options: [
        { label: '确认回滚' },
        { label: '取消' },
      ],
    }]))[0]
  )
  if (confirmed.value !== '确认回滚') return { kind: 'success', text: '已取消，未做任何更改。' }
  writeText(patchPath, backup)
  try { fs.rmSync(path.join(home, STATE_FILE)) } catch { /* absent is fine */ }
  active = null
  return {
    kind: 'success',
    text: `已恢复 ${HOME_PATCH} 并停用守卫。备份文件保留在 ${BACKUP_FILE}，可手动删除。`,
  }
}

export function apply(ctx) {
  active = loadState(dshHome())
  if (active && !Array.isArray(active.denyGlobs)) active = null

  ctx.inject(['commands'], (ctxWithCommands) => {
    ctxWithCommands.commands.register({
      name: 'safe-setup',
      description: '交互式安全配置向导（只读评估→披露→计划→确认写入→验证）',
      handler: (invocation) => runWizard(ctxWithCommands, invocation),
    })
    ctxWithCommands.commands.register({
      name: 'safe-setup-rollback',
      description: '回滚 safe-setup 的写入并停用守卫（展示备份后按确认恢复）',
      handler: (invocation) => runRollback(ctxWithCommands, invocation),
    })
  })

  ctx.on('tools/pre-execute', async (exec, next) => {
    if (active) {
      const args = (exec.arguments && typeof exec.arguments === 'object') ? exec.arguments : {}
      if (exec.name === 'web_fetch' && typeof args.url === 'string') {
        const verdict = checkWebFetch(args.url, active.networkMode)
        if (!verdict.allowed) return { kind: 'deny', reason: verdict.reason }
      }
      if (FS_TOOLS.has(exec.name)) {
        const target = args.file_path ?? args.path
        if (typeof target === 'string') {
          const verdict = checkFsRead(target, active.denyGlobs)
          if (!verdict.allowed) return { kind: 'deny', reason: verdict.reason }
        }
      }
    }
    return next()
  })
}
