# AgentBrew 当前任务

状态词汇：待评估 / 待办 / 进行中 / 阻塞 / 待验收。

## 主线

### AB-001 阶段一：上游源码审计与本机环境检查
- 类型：主线开发 · 状态：**待验收**
- 产出：`docs/BASELINE_AUDIT.md`（架构总览、必须保留功能→源码映射、状态机映射表、10 处隔离改造点、风险 R1–R4、本机环境、UI 层子审计）。
- 验收标准：覆盖任务书第一节审计清单（电源管理/闭盖/后台服务/XPC/Agent Hook/会话管理/状态机/菜单栏 UI）；隔离改造点与身份标识完整；环境缺口明确。
- 备注：审计基于上游 `0df676c`（v1.0.0 / build 45）。

### AB-002 阶段二：独立开发分支与隔离基座
- 类型：主线开发 · 状态：**进行中**
- 已完成：Fork `luluaterra/agentbrew`；分支 `agentbrew/main`；remote：origin=fork、upstream=上游；项目记录（AGENTS.md、TASK_STATE.md）。
- 待办：身份参数化改造（Bundle ID/daemon 标识/hook marker/数据目录/App 名称，按 BASELINE_AUDIT 第 4 节 10 处）；R1 电源互斥机制设计；防睡眠基线验证 `docs/POWER_MANAGEMENT_TEST.md`。
- 验收标准：`swift test` 全绿（身份改动后）；官网版零改动；互斥机制有测试覆盖。

### AB-003 环境缺口：Xcode 与签名身份
- 类型：阻塞 · 状态：**阻塞**（需用户决策）
- 内容：① 完整 Xcode 未安装（App/daemon/CLI 无法构建，约 12GB）；② 开发版签名需带 Team ID 的证书（ad-hoc 会被 XPC `anchor apple generic` 校验拒绝），需确认用户是否有 Apple 开发身份（免费 Personal Team 的开发证书可满足本地验证）。
- 影响：第三阶段（防睡眠真实验证）开始前必须解决。

## 阻塞与风险

- R1 双应用 `disablesleep` 争夺：官网版与开发版都会写系统级 SleepDisabled，必须实现互斥（方案见 BASELINE_AUDIT 第 5 节），未实现前不得双版本并行测试。
- R2/R3：见 AB-003。
- R4 官网版运行中：审计全程只读，未触碰。

## 待评估（新想法池）

- 暂无。
