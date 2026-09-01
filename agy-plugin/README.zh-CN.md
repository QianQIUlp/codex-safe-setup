# Antigravity Safe Setup (`agy-safe-setup`)

[English](README.md) · [中文说明](README.zh-CN.md) · [威胁模型](skills/secure-agy-setup/references/threat-model.md) · [恢复指南](skills/secure-agy-setup/references/recovery.md)

**审批不是安全边界。真正需要限制的是 Agent 能读什么、改什么、发送什么。**

`agy-safe-setup` 是为 Google Antigravity (AGY) 生态（支持 Antigravity CLI `agy`、IDE 与 Antigravity 2.0 桌面端）打造的最小权限、确定性拦截、可逆恢复的安全插件。

## 核心控制能力

1. **确定性生命周期钩子 (`hooks.json` & `PreToolUse`)**：
   - 物理阻断 `view_file` / `write_to_file` / `replace_file_content` 读取项目内外敏感凭据（`.env`、`id_rsa`、`*.pem`、云凭据等）。
   - 阻断不透明混淆命令（`powershell -EncodedCommand`）与越界注册表/凭据扫描。
2. **基线权限锁定**：
   - `Non-Workspace File Access: deny`（锁定非工作区访问为拒绝）。
   - `Terminal Sandbox: true`（启用终端沙箱隔离）。
   - `Tool Execution Policy: proceed-in-sandbox`（推荐边界内自主工作模式，越界直接失败，无需频繁审批）。
3. **安全 Git 快照桥接器 (`New-AgyCheckpoint`)**：
   - 依托 Git 独立临时索引，将代码快照封存至隐藏引用 `refs/agy-safe/checkpoints/*`。
   - 绝不改动活跃分支、HEAD 与工作树；自动拒绝敏感未跟踪文件进快照。
4. **分阶段透明流程**：
   - 只读审计 $\to$ 风险说明 $\to$ 前置依赖单独确认 $\to$ 计划预览 $\to$ 原子应用 $\to$ 验证报告 $\to$ 一键回滚备份。

## 安装与使用

在 Antigravity 会话中输入：
```text
使用 $secure-agy-setup 审计我当前的反重力权限，并安装推荐配置。
```
