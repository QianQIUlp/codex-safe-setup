# dsh-safe-setup

[English](README.md) | 中文

为 DeepSeek Harness (dsh) 做的交互式安全配置向导插件。核心理念与 [codex-safe-setup](https://safercodex.qiu.works) 一致：

> **审批不是安全边界。** 命令复杂到无法逐条审读，审批疲劳后必然"扫一眼就过"；还有"每一行都合理、组合起来是灾难"的语义事故。关键不是审查，而是**把范围卡死**——越界动作直接失败，审批降级为边界内的工作流选择。

## 它做什么（模型轴）

向导问你几个问题，然后：

1. 在 `$DSH_HOME/cordis.patch.yml` 写入**托管块**（带标记，可整体回滚）：锁定 `sandbox-policy` 为 `workspace-write`、按你选的模式锁定 `approval` 策略；
2. 在工具层启用守卫：
   - **web_fetch 域名白名单**（dsh 自己没有网络轴——这是它补的位）：Off / Allowlist / Unrestricted（需逐字确认）；
   - **凭据路径读取拦截**：`.env`、`*.pem`、`id_rsa`、`~/.dsh/.credentials.yaml` 等形状的路径在文件工具层拒绝；
3. 全程遵循固定流程：**只读评估 → 解释边界 → 完整披露 → 仅展示计划 → 明确确认后写入 → 验证 → 记录回滚**。

审批模式（共享同一最小权限文件档位）：

| 模式 | dsh 映射 | 行为 |
|---|---|---|
| BoundedAutonomy（推荐） | approval `never` | 无弹窗，越界直接失败 |
| AskMe | approval `ask` | 沙箱升级请求逐次审批（严格单次授权） |

## 它管不住什么（诚实清单）

一个可信的安全工具会说明它不控制什么：

- **第三方插件**：dsh 插件在宿主进程内运行、无隔离——任何插件（包括本插件）都管不住其他插件。装任何插件前请审源码并 pin commit。
- **bash 发起的联网**：dsh 无网络沙箱，白名单只覆盖 `web_fetch` 工具。
- **bash `cat` 读敏感文件**：文件守卫只在文件工具层生效（PARTIAL）。
- **MCP 子进程**、**危险命令内容**（如 `curl | sh`）：dsh 词汇表之外。

完整的源码级证据见 [codex-safe-setup 的 dsh 审计](../docs/dsh/audit.zh-CN.md)。

## 安装与使用

```sh
dsh plugin --profile web add github:<you>/dsh-safe-setup#<commit-sha>
```

然后在 dsh Web UI 的会话里运行 `/safe-setup`（命令不经模型轮次）。

## 回滚

托管块首尾有 `managed by dsh-safe-setup` 标记；`/safe-setup rollback` 展示备份并按确认恢复，或手动删除标记块。

## 状态

原型（developer preview 阶段的 dsh 上的原型）。逻辑层测试 10/10 通过；真实 dsh 环境验证结果见发布说明。Apache-2.0，与 DeepSeek 无隶属关系。
