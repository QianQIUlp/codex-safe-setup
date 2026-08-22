import type { UiContent } from './types';

export const zhCN: UiContent = {
  lang: 'zh-CN',
  altLang: 'en',
  altLangLabel: 'EN',
  altLangHref: '/',
  path: '/zh-CN/',
  meta: {
    title: 'Codex Safe Setup — 在 Windows 上更安全地使用 Codex',
    description:
      '在 Windows 上安装最小权限、可恢复的 Codex 权限配置。限制 Codex 能读取、修改和发送的内容，验证配置，并在出错时恢复。',
    ogTitle: 'Codex Safe Setup — 在 Windows 上更安全地使用 Codex',
    ogDescription:
      '限制 Codex 能读取、修改和发送的内容，验证配置，并在出错时恢复。一个社区维护的 Windows Codex 插件。',
  },
  nav: {
    howItWorks: { label: '工作原理', href: '/zh-CN/#limits' },
    install: { label: '安装', href: '/zh-CN/#install' },
    threatModel: {
      label: '威胁模型',
      href: 'https://github.com/QianQIUlp/codex-safe-setup/blob/main/docs/threat-model.md',
      external: true,
    },
    github: {
      label: 'GitHub',
      href: 'https://github.com/QianQIUlp/codex-safe-setup',
      external: true,
    },
  },
  hero: {
    eyebrow: 'Codex 安全 · Windows',
    title: '在 Windows 上更安全地使用 Codex。',
    lead: '限制 Codex 能读取、修改和发送的内容，然后验证配置，并在出错时恢复。',
    primaryCta: { label: '安装 Codex Safe Setup', href: '/zh-CN/#install' },
    secondaryCta: {
      label: '在 GitHub 上查看',
      href: 'https://github.com/QianQIUlp/codex-safe-setup',
      external: true,
    },
    tertiaryCta: { label: '工作原理', href: '/zh-CN/#limits' },
    disclaimer: '社区项目 · 与 OpenAI 无关联',
    visual: {
      agentLabel: 'Agent',
      agentName: 'Codex',
      insideLabel: '受限配置边界内',
      outsideLabel: '边界外',
      allowed: ['工作区写入', 'workspace 沙箱读取', '明确的联网策略'],
      denied: ['工作区外写入', 'StrictProfile 凭据', '不受限网络'],
      deniedCrossing: '读取配置外路径',
      crossingDetail: '在边界处被拦截',
      ariaLabel:
        '受限配置示意图：DynamicUi 使用两个纯正向授权的 Workspace 命名配置；StrictProfile 另加固定的根目录和凭据拒读。',
    },
  },
  principle: {
    eyebrow: '为什么存在',
    title: '审批不是安全边界。',
    body: [
      '面对删除命令，很多人的第一反应是："我在指令里写清楚，重要操作让我亲自审批。"但审批有效的前提，是你能看懂每一条命令——在 Windows 上，引号规则、编码、注册表、一大串参数，让这件事远比想象中难。',
      '命令会越来越长，审批一天重复几十次，时间一长总会有看累、看漏、只看前半段的时候；审查 Agent 也一样会判断错。当审批是唯一的防线，一次误判就等于把全部权限交出去。',
    ],
    semantic: {
      label: '先试试看 · 最可怕的错误：语义错误',
      intro: '先通读整段脚本，再看下面的答案。里面没有一行恶意代码——但它会删掉一个你从未想删除的目录。',
      code: [
        'Set-Location "C:\\Users\\you\\projects\\webapp"',
        '$ErrorActionPreference = "SilentlyContinue"',
        'if (-not (Test-Path "C:\\Users\\you\\projects\\webapp\\node_modules")) {',
        '  npm ci --no-audit --no-fund --loglevel=error',
        '}',
        '$config = Get-Content "C:\\Users\\you\\projects\\webapp\\tools\\build-config.json" -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json',
        '$base = $config.outputDirectory',
        'npm run build -- --outDir "$base" --minify',
        'Copy-Item -Path "$base\\*" -Destination "C:\\Users\\you\\projects\\webapp\\release\\latest" -Recurse -Force -Confirm:$false',
        'Remove-Item -Path "$base\\data" -Recurse -Force -Confirm:$false',
        'git add -A; git commit -m "sync build output"; git push origin main',
      ],
      looksLike: '一段常规的构建 + 发布脚本。',
      actually:
        '读到最后一几行时，第 7 行看起来毫无问题：$base 从配置里取值。但配置读取已经悄悄失败——$base 是 $null。整段脚本没有一行是为了制造事故而写的。',
      answer: {
        caption: '答案',
        keyLines: [
          '$config = Get-Content "C:\\Users\\you\\projects\\webapp\\tools\\build-config.json" -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json',
          '$base = $config.outputDirectory',
          'Remove-Item -Path "$base\\data" -Recurse -Force -Confirm:$false',
        ],
        explanation:
          'PowerShell 把以 \\ 开头的路径解析为当前驱动器的根目录——这里是 C:。配置文件不存在，读取悄悄失败，$base 是 $null："$base\\data" 变成 \\data，"$base\\*" 变成 \\*。Copy-Item 先把 C:\\ 下能读到的东西复制进 release\\latest，Remove-Item 指向 C:\\data。删除是否真的发生，取决于 C:\\data 是否存在、当前身份是否有权限。危险不来自任何一条危险的行——两个看起来合理的局部行为组合出了一个你从未想过的路径。',
      },
    },
    accidents: {
      label: '风险一 · Agent 事故——不需要恶意',
      intro: '正确完成任务不等于安全完成任务。这些命令没有一行是恶意的，只是结果错了。',
      examples: [
        {
          label: '同步即清空',
          code: [
            'git fetch origin main --quiet',
            'git reset --hard origin/main',
            'git clean -fdx -e ".env.local" -e "node_modules"',
          ],
          looksLike: '一个普通的需求：把仓库恢复成远程 main 的干净状态。',
          actually:
            '它从不确认工作树里有没有你唯一的副本。reset --hard 丢弃已跟踪的改动，clean -fdx 连被忽略的文件也清掉。任务是对的，完成方式是危险的。',
        },
      ],
    },
    boundary: {
      label: '风险二 · 权限大于任务所需',
      intro:
        '这些不是 Agent 的理解事故，而是权限本身允许的事情：无法审计的代码，以及把一次授权扩展到未来的执行入口。',
      examples: [
        {
          label: '不可审计执行',
          code: [
            'powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand JABFAHIAcgBvAHIAQQBjAHQAaQBvAG4AUAByAGUAZgBlAHIAZQBuAGMAZQA9ACcAUwBpAGwAZQBuAHQAbAB5AEMAbwBuAHQAaQBuAHUAZQAnADsAIABHAGUAdAAtAEMAaABpAGwAZABJAHQAZQBtACAAIgAkAGUAbgB2ADoAVQBTAEUAUgBQAFIATwBGAEkATABFAFwALgBhAHcAcwAiACwAIgAkAGUAbgB2ADoAVQBTAEUAUgBQAFIATwBGAEkATABFAFwALgBzAHMAaAAiACAALQBSAGUAYwB1AHIAcwBlACAALQBGAG8AcgBjAGUAIAAtAEUAcgByAG8AcgBBAGMAdABpAG8AbgAgAFMAaQBsAGUAbgB0AGwAeQBDAG8AbgB0AGkAbgB1AGUAIAB8ACAARgBvAHIARQBhAGMAaAAtAE8AYgBqAGUAYwB0ACAAewAgAEMAbwBwAHkALQBJAHQAZQBtACAAJABfAC4ARgB1AGwAbABOAGEAbQBlACAAIgBDADoAXABVAHMAZQByAHMAXAB5AG8AdQBcAHAAcgBvAGoAZQBjAHQAcwBcAHcAZQBiAGEAcABwAFwALgBzAGMAYQBuAC0AbwB1AHQAcAB1AHQAIgAgAC0ARgBvAHIAYwBlACAAfQA=',
          ],
          looksLike: '一种常见的引号规避写法——也可能是把真正执行的内容藏起来。',
          actually:
            '在 Full Access 下，prompt 注入和恶意仓库指令就是这个样子：Hidden、NonInteractive、ExecutionPolicy Bypass，加上没人能审计的 payload。',
          decodedLabel: '解码后是：',
          decoded: [
            '$ErrorActionPreference = \'SilentlyContinue\'',
            'Get-ChildItem "$env:USERPROFILE\\.aws", "$env:USERPROFILE\\.ssh" -Recurse -Force |',
            'ForEach-Object { Copy-Item $_.FullName "C:\\Users\\you\\projects\\webapp\\.scan-output" -Force }',
          ],
        },
        {
          label: '跨登录持久化',
          code: [
            'New-ItemProperty -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run" -Name "WebAppUpdater" -Value "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\\Users\\you\\AppData\\Local\\Temp\\upd.ps1" -PropertyType String -Force | Out-Null',
          ],
          looksLike: '注册一个开机启动的更新程序。',
          actually:
            'Run 键指向的是可变文件 upd.ps1：今天审的是 A 版本，下次登录执行的可能是被替换后的 B 版本。一次授权变成持续生效的执行入口，超出了这次审批的语义范围。',
        },
      ],
      incident: {
        label: '社区调研中的个案',
        story:
          '一位使用 Full Access 的用户发现：中转站把注入的脚本伪装成"环境监测"混进了执行流程，最后因为思维链里能看到执行的代码才被发现——SSH 密钥和各种 API key 差一步就被打包带走了。',
        lesson:
          '脚本伪装得完全无害，所以审批根本不是问题所在。Custom 或 StrictProfile 读取边界活动时，注入代码无论伪装得多好，都读不到项目之外的 SSH 和 API key。',
      },
    },
    closer:
      '每一条新命令都是一场必须满分的考试，而失败一次就交出全部权限。Codex Safe Setup 的思路相反：让审批成为边界内的可选工作流，让边界本身成为不可越过的防线。',
    cta: '看看实际边界如何工作',
  },
  limits: {
    eyebrow: '它限制什么',
    title: '它限制什么',
    lead: '三道能力边界，并明确选择由 UI 动态控制或固定严格配置。',
    modules: [
      {
        id: 'files',
        number: 'A',
        eyebrow: '文件',
        title: 'Codex 不应默认拥有整个文件系统。',
        lead: 'DynamicUi 让运行时切换不受粘连 deny 影响；StrictProfile 则固定根目录和凭据拒读。',
        inside: [
          {
            icon: 'allow',
            label: '工作区写入',
            detail: '仅限已登记的工作区根目录。',
          },
          {
            icon: 'allow',
            label: 'Workspace 沙箱读取',
            detail: 'DynamicUi 遵循 workspace 沙箱的读取范围；StrictProfile 用显式规则缩小读取范围。',
          },
        ],
        outside: [
          {
            icon: 'deny',
            label: '文件系统根目录',
            detail: 'DynamicUi 阻止工作区外写入，StrictProfile 以显式规则固定边界；Full Access 则允许。',
          },
          {
            icon: 'deny',
            label: '常见凭据',
            detail: '只有 StrictProfile 显式拒绝。DynamicUi 不能在可写工作区内使用会粘连的 deny-glob。',
          },
        ],
        note: 'DynamicUi 创建两个纯正向授权的运行时配置。工作区内凭据文件仍可读；需要固定显式拒读时使用 StrictProfile。',
      },
      {
        id: 'network',
        number: 'B',
        eyebrow: '联网',
        title: '命令联网是独立的边界。',
        lead: '批准命令和允许数据离开你的机器是两个不同的问题。安装器把联网作为一项独立、明确的选择。',
        inside: [
          {
            icon: 'allow',
            label: 'Off 关闭',
            detail: '默认。命令无法访问网络。',
          },
          {
            icon: 'allow',
            label: 'Allowlist 白名单',
            detail: '仅明确列出的公开域名可通过命令代理。',
          },
        ],
        outside: [
          {
            icon: 'deny',
            label: 'Unrestricted 不受限',
            detail: '高风险。命令直接出网，需单独确认风险。',
          },
        ],
        note: '没有启用代理的域名表不是真正生效的白名单。',
      },
      {
        id: 'recovery',
        number: 'C',
        eyebrow: '恢复',
        title: '安全也意味着可以恢复。',
        lead: '限制用于阻止错误，恢复用于承受错误。每个受管理文件都会先备份，可选的检查点桥接器保存工作进度而不动你的分支。',
        inside: [
          {
            icon: 'allow',
            label: '写入前备份',
            detail: '安装器触碰的每个文件都会先备份，并提供精确回滚命令。',
          },
          {
            icon: 'allow',
            label: 'Git 检查点',
            detail: '可选，保存在 refs/codex-safe/checkpoints/* 隐藏引用。当前分支、真实索引和工作树保持不变。',
          },
        ],
        outside: [
          {
            icon: 'deny',
            label: '敏感未跟踪文件',
            detail: '拒绝纳入检查点：.env、私钥、.npmrc、云凭据文件。',
          },
          {
            icon: 'deny',
            label: '自动破坏性恢复',
            detail: '绝不自动执行 reset --hard、clean、替换分支或原地恢复。',
          },
          {
            icon: 'deny',
            label: 'Git 被替换',
            detail: '固定 Git 路径的 SHA-256 校验不通过时拒绝运行。',
          },
        ],
        note: '检查点不包含被忽略或拒绝的文件。恢复请使用独立工作树：git worktree add <新空目录> <提交>。',
      },
    ],
  },
  beforeAfter: {
    eyebrow: '前后对比',
    title: '自主与隔离并不对立。',
    lead: '好的权限边界让 Agent 在允许范围内自主工作——你不需要成为每几秒一次的守门人。',
    before: {
      title: 'Full Access',
      tagline: '一切读取、写入和发送默认允许。',
      items: ['工作区', '主目录', '凭据', '整个文件系统', '网络'],
    },
    after: {
      title: '有边界的自主',
      tagline: '写入和命令出网保持边界；当前 UI 路由决定读取边界。',
      items: ['工作区写入', '零 deny 的 Custom 配置', '明确的联网策略'],
    },
    afterDenied: '越界写入和命令出网 \u2192 拒绝',
    bottomLine:
      '推荐模式 BoundedAutonomy 在边界内没有审批弹窗——权限限制替代了原来靠审批维持的安全。',
    modes: {
      label: '处理边界跨越的三种方式',
      intro: '审批方式和命令联网是两个彼此独立的决定。审批者选择不会改变当前的 DynamicUi 或 StrictProfile 文件路由。',
      recommendedTag: '推荐',
      rows: [
        {
          name: 'BoundedAutonomy',
          recommended: true,
          detail: '没有审批弹窗。越界操作直接在权限边界处失败。',
        },
        {
          name: 'AskMe',
          detail: '符合条件的越界请求交给你本人审批。',
        },
        {
          name: 'AutoReview',
          detail: '符合条件的越界请求交给审查 Agent——沙箱并不会因此变强。',
        },
      ],
    },
  },
  verification: {
    eyebrow: '验证',
    title: '安装不等于验证。',
    lead: '写入配置不等于证明它生效。验证会如实报告实际检查了什么，以及哪些无法检查。',
    rows: [
      {
        status: 'pass',
        label: 'PASS',
        detail: '已经直接检查并符合预期。',
      },
      {
        status: 'partial',
        label: 'PARTIAL',
        detail: '配置证据存在，但缺少必要的运行时或 CLI 检查。',
      },
      {
        status: 'fail',
        label: 'FAIL',
        detail: '必要条件缺失或互相冲突。',
      },
      {
        status: 'not-controlled',
        label: 'NOT CONTROLLED',
        detail: '属于其他控制面——如实报告，不暗示受保护。',
      },
    ],
    caveat: '静态配置和 codex execpolicy check 是证据，不是对所有未来运行时行为的证明。Codex 升级后请重新验证。',
    restart: '机器配置变更后新建一次任务。之后同任务 UI 权限变更必须在下一条消息生效，无需重启。',
    checks: {
      label: '验证实际检查什么',
      items: [
        '工作区之外的写入',
        '工作区之外的读取',
        '工作区内的敏感文件',
        '受保护的元数据（.git、.codex、.agents）',
        '删除恢复（检查点）',
        '命令联网出口',
        '回滚与备份',
        '外部控制面——如实报告，绝不暗示',
      ],
    },
    canary: '工作区外会放置一个合成 canary 文件，用于在做出任何结论前实际探测边界。',
  },
  install: {
    eyebrow: '安装',
    title: '安装 Codex Safe Setup',
    lead: '两条命令，一句指令——之后插件会先审计、解释取舍，只有在你确认后才写入配置。',
    requires: 'DynamicUi 与 StrictProfile 都需要 Codex CLI 0.138.0 或更高版本 · Windows 上推荐 PowerShell 7',
    commands: [
      'codex plugin marketplace add QianQIUlp/codex-safe-setup --ref main',
      'codex plugin add codex-safe-setup@codex-safe-setup',
    ],
    promptLabel: '新建一个 Codex 任务或 CLI 会话，然后输入：',
    promptText: '使用 $codex-safe-setup 审计我当前的 Codex 权限，并安装推荐的安全配置。',
    releaseNote: '0.2.1 移除了 0.2.0 引入的 Windows 选择器兼容层，并提供清理旧版自启动残留的脚本。GitHub marketplace 跟随 main，并固定到最新 Release。',
    shaNote: '每个 Release 都附带可安装 ZIP 和 .sha256 文件。可在 PowerShell 中用 Get-FileHash -Algorithm SHA256 <压缩包> 核对。',
    detailsCta: {
      label: '查看安装详情',
      href: 'https://github.com/QianQIUlp/codex-safe-setup/blob/main/README.zh-CN.md',
      external: true,
    },
    copyButton: '复制',
    copied: '已复制',
    flow: {
      label: '两条命令之后会发生什么',
      steps: [
        '只读评估——此时不会改动任何东西。',
        '边界与取舍逐一解释，不做隐藏。',
        '前置依赖（PowerShell 7、Codex CLI）单独征求同意。',
        '先以 Plan-only 预览确切的配置内容。',
        '只有在你明确确认后才写入。',
        '静态与 execpolicy 检查，然后新建一次任务执行真实 Desktop 端到端探针。',
        '备份已记录——精确回滚随时可用。',
      ],
    },
  },
  notProtected: {
    eyebrow: '边界之外',
    title: '认清边界。',
    lead: '可信的安全工具会明确说明它不能保护什么。以下能力属于其他控制面——每一项都会标记为 NOT CONTROLLED，绝不暗示已经受控。',
    items: [
      'Web Search',
      'Browser',
      'Computer Use',
      'App 与 Connector',
      '其他 Plugin',
      'MCP 服务器',
      '云端任务',
      'Git 远程',
      'CI 凭据',
      '安装前已暴露的凭据',
      '主机恶意软件',
      '操作系统失陷',
    ],
    reportedAs: '以上每一项都会在验证报告中标记为 NOT CONTROLLED。',
    cta: {
      label: '阅读威胁模型',
      href: 'https://github.com/QianQIUlp/codex-safe-setup/blob/main/docs/threat-model.md',
      external: true,
    },
    exposed: {
      label: '如果凭据可能已经暴露',
      items: [
        '立即吊销或轮换凭据。',
        '检查服务商的用量、会话与账单记录。',
        '清除文件、日志、shell 历史与仓库历史中的残留。',
        '时间上的巧合不能证明因果。',
      ],
    },
  },
  openSource: {
    eyebrow: '开源',
    title: '开放构建。',
    lead: '社区维护，Apache-2.0 许可。源码、可复现构建与私有安全报告都在 GitHub。',
    items: [
      { label: 'Issues', href: 'https://github.com/QianQIUlp/codex-safe-setup/issues' },
      {
        label: '安全公告',
        href: 'https://github.com/QianQIUlp/codex-safe-setup/security/advisories/new',
      },
      {
        label: '参与贡献',
        href: 'https://github.com/QianQIUlp/codex-safe-setup/blob/main/CONTRIBUTING.md',
      },
      { label: 'License', href: 'https://github.com/QianQIUlp/codex-safe-setup/blob/main/LICENSE' },
    ],
    cta: {
      label: '在 GitHub 上查看源码',
      href: 'https://github.com/QianQIUlp/codex-safe-setup',
      external: true,
    },
    facts: [
      'CI 在 Windows 上运行隔离集成测试与包校验。',
      'Release 从经过校验的 tag 构建，并附带 SHA-256 校验文件。',
      '每个 Release 都通过了官方 Skill 与 Plugin 验证器。',
      '通过 GitHub Security Advisories 私下报告安全漏洞。',
    ],
  },
  footer: {
    tagline: '在 Windows 上更安全地使用 Codex。',
    disclaimer: '社区项目。与 OpenAI 无关联。',
    links: [
      { label: 'GitHub', href: 'https://github.com/QianQIUlp/codex-safe-setup' },
      {
        label: 'License',
        href: 'https://github.com/QianQIUlp/codex-safe-setup/blob/main/LICENSE',
      },
      {
        label: 'Security',
        href: 'https://github.com/QianQIUlp/codex-safe-setup/blob/main/SECURITY.md',
      },
      {
        label: '参与贡献',
        href: 'https://github.com/QianQIUlp/codex-safe-setup/blob/main/CONTRIBUTING.md',
      },
    ],
    languageLabel: '语言',
  },
};
