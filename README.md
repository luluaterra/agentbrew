# AgentBrew

基于开源项目 [Let It Brew](https://github.com/ruban-24/letitbrew)（上游 README 见 [docs/UPSTREAM-README.md](docs/UPSTREAM-README.md)）的独立增强版。

**两个核心能力**：

1. **Mac 防睡眠**：本地 AI Agent 工作时自动保持 Mac 唤醒，结束自动恢复；支持合盖运行（通过特权 daemon 写 `pmset disablesleep`，恢复时使用记录的真实系统状态，绝不猜测）。
2. **多 Agent 统一监控**：菜单栏面板实时显示每个 Agent 的会话、任务标题、运行时长与状态（工作中/等待/空闲），多会话按项目分组。

## 支持的 Agent

| 接入方式 | Agent |
|---|---|
| 生命周期 Hook（完整监控） | Claude Code、Codex、OpenCode、GitHub Copilot CLI、Pi、Cursor、Gemini CLI、Qwen Code、Kimi Code、**ZCode** |
| 自有数据轮询（部分监控） | **WorkBuddy（国内版）**、**WorkBuddy AI（国际版）**、**豆包 Z** |

轮询型适配器只读各应用自己的会话存储（SQLite/JSON 快照），带 5 分钟新鲜度门——应用退出留下的陈旧行不会被误判为工作。

## 隐私边界

- 只读生命周期元数据（会话 ID、状态、工作目录、时间戳、任务标题）
- 不读对话内容、模型输出、工具输出、文件内容（豆包的 `fileContents` 快照字段零接触）
- 不上传任何数据；后台助手仅在本地运行

## 构建与运行

要求：Xcode 15+（本机实测 Xcode 27.2）、Apple 开发证书（免费 Personal Team 即可）。

```bash
# 1. 生成工程并构建（Debug，本机签名自动静默）
xcodegen generate
xcodebuild -scheme LetItBrew -configuration Debug build

# 2. 安装到 /Applications 并保持 daemon 一致（零密码，daemon 变化时才需一次授权）
scripts/reinstall-dev.sh            # 日常改动
scripts/reinstall-dev.sh --clean    # plist/资源结构变化后

# 3. 首次使用：菜单栏烧瓶图标 → 设置 → Agents 页打开要监控的 Agent；
#    Closed Lid 页的 Repair Helper 注册特权 daemon（会弹一次管理员授权）
```

库代码测试：`SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test --no-parallel`

## 安装与卸载

- **安装**：把构建产物拖入 `/Applications`，首次启动后在设置里连接 Agent；闭盖功能需要注册后台助手（应用内一键）
- **卸载**：设置 → 关于 → Uninstall——会先释放保持唤醒、注销后台服务、清理数据目录，之后才移除 App（顺序有硬闸保证，不会让 Mac 卡在无法睡眠的状态）

## 与上游的关系

- 上游电源管理代码（决策引擎、IOKit assertion、daemon、睡眠看门狗）**原样复用**，未重写
- 隔离方式：独立 Bundle ID（`com.agentbrew(.dev)`）、hook marker（`__agentbrew_*`）、独立数据目录；与官网版 Let It Brew 可并存——daemon 层内置互斥检查（`ForeignSleepHoldDetection.swift`），两个版本不会争夺系统睡眠状态
- 上游更新：`git fetch upstream && git merge upstream/main`

## 文档

- [`docs/BASELINE_AUDIT.md`](docs/BASELINE_AUDIT.md) — 上游架构审计、必须保留功能清单、隔离改造点
- [`docs/POWER_MANAGEMENT_TEST.md`](docs/POWER_MANAGEMENT_TEST.md) — 防睡眠功能实测记录（全部通过）
- [`docs/AGENT-INTEGRATION-RESEARCH.md`](docs/AGENT-INTEGRATION-RESEARCH.md) — 四个新增目标的接入调研
- [`docs/AGENT-HOOK-CONTRACTS.md`](docs/AGENT-HOOK-CONTRACTS.md) — 各 Agent hook 事件契约（上游文档）
- [`docs/UPSTREAM-README.md`](docs/UPSTREAM-README.md) — 上游原 README
