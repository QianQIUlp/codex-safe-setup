# Codex Safe Setup

[English](README.md) · [威胁模型](docs/threat-model.md) · [实现原理](docs/how-it-works.md) · [参与贡献](CONTRIBUTING.md)

**审批不是安全边界。真正需要限制的是 Agent 能改什么、能读什么、能发送什么。**

Codex Safe Setup 是一个社区维护的 Codex 插件，用来安装最小权限、可验证、可恢复的本地配置。它先做只读审计，再解释选择，分别征得关键操作的同意，备份后才写入配置，最后验证实际建立了哪些边界。

这个项目要解决的不是“怎样更放心地点批准”，而是更根本的问题：人会判断错，审查用的 AI 也会判断错；Full Access 还可能让凭据和隐私文件进入 Agent 的上下文、日志或工具输出，即使它没有执行破坏命令。硬权限边界可以缩小错误后果，审批只是边界内外的一种工作流。

本项目不能保证绝对安全，也不是 OpenAI 官方项目。它通过第三方 GitHub marketplace 分发，尚未提交到 OpenAI 的通用公共插件目录，也没有被该目录收录。

## 安装

需要 Codex CLI 0.138.0 或更高版本。Windows 上推荐 PowerShell 7；插件只会在用户明确同意后安装前置依赖。

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

升级会先展示原有和目标审批方式、联网模式、Windows 沙箱和工作区选择；确认前不会写入。应用时会创建按事务隔离的备份和不可变的前一状态快照，回滚每次只退回一个配置世代。插件刷新、机器配置迁移、任务激活是三个不同阶段；配置升级后必须完整重启 Codex，并新建任务。

0.1.1 的 `Unrestricted` 用户必须执行 0.1.2 配置迁移：旧版通配符代理并不能让原生 SSH 等直连协议联网。迁移会关闭过滤代理并删除通配符域名表。若保留的是无限制联网和 Windows `Elevated`，仍需重新确认相应风险与一次管理员设置提示。

0.1.3 新增适配 linked worktree 的真实状态检查与可选正常提交，同时不把父仓库共享 `.git` 直接开放为可写。刷新插件后先预览配置升级；只有显式以 `-EnableGitCommitBridge $true` 注册具体 worktree 才会启用提交。它只提交明确列出的路径，并限制在允许的分支前缀（默认 `codex/`），未选择的修改保持不动。

如果你以前是手动复制 `~/.codex/skills/secure-codex-setup`，而不是通过 marketplace 安装插件，请先把旧目录可恢复地移出技能发现路径，再添加 GitHub marketplace、安装 `codex-safe-setup` 并新建任务。不要让独立旧副本和插件副本同时被发现。

如果你曾按旧文档用固定的 `v0.1.0` 添加 marketplace，只需迁移一次到可更新通道：

```powershell
codex plugin remove codex-safe-setup@codex-safe-setup
codex plugin marketplace remove codex-safe-setup
codex plugin marketplace add QianQIUlp/codex-safe-setup --ref main
codex plugin add codex-safe-setup@codex-safe-setup
```

每个 Release 都附带 `.sha256` 文件。可在 PowerShell 中运行 `Get-FileHash -Algorithm SHA256 <压缩包>` 核对下载内容。

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

- 用命名权限配置拒绝文件系统根目录，只保留最小运行时读取，并把写入限制到已登记工作区。
- 默认拒绝工作区中的 `.env`、私钥、npm 凭据、云凭据等常见敏感文件。
- 明确选择离线、由代理强制执行的域名白名单，或关闭代理的直连无限制联网。
- 保留 Codex 对 `.git`、`.codex`、`.agents` 的保护。
- 可选安装范围严格、固定 Git 路径与哈希的桥接器：可读取真实状态、保存不改分支/索引的检查点；另行授权的 linked worktree 可在不直接开放共享 `.git` 的情况下提交明确路径。
- 备份每个受管理文件，并生成精确回滚命令。

安装器不会默默混用新版 permission profiles 与旧版 sandbox 设置。迁移旧设置必须明确同意，而且会先完整备份。

## 它没有控制的范围

Web Search、Browser、Computer Use、App、Connector、其他 Plugin、MCP、云端任务、Git 远程、CI 凭据、安装前已经暴露的密钥、主机恶意软件和操作系统失陷都属于别的控制面。验证报告会把这些标记为 `NOT CONTROLLED`，而不是假装已经安全。

在把配置当作安全控制前，请阅读完整的[威胁模型](docs/threat-model.md)。

## 验证与恢复

每项控制会报告为：

- `PASS`：已经直接检查并符合预期。
- `PARTIAL`：配置证据存在，但缺少必要的运行时或 CLI 检查。
- `FAIL`：必要条件缺失或互相冲突。
- `NOT CONTROLLED`：属于其他控制面。

配置检查和 `codex execpolicy check` 是证据，不是对所有未来行为的绝对证明。安装完成后，必须在 Codex 的权限选择器中选择 **自定义（Custom）**，确认当前配置为 `codex-safe-workspace`，不要切回 Full Access。Windows 上先重启 Codex 并新建任务，不要继续使用安装前的旧任务；只有管理员提示反复出现时，才需要完整退出所有 Codex 桌面窗口和 CLI 进程后重新启动。其他平台新建任务或 CLI 会话后再做运行时验证。

运行时验证必须匹配模式：`Off` 要证明可达目标被阻断；`Allowlist` 要证明白名单目标经代理成功、未列出目标失败；`Unrestricted` 要用直连 TCP 或原生 OpenSSH 成功，代理横幅不能作为直连证据。

Windows 上推荐的 `Elevated` 沙箱需要管理员确认操作系统级初始化，但工作区内的每条命令不应逐次提权。如果管理员提示反复出现，请运行只读审计并查看 `WindowsSandboxSetupHealth`。`Allowlist` 期望代理端口 3128 和 8081，`Off` 与直连 `Unrestricted` 期望空端口集。历史上发生过端口变化、但最新设置已经对齐时只记为信息，无需处理；只有当前仍冲突或继续反转时，才完整退出全部 Codex 进程并重新启动一次。不要仅为了隐藏这个生命周期问题而降级到 `Unelevated`。

带版本的安装状态会保留按事务隔离的备份和不可变的前一状态快照。升级后的回滚会同时恢复上一代受管理文件和上一代活动状态，因此可以按世代继续回滚。

可选桥接器会把已跟踪文件和普通未跟踪文件保存到 `refs/codex-safe/checkpoints/*` 隐藏引用中；`Status` 可区分真实仓库状态与沙箱/ACL 可见性假象。显式启用的 `Commit` 只接受具体路径、允许的分支前缀、干净的初始索引且拒绝进行中的 Git 操作，并关闭 hook 与签名、保留未选择的修改。它拒绝敏感未跟踪文件，也不会自动运行 `reset --hard`、`clean`、替换分支或原地恢复。详见[实现原理](docs/how-it-works.md)。

## 开发与贡献

在仓库根目录使用 PowerShell 7：

```powershell
pwsh -NoProfile -File ./tests/Validate-Package.ps1
pwsh -NoProfile -File ./tests/Run-Tests.ps1
pwsh -NoProfile -File ./tools/Build-Release.ps1 -Force
```

测试只使用临时 Codex Home 和临时 Git 仓库，不会修改真实 Codex 配置。Bug 和功能建议请提交到 [Issues](https://github.com/QianQIUlp/codex-safe-setup/issues)，提交 PR 前阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。安全漏洞必须通过 [GitHub Security Advisories](https://github.com/QianQIUlp/codex-safe-setup/security/advisories/new) 私下报告，不要公开披露。

本项目采用 [Apache-2.0](LICENSE) 许可证。
