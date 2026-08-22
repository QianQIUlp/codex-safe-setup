# Codex Safe Setup

[English](README.md) · [威胁模型](docs/threat-model.md) · [实现原理](docs/how-it-works.md) · [参与贡献](CONTRIBUTING.md)

**审批不是安全边界。真正需要限制的是 Agent 能改什么、能读什么、能发送什么。**

Codex Safe Setup 是一个社区维护的 Codex 插件，用来安装最小权限、可验证、可恢复的本地配置。它先做只读审计，再解释选择，分别征得关键操作的同意，备份后才写入配置，最后验证实际建立了哪些边界。

这个项目要解决的不是“怎样更放心地点批准”，而是更根本的问题：人会判断错，审查用的 AI 也会判断错；Full Access 还可能让凭据和隐私文件进入 Agent 的上下文、日志或工具输出，即使它没有执行破坏命令。硬权限边界可以缩小错误后果，审批只是边界内外的一种工作流。

本项目不能保证绝对安全，也不是 OpenAI 官方项目。它通过第三方 GitHub marketplace 分发，尚未提交到 OpenAI 的通用公共插件目录，也没有被该目录收录。

## 安装

DynamicUi 与 StrictProfile 都需要 Codex CLI 0.138.0 或更高版本。Windows 上推荐 PowerShell 7；插件只会在用户明确同意后安装前置依赖。

```powershell
codex plugin marketplace add QianQIUlp/codex-safe-setup --ref main
codex plugin add codex-safe-setup@codex-safe-setup
```

新建一个 Codex 任务或 CLI 会话，然后输入：

```text
使用 $codex-safe-setup 审计我当前的 Codex 权限，并安装推荐的安全配置。
```

marketplace 跟随 `main`，其中的目录会把插件固定到最新的正式 Release。也可以从 [Releases](https://github.com/QianQIUlp/codex-safe-setup/releases) 下载可安装 ZIP。

## 更新已有安装

先刷新 GitHub marketplace 快照，再原位重新安装插件包：

```powershell
codex plugin marketplace upgrade codex-safe-setup
codex plugin add codex-safe-setup@codex-safe-setup
```

不要先卸载：卸载既无必要，也不会迁移已经写入机器的配置。新建任务以加载新插件，然后输入：

```text
使用 $codex-safe-setup 预览并应用我现有 Codex Safe Setup 安装的升级。
```

升级会先展示原有和目标审批方式、联网模式、Windows 沙箱和工作区选择；确认前不会写入。应用时会创建按事务隔离的备份和不可变的前一状态快照，回滚每次只退回一个配置世代。插件刷新、机器配置迁移、任务激活是三个不同阶段；配置升级后新建一次任务。只有 Windows 管理员提示反复出现时，才把完整退出并重启作为诊断步骤。

0.1.1 的 `Unrestricted` 用户必须执行 0.1.2 配置迁移：旧版通配符代理并不能让原生 SSH 等直连协议联网。迁移会关闭过滤代理并删除通配符域名表。若保留的是无限制联网和 Windows `Elevated`，仍需重新确认相应风险与一次管理员设置提示。

0.1.5 恢复了原生 Git 并移除了 Status/Commit 桥接，但命名默认权限仍可能把 Desktop 任务固定在旧路由上。

0.1.6 提供两条明确路线。默认 `DynamicUi` 会移除插件写入的 `default_permissions` 和命名权限固定，保留已有 UI 沙盒选择，使 Full Access、Workspace、Read-only 在同一任务的下一条用户消息生效。`StrictProfile` 保留根目录拒读、凭据文件拒读和代理白名单，适合把这些边界置于纯动态切换之前的场景。

0.2.0 保留了 0.1.7–0.1.9 开发阶段已经验证的运行时规则：下一轮实际权限由最后一次手动点击决定。DynamicUi 只把内建 Workspace 作为启动默认值，并提供两个纯正向授权配置：`codex-safe-workspace` 与 `codex-safe-workspace-offline`；这些动态选项不会加入会跨选择保留的文件系统 deny。

部分 Windows Desktop 构建仍可能在发送或完成期间显示另一个标签，即使实际路由正确。0.2.0 因此提供独立、可选的兼容层：它先确认本机签名 Desktop 仍包含经过验证的选择器 gate 与结构锚点，再用仅对该次 Codex 进程生效的主进程加载器，在 renderer 第一段脚本之前注册一个哈希固定的 session preload。它不提取、不修改、不复制客户端，不写 WindowsApps，不开放调试端口，也不写入用户级或机器级环境变量。官方 Desktop 更新后，启动器只有在精确包身份、有效签名者身份、选择器结构、隔离主进程探针和文档起始探针全部通过时，才会自动接受新构建并原子刷新版本与字节固定值；不兼容更新会保留上一次接受的状态并安全拒绝，无需用户为兼容更新重新安装或确认。验收会先故意提供不可用的继承模块路径，在真实 Windows PowerShell 下执行已安装启动器的无副作用校验路径（包括当前进程路由分支），成功后才接受 renderer 探针。

该兼容层绝不关闭、强杀或重启任何正在运行的 Codex Desktop 进程。当普通未注入的 Desktop 已经在运行时，启动器只记录 `MANUAL_ACTION_REQUIRED` 并退出；由用户完整退出 Codex 后改用专用快捷方式启动。可选的每用户启动监视器因此是纯观察者：只记录路由状态，从不对运行中的 Desktop 调用启动器。安装会在任何状态变更之前归档并移除可证明指向旧 `desktop-ui-fix` watcher 的自启动项，升级不会再留下开机弹窗。

如果你以前是手动复制 `~/.codex/skills/secure-codex-setup`，而不是通过 marketplace 安装插件，请先把旧目录可恢复地移出技能发现路径，再添加 GitHub marketplace、安装 `codex-safe-setup` 并新建任务。不要让独立旧副本和插件副本同时被发现。

如果你曾按旧文档用固定的 `v0.1.0` 添加 marketplace，只需迁移一次到可更新通道：

```powershell
codex plugin remove codex-safe-setup@codex-safe-setup
codex plugin marketplace remove codex-safe-setup
codex plugin marketplace add QianQIUlp/codex-safe-setup --ref main
codex plugin add codex-safe-setup@codex-safe-setup
```

每个 Release 都附带 `.sha256` 文件。可在 PowerShell 中运行 `Get-FileHash -Algorithm SHA256 <压缩包>` 核对下载内容。

### 可选的 Windows Desktop 选择器兼容层

只有在直接观察到“没有点击但标签自行变化”时才使用。先预览；正式安装会单独要求确认，因为它依赖未公开的 Desktop 功能 gate，并增加一个仅当前 Codex 进程使用的 session preload。安装不会重启正在运行的任务。启动监视器为可选且纯观察；只有需要登录期路由状态记录时才传 `-EnableStartupWatcher`：

```powershell
& <skill-dir>/scripts/Install-DesktopPermissionSelectorFix.ps1 -PlanOnly
& <skill-dir>/scripts/Install-DesktopPermissionSelectorFix.ps1 -ConfirmApply -AcknowledgeUnsupportedDesktopOverride
& <skill-dir>/scripts/Test-DesktopPermissionSelectorFix.ps1
```

兼容的官方客户端更新不需要重新安装或手动批准；如果选择器 gate、结构锚点、包身份、签名身份或 Electron preload 行为发生不兼容变化，启动会保持禁用，且不会覆盖上一次通过验证的固定值，直到兼容层自身更新。

回滚是可恢复的，停用的加载器世代以及迁移前的旧派生副本都会保存在 `CODEX_HOME/safe-setup/desktop-selector-fix-history`：

```powershell
& <skill-dir>/scripts/Rollback-DesktopPermissionSelectorFix.ps1 -PlanOnly
& <skill-dir>/scripts/Rollback-DesktopPermissionSelectorFix.ps1 -ConfirmRollback
```

## 你会做出的选择

审批方式和命令联网是两个独立维度：

| 选项 | 推荐 | 含义 |
|---|---:|---|
| `BoundedAutonomy` | 是 | 边界内自主工作；越界操作直接失败，不靠频繁审批维持安全。 |
| `AskMe` | 可选 | 符合条件的越界请求交给用户审批。 |
| `AutoReview` | 可选 | 符合条件的越界请求交给审查 Agent；不会增强沙箱。 |
| 联网 `Off` | 是 | 命令无法访问网络。 |
| 联网 `Allowlist` | 可选 | 只有明确列出的公开域名可通过命令代理访问。 |
| 联网 `Unrestricted` | 高风险 | 启用直连无限制联网并关闭过滤代理，原生 SSH 等协议可用；必须先说明具体风险，再单独确认。 |

`Unrestricted` 联网本身不会扩大文件系统权限，也不会额外获得删除权限；原有文件权限仍然生效，因此在可写工作区内原本允许的修改和删除仍然可以发生。过滤代理及其域名限制会被关闭，使原生 SSH 等直连协议可用。新增风险是失去网络目的地边界：命令已经能够读取或生成的任何数据，都可能被发送到任意公网地址，包括源码、配置、命令输出、隐私信息，以及文件名没有命中拒绝规则的凭据。网页、Issue、依赖说明还可能携带提示注入，诱导 Agent 外传数据或执行不安全步骤；联网命令也可能下载恶意软件、有漏洞的依赖，或引入许可证受限内容。OpenAI 建议普通任务使用 `Allowlist`，只开放实际需要的目的地。详见 [Agent internet access](https://learn.chatgpt.com/docs/cloud/internet-access) 与 [Agent approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security)。

Windows 上还会分别询问是否安装 PowerShell 7、Codex CLI，以及是否启用需要管理员确认的增强沙箱。拒绝依赖安装不会触发静默安装。PowerShell 7 能减少旧版 PowerShell 的编码、引号、兼容性与语义差异，但它本身不是安全边界。

## 它建立的控制

- 默认安装 DynamicUi，保留 Custom / 自定义，同时让任务 UI 对 Custom、Full Access、Workspace、Read-only 的修改在下一条消息生效，无需重启 Codex。
- 需要根目录拒读和常见凭据文件拒读时，可明确选择 StrictProfile。
- 明确选择离线、由代理强制执行的域名白名单，或关闭代理的直连无限制联网。
- 保留 Codex 对 `.git`、`.codex`、`.agents` 的保护。
- 可选安装只提供 Save/List 的窄恢复检查点桥接，不替代原生 Git 的 status 或 commit。
- 备份每个受管理文件，并生成精确回滚命令。

DynamicUi 的两个命名配置都继承 Codex 内建 Workspace 沙箱，并且不安装根目录或凭据 deny。`codex-safe-workspace` 使用所选命令联网策略，`codex-safe-workspace-offline` 始终关闭命令联网。读取范围因此遵循更宽的 workspace 沙箱语义；工作区可写时，工作区内的凭据文件仍可读。安装器会先披露并要求确认这一取舍。DynamicUi 支持 Off 和 Unrestricted；需要显式拒读或代理白名单固定边界时选择 StrictProfile。所有写入前都会备份。

## 它没有控制的范围

Web Search、Browser、Computer Use、App、Connector、其他 Plugin、MCP、云端任务、Git 远程、CI 凭据、安装前已经暴露的密钥、主机恶意软件和操作系统失陷都属于别的控制面。验证报告会把这些标记为 `NOT CONTROLLED`，而不是假装已经安全。

在把配置当作安全控制前，请阅读完整的[威胁模型](docs/threat-model.md)。

## 验证与恢复

每项控制会报告为：

- `PASS`：已经直接检查并符合预期。
- `PARTIAL`：配置证据存在，但缺少必要的运行时或 CLI 检查。
- `FAIL`：必要条件缺失或互相冲突。
- `NOT CONTROLLED`：属于其他控制面。

配置检查、权限列表回读和 codex execpolicy check 只是证据，不能证明当前任务的实际权限。运行 `<skill-dir>/scripts/Test-DesktopPermissionE2E.ps1 -ShowPrompts`，先完成初始化轮，再在同一 Desktop 任务内依次执行 `codex-safe-workspace` → Full Access → 内建 Workspace，期间不重启。PASS 必须同时满足两类证据：直接观察每次主动点击后的标签在发送前、执行中和完成后都不变；以及 Desktop `session_meta` 未更换、真实下一轮 `turn_context`、后续 `task_complete`、逐字匹配的 unified exec 探针及退出码、工作区外 canary 全部匹配。rollout 或设置记录不能证明 UI 显示稳定，设置回显也不能单独证明实际权限。codexsandboxonline/offline 账户名不是权限证据，真正的 Full Access 直接使用原生 Git。

运行时验证必须匹配模式：`Off` 要证明可达目标被阻断；`Allowlist` 要证明白名单目标经代理成功、未列出目标失败；`Unrestricted` 要用直连 TCP 或原生 OpenSSH 成功，代理横幅不能作为直连证据。

Windows 上推荐的 `Elevated` 沙箱需要管理员确认操作系统级初始化，但工作区内的每条命令不应逐次提权。如果管理员提示反复出现，请运行只读审计并查看 `WindowsSandboxSetupHealth`。`Allowlist` 期望代理端口 3128 和 8081，`Off` 与直连 `Unrestricted` 期望空端口集。历史上发生过端口变化、但最新设置已经对齐时只记为信息，无需处理；只有当前仍冲突或继续反转时，才完整退出全部 Codex 进程并重新启动一次。不要仅为了隐藏这个生命周期问题而降级到 `Unelevated`。

带版本的安装状态会保留按事务隔离的备份和不可变的前一状态快照。升级后的回滚会同时恢复上一代受管理文件和上一代活动状态，因此可以按世代继续回滚。

可选恢复桥接只会把已跟踪文件和普通未跟踪文件保存到 refs/codex-safe/checkpoints/* 隐藏引用，且只提供 Save 和 List。它拒绝敏感未跟踪文件，也不会自动运行 reset --hard、clean、替换分支或原地恢复。Git status/add/commit/branch 不由本项目代理。详见实现原理。

## 开发与贡献

在仓库根目录使用 PowerShell 7：

```powershell
pwsh -NoProfile -File ./tests/Validate-Package.ps1
pwsh -NoProfile -File ./tests/Run-Tests.ps1
pwsh -NoProfile -File ./tools/Build-Release.ps1 -Force
```

自动测试只使用临时 Codex Home 和临时 Git 仓库，不会修改真实 Codex 配置；它只验证静态路由、权限目录和迁移，不能替代上述真实 Desktop 端到端验收。Bug 和功能建议请提交到 [Issues](https://github.com/QianQIUlp/codex-safe-setup/issues)，提交 PR 前阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。安全漏洞必须通过 [GitHub Security Advisories](https://github.com/QianQIUlp/codex-safe-setup/security/advisories/new) 私下报告，不要公开披露。

本项目采用 [Apache-2.0](LICENSE) 许可证。
