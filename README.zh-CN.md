# Codex Safe Setup

[English](README.md) · [威胁模型](docs/threat-model.md) · [实现原理](docs/how-it-works.md) · [参与贡献](CONTRIBUTING.md)

**审批不是安全边界。真正需要限制的是 Agent 能改什么、能读什么、能发送什么。**

Codex Safe Setup 是一个社区维护的 Codex 插件，用来安装最小权限、可验证、可恢复的本地配置。它先做只读审计，再解释选择，分别征得关键操作的同意，备份后才写入配置，最后验证实际建立了哪些边界。

这个项目要解决的不是“怎样更放心地点批准”，而是更根本的问题：人会判断错，审查用的 AI 也会判断错；Full Access 还可能让凭据和隐私文件进入 Agent 的上下文、日志或工具输出，即使它没有执行破坏命令。硬权限边界可以缩小错误后果，审批只是边界内外的一种工作流。

本项目不能保证绝对安全，也不是 OpenAI 官方项目。

## 安装

需要 Codex CLI 0.138.0 或更高版本。Windows 上推荐 PowerShell 7；插件只会在用户明确同意后安装前置依赖。

```powershell
codex plugin marketplace add QianQIUlp/codex-safe-setup --ref main
codex plugin add codex-safe-setup@codex-safe-setup
```

新建一个 Codex 任务或 CLI 会话，然后输入：

```text
使用 $secure-codex-setup 审计我当前的 Codex 权限，并安装推荐的安全配置。
```

marketplace 跟随 `main`，其中的目录会把插件固定到最新的正式 Release。也可以从 [Releases](https://github.com/QianQIUlp/codex-safe-setup/releases) 下载可安装 ZIP。

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
| 联网 `Unrestricted` | 高风险 | 允许访问任意公网目的地；必须先说明具体风险，再单独确认。 |

`Unrestricted` 联网本身不会扩大文件系统权限，也不会额外获得删除权限；原有文件权限仍然生效，因此在可写工作区内原本允许的修改和删除仍然可以发生。新增风险是失去网络目的地边界：命令已经能够读取或生成的任何数据，都可能被发送到任意公网地址，包括源码、配置、命令输出、隐私信息，以及文件名没有命中拒绝规则的凭据。网页、Issue、依赖说明还可能携带提示注入，诱导 Agent 外传数据或执行不安全步骤；联网命令也可能下载恶意软件、有漏洞的依赖，或引入许可证受限内容。OpenAI 建议只开放任务实际需要的域名和 HTTP 方法。详见 [Agent internet access](https://learn.chatgpt.com/docs/cloud/internet-access) 与 [Agent approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security)。

Windows 上还会分别询问是否安装 PowerShell 7、Codex CLI，以及是否启用需要管理员确认的增强沙箱。拒绝依赖安装不会触发静默安装。PowerShell 7 能减少旧版 PowerShell 的编码、引号、兼容性与语义差异，但它本身不是安全边界。

## 它建立的控制

- 用命名权限配置拒绝文件系统根目录，只保留最小运行时读取，并把写入限制到已登记工作区。
- 默认拒绝工作区中的 `.env`、私钥、npm 凭据、云凭据等常见敏感文件。
- 命令联网默认关闭，或经由真正启用的域名白名单代理。
- 保留 Codex 对 `.git`、`.codex`、`.agents` 的保护。
- 可选安装一个范围严格、固定 Git 路径与哈希的检查点桥接器；它不会改当前分支、真实索引或工作树。
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

配置检查和 `codex execpolicy check` 是证据，不是对所有未来行为的绝对证明。安装完成后，必须在 Codex 的权限选择器中选择 **自定义（Custom）**，确认当前配置为 `codex-safe-workspace`，不要切回 Full Access；然后新建任务或 CLI 会话，再做运行时验证。

可选检查点会把已跟踪文件和普通未跟踪文件保存到 `refs/codex-safe/checkpoints/*` 隐藏引用中。它拒绝敏感未跟踪文件，也不会自动运行 `reset --hard`、`clean`、替换分支或原地恢复。详见[实现原理](docs/how-it-works.md)。

## 开发与贡献

在仓库根目录使用 PowerShell 7：

```powershell
pwsh -NoProfile -File ./tests/Validate-Package.ps1
pwsh -NoProfile -File ./tests/Run-Tests.ps1
pwsh -NoProfile -File ./tools/Build-Release.ps1 -Force
```

测试只使用临时 Codex Home 和临时 Git 仓库，不会修改真实 Codex 配置。Bug 和功能建议请提交到 [Issues](https://github.com/QianQIUlp/codex-safe-setup/issues)，提交 PR 前阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。安全漏洞必须通过 [GitHub Security Advisories](https://github.com/QianQIUlp/codex-safe-setup/security/advisories/new) 私下报告，不要公开披露。

本项目采用 [Apache-2.0](LICENSE) 许可证。

## ZCode 版(OS 沙箱,Windows)

同一哲学在 ZCode 上的落地,机制不同:ZCode 没有 Codex `config.toml` 权限档案那样的配置面,因此边界由 **Windows 本身**强制。ZCode 版安装的是一个 *OS 笼子*:

- 专用**标准(非管理员)本地用户**运行 ZCode;
- 你的 profile、`~/.ssh`、`~/.aws`、ZCode 凭据对 agent 会话**不可读**——由 NTFS 强制,不依赖模型行为;
- 已注册的工作区根授予显式 Modify ACL,其内既有密钥类文件加拒绝 ACE;
- ZCode 从 `C:\Program Files\ZCodeSandbox` 的**受管副本**运行(在禁止用户可写路径执行 exe 的加固机器上这是必须的);
- 安装过程一次 UAC、DPAPI 保护的启动凭据、开始菜单快捷方式 **"ZCode (Sandboxed)"**、精确回滚、可选的分支/索引中立 Git 检查点(`refs/zcode-safe/*`)。

以 ZCode 插件安装:打开 **设置 -> 插件管理 -> 发现 -> +**,把本 GitHub 仓库(或本地检出)添加为 marketplace,然后安装 **ZCode Safe Setup**。在 ZCode 里运行 `/zcode-safe-setup`,或直接说:

```text
Use secure-zcode-setup to audit my exposure and install the OS cage.
```

诚实的边界:网络出口**不受控制**(Windows 防火墙无法按用户区分同一可执行路径)、安装后新建的密钥文件不在拒绝 ACE 覆盖内、只有经沙箱快捷方式启动的会话在笼子内。机器实测证据见
[docs/zcode-probe/PROBE-REPORT.md](docs/zcode-probe/PROBE-REPORT.md),Codex 到 NTFS 的边界映射见
[zcode/skills/secure-zcode-setup/references/os-boundary-model.md](zcode/skills/secure-zcode-setup/references/os-boundary-model.md)。
