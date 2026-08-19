// Mode vocabulary for the dsh safe-setup wizard.
// Philosophy (safercodex.qiu.works): approval is a workflow choice, never a
// security boundary. Every approval mode shares the same least-privilege
// filesystem tier; only the reviewer of a boundary crossing differs.

// dsh approval policy is 'ask' | 'never' (packages/interaction/user-approval).
// 'never' means escalations are auto-REJECTED (fail closed) — which is exactly
// BoundedAutonomy: out-of-bound actions fail instead of prompting.
// AutoReview has no dsh equivalent (no reviewer-agent channel for approvals),
// so it is not offered; the wizard explains why instead of silently mapping it.
export const APPROVAL_MODES = {
  bounded: {
    key: 'bounded',
    label: 'BoundedAutonomy（推荐）',
    dshApprovalPolicy: 'never',
    dshSandboxMode: 'workspace-write',
    summary: '无审批弹窗；越界动作直接失败，失败原因可见。',
  },
  ask: {
    key: 'ask',
    label: 'AskMe',
    dshApprovalPolicy: 'ask',
    dshSandboxMode: 'workspace-write',
    summary: '沙箱拒绝后的升级请求交给你逐次审批（严格单次授权，无 always-allow）。',
  },
}

// dsh has no network axis in its sandbox vocabulary, so the plugin enforces
// this at the web_fetch tool layer. Bash-initiated network is NOT covered —
// the wizard must disclose that as NOT CONTROLLED.
export const NETWORK_MODES = {
  off: {
    key: 'off',
    label: 'Off（推荐）',
    allowlist: [],
    summary: 'web_fetch 全部拒绝。命令行发起的联网不受此控制（dsh 无网络沙箱）。',
  },
  allowlist: {
    key: 'allowlist',
    label: 'Allowlist',
    allowlist: null, // filled with user-provided domains
    summary: '仅放行明确列出的域名。',
  },
  unrestricted: {
    key: 'unrestricted',
    label: 'Unrestricted',
    allowlist: null,
    requiresAcknowledgement: true,
    summary: 'web_fetch 不设限（需要完整披露与确认）。',
  },
}

// The unrestricted-network disclosure, verbatim in spirit from the website:
// explain everything BEFORE asking for acknowledgement; never reduce it to
// "high risk".
export const UNRESTRICTED_DISCLOSURE = [
  '1. 选择不限联网并不会扩大文件权限，也不会新增删除能力；工作区边界内可改的内容不变。',
  '2. 不限联网移除了目的地限制：命令或工具已能读到的任何数据（源码、配置、输出、隐私、未被 deny 规则覆盖的凭据）都可以被发送到任何公网目的地。',
  '3. 不可信的网页、issue、依赖文档可能携带提示注入；被操纵的 agent 可以外传数据或执行不安全的联网步骤。',
  '4. 联网可以下载恶意软件或有漏洞的依赖，也可能把授权受限的内容拉进工作区。',
  '5. 以上是可能的后果，不代表开启就必然泄露。日常建议 Allowlist；只有短期、可信、无法枚举目的地的任务才考虑不限联网。',
]

export const UNRESTRICTED_ACKNOWLEDGEMENT = '我理解并接受不限联网的风险'

// Credential-shaped read targets the fs-tool guard denies by default.
// Bash `cat` is NOT covered by this list (kernel enforces writes only) —
// disclosed as PARTIAL by the wizard.
export const DEFAULT_DENY_GLOBS = [
  '**/.env',
  '**/*.pem',
  '**/id_rsa',
  '**/id_ed25519',
  '**/.dsh/.credentials.yaml',
  '**/.aws/credentials',
  '**/.ssh/config',
]
