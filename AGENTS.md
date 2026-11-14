# AgentBrew 项目规则

AgentBrew：基于上游 Let It Brew（ruban-24/letitbrew）的独立增强版。
两个核心目标，优先级不可交换：① 完整保留并增强 Mac 防睡眠/闭盖运行；② 新增多 Agent 统一监控（ZCode、WorkBuddy 国内/国际版、豆包 Z + 原版 9 个 Agent）。

## 必读入口

- `docs/BASELINE_AUDIT.md` — 项目基线：上游架构、必须保留的功能→源码映射、隔离改造点、风险（R1–R4）。
- `TASK_STATE.md` — 当前任务唯一入口。
- 上游文档：`docs/ARCHITECTURE.md`、`docs/AGENT-HOOK-CONTRACTS.md`（随上游保留，只读参考）。

## 硬性红线

1. **电源管理代码（Decision / PowerAssertions / DaemonHoldCoordinator / SleepWatchdog / PMSet / LidHold）原样复用，不重写、不绕过。**
2. 恢复 `SleepDisabled` 必须用记录的真实 prior 值，绝不硬编码 0。
3. 不得卸载/覆盖/修改官网版 `/Applications/Let It Brew.app` 及其数据；测试期一次只允许一个版本控制系统睡眠（互斥机制见 BASELINE_AUDIT R1）。
4. 不伪造任务进度；不可确认的状态显示 Unknown。
5. 不上传用户本地任务数据。
6. Hook 命令无条件 exit 0（fail-open 是上游故意设计）。

## 开发版身份（当前提案，如变更需同步全部隔离点）

| 项 | 值 |
|---|---|
| App 名称 | AgentBrew Dev |
| Bundle ID | `com.agentbrew.dev` |
| Daemon 标识 | `com.agentbrew.dev.daemon`（由 Bundle ID 派生，勿硬编码） |
| Hook marker | `__agentbrew_hook` / `__agentbrew_<agent>_hook` |
| 用户数据目录 | `~/Library/Application Support/AgentBrew/` |
| Daemon 状态目录 | `/Library/Application Support/AgentBrew/`（互斥检查读取官网版 `/Library/Application Support/LetItBrew/` 的活跃 debt，见 ForeignSleepHoldDetection.swift） |
| GitHub | origin = luluaterra/agentbrew（fork），upstream = ruban-24/letitbrew |

隔离改造点全清单：`docs/BASELINE_AUDIT.md` 第 4 节（10 处）。

## 命令

- 库代码测试（权威验证命令，本机实测全绿）：
  `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test --no-parallel`
  （需 swiftly 工具链 `~/.swiftly/bin`；`--no-parallel` 必须：Pi 扩展运行时测试在并行负载下会超其内部 spawn 超时，属上游测试负载敏感，非代码缺陷）。
- App/daemon/CLI：**仅 Xcode**（`xcodegen generate && xcodebuild`）。本机当前未装 Xcode（审计 R3）。
- 上游脚本：`scripts/` 下有构建/验证脚本，随上游保留。
- Git：开发在 `agentbrew/main` 分支；同步上游 `git fetch upstream && git merge upstream/main`。不 push 未经用户要求。

## 阶段纪律

按任务书七阶段推进：审计 → 分支 → 防睡眠验证（`docs/POWER_MANAGEMENT_TEST.md`）→ Agent 适配器 → UI → 集成测试 → 交付。
**防睡眠核心测试未通过，不得进入正式集成阶段。**
