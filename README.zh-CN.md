# Codex Safe Setup

[English](README.md) · [威胁模型](docs/threat-model.md) · [实现原理](docs/how-it-works.md) · [参与贡献](CONTRIBUTING.md)

**审批不是安全边界。真正需要限制的是 Agent 能改什么、能读什么、能发送什么。**

Codex Safe Setup 是一个社区维护的 Codex 插件，用来安装最小权限、可验证、可恢复的本地配置。它先做只读审计，再解释选择，分别征得关键操作的同意，备份后才写入配置，最后验证实际建立了哪些边界。

这个项目要解决的不是“怎样更放心地点批准”，而是更根本的问题：人会判断错，审查用的 AI 也会判断错；Full Access 还可能让凭据和隐私文件进入 Agent 的上下文、日志或工具输出，即使它没有执行破坏命令。硬权限边界可以缩小错误后果，审批只是边界内外的一种工作流。

本项目不能保证绝对安全，也不是 OpenAI 官方项目。

## 安装

需要 Codex CLI 0.138.0 或更高版本。Windows 上推荐 PowerShell 7；插件只会在用户明确同意后安装前置依赖。

```powershell
codex plugin marketplace add QianQIUlp/codex-safe-setup --ref v0.1.0
codex plugin add codex-safe-setup@codex-safe-setup
```

新建一个 Codex 任务或 CLI 会话，然后输入：

```text
使用 $secure-codex-setup 审计我当前的 Codex 权限，并安装推荐的安全配置。
```

也可以从 [Releases](https://github.com/QianQIUlp/codex-safe-setup/releases) 下载可安装 ZIP。推荐 marketplace 安装方式，因为 Codex 能记录来源和版本。

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
| 联网 `Unrestricted` | 高风险 | 命令可直接出网，需要单独确认风险。 |

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

配置检查和 `codex execpolicy check` 是证据，不是对所有未来行为的绝对证明。安装后需重启 Codex，再做运行时验证。

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
