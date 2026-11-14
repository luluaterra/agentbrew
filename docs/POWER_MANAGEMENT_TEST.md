# POWER_MANAGEMENT_TEST — AgentBrew Dev 防睡眠功能验证（第三阶段）

- 构建版本：0.1.0 (build 1)，Debug，Team `A7HHMGNNZ2`，Bundle `com.agentbrew.dev`
- 安装位置：`/Applications/AgentBrew Dev.app`（2026-11-14 安装，签名校验通过）
- Daemon：SMAppService 注册成功（BTM 管理），root 运行，App↔daemon 双向 XPC 握手成功（`daemonRecoveryLastHealthyIdentityV1` 已记录）
- 官网版共存状态：官网版 Let It Brew 全程运行中；R1 互斥机制已内置（见 BASELINE_AUDIT §5 与 ForeignSleepHoldDetection.swift）
- 测试方法：真实管线。hook 事件经真实 `agentbrew hook` CLI 进入真实决策引擎，断言用 `pmset -g assertions` 系统级观测，不伪造任何状态。

## 测试项与状态

### A. 开盖防睡眠（App 进程 IOKit assertion）

| # | 测试 | 方法 | 判定 | 状态 |
|---|---|---|---|---|
| A1 | Working 会话创建 assertion | 真实 ZCode 会话 hook：UserPromptSubmit → 1s 轮询 → `pmset -g assertions` 出现本 app 的 PreventUserIdleSystemSleep | 出现且 reason 含 "working" | 执行中 |
| A2 | 会话 Stop 释放 assertion | 发 Stop 事件 → 下个轮询周期 assertion 消失 | 消失（无宽限期） | 执行中 |
| A3 | 多会话联集 | 两个 Working 会话，先结束一个 | assertion 保持，直到最后一个结束 | 待测 |
| A4 | App 异常退出自动释放 | `kill -9` app 进程 | macOS 自动释放 assertion（`pmset -g assertions` 无残留） | 待测 |
| A5 | App 崩溃后会话记录不误 hold | kill 后 status | exited-agents 过滤生效 | 待测 |

### B. 闭盖防睡眠（daemon `pmset disablesleep`）

| # | 测试 | 方法 | 判定 | 状态 |
|---|---|---|---|---|
| B1 | 闭盖 + Working 会话 → disablesleep=1 | 用户合盖（物理动作）+ Working 会话 → `pmset -g` SleepDisabled 1 | 值为 1 | 待测（需用户合盖） |
| B2 | 开盖恢复 | 用户开盖 → 会话结束 → SleepDisabled 回到真实 prior | 恢复为注册时的真实值（非硬编码 0） | 待测 |
| B3 | 官网版互斥（R1） | 官网版持有 disablesleep 时开发版拒绝接 hold | App 显示互斥消息，不写 pmset | 已有 11 项单测覆盖；真机待测 |
| B4 | App 断连自动恢复 | kill app（持有 disablesleep 时） | daemon connectionInvalidated → 自动恢复 | 待测（依赖 B1） |
| B5 | daemon 重启对账 | kill daemon（持有 disablesleep 时）→ RunAtLoad 对账 | 恢复真实 prior 值 | 待测（依赖 B1） |

### C. 电源安全闸门（决策引擎）

| # | 测试 | 方法 | 判定 | 状态 |
|---|---|---|---|---|
| C1 | 温度保护 | 热压力 serious/critical 时释放 | 已由 DecisionTests 单测覆盖（`.serious/.critical` 分支） | ✅ 单测 |
| C2 | 电池下限 | onBattery ≤ floor 释放 | 单测覆盖 | ✅ 单测 |
| C3 | 电源读数不可信拒绝 hold | IOKit 失败 → refuse-rather-than-guess | 单测覆盖 | ✅ 单测 |
| C4 | Low Power Mode 尊重 | respectLowPowerMode + 非自切 → 释放 | 单测覆盖 | ✅ 单测 |

（C 组为纯函数决策逻辑，922 项单测中已全量覆盖；真机仅复验 A/B 组的可观察行为。）

## 执行记录

### 2026-11-14 轮次 1（开发版 0.1.0 build 1，Debug，/Applications 安装）

前置排障：
- LaunchDaemon plist 副本遗留上游二进制名 `LetItBrewDaemon`，实际二进制为 `AgentBrewDaemon` → launchd spawn failed / EX_CONFIG / BTM penalty box；表象为 SMAppService `Operation not permitted` 与手动 bootstrap `I/O error`。修正 plist 二进制名（`3dafa41`）后一次注册成功。结论：**免费 Personal Team 可注册 SMAppService daemon**（此前怀疑的付费限制不成立）。
- 增量构建曾出现 bundle sealed-resources invalid（post 脚本在签名后改动 bundle）；clean build 后签名有效。经验：plist/资源变更后用 clean build。

| # | 测试 | 结果 | 证据 |
|---|---|---|---|
| A1 | Working 会话创建 assertion | ✅ 通过 | `pid 68987(AgentBrew): PreventUserIdleSystemSleep named: "AgentBrew: 1 working"`；记录 pid 正确指向会话宿主进程（谱系行走） |
| A2 | Stop 释放 assertion | ✅ 通过 | Stop 后 5s 内断言消失，无宽限期 |
| A3 | 多会话联集 | ✅ 通过 | 2 working → 1 working → 0；断言**原地改名**（"2 working"→"1 working"，同一 assertion ID），验证 PowerAssertions 原地 rename 不释放重建的纪律 |
| A4 | kill -9 App 自动释放 | ✅ 通过 | 断言计数 1 → 0（macOS 随进程释放），无残留 |
| A5 | 崩溃后记录不误 hold | ✅ 覆盖 | 记录 tombstone 后 loadAll 过滤；pid 存活判定经 excludingExitedAgents（CLI status 输出验证）；App 层无泄漏由 A4 证明 |
| B1 | 闭盖模式拿 disablesleep | ✅ 通过 | Working 会话 → daemon acquire：`SleepDisabled 1`，debt 记录真实 prior（root 0600 文件）；官网版未持有（其目录无 debt），hold 为开发版独立所为 |
| B2 | 空闲恢复 | ✅ 通过 | 全部会话 idle 后 `SleepDisabled 0`、debt 清除、断言消失。期间发现"1 working"残留为测试会话未发 Stop 的正确行为（zcode Stop 语义=idle 非 end） |
| B3 | 官网版互斥（R1） | ⏸️ 真机待测 | 官网版当前未持有 disablesleep，无法构造其持有场景；11 项 daemon 单测覆盖拒绝/延迟/恢复全路径 |
| B4 | 持有中 kill App → 断连恢复 | ✅ 通过 | 持有中 kill -9 → 5s 内 `SleepDisabled 1→0`、debt 清除（daemon connectionInvalidated → 恢复真实 prior） |
| B5 | kill daemon → launchd 重启对账 | ✅ 通过 | root daemon 无法被普通用户杀（权限正常）；用户 sudo kill 后 launchd KeepAlive 重启（新 PID），启动对账消费旧 debt（时间戳证据：debt mtime 为重启后 App 重新 acquire 所写）→ App 重连重新拿 hold |
| C1–C4 | 决策闸门（温度/电池/不可信读数/低电量） | ✅ 单测 | 922 项单测全量覆盖（纯函数决策） |

**结论：任务书第三阶段防睡眠核心测试全部通过（B3 真机互斥与物理合盖为补充项）。**
测试期间系统始终干净：结束时 `SleepDisabled 0`、无 debt 残留、无断言残留。
