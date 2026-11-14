# AGENT-INTEGRATION-RESEARCH — 四个新增监控目标接入调研（第四阶段前置）

调研日期：2026-11-14。方法：本机只读检查（bundle 元数据、数据目录结构、schema 字段名、进程/端口观测、官方内置文档线索），未读取任何对话/聊天正文。上游 9 个 Agent 的 hook 契约见 `docs/AGENT-HOOK-CONTRACTS.md`（随上游保留）。

结论速览：

| 目标 | 本机版本 | 接入评级 | 主数据源 | 风险 |
|---|---|---|---|---|
| **ZCode** | app 3.18.2 / 引擎 0.17.1 | **完整生命周期监控**（hook 可用） | `~/.zcode/cli/config.json` hooks（7 事件） | 无官方 Stop 触发报告（第三方 issue，需实测） |
| **WorkBuddy 国内版** | 5.9.3 (`com.tencent.workbuddy.mac`) | **部分状态监控** | `~/.workbuddy/workbuddy.db` + audit-log JSONL | schema 演进快；Waiting 落盘信号不全 |
| **WorkBuddy 国际版** | 5.9.4 (`com.workbuddy.workbuddy-ai`) | **部分状态监控**（同一适配器） | `~/.workbuddy-ai/`（结构逐项同国内版） | 同上 |
| **豆包 Z** | Doubao 2.36.8 | **部分状态监控**（轮询+保守策略） | `background_history_task/index.json` + `coding/snapshot` + output.log 心跳 | 高（内部无契约，周更节奏） |

---

## 1. ZCode — 完整生命周期监控（第一优先）

### 关键事实
- 引擎：`/Applications/ZCode.app/Contents/Resources/glm/zcode.cjs`（Node bundle，引擎版本 0.17.1）；桌面 app 为 Electron 壳（`dev.zcode.app`）。
- **Hook 体系与 Claude Code 同构**：事件恰为 7 个——`SessionStart`、`UserPromptSubmit`、`PreToolUse`、`PermissionRequest`、`PostToolUse`、`PostToolUseFailure`、`Stop`。**不支持** `Notification`、`SubagentStop`、`PreCompact`。
- 配置：用户级 `~/.zcode/cli/config.json` 顶层 `hooks` 键；工作区级 `<repo>/.zcode/config.json`。结构 `{"hooks": {"enabled": true, "timeoutMs": 60000, "events": {...}}}`。
- **坑：配置文件 hook 必须显式 `"enabled": true`，默认禁用**（插件贡献的 hook 才自动启用）。
- stdin JSON（Claude 兼容字段）：`hook_event_name`、`session_id`、`cwd`（经 `ZCODE_PROJECT_DIR`/`CLAUDE_PROJECT_DIR` 环境变量）、工具事件附 `tool_name`/`tool_input`；`Stop` 附 `last_assistant_message`；`PostToolUseFailure` 附 `error`/`is_interrupt`；`PermissionRequest` 附 `permission_suggestions`。
- 会话↔PID：SQLite `session_runtime_presence`（`session_id` / `process_id`），兜底 `lsof` 读 `zcode-cli` 进程 cwd。
- 进程形态：`ZCode.app` → `zcode-host-local-1` → 每会话一个 `zcode-cli` 长驻进程。
- 本机现状：`~/.zcode/cli/config.json` 无 `hooks` 键（未启用）。

### 适配器映射（→ HookReducer 词汇表）
| ZCode 事件 | HookReducer 效果 |
|---|---|
| `SessionStart` | `.set(.idle)`（source `compact` 时无效果——与 Claude 同规则） |
| `UserPromptSubmit` / `PostToolUse` | `.set(.working)` |
| `PreToolUse` | 问题工具（如 `AskUserQuestion`）→ `.set(.waiting, question)`；其余 `.set(.working, tool:<name>)` |
| `PermissionRequest` | **`.set(.waiting, approval)`**——ZCode 在此事件上比 Claude 更可靠（Claude 的该事件不证明弹窗存在） |
| `PostToolUseFailure` | `.set(.working)`；`is_interrupt` 时 `.set(.idle)`（Qwen 同款规则） |
| `Stop` | `.set(.idle)`（无 background_tasks 概念——ZCode 无该 payload 字段） |
| 生命周期结束 | `Stop` 后由 `session_runtime_presence` 行消失（进程退出）佐证；无 `SessionEnd`/`SubagentStop` |

差异与注意：
1. 无 `SubagentStop`/`Notification`：子 agent 无独立终止事件 → 不启用子会话记录（parent-only），`session_id` 直接用 `sess_<uuid>`。等待应答不发 hook 的问题不存在——`PermissionRequest` 的应答即 `PostToolUse`/后续事件。
2. hook 必须快速执行（内联阻塞会话）：沿用上游 fail-open 哨兵 + 5s 超时模式。
3. 兜底（未装 hook 时）：轮询 `~/.zcode/cli/db/db.sqlite` WAL（`tool_usage.status='running'`、`turn_usage`）——只读打开，WAL 模式下用 immutable/复制后读策略。
4. ZCode 自带 `keepAwakeWhileRunning` 设置（本机 False）：AgentBrew 与其互补，文档说明即可，无冲突。

### 风险
- 第三方报告称某些版本 `Stop` hook 注册后不触发（[ai-memory#512]），需在真实会话中实测（第四阶段验证项）。

## 2. WorkBuddy（国内 + 国际）— 部分状态监控（第二优先）

### 关键事实
- **同一代码库双发行**：Electron 37.10.3，内嵌 CodeBuddy Code CLI（`@genie/agent-cli` 2.165.0，入口 `cli/dist/codebuddy-lite-wb.mjs`）。国内版 URL scheme `workbuddy`，国际版 `workbuddy-ai`。
- 数据根：国内 `~/.workbuddy/`，国际 `~/.workbuddy-ai/`，**结构逐项一致** → 一个适配器参数化根目录。
- 核心 SQLite：`workbuddy.db`（Drizzle ORM，WAL）。`sessions` 表：`id, cwd, title, status(active|completed|error), created_at, last_activity_at, permission_mode, transport(local|cloud), unread…`。**无 waiting 状态值**。
- 审计链：`audit-log/YYYY-MM-DD.jsonl`（哈希链），`eventType` 含 `file-safety.needs-approval` / `file-safety.ask-matched` / `command-safety.sandbox-executed` 等。
- 进程指纹：daemon fork + 预热 CLI 进程池（`ps` 匹配 `codebuddy-lite-wb.mjs`）；运行时 IPC `wbipc/endpoint.json` + `b-*.sock`（0700，nonce 认证——第三方接入未确认）。
- **Hooks 机制存在（CLI 内部有 SessionStart/PreToolUse/PostToolUse 事件名）但落盘配置位置未确认**——两版 settings.json 均无 hooks 键。
- 更新器直接替换 /Applications bundle；Bundle ID 已迁移过一次（`com.workbuddy.workbuddy` → 现两个）→ 监控锚定**数据目录路径**而非 Bundle ID。

### 状态映射
| AgentBrew 状态 | 判定信号 | 可靠性 |
|---|---|---|
| Working | `sessions.status='active'` 且 `last_activity_at` 更新；audit-log 新增 sandbox-executed；`traces/<pid>/` 增长 | 高 |
| Waiting（审批） | audit-log 出现 `file-safety.needs-approval`/`ask-matched`（时刻可判）；**解除时刻无落盘信号** | 中 |
| Waiting（等待输入） | 无落盘信号（未确认） | 不可判 → 显示 Unknown |
| Completed | `sessions.status='completed'`（+`unread`） | 高 |
| Error | `sessions.status='error'` | 高 |
| 兜底 | `wbipc/endpoint.json` 存在 + `ps` 匹配 CLI 进程 | 低分辨率 |

### 实现要点
- SQLite WAL：运行期只读用"复制后读"或 `?mode=ro&immutable=0` 探测；轮询间隔 ≥2s（读文件而非长连接）。
- Waiting 保守策略：检测到 `needs-approval` → Waiting（释放 hold）＋失效保护（如 30 分钟无新事件 → 回退 Working 展示？**不**——按任务书"不可确认显示 Unknown"，审批解除信号缺失期间维持 Unknown 展示，防睡眠决策按"非 Working"处理，与上游 Waiting 语义一致）。
- schema 探测：按 `migration_meta`/表结构探测而非硬编码列集；状态枚举白名单外 → Unknown。

## 3. 豆包 Z — 部分状态监控 + 保守防睡眠（第三优先）

### 关键事实
- 无独立 CLI/应用：Agent 能力是 Doubao.app（Chromium 壳）内置 task mode（内部代号 saman/aha），运行时 = renderer + C++ AgentTaskService + `AgentInfraService.xpc` + `file_utils_host` + `python_worker.py`。
- **无 hook、无 CLI、无公开 HTTP API**（内部 JSBridge/端口不可外部调用）。
- 结构化数据：
  - `~/Library/Application Support/Doubao/Default/.doubao/agent_mode/workspace/conversation/<id>/background_history_task/index.json`：`tasks[] {taskId, status(finished|…), exitCode, outputFilePath}`（`version:1`）。
  - `…/Doubao/coding/snapshot/<userId>/<conversationId>/<executionUuid>/<snapshotUuid>.json`：`execution {startedAtMs, endedAtMs, agentType…}` + `files[]` 元数据。**隐私红线：`fileContents` 字段绝不可读。**
  - `…/Default/agent_infra/to/lr_<hash>/task_outputs/<task>/output.log`：mtime/size 心跳 = Working 信号。**不读正文。**
- Waiting（ask-human 弹窗）：机制存在（`ask_human_popup_view.cc`）但**无落盘状态文件**——不可判 → Unknown。
- 版本漂移风险高（周更、无契约）：适配器按"字段存在性探测 + 多源冗余 + 动态 glob"，字段缺失降级为仅进程监控。

### 状态映射
| AgentBrew 状态 | 判定信号 |
|---|---|
| Working | 新 execution 且 `endedAtMs` 空；`output.log` mtime 心跳；`file_utils_host` 进程存在 |
| Completed | `endedAtMs>0`；`index.json` `status=='finished' && exitCode==0` |
| Error | `exitCode!=0`；`ok=false` 日志终态；`non_interactive_init_error_*.txt` 出现 |
| Waiting | **Unknown**（无落盘信号；运行时采样验证后再评估） |
| 兜底 | Doubao 主进程 + `file_utils_host` 存活 → 仅进程监控（展示"检测到豆包进程"级别） |

### 保守防睡眠策略（任务书第四节）
豆包 Z 无法可靠确认状态时：Unknown 不冒充 Working；提供**人工保持唤醒开关**（每会话，带 2h 失效保护——复用 `MonitoringLease` 模式），避免无限期保持唤醒。

---

## 4. 适配器实施顺序与工作量预估

1. **ZCode（AB-401）**：hook 安装器（新 `ZCodeHooks.swift`，marker `__agentbrew_zcode_hook`，目标 `~/.zcode/cli/config.json` 顶层 `hooks` 且 `"enabled": true`，写法遵循 ClaudeHooks 的 JSONSerialization 纪律）+ AgentID 扩展 + HookReducer 事件映射 + `LETITBREW_TEST_HOME` 路径测试。评级：完整生命周期。**唯一可真机实测的完整监控目标（本机即在 ZCode 中运行）。**
2. **WorkBuddy（AB-402）**：新适配器类型（文件轮询型，不走 hook CLI）：`WorkBuddyPollingMonitor`（App 侧每 2s 读两个根目录的 db/audit-log）→ 产出 `SessionRecord` 写入同一 SessionStore（复用 `session_id`/`cwd`）。两版共用，参数化根目录。
3. **豆包 Z（AB-403）**：同类轮询监控 + 人工保持唤醒开关 + 失效保护。

统一约束（任务书第五节）：各适配器独立启停（复用 `connectedAgentIDsV2` 机制扩展 agent 行）；事件缺失映射为 nil；不可确认状态一律 Unknown；不伪造进度。

## 5. 待验证清单（第四阶段真机验证项）

- [ ] ZCode：真实会话中 7 个 hook 事件的实际触发与 `Stop` 触发问题复现。
- [ ] ZCode：`hooks.enabled:true` 写入后对现有会话的影响（增量安装是否安全）。
- [ ] WorkBuddy：运行期 WAL 只读访问策略实测；审批产生/解除的 audit-log 行为实测。
- [ ] 豆包 Z：发起一个真实 Agent 任务，验证 index.json/snapshot/output.log 的实时性；Waiting 弹窗期间是否存在任何可观测文件信号。
- [ ] 各适配器禁用开关的隔离性（禁用后零文件写入）。
