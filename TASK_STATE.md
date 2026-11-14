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

### AB-003 环境缺口：Xcode 与签名身份（已解除）
- 状态：**已关闭**（2026-11-14）
- Xcode 27.2 已安装；Apple Development 证书（Personal Team `A7HHMGNNZ2`）已创建；WWDR G6 中间证书从 Xcode 内置资源补齐；Team ID 已填入 project.yml 与 BackgroundServiceEligibility（`1085399`）。
- 关键结论：免费 Personal Team **可以**注册 SMAppService daemon（注册失败的真因是 plist 二进制名错位，`3dafa41`）。

## 阻塞与风险

- 阶段三已完成（`e333139`）：防睡眠核心测试全部通过（A1-A4、B1/B2/B4/B5 实测，C 组单测覆盖），按任务书纪律可进入第四阶段正式集成。
- R1 残余：App 层互斥 UI 提示（第五阶段）；官网版 CLI watch 路径的 App 层检查（第五阶段）。
- R4 官网版运行中：全程只读，未触碰。
- 待验收项：AB-001（审计）、AB-002（隔离基座）、AB-401（ZCode 适配器）等待用户验收确认。

## 待评估（新想法池）

- 暂无。

## 第四阶段前置（AB-4xx，均已登记方案，待防睡眠验证解锁后实施）

### AB-401 ZCode 适配器（完整生命周期监控）
- 类型：主线开发 · 状态：**待验收**（代码完成 `a9c9af7`；真实 hook 已安装并部分验证 `0428f23`）
- 真机验证（2026-11-14，hook 已装入用户真实 `~/.zcode/cli/config.json`，原配置备份为 `config.json.pre-agentbrew-backup`）：
  - ✅ SessionStart/UserPromptSubmit hook 真实触发，记录写入 AgentBrew 隔离目录，tool=zcode、state=working
  - ✅ cwd 经 ZCODE_PROJECT_DIR 环境变量回退正确落盘
  - ✅ 会话进程退出后 status 正确过滤（不误保持唤醒）
  - ✅ 外来键（mcp/plugins）逐字保留；doctor 报 healthy
  - ⏸️ Stop/PreToolUse/PostToolUse/PermissionRequest 未验证：headless CLI 稳定报 authentication_error（凭据在桌面 app 侧）。**验证途径：用户在 ZCode 桌面 app 开一个新会话跑一轮任务，hook 即触发**
  - 测试基线：串行全量 923 项全绿（含 registry 隔离修复 +1）

### AB-403 豆包 Z：运行期观测已完成
- ✅ 三路数据源全部实证（2026-11-14 豆包运行中）：AgentInfraService XPC 常驻 + 每会话 `file_utils_host` 进程；`output.log` 心跳（1 小时内活跃）；`coding/snapshot` 11 个 execution（startedAt/endedAtMs 齐全）；`fileContents` 隐私红线确认存在
- 待办：按调研文档实现轮询适配器（不被阻塞，可与 AB-402 并行）

### AB-402 WorkBuddy 双版适配器（部分状态监控）
- 类型：主线开发 · 状态：**待验收**（核心完成 `89524f9`）
- 已实现：WorkBuddySource（双版一 schema，SQLite mode=ro + immutable 兜底）+ PollingSessionSynchronizer 镜像进统一 SessionStore；5 分钟新鲜度门（25 个陈旧 active 行真机验证不误 hold）；安装器合成健康报告；接入 App 每秒轮询。
- 遗留：真实活跃会话的菜单显示待用户跑一个 WorkBuddy 会话验证；Waiting 判定（audit-log needs-approval）未实现——当前 Unknown 如实呈现。

### AB-403 豆包 Z 适配器（部分状态监控）
- 类型：主线开发 · 状态：**待验收**（核心完成 `89524f9`）
- 已实现：DoubaoSource（coding/snapshot 最新快照轮询；字段缺失跳过降级；fileContents/output.log 零接触）+ 同一新鲜度门；真机验证 11 个 ended 执行全部正确静默。
- 遗留：真实运行任务的活体验证；人工保持唤醒开关（任务书要求的保守策略）留到第五阶段 UI。
