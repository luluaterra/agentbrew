# AgentBrew 当前任务

状态词汇：待评估 / 待办 / 进行中 / 阻塞 / 待验收。

## 主线

### AB-001 阶段一：上游源码审计与本机环境检查
- 类型：主线开发 · 状态：**待验收**
- 产出：`docs/BASELINE_AUDIT.md`（架构总览、必须保留功能→源码映射、状态机映射表、10 处隔离改造点、风险 R1–R4、本机环境、UI 层子审计）。
- 验收标准：覆盖任务书第一节审计清单（电源管理/闭盖/后台服务/XPC/Agent Hook/会话管理/状态机/菜单栏 UI）；隔离改造点与身份标识完整；环境缺口明确。
- 备注：审计基于上游 `0df676c`（v1.0.0 / build 45）。

### AB-002 阶段二：独立开发分支与隔离基座
- 类型：主线开发 · 状态：**待验收**
- 提交：`d07b6ca`（审计+记录）、`a7c3c5c`（身份隔离+R1 互斥，92 文件）。均未 push。
- 已完成：
  - Fork `luluaterra/agentbrew`；分支 `agentbrew/main`；remote：origin=fork、upstream=上游。
  - 身份参数化（BASELINE_AUDIT 第 4 节清单逐项落地）：
    - Bundle ID：Release `com.agentbrew` / Debug `com.agentbrew.dev`；daemon 标识随派生。
    - App 名称：Release "AgentBrew.app" / Debug "AgentBrew Dev.app"；EXECUTABLE_NAME `AgentBrew`。
    - CLI：二进制名 `agentbrew`；守护进程二进制 `AgentBrewDaemon`。
    - Hook markers：`__agentbrew_hook` / `__agentbrew_<agent>_hook`（9 个适配器）。
    - 数据目录：用户域 `~/Library/Application Support/AgentBrew/`；daemon 状态域 `/Library/Application Support/AgentBrew/`。
    - 更新/链接指向 `luluaterra/agentbrew`（无 Release 时检查自然失败，不会误更新到上游）。
    - 用户可见文案全量改名（Sources+Tests 中 "Let It Brew"→"AgentBrew"）。
    - 上游自有文件（Config/LetItBrew-Info.plist、上游 LaunchDaemon plist）保留原样，新建副本 `Config/AgentBrew-Info.plist`、`Config/LaunchDaemons/com.agentbrew(.dev).daemon.plist` 并由 project.yml 引用——降低上游合并冲突面。
  - **R1 电源互斥机制已实现**（`Sources/LetItBrewDaemonCore/ForeignSleepHoldDetection.swift` + DaemonHoldCoordinator 两层闸门 + 11 个新测试）：
    - acquire：检测到官网版活跃 sleep-debt 记录 → 拒绝接闭盖 hold（fail-closed，消息可行动）。
    - restore/reconcile：检测到官网版记录 → 延迟恢复（保留我方 debt，5 秒重试计时器在官网版释放后自动恢复真实 prior）。
    - 推演覆盖双向争夺场景（官网版先持/后持、重启对账、升级静默），终态一致恢复 0。
  - 测试：**串行全量 906 项（15+74+523+294）全部通过，0 失败**（权威命令见 AGENTS.md）。
- 待办：（第三阶段）防睡眠真实验证——前置 AB-003。
- 已知非阻塞项：
  - `piExtensionRuntimeDrivesIsolatedSessionStorage` 在全量并行运行时可能超时失败（mjs 内 5s 性能护栏在负载下超限），单测稳定通过；属上游测试负载敏感，非身份改动引起。验证以单测为准。
  - `scripts/*.sh`（发布/DMG/验证脚本）仍含上游名称，属第七阶段交付工具，暂不动。
  - `LETITBREW_TEST_HOME` 测试环境变量名保留（50 处引用，跨脚本，重命名收益低）。
  - 图标（AppIcon asset）仍为上游烧瓶图标，第五阶段 UI 时替换。

### AB-003 环境缺口：Xcode 与签名身份
- 类型：阻塞 · 状态：**阻塞**（需用户决策）
- 内容：① 完整 Xcode 未安装（App/daemon/CLI 无法构建，约 12GB）；② 开发版签名需带 Team ID 的证书：`project.yml` 的 `DEVELOPMENT_TEAM` 与 `BackgroundServiceEligibility.expectedTeamIdentifier` 已留空并标注 TODO(AB-003)，填入用户自己的 Team ID 前资格闸门按设计拒绝注册（fail-closed）。
- 附：本机已装用户级 Swift 6.4.2 工具链（swiftly）；`swift build/test` 需 `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`（CLT 27.0 SDK 的 tbd 与 6.4.2 工具链不兼容）。

## 阻塞与风险

- R1：互斥已实现（daemon 层）；App 层 UI 提示（检测到官网版时在 Closed Lid 设置给出说明）留到第五阶段 UI 任务。
- R1 残余面：官网版 CLI `watch --lid-closed`（osascript 看门狗路径，用户域租约）不受 daemon 层检查覆盖；App 层补充检查待第五阶段实现，当前文档记录。
- R2/R3：见 AB-003。
- R4 官网版运行中：全程只读，未触碰。

## 待评估（新想法池）

- 暂无。

## 第四阶段前置（AB-4xx，均已登记方案，待防睡眠验证解锁后实施）

### AB-401 ZCode 适配器（完整生命周期监控）
- 类型：主线开发 · 状态：**待办**（前置 AB-002 验收；唯一不受 AB-003 阻塞的适配器代码工作）
- 方案：hook 安装器写入 `~/.zcode/cli/config.json`（7 事件，`enabled:true` 必须），映射到 HookReducer；`Stop` 触发问题需真机实测。
- 调研：`docs/AGENT-INTEGRATION-RESEARCH.md` §1。

### AB-402 WorkBuddy 双版适配器（部分状态监控）
- 类型：主线开发 · 状态：**待办**
- 方案：一个适配器参数化 `~/.workbuddy` / `~/.workbuddy-ai` 双根目录；SQLite（复制后读）+ audit-log JSONL 轮询；锚定数据目录路径而非 Bundle ID。

### AB-403 豆包 Z 适配器（部分状态监控 + 人工保持开关）
- 类型：主线开发 · 状态：**待办**
- 方案：`index.json` + `coding/snapshot` + `output.log` 心跳轮询；Waiting 不可判 → Unknown + 人工保持唤醒开关（2h 失效保护，复用 MonitoringLease 模式）；隐私红线：不读 fileContents/output.log 正文。
