# BASELINE_AUDIT — 上游 Let It Brew 源码审计（AgentBrew 第一阶段）

- 审计对象：https://github.com/ruban-24/letitbrew ，克隆于 `0df676c`（"Prepare plain-English docs for 1.0.0 (#52)"，对应官网 v1.0.0 / build 45）。
- 审计日期：2026-11-14。
- 审计方法：精读全部核心源文件（Decision / PowerAssertions / Daemon* / SessionRecord / HookReducer / HookPayload / 签名与资格校验 / CLI），UI 层由独立子审计覆盖（见第 8 节），官方文档（ARCHITECTURE.md、AGENT-HOOK-CONTRACTS.md）与代码交叉核对。
- 结论：上游代码质量高、边界清晰、安全纪律严格。AgentBrew 的正确路径是**复用全部电源管理代码 + 参数化身份标识 + 新增 Agent 适配器**，不重写电源逻辑。

---

## 1. 系统架构总览

| Target | 形态 | 职责 | 构建方式 |
|---|---|---|---|
| `LetItBrewApp` | 菜单栏 App（LSUIElement） | 轮询/决策/UI/本地 IOKit assertion/daemon 生命周期管理 | **仅 Xcode**（`project.yml`，XcodeGen） |
| `LetItBrewAppCore` | SwiftPM 库 | App 侧策略与状态机（无 I/O） | swift build/test |
| `LetItBrewCore` | SwiftPM 库 | Hook、会话记录、电源原语、决策函数 | swift build/test |
| `LetItBrewDaemonCore` | SwiftPM 库 | XPC 协议、hold 协调、睡眠控制、签名 | swift build/test |
| `LetItBrewDaemon` | launchd root daemon | 唯一有权限写 `pmset disablesleep` 的进程 | **仅 Xcode** |
| `letitbrew` | CLI | agent hook 调用的 shim（hook/install/watch/status/…） | **仅 Xcode**（嵌入 App bundle） |

数据流（一次会话如何变成"保持唤醒"）：

```
agent 生命周期事件 → hook 调用 letitbrew hook <agent> <event>
  → HookPayload（stdin JSON）→ HookReducer.reduce → .set(working|waiting|idle) / .end
  → SessionStorage（每会话一个原子 JSON 记录，~/Library/Application Support/LetItBrew/sessions/）
  → App 每秒轮询 SessionStorage.loadAll()
  → Decision.decide(sessions, settings, power)   ← 纯函数，所有安全闸门所在
  → IOKitPowerAssertion（开盖，App 进程持有）
  → XPC setLidClosedHold → daemon `pmset disablesleep 1`（闭盖）
```

三种"保持唤醒"机制互不替代（PowerAssertions.swift:4-8 注释明确）：
1. **开盖**：`kIOPMAssertPreventUserIdleSystemSleep` / `kIOPMAssertPreventUserIdleDisplaySleep`，由 App 进程持有，App 崩溃自动释放。
2. **闭盖**：clamshell 睡眠**完全无视** IOKit assertion，唯一有效手段是系统级 `SleepDisabled`，仅特权进程可写 → daemon 的存在理由。
3. **显示器**：`pmset displaysleepnow`（闭盖且无外接屏时主动熄屏）+ display assertion。

---

## 2. 必须完整保留的功能清单（功能 → 源码映射）

### A. 电源状态决策引擎（最高优先级）
- `Sources/LetItBrewCore/Decision.swift` — `decide()` 纯函数（197-274 行）。优先级从高到低：
  1. `!power.trusted`（IOKit 读数失败）→ 释放，reason "battery state unknown"（**refuse-rather-than-guess 原则，绝不允许把读取失败当作"接电 100%"**）。
  2. `onlyWhileConnectedToPower && onBattery` → 释放。
  3. `onBattery && batteryPercent <= batteryFloor` → 释放（电池下限，默认 20%，范围 5–50）。
  4. `respectLowPowerMode && lowPowerModeEnabled && !lowPowerModeOwnedByLetItBrew` → 释放（App 自己为闭盖切的低电量不算用户选择）。
  5. thermal `.serious/.critical` → 释放（**温度保护是硬编码规则，不是设置项**）。
  6. 有 Working（含被 `WaitAnswerLatch.holdsAwake` 判为可能已应答的等待，剔除 `MonitoringLease` 过期租约）→ hold。**多会话联集：任意一个 Working 就 hold** —— 天然满足任务书"一个 Agent 等待、另一个 Working 仍保持唤醒"的要求。
  7. 无会话/全 waiting/全 idle → 释放，无宽限期。
- `MonitoringLease`（Decision.swift:280-319）：后台任务监控子状态的有界 hold（默认 2 小时），家族内任意 hook 续租。
- **结论：直接原样复用，不改一行。新增 Agent 的状态写入同一 SessionStore 后自动参与此决策。**

### B. 开盖 IOKit Power Assertion
- `Sources/LetItBrewCore/PowerAssertions.swift` — `IOKitPowerAssertion` 双槽位（system/display）。
- 关键纪律：幂等（每 tick 安全）；已持有仅原地改名不释放重建（90-110）；**只有确认 `IOPMAssertionRelease` 成功才清 `held`**，失败保留至下 tick 重试（111-123，防 assertion 泄漏）。
- 调用方：`LetItBrewAppModel`（`Sources/LetItBrewApp/LetItBrewAppModel.swift:335,2260-2267`），暂停/退出时释放。

### C. 闭盖运行（核心中的核心）
- App 侧：`Sources/LetItBrewApp/LetItBrewAppModel.swift` — `requestedLidHold` → XPC `setLidClosedHold`（2397-2451）；设置 `keepWorkingWithLidClosed`（默认 true）。
- 策略：`Sources/LetItBrewCore/LidHold.swift` — **"never clear what we did not take"**：系统级 flag 无法区分持有者，只归还自己拿的。
- Daemon 侧：`Sources/LetItBrewDaemonCore/DaemonHoldCoordinator.swift`
  - 多客户端 hold 联集（connectionID → holders 集合，249-320）。
  - **sleep-debt 崩溃恢复**：改 `disablesleep` 前先把真实旧值+时间戳写入 `/Library/Application Support/LetItBrew/<daemon标识>.sleep-debt.json`（acquire 262-303；reconcileDebt 465-512）。
  - **恢复铁律：恢复记录的真实 prior 值，绝不硬编码 0**（"An unreadable value is an error, never 0"）。unreadable 记录 + live=1 → 拒绝猜测所有权，保持 blocked。
  - `RunAtLoad` 启动即对账（daemon main.swift:184-208）；无客户端时 5 秒定时器重试失败的恢复（`startRestoreRetryTimer`，DaemonHoldCoordinator.swift:144-154）。
  - 连接断开自动释放（XPC invalidationHandler → connectionInvalidated）。
- 闭盖检测：`Sources/LetItBrewApp/LidCloseMonitors.swift:6-26` — 每秒轮询 IOKit registry `AppleClamshellState`（无通知注册）；外接屏判定 `CGDisplayIsBuiltin`（28-46）。
- 闭盖熄屏：`Sources/LetItBrewAppCore/LidCloseDisplaySleep.swift` 状态机（合盖边沿/最后一台外接屏断开 + 自己持有 lid hold 且无外接屏 → `pmset displaysleepnow`）。
- Low Power Mode（嵌套于闭盖 hold）：`setLowPowerModeHold`（DaemonHoldCoordinator.swift:322-396）；power-mode-debt.json 记录每电源源的真实 energy mode，按值恢复（键名随 macOS 改名自适应，402-463）；恢复失败**不阻断**闭盖 hold（低电量不可能阻止睡眠，方向相反）。App 仅在 `clamshell==.closed && 无外接屏` 时发起。
- **结论：整条链路原样保留。闭盖是任务书红线。**

### D. 电源安全与失败恢复
- 电源读数：`Sources/LetItBrewCore/PowerSource.swift` — `IOKitPowerSource`，桌面机空源列表=可信"接电 100%"，API 失败=`trusted:false`。
- pmset 解析：`Sources/LetItBrewCore/PMSet.swift` — `parseSleepDisabled`（缺失行=0，歧义=nil 拒绝）、`parsePowerModes`（冲突行=nil）。
- 睡眠看门狗（CLI `watch` 模式的后备路径，无 daemon 时）：`Sources/LetItBrewCore/SleepWatchdog.swift` — osascript root shell 循环、原子 mkdir 租约、pid+start-time 双重活性校验、修复前在特权 shell 内**重新推导**全部决策（防 TOCTOU）。`letitbrew watch`（WatchCommand.swift）与 `letitbrew repair` 使用。
- 手动暂停：`Sources/LetItBrewAppCore/LetItBrewPauseController.swift` — 持久化到 UserDefaults（`letitbrewPaused`），重启后不得静默恢复；paused 时三个 hold 全 false 但会话照常采集展示。

### E. 会话状态机与存储
- 状态：`SessionState` = working / waiting(存储名 `awaiting_input`) / idle（HookReducer.swift:4-18）。Detail 是语义 token，绝不存英文散文（`SessionWaitDetail`、`SessionWorkDetail`、`tool:<name>`）。
- 事件映射：`Sources/LetItBrewCore/HookReducer.swift:52-178`（完整映射表见第 4 节）。未知事件=无效果（不猜测）。
- 家族协调：`Sources/LetItBrewCore/HookSessionUpdater.swift`（351 行）— Claude/Codex 父子记录、family lock、terminal marker 防迟到子事件复活、`stale_child_cutoff` 清扫静默子会话。
- 存储：`Sources/LetItBrewCore/SessionRecord.swift` — `SessionStorage`：
  - 每会话一个原子 JSON；目录 `~/Library/Application Support/LetItBrew/sessions/`（386-399，**硬编码 "LetItBrew"，隔离改造点**）。
  - 有界 per-ID flock 锁（569-645）+ Claude/Codex 家族锁（501-508）。
  - 终态 tombstone：先提交到活动路径再移入 `.locks/` 隐藏目录，防旧事件复活已完成会话（536-567）。
  - 文件名白名单 + FNV-1a 摘要防碰撞/防路径逃逸（414-474）；不跟随符号链接；解码 id 必须能 sanitize 回文件名。
- 读取：`Sources/LetItBrewCore/SessionStore.swift` — `recent`(TTL 12h) + `excludingExitedAgents`（in-turn 且有 pid 的记录，进程退出则既不展示也不 hold）。
- Hook CLI 边界：`Sources/letitbrew/HookCommand.swift` — **无条件返回 0**（hook 在用户工作关键路径上，存储故障不能阻塞 agent）；fail-open 只丢事件，不绕过任何安全闸门。
- 进程谱系：`Sources/LetItBrewCore/ProcessAncestry.swift` — 穿过 shell 包装找到 agent 真实 pid（用于把 App 带到前台 + 判定输入归属 App；不影响 hold 本身，经 `excludingExitedAgents` 影响展示/hold）。

### F. 等待应答判定（Waiting 释放 hold 的配套）
- `WaitAnswerLatch`（Decision.swift:81-187）：Claude/Copilot/Gemini/Qwen 的 approval 应答不发 hook，靠本地输入（HID idle 计数器，无需权限）推断， answered 后按 Working hold。
- `Sources/LetItBrewAppCore/FrontmostInputAttribution.swift`：输入只归功于该会话自己的 App。
- `Sources/LetItBrewAppCore/OwnMenuInputFilter.swift`：本 App 菜单内的点击/按键不算应答。

### G. Agent Hook 安装体系（9 个适配器）
- 适配器：`ClaudeHooks.swift`（`~/.claude/settings.json`）、`ClaudeStyleHooks.swift`（Gemini `~/.gemini/settings.json`、Qwen `~/.qwen/settings.json` 共用风格）、`CodexHooks.swift`（`~/.codex/hooks.json` / `$CODEX_HOME`）、`CopilotHooks.swift`（`~/.copilot/hooks/letitbrew.json` / `$COPILOT_HOME`）、`CursorHooks.swift`（`~/.cursor/hooks.json`）、`KimiHooks.swift`（`~/.kimi-code/config.toml`）、`OpenCodePlugin.swift`（自有插件文件 `~/.config/opencode/plugins/letitbrew.js`）、`PiExtension.swift`（自有扩展文件 `~/.pi/agent/extensions/letitbrew.ts`）。
- 安装纪律（ClaudeHooks.swift:1-17 为代表，全体系共享）：
  1. `JSONSerialization` 而非 Codable（防丢用户配置键）；"文件不存在"≠"文件不可读"，后者拒绝而非覆盖。
  2. 绝对路径 CLI，永不 PATH 查找（防 app 删除后任意 PATH 上的同名二进制在每个 tool call 执行）。fallback 路径硬编码 `/Applications/Let It Brew.app/Contents/Helpers/letitbrew`（ClaudeHooks.swift:35，**隔离改造点**）。
  3. 冻结 marker：`__letitbrew_hook`（Claude）与 `__letitbrew_<agent>_hook`（其余）——发布的版本必须互相识别，改 marker 会孤儿化既有安装。
  4. uninstall 只摘自己的 marker 条目，保留其他工具的钩子原样。
  5. 不可解析的配置：报 Action needed，绝不重写。
- 注册表：`~/Library/Application Support/LetItBrew/agent-hook-targets.json`（版本化，记录每个 agent 实际选中的目标文件，防环境变量变化后重定向；`AgentInstallRegistry.swift`）。
- Codex 特殊：需要显式 `/hooks` 信任步骤；`CodexHookTrust`/`CodexTrustInspection` 处理。
- 事件超时 5s；hook 命令尾部有 ownership 哨兵注释（`HookFile.ownershipComment`），匹配用 `hasSuffix`。
- 测试环境变量：`LETITBREW_TEST_HOME` 重定向所有 agent 配置路径（main.swift）。

### H. XPC 安全模型（App ↔ daemon 双向认证）
- 协议：`Sources/LetItBrewDaemonCore/DaemonProtocol.swift` — 仅 4 个具名、可逆开关（protocolVersion / daemonHandshake / prepareForUpgrade / setLidClosedHold / setLowPowerModeHold），**故意不暴露任意命令执行面**。
- 客户端身份：`Sources/LetItBrewDaemonCore/RuntimeSigningIdentity.swift` — 读活代码对象签名（非路径），要求 Team ID 存在（缺失即拒绝启动），cdhash 精确到构建。
- 双向校验：
  - daemon 对每个新连接 `setCodeSigningRequirement(appIdentity.codeSigningRequirement)`（main.swift:129）——requirement 由 daemon 自己的签名**派生**（`anchor apple generic and certificate leaf[subject.OU] = <team> and identifier <id>`，RuntimeSigningIdentity.swift:197-201），dev/prod 无法互相伪装。
  - App 对 daemon：连接前校验内嵌 daemon 二进制签名 + 握手比对 marketing/build/cdhash（`LetItBrewDaemonBuildIdentity`），stale build 走受控升级路径。
- Daemon 标识 = App bundle identifier + `.daemon` 后缀（`appClientIdentity()`，RuntimeSigningIdentity.swift:188-195）；MachServiceName、LaunchDaemon plist、debt 文件名全部由此派生。**改 Bundle ID 即全链路一致隔离**。
- App 侧连接：`Sources/LetItBrewApp/DaemonConnection.swift`（握手 5s 超时、transport 错误保真、`DaemonHoldRequestState` 单 in-flight + connectionGeneration 防旧连接污染）。
- 服务资格闸门：`Sources/LetItBrewDaemonCore/BackgroundServiceEligibility.swift` — **App 必须位于 /Applications 且 bundle ID ∈ {com.ruban24.letitbrew, com.ruban24.letitbrew.dev}，且签名 Team ID == MV2UL94MDC**（10-12, 34-47）。任何 SMAppService 调用前必须过此闸。
- 恢复编排：`DaemonRecoveryPolicy/Coordinator/Integration` — 不读 `SMAppService.status`（有副作用），存在性只通过"询问已认证的 daemon 本身"建立。

### I. 更新与卸载（完整性保留，暂不改动）
- 一次性更新：staged + 验签 + 同卷原子替换，绝不覆盖运行中的已签名可执行文件；`prepareForUpgrade` 先对账并冻结 daemon。
- 卸载：三道硬闸（释放 hold → daemon 对账 → 注销 daemon）先于任何删除；其余步骤 best-effort 累积报告。

### J. CLI 完整命令面
`hook / install / uninstall / doctor / prepare-exact / watch [--lid-closed] / status [--json] / repair / --version`（Sources/letitbrew/main.swift）。

---

## 3. 状态机与事件映射速查

HookReducer.reduce（HookReducer.swift:52-178）关键映射：

| 事件 | 效果 | 备注 |
|---|---|---|
| SessionStart | idle（Claude 仅 source∈{startup,resume,clear}；其他 agent source=compact 时无效果） | 未 prompt 的会话不应长 hold |
| UserPromptSubmit / PostToolUse / SubagentStart | working | turn 开始 |
| PreToolUse | working；问题工具（AskUserQuestion 等）→ waiting(question) | detail=tool token |
| PostToolUseFailure | copilot→working；qwen 按是否 isInterrupt | |
| PermissionRequest | opencode/kimi→waiting(approval)；copilot 问题工具→waiting；claude/codex→无效果 | claude/codex 在决策前触发 |
| Notification | claude `permission_prompt`→waiting(approval)；qwen `permission_prompt`/gemini `ToolPermission`→waiting；copilot `permission_prompt`/`elicitation_dialog`→waiting；`idle_prompt`→idle | |
| UserInputRequested / UserInputResolved | opencode/pi（+kimi resolved）→ waiting/working | |
| Stop | idle；带 background_tasks/session_crons → working 监控子态（background-shell/background-agent/scheduled-tasks） | |
| StopFailure / ErrorOccurred(recoverable=false) | idle | |
| Interrupt | codex/kimi → idle | Esc 取消唯一钩子 |
| PreCompact / PostCompact | claude 手动 compact→idle，其余无效果 | |
| SubagentStop / SessionEnd | 删除记录（父 SessionEnd 级联删子） | |

**对 AgentBrew 新增适配器的意义**：统一事件模型已经存在（即任务书第五节的统一事件清单），新 Agent 只需把自身生命周期事件映射到这套词汇表，写入同一 SessionStore，即自动获得全部决策/安全/展示能力。允许部分映射：映射不到的事件返回 nil 即可，状态如实展示（不可确认=不冒充）。

---

## 4. 隔离改造点清单（开发版 AgentBrew 必改的身份标识）

| # | 位置 | 当前值 | 改造方向 |
|---|---|---|---|
| 1 | `project.yml`（Release/Debug bundle ID、daemon label、plist） | `com.ruban24.letitbrew(.dev)` | AgentBrew 独立 Bundle ID（如 `com.agentbrew.dev`）；daemon 标识随 Bundle ID 派生，全链路自动一致 |
| 2 | `BackgroundServiceEligibility.swift:10-12` | 上游两个 ID + Team `MV2UL94MDC` + `/Applications` 路径 | 改为 AgentBrew 的 ID/Team/路径白名单（App 名称也要改，路径判定需同步） |
| 3 | `ClaudeHooks.fallbackCLIPath`（ClaudeHooks.swift:35）及各适配器 fallback | `/Applications/Let It Brew.app/...` | AgentBrew.app 路径 |
| 4 | `SessionStorage.applicationSupportDirectory`（SessionRecord.swift:394） | `~/Library/Application Support/LetItBrew/` | AgentBrew 独立数据目录（含 sessions/ 与 agent-hook-targets.json） |
| 5 | daemon 状态目录（main.swift:164-175） | `/Library/Application Support/LetItBrew/`（debt 文件名已按 daemon 标识区分） | 独立目录或沿用（文件名已隔离）——见第 5 节互斥设计 |
| 6 | Hook markers（`__letitbrew_hook` 等） | 冻结 | 开发版必须用**新 marker**（如 `__agentbrew_hook`），否则两版会在同一配置文件里互相 sweep/识别 |
| 7 | `DaemonHoldCoordinator.swift:148` 重试队列名 `com.ruban24.letitbrew.restore` | 硬编码 | 随新 Bundle ID |
| 8 | UserDefaults domain | 随 Bundle ID（自动隔离） | 无需改动，确认即可 |
| 9 | App 名称/图标/URL scheme/CLI 帮助文本 | "Let It Brew"/letitbrew | AgentBrew Dev / agentbrew |
| 10 | `ONE-CLICK 更新`相关（Updater 指向上游 Release） | 上游 GitHub Release | 开发版禁用或指向自己的仓库（避免误更新到上游正式版） |

**Hook 并存可行性**：两版各自的 marker 不同 → 可在同一 agent 配置文件中共存（Claude 会同时执行两套 hook 命令，各写各的 sessions 目录）。但**电源控制不可并存**，见下节。

---

## 5. 关键风险与设计约束（进入第二阶段前必须解决）

### R1. 双应用 `disablesleep` 争夺（任务书明确要求互斥机制）
官网版 daemon 与 AgentBrew daemon 都会写同一个系统级 `SleepDisabled`。灾难场景：官网版记录 prior=0 后置 1；AgentBrew daemon 读到 1 当作自己的 prior 记录；官网版释放恢复 0；AgentBrew 释放时"恢复"到它记录的 1 → Mac 永久不睡。
上游架构本身把 `disablesleep` 视为**单全局资源**（LidHold："never clear what we did not take" 正是为无法区分持有者设计的）。可行的互斥方案（第二阶段设计，倾向 A）：
- **A. 数据目录级互斥锁**：两个 daemon 共用 `/Library/Application Support/LetItBrew/`（文件名已按 daemon 标识隔离），AgentBrew daemon 在 acquire 前检查是否存在**任何其他** `.sleep-debt.json` 活跃记录，存在则拒绝接 hold（fail-closed），并在 App UI 提示"检测到官方版正在控制闭盖睡眠"。
- B. Advisory 锁文件（mkdir 原子锁，SleepWatchdog 的租约模式）：持有闭盖控制权的 daemon 持有租约目录，另一个 daemon 探测到即拒绝。
- 无论哪种：**测试期一次只允许一个版本实际控制系统睡眠**（任务书第六节），开盖 assertion 路径互不影响（各 App 各自的 assertion，可并存）。

### R2. 签名 Team ID（开发版构建的硬约束）
- `RuntimeSigningIdentity.validatedCode` 强制要求签名含 Team ID（`missingTeamIdentifier` 即退出，RuntimeSigningIdentity.swift:119-121）；XPC requirement 用 `anchor apple generic`（拒绝 ad-hoc 签名）。
- 本机无 Xcode、签名身份未知。开发版需要：用户自己的 Apple 开发证书（免费 Personal Team 的 development 证书也带 Team ID，可满足本地 `anchor apple generic` 链；无需付费账号即可本地开发验证，但无法公证/分发）。**需在第三阶段前与用户确认签名身份**。
- 同时 `BackgroundServiceEligibility` 的 Team ID 白名单要加入用户自己的 Team ID。

### R3. 构建依赖
- `swift build` 当前失败：本机 CLT 26.6.0 的 SwiftPM 组件 dyld 符号缺失（`swift-package` 引用的 `BuildServerProtocol` framework 版本错配）——**工具链损坏，非代码问题**。
- App/daemon/CLI 三个 target 只有 Xcode 能编（project.yml + XcodeGen）。本机未装 Xcode。**完整交付需要安装 Xcode（约 12GB）**，或至少 Xcode + CLT 组合。
- 已启动用户级 Swift.org 工具链安装（swiftly）以先行恢复 `swift build`/`swift test` 验证能力；结果待验证。

### R4. 官网版在运行中（隔离红线）
- `/Applications/Let It Brew.app` v1.0.0 (build 45) 正在运行。审计期间全部操作为只读。开发版安装/测试阶段不得卸载/覆盖官网版，不得动它的 `/Library/Application Support/LetItBrew/` 记录。

---

## 6. 本机环境检查结果（2026-11-14）

| 项目 | 状态 |
|---|---|
| 官网版 Let It Brew | `/Applications/Let It Brew.app`，`com.ruban24.letitbrew` v1.0.0 (45)，min macOS 14，**运行中** |
| 守护进程 | `/Library/PrivilegedHelperTools` 无 brew 相关条目；`launchctl` 仅见 App 进程（daemon 经 SMAppService/launchd 管理，探测以询问 daemon 本身为准——上游明确不读 SMAppService.status） |
| macOS / 机器 | darwin 25.6.0 arm64（macOS 26），Swift 6.3.3 driver 可用 |
| Xcode | **未安装**（仅 CLT 26.6.0；CLT SwiftPM 组件损坏） |
| git / gh | git 2.50.1；gh 已登录 `luluaterra`（repo/workflow scope，可 Fork） |
| ZCode | ZCode.app 已装（`~/.zcode` 存在，PATH 无 CLI——监控适配器需另行调查其 Hook/事件机制） |
| WorkBuddy | `WorkBuddy.app` 与 `WorkBuddy AI.app` 两个 bundle 并存（对应国内版/国际版，待版本与数据位置调查） |
| 豆包 | `Doubao.app` 与 `豆包浏览器.app` 已装（豆包 Z 监控目标） |
| 其他 Agent CLI | PATH 中仅 `codex`（~/.local/bin）；claude/opencode/gemini/qwen/kimi/copilot/pi/cursor-agent 均不在 PATH（对应 CLI 未装或以其他形态安装，适配器开发前需逐个确认） |

---

## 7. 新增监控目标接入方式评估（初步，第四阶段详查）

上游产品边界（AGENT-HOOK-CONTRACTS.md:3-8）明确"只观察本地 lifecycle hooks，不枚举进程/不解析对话"。新增四个目标必须先调查其 Hook/IPC 能力：

1. **ZCode**：本机即为 ZCode 运行环境（hooks、`~/.zcode`、session 文件结构可直接调查）。预期可用官方 Hook（SessionStart/UserPromptSubmit/PreToolUse/PostToolUse/Notification/Stop 等 Claude 风格体系）→ 完整生命周期监控。
2. **WorkBuddy 国内版 / 国际版**：两个 bundle，需调查 Bundle ID、本地数据目录、是否有 hook/CLI/IPC；无可靠 hook 时按任务书第四节用"会话元数据/事件文件监听"做部分状态监控，如实标注监控级别。
3. **豆包 Z**：GUI 应用，预期无 hook；调查本地会话/日志文件与可达 IPC；最多做到部分状态监控 + 保守防睡眠策略（带失效保护）。

---

## 8. UI 层审计摘要（子审计已完成，要点）

- 启动：`LetItBrewMenuBarApp`（@main）→ `LetItBrewBootstrap`（NSApplicationDelegate）+ `LetItBrewAppModel`（init 409-511：存储/断言/监控器/设置迁移/agent 连接迁移/启动轮询与 daemon 恢复）。普通 GUI 与命令行模式经 `LetItBrewLaunchMode` 分流。
- 轮询：固定 1s（AppModel:1284-1291）；`pollOnce` 采集 sessions+power+clamshell+display+input 快照 → `applyVisibleSnapshot`（2196-2336）组装 Settings → `SessionStore.excludingExitedAgents` → `decide()` → `pauseController.resolve` → 本地 assertion + `synchronizeDaemonHold`（2s 超时）→ 健康检查（hold 中 5s/释放后 15s）。
- 设置项全集（UserDefaults）：General（launchAtLogin 等）/ Agents（`connectedAgentIDsV2`）/ Power（`onlyWhileConnectedToPower` 默认 false、`batteryFloor` 默认 20、`respectLowPowerMode` 默认 false、`allowDisplaysToSleep` 默认 true）/ Closed Lid（`keepWorkingWithLidClosed` 默认 true、`useLowPowerModeWithLidClosed` 默认 true）/ 暂停（`letitbrewPaused`）。
- 菜单栏：烧瓶图标（awake 有液面）+ 主状态 + 电池行 + 会话板（Waiting 单列一节，多会话按项目目录分组、单选展开）+ 行点击 `SessionHostActivator` 前台激活 + Stop Tracking（`sessionTrackingSuppressionsV1`）。
- App/daemon 职责边界：App 持有——会话事实来源（只读）、本地 assertion、全部设置、hook 安装（经 embedded helper）、SMAppService 注册、决策函数；daemon 持有——`pmset disablesleep`、低电模式切换、debt 记录与启动对账。
- 完整清单（含逐项文件:行号）已核对，作为第五阶段 UI 扩展的基线：**新增监控 UI 必须保留 General/Agents/Power/Closed Lid 四个设置区与现有菜单结构**。

---

## 9. 结论与下一步

1. 上游所有电源管理、闭盖、daemon、XPC、hook 机制**全部原样保留**，AgentBrew 以"身份参数化 + 适配器扩展 + UI 扩展"方式开发，禁止重写电源路径。
2. 隔离靠新 Bundle ID 全链路派生 + 新 hook marker + 独立数据目录；**电源互斥机制（R1）在第二阶段设计并先于任何双版本并行测试实现**。
3. 环境缺口：Xcode 未装（R3）、签名身份待确认（R2）——进入第三阶段（防睡眠验证）前需要用户决策。
4. 下一步（第二阶段）：Fork 仓库（gh，luluaterra）→ 建立独立分支 → 身份参数化改造 → 防睡眠基线验证（docs/POWER_MANAGEMENT_TEST.md）。
