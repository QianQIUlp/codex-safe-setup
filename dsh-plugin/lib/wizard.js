// Wizard content and validation. The staged flow mirrors safercodex.qiu.works:
// assess → explain → choose (with full disclosure before any acknowledgement)
// → plan-only preview → explicit apply confirmation → verify → rollback record.

import {
  APPROVAL_MODES,
  NETWORK_MODES,
  UNRESTRICTED_DISCLOSURE,
  UNRESTRICTED_ACKNOWLEDGEMENT,
  DEFAULT_DENY_GLOBS,
} from './modes.js'

export const PHILOSOPHY = [
  '审批不是安全边界。命令复杂到无法逐条审读，审批疲劳后必然"扫一眼就过"；',
  '还有"每一行都合理、组合起来是灾难"的语义事故。所以这里的关键不是审查，',
  '而是把范围卡死：越界动作直接失败，审批只是边界内的工作流选择。',
].join('\n')

export const NOT_CONTROLLED_DISCLOSURE = [
  'dsh 的权限档位只管"文件写效果"。以下面在任何档位都不受控，本插件只覆盖标注的部分：',
  '- 网络出站：dsh 无网络沙箱；本插件拦截 web_fetch 工具（覆盖），bash 发起的联网不覆盖（NOT CONTROLLED）。',
  '- 文件读取：任何档位都允许全盘读；本插件在文件工具层拒绝敏感路径（PARTIAL，bash cat 可绕过）。',
  '- 第三方插件：在宿主进程内运行，无隔离，任何插件（包括本插件）都管不住其他插件（NOT CONTROLLED）。',
  '- MCP 子进程：以宿主完整权限运行（NOT CONTROLLED）。',
  '- 危险命令内容（如 curl | sh）：dsh 无静态识别（NOT CONTROLLED）。',
].join('\n')

export function validateChoices(choices) {
  const errors = []
  const network = NETWORK_MODES[choices.network]
  const approval = APPROVAL_MODES[choices.approval]
  if (!network) errors.push(`未知联网模式：${choices.network}`)
  if (!approval) errors.push(`未知审批模式：${choices.approval}`)
  if (network && network.key === 'allowlist') {
    const domains = (choices.allowlist || []).filter((d) => typeof d === 'string' && d.trim())
    if (domains.length === 0) errors.push('Allowlist 模式需要至少一个域名。')
    for (const domain of domains) {
      if (!/^[a-z0-9*.-]+\.[a-z]{2,}$/i.test(domain.trim())) {
        errors.push(`域名格式可疑：${domain}`)
      }
    }
  }
  if (network && network.requiresAcknowledgement) {
    if (choices.unrestrictedAcknowledgement !== UNRESTRICTED_ACKNOWLEDGEMENT) {
      errors.push('不限联网需要先阅读完整披露，并逐字确认："我理解并接受不限联网的风险"。')
    }
  }
  return { ok: errors.length === 0, errors }
}

// The plan-only preview: exactly what will be written, nothing applied yet.
export function buildPlan(choices) {
  const network = NETWORK_MODES[choices.network]
  const approval = APPROVAL_MODES[choices.approval]
  const lines = [
    '计划（未写入任何内容）：',
    `1. $DSH_HOME/cordis.patch.yml 托管块：sandbox-policy mode=${approval.dshSandboxMode}；approval policy=${approval.dshApprovalPolicy}（对 ${approval.label}）。`,
    `2. 本插件守卫：web_fetch=${network.key}${network.key === 'allowlist' ? `（白名单：${choices.allowlist.join(', ')}）` : ''}。`,
    `3. 文件工具受保护路径（默认）：${DEFAULT_DENY_GLOBS.length} 条凭据形状的 glob。`,
    '4. 写入前备份原文件；托管块有标记，可整体移除（回滚）。',
    `审批模式说明：${approval.summary}`,
  ]
  return lines.join('\n')
}
