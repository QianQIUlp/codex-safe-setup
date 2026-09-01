# DeepSeek Harness（dsh）插件加载与权限模型安全审计

| | |
|---|---|
| 审计对象 | [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) |
| 版本基线 | `0.1.0-rc.5`，commit `47f9438`（2026-08-13，shallow clone） |
| 审计日期 | 2026-08-16 |
| 方法 | 源码通读 + 定向 grep（缺失证明）+ 官方文档/postmortem 交叉验证；每条结论标注 `文件:行号`，区分**代码实证**与**文档声称** |
| 目的 | 为 codex-safe-setup 向 dsh 生态的延伸提供事实基础 |

---

## 执行摘要

dsh 的安全架构护住了**「模型 → 工具」**这条轴：三档文件写策略定义清晰、fail-closed 纪律严格、审批升级梯子只宽不严、审计日志完善，Web 服务的浏览器信任围栏实现质量高于多数同类本地工具。

但**「插件 → 宿主」**这条轴完全敞开：第三方插件安装与加载全程零隔离、零校验、零审批门，官方文档对此完全知情（原话承认放行构建脚本 = "在 agent 沙箱之外执行包代码的许可"）。结合 dsh 受众中大量缺乏计算机基础的用户，**插件供应链是当前最现实、最高危的攻击面**，而官方仓库内不存在任何插件审计工具。

一句话结论：**dsh 的权限模型是一个诚实且扎实的"文件写效果策略系统"，不是通用安全边界——它自己也是这么写的**（`packages/sandbox/sandbox/src/index.ts:23-28`）。

---

## 1. 架构背景（理解攻击面的前提）

dsh 基于 Cordis 框架，"一切皆插件"：模型适配器、工具注册表、会话日志、**沙箱与审批策略本身**、连 agent loop 都是插件（`docs/architecture.zh.md:11`）。运行实例是一棵插件树，由四层叠加而成（`docs/architecture.zh.md:17-27`）：

1. profile 列出的 bundle（组合包）按序应用
2. profile 的 `cordis.patch.yml`
3. home 级（`$DSH_HOME`）`cordis.patch.yml`
4. 任意 `--patch` 命令行覆盖层

**安全含义**：任何位于上层的配置都能按 id **整条替换**下层条目——包括沙箱提供方和审批策略本身。引导用户"加一条 patch 开启某功能"等价于替换其安全配置。

**配置即代码**：任何 patch 层中的 `!!js` 表达式都在加载时经 `with(ctx){eval(expr)}` 于宿主进程内求值（`vendor/loader/src/config/utils.ts:5-9`）。YAML 配置文件是名副其实的 JavaScript 执行面。

## 2. 权限模型：三档 + 审批

### 2.1 三档的定义（代码实证）

```ts
// packages/sandbox/sandbox/src/index.ts:29
export type SandboxMode = 'read-only' | 'workspace-write' | 'danger-full-access'
```

第三档内部名就叫 **`danger-full-access`**。词汇表注释（`index.ts:23-28`）明确了管辖范围：**只管文件写效果；网络与进程可见性不在词汇表内**。

| 档位 | 文件读 | 文件写 | 网络出站 |
|---|---|---|---|
| `read-only` | **全盘任意读** | 拒绝（仅 `/dev/null` 等 sink） | 不限 |
| `workspace-write` | **全盘任意读** | workspace 根 + `/tmp` + `os.tmpdir()` | 不限 |
| `danger-full-access` | 全盘 | 全盘 | 不限 |

代码证据：`packages/fs/fs-sandbox/src/index.ts:6-7`（"Reads pass through untouched: every mode permits reading"）；`packages/sandbox/sandbox-local/src/profiles.ts:31,35,52`（Landlock `readOnly: ['/']`、bwrap `--ro-bind / /`、Seatbelt `(allow default) (deny file-write*)`——三个后端都只禁写）。

### 2.2 出厂默认

- 包级 fail-safe 默认是 `read-only`（`packages/sandbox/sandbox-policy/src/index.ts:94`）。
- 出货组合覆盖为 `workspace-write` + 审批 `ask`：`packages/bundle/base/cordis.patch.yml:172-191`，由 `DSH_PERMISSION_MODE` 环境变量控制；端到端测试断言了这一默认（`apps/web/tests/shipped-composition.e2e.ts:109-111`）。
- 注意 `DSH_PERMISSION_MODE=danger-full-access` 会**同时**把审批设为 `never`（自动拒绝）——全开档下没有任何确认门。

### 2.3 审批机制（做得好的部分）

审批不是对"危险操作"的通用闸门，只覆盖一种动作：**沙箱拒绝后的升级重试**。设计纪律值得肯定：

- 严格单调放宽（`packages/sandbox/sandbox/src/escalation.ts:28-31`），非放宽的升级请求直接拒绝不弹窗（`:162-164`）；
- 结果只有 4 个封闭值（`allowed-once | rejected | cancelled | unavailable`，`:93`），**没有 "always allow"**，授权严格单次；
- fail-closed：无人应答或应答方异常一律 `unavailable`（`packages/interaction/user-approval/src/index.ts:304-344`）；`never` 是**自动拒绝**而非自动放行（`:100`）——不存在 auto-approve 档；
- 每次询问与裁决都持久化进会话日志（`user-approval/src/index.ts:44-59,257-276`）；
- agent 无法经任何模型可见工具改档位：切换只来自用户面 `/permission` 命令，模型仅收到"changed by the user"通知（`user-approval/src/index.ts:230-236`）。

**缺口**：
- **TUI（终端）没有审批应答方**——升级请求一律 fail-closed 失败，终端用户只能手动 `/permission` 换档（`.agents/notes/implemented/feature/2026-07-31-workspace-write-surface-default.md`，grep `apps/cli/src` 无 `approval` 命中佐证）。
- **审计发现的潜在绕过向量**：插件 API 目录把 `approval/request` 事件公开给插件作者（`packages/extensions/tool-cordis/src/api-catalog.ts:2273-2275`），且动态插件 ctx 门面白名单含 `on`（`packages/extensions/cordis-host-runner/src/guard.ts:632-636`）——一个已激活的插件可注册审批应答器自动返回 `allowed-once`（waterfall 先到先得）。属代码事实推演，未见测试覆盖。

## 3. 沙箱实现

后端按平台选择（`packages/sandbox/sandbox-local/src/index.ts:159-166`）：

| 平台 | 后端 | 说明 |
|---|---|---|
| Linux | bwrap → Landlock（探测回退） | Landlock 是原生 C 启动器（`native/landlock-run`），只处理 `LL_FS_*` 文件位，**ABI 4 的 TCP 位未纳入**（`packages/entry/src/main.c:71-88`） |
| macOS | Seatbelt（`sandbox-exec`） | `(allow default) (deny file-write*)`——除写文件外一切默认放行 |
| Windows | 受限令牌 + DACL | **官方自评 `partial` 强制**：Everyone-ACE 缺口 + NTFS 硬链接可把 workspace 文件别名到外部（`sandbox-local/src/index.ts:177-187`）；workspace ACE 常设、跨会话复用且刻意不撤销（`packages/sandbox/sandbox-windows-acl/src/index.ts:10-15`） |

管辖范围：一次性 bash/pwsh 子进程、文件工具（write/edit 的**进程内**策略栅栏——自认"非内核边界，接受残余 TOCTOU"，`packages/fs/fs-sandbox/src/index.ts:10-18`）、PTY 终端。三者共享同一 writable-roots，防漂移。

**沙箱之外**：MCP server 子进程（SDK stdio transport 自行 spawn，不经 `ctx.shell`/`ctx.sandbox`，`packages/mcp/mcp-client/src/transport.ts:10,18`）、打包 ripgrep、E2B 远程执行。

## 4. 权限模型管不到的东西（任何档位下）

1. **网络出站**——无禁网、无域名白名单；`web_fetch`/`web_search` 目标由模型自选（`shipped-composition.e2e.ts:30-33` 官方测试注释直言）。
2. **任意读取**——`read-only` 也允许读全盘；机密外泄不设防。
3. **进程可见性与进程间操作**（Windows ACL 文档自认，`sandbox-windows-acl/src/index.ts:23-25`）。
4. **MCP 子进程**——以宿主完整权限运行。
5. **动态 Cordis 插件宿主代码**——见 §5.3。
6. **危险命令内容**——无静态识别/黑名单，`bash -c` 原样透传（`packages/shell/tool-bash/src/index.ts:6-7` 官方 TODO 自认）；`curl | sh` 在任何档位都能执行。
7. **系统临时目录**——`workspace-write` 恒含 `/tmp` 与 `os.tmpdir()`，跨会话共享（`packages/sandbox/sandbox/src/roots.ts:54`）。
8. **配置层替换**——上层 patch 可整条替换沙箱/审批条目（§1）。
9. **插件本身**——见下节，这是最大的一块。

## 5. 插件系统攻击面（核心发现）

### 5.1 安装：薄 pnpm 转发器，无参数白名单

`dsh plugin --profile <name> <args...>` 直接 `spawnSync('pnpm', args)`（`apps/cli/src/plugin.ts:120-133`）。两条"安装时执行任意代码"的路径：

- **npm 生命周期脚本**：pnpm ≥10 默认拦截构建脚本，但 dsh **主动指引用户**把包的 key 加进 profile 的 `allowBuilds` 放行重跑（`plugin.ts:149-155`）；
- **加载即执行**（无条件）：预构建包"不需要任何构建许可"，安装后首次 boot 即在宿主进程内执行模块代码（`docs/user/develop/basic/publish.md:175-178`）。

官方文档原话（`publish.md:173`，硬证据，报告可直接引用）：

> "Treat that allowance as what it is: **permission to execute the package's code on your machine at install time, outside any sandbox the agent runs under**. Only allow packages whose source you trust, and pin a commit…"

**无签名、无校验、无来源验证**：`packages/boot/` 与 `apps/cli/src/` 全量 grep `signature|integrity|checksum|attestation|verify` 无安全相关命中；浮动引用（`github:you/hello-plugin`）与锁定 commit 安装在 dsh 侧无差别处理。

### 5.2 加载：宿主进程内 import，零隔离

加载链全程同进程：`loadProfile` 读 bundle manifest（`packages/boot/app-boot/src/profile.ts:371-403`）→ `boot` → 经 Node ESM loader `import(specifier)`（`packages/boot/app-boot/src/index.ts:492-503`）→ 每个条目动态 import 后调用 `apply(ctx, config)`（`vendor/loader/src/config/entry.ts:280-282`）。

**隔离机制排查（缺失证明）**：`packages/bundle/` 与 `apps/cli/src/bin.ts` 中 grep `worker_threads|new Worker|fork|vm` 零命中。Cordis 的 `isolate` 只是符号域（symbol realm）级的服务可见性隔离，不是执行隔离（`vendor/loader/src/config/isolate.ts:26-40`）。boot 后**强制**激活所有启用条目，失败即退出（`app-boot/src/index.ts:692-725`）——没有审批门。

插件可直接 `import node:fs / node:child_process / node:net`，进程内代码不受 fs-sandbox/approval/Landlock 任何约束——**能力裁剪全部位于"模型工具调用"层，不位于"插件代码"层**。Postmortem 0002 官方自认："权限预设无法挂载、卸载或约束文件系统栈"（`docs/postmortem/0002-…zh.md:21`）。

### 5.3 升级即扩权 + 模型自写插件

- **升级即扩权**：`dsh plugin update` 时，已装包只要在新版本中新增 `dsh.bundle` 声明就被**自动追加**进加载层栈，无需审批（`apps/cli/src/plugin.ts:59-91`，注释原文确认 "an `update` activates a package that gained its `dsh.bundle` declaration in a newer version"）。
- **模型可自写插件**：`cordis_define` 工具族允许模型编写动态包并在 `node:vm` 中运行——该 vm 官方自述"不是遏制，宿主 realm 辅助函数仍是逃逸路径"（`cordis-host-runner/src/sandbox.ts:6-7`）。只含 host 半边的动态包**不经用户批准直接激活**（`cordis-host-runner/src/index.ts:270-274`）；声明 `inject` 可拿到**真实** `ctx.fs / ctx.web / ctx.bash` 服务，以默认档静默执行读写与网络，**不经过工具层审批路径**。激活审批存在"双勾授权未来版本"（`approveFutureVersions`）——**一次双勾后同一插件后续任意代码版本自动运行**（`tool-cordis/src/prompt.ts:45`）。这是提示注入 → 宿主进程的现实路径，出货组合的测试注释也直言："the `cordis_*` toolset executes model-written JavaScript **that no sandbox row confines**"（`shipped-composition.e2e.ts:30-33`）。

### 5.4 清单与盘点能力

bundle 通过 `package.json` 的 `"dsh": { "bundle": { "patch": "./cordis.patch.yml" } }` 声明（`profile.ts:41-51`）。**没有任何权限声明字段**（无 permissions/capabilities 键概念）。`plugin-inventory` 是纯只读状态投影——README 自述"no cache, history, provenance model, event stream"，不记录哪个 bundle/profile 引入了哪个条目（`packages/host/plugin-inventory/src/index.ts:56-69`）。

### 5.5 官方审计工具：不存在

社区文章提到的 `audit_plugin` / `audit_installed` 在仓库内**无任何命中**（全仓库 grep）；CLI 只注册 `plugin` 与 `web` 两个子命令。第三方插件审计生态位目前是**空的**。

## 6. Web 攻击面：做得对的一项

底层 webserver 是零认证纯路由表（`packages/host/webserver/src/index.ts`，支持绑 `0.0.0.0`），但上层有一道设计讲究的浏览器信任围栏（`packages/client/connection/src/api-request-trust.ts:96-123`）：

- **Host 围栏**对所有请求生效（防 DNS rebinding——浏览器无法伪造 Host 是其论证核心，纯 HTTP 读取不带 Origin/Fetch-Metadata 的边角都考虑到了）；
- `Sec-Fetch-Site: cross-site` 一律拒绝；Origin 若存在必须精确匹配 Host，`null` origin 拒绝；
- 注释明确"这不是认证层"——本机任意进程可调 API（本地工具常态），恶意网页在现代浏览器下打不进来。

**边界**：绑定 `0.0.0.0` + `--trusted-host` 的 LAN 部署会把信任边界扩到局域网；老浏览器（无 Sec-Fetch-Site）仅剩 Host 围栏保护。

## 7. 凭据与会话日志

- **凭据明文存储**：API key 存 `~/.dsh/.credentials.yaml`（0600/0700，POSIX 校验权限位，Windows 跳过检查）。官方 README 安全边界一节原文（`packages/credentials/credentials-local/README.md:54`）："这挡得住其他系统用户——**挡不住模型**……这是审慎（discretion），不是边界（boundary）"。workspace-write 只限制写不限制读，工具进程与用户同身份：**提示注入引导 agent 读该文件即可窃取全部 API key**（harness 不把路径给模型，但一个 `cat ~/.dsh/.credentials.yaml` 就够了）。OS 钥匙串是官方自认的"延期工作"。
- **会话日志**："模型可见即已记录"是运行时强断言（`docs/architecture.zh.md:96-100`），取证基础好；但 `packages/core/session/src` 内**无哈希链/完整性校验**——仅追加是设计纪律，不防有意篡改。

## 8. 针对小白用户的现实攻击剧本

把上述发现翻译成受害者视角（这也是 safe-setup 内容的骨架）：

1. **恶意插件**（最高危）：教程里一句"运行 `dsh plugin add github:xxx/yyy`"——安装即沙箱外任意代码执行；就算首版无害，后续 `update` 新增 bundle 声明即静默扩权。小白无从分辨。
2. **诱导 patch**：群里流传的"解锁全权限教程"，一条 `cordis.patch.yml` 或环境变量 `DSH_PERMISSION_MODE=danger-full-access` 就拆掉全部护栏（后者还顺带关掉审批）。
3. **提示注入 → 自写插件**：浏览网页/读仓库时被注入，模型经 `cordis_define` 在"可逃逸的 vm"里写代码；用户面对激活弹窗大概率点同意，甚至双勾授权未来版本。
4. **API key 窃取**：注入让 agent `cat ~/.dsh/.credentials.yaml`——read-only 档都拦不住（只禁写不禁读），拿到的 key 直接经不限网络的出站请求外传。
5. **下载器攻击**：任意档位网络全开，`curl | sh` 无内容识别，无域名白名单。

## 9. 与 Codex CLI 的对比（迁移视角）

| 维度 | Codex CLI | dsh |
|---|---|---|
| 权限词汇 | 读/写/网络多轴，sandbox 档位含网络隔离 | **仅文件写效果**；网络、读取、进程均在词汇表外 |
| 沙箱 | 平台机制 + 网络隔离（依配置） | 文件写 ACL/Landlock/Seatbelt；Windows 自评 partial；**无网络隔离** |
| 扩展模型 | 配置文件 + MCP；MCP 进程独立 | **进程内插件，零隔离**，配置即代码（`!!js`→eval） |
| 供应链 | npm 包 + 官方源 | pnpm 转发 + GitHub 生态，无审核、无签名，升级即扩权 |
| 本地服务 | — | Web UI + 三重浏览器围栏（做得好） |
| 凭据 | — | 明文 yaml，官方承认挡不住模型 |
| 审计 | 会话记录 | 会话日志强（模型可见即记录），但无防篡改 |

结论：codex-safe-setup 的核心方法论（威胁模型 → 安全配置档 → 一键安装/回滚 → 体检脚本）**整体可迁移**，但 dsh 版的重点从"网络风险说明"（v0.1.1 的主题）转向**插件供应链与配置层替换**——因为那才是 dsh 真正敞开的门。

## 10. 对 codex-safe-setup 延伸的建议

1. **产品形态优先做"体检 + 指南"，插件化后置**：`Assess-CodexSafety` 的对应物（`dsh --dump-config` 巡检档位/审批/已装 bundle/allowBuilds/凭据权限）+ 中文保姆教程，比第三方安全插件更能触达小白（信任自举问题：经无审核渠道分发安全插件本身就是我们要防的攻击面）。
2. **利用 dsh 自己的机制做防御**：`tools/pre-execute` waterfall 是现成的拦截点（官方部署策略 TODO 仍空缺，`packages/shell/tool-bash/src/index.ts:6-7`）；home 级 `cordis.patch.yml` 可用来锁紧默认档；插件 API 可实现审批应答器 UI——但都应作为**建议部署的配置**而非仅是又一个插件。
3. **上策是推向上游**：向官方提 lockfile/commit-pin 安装默认、`dsh bundle` 变更需确认（堵"升级即扩权"）、凭据 OS 钥匙串化（官方已在 roadmap 语义上承认）。PR 比 fork 更能成为"小白路径上的默认安全选项"。
4. **Windows 用户特别注意**：Windows 沙箱是 partial 强制 + ACE 常设不撤销，而 dsh 的小白受众大量在 Windows——这正好是 codex-safe-setup（PowerShell、Windows 优先）的既有优势主场。

---

## 附：证据索引（主要条目）

| 结论 | 证据位置（相对 dsh 仓库根） |
|---|---|
| 三档定义与"网络不在词汇表" | `packages/sandbox/sandbox/src/index.ts:23-29` |
| 出厂默认 workspace-write + ask | `packages/bundle/base/cordis.patch.yml:172-191` |
| 审批封闭结果集/单次授权/fail-closed | `packages/sandbox/sandbox/src/escalation.ts:93,157-189`；`packages/interaction/user-approval/src/index.ts:304-344` |
| TUI 无审批应答方 | `.agents/notes/implemented/feature/2026-07-31-workspace-write-surface-default.md` |
| 所有档位允许全盘读 | `packages/fs/fs-sandbox/src/index.ts:6-7` |
| 无网络隔离（三平台） | `packages/sandbox/sandbox-local/src/profiles.ts:16-58`；`native/landlock-run/packages/entry/src/main.c:71-88`；`sandbox-windows-acl/src/index.ts:23-25` |
| Windows partial 强制/ACE 常设 | `packages/sandbox/sandbox-local/src/index.ts:177-187`；`sandbox-windows-acl/src/index.ts:10-15` |
| 无危险命令静态识别（官方 TODO） | `packages/shell/tool-bash/src/index.ts:6-7` |
| dsh plugin = pnpm 转发器 | `apps/cli/src/plugin.ts:120-133` |
| "安装时沙箱外执行"官方承认 | `docs/user/develop/basic/publish.md:173-178` |
| 插件加载零隔离 | `packages/boot/app-boot/src/index.ts:492-503,692-725`；`vendor/loader/src/config/entry.ts:280-282`（grep 无 worker/vm） |
| 升级即扩权 | `apps/cli/src/plugin.ts:59-91` |
| 配置即代码 | `vendor/loader/src/config/utils.ts:5-9` |
| vm 非遏制/双勾授权/纯 host 包免批 | `packages/extensions/cordis-host-runner/src/sandbox.ts:6-7`；`tool-cordis/src/prompt.ts:45`；`cordis-host-runner/src/index.ts:270-274` |
| "no sandbox row confines"（官方测试注释） | `apps/web/tests/shipped-composition.e2e.ts:30-33` |
| 权限管不住进程内栈（官方 postmortem） | `docs/postmortem/0002-js-expression-disabled-filesystem-tools.zh.md:21,47` |
| 浏览器信任围栏 | `packages/client/connection/src/api-request-trust.ts:96-123` |
| 凭据明文/挡不住模型（官方承认） | `packages/credentials/credentials-local/README.md:44-56` |
| MCP 进程在沙箱外 | `packages/mcp/mcp-client/src/transport.ts:10,18` |
| plugin-inventory 无来源追踪 | `packages/host/plugin-inventory/src/index.ts:56-69` |
| audit_* 工具不存在 | 全仓库 grep 零命中；CLI 仅 `plugin`/`web` 子命令 |
