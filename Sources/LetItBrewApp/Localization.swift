import Foundation

/// 中文界面映射（zh-Hans）。
///
/// 设计约束：上游策略层（MenuPresentationPolicy / Decision）继续产出英文
/// 语义字符串，测试断言不受影响；本表只在 App 渲染层消费。键为精确英文
/// 原文，模板化字符串用正则规则覆盖。上游新增的字符串自动回落为英文——
/// 优雅降级，不阻塞合并。
enum L10n {
    private static let exact: [String: String] = [
        // 菜单头部
        "Keeping your Mac awake": "正在保持 Mac 唤醒",
        "Agents are waiting for you": "Agent 正在等你",
        "AgentBrew is paused": "AgentBrew 已暂停",
        "Watching for agents": "正在监视 Agent",
        // 头部副标题（MenuHeaderDetailCopy）
        "No agents are working": "没有 Agent 在工作",
        "1 agent is working": "1 个 Agent 正在工作",
        "1 agent is monitoring background tasks": "1 个 Agent 正在监控后台任务",
        "Your Mac can sleep normally": "Mac 可以正常睡眠",
        "Agents will not keep your Mac awake": "Agent 不会保持 Mac 唤醒",
        // 会话状态（MenuSessionState.text）
        "Working": "工作中",
        "Monitoring background tasks": "监控后台任务中",
        "Waiting for your answer": "等待你的回答",
        "Needs your approval": "等待你的批准",
        "Idle": "空闲",
        // 电池行（MenuBatteryPresentationPolicy）
        "Low Power Mode released the sleep hold": "低电量模式已释放保持唤醒",
        "Battery power released the sleep hold": "电池供电已释放保持唤醒",
        // 释放约束（MenuHeaderCopy.ReleaseConstraint.message）
        "Battery limit reached": "已达电量下限",
        "Running on battery": "正在使用电池",
        "Low Power Mode is on": "低电量模式已开启",
        "Mac is too warm": "Mac 温度过高",
        "Power unavailable": "电源不可用",
        // 决策原因（Decision.reason，经 accessibility 与状态行展示）
        "battery power": "电池供电",
        "low power mode": "低电量模式",
        "thermal pressure": "温度压力",
        "no agent sessions": "无 Agent 会话",
        "all agents idle": "所有 Agent 空闲",
        "agents waiting for you": "Agent 等待你",
        "monitoring hold expired": "监控保持已过期",
        "battery state unknown": "电池状态未知",
        // 设置提醒行（MenuSetupAttentionPolicy）
        "Finish closed-lid setup": "完成闭盖设置",
        "Complete the remaining step in Settings": "到设置中完成剩余步骤",
        // 面板固定件
        "AgentBrew enabled": "启用 AgentBrew",
        "Settings…": "设置…",
        "Quit AgentBrew": "退出 AgentBrew",
    ]

    /// 模板族：按顺序尝试，命中即格式化。
    private static let patterns: [(NSRegularExpression, String)] = {
        func regex(_ pattern: String) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern)
        }
        return [
            // 头部副标题
            (regex("^([2-9]\\d*) agents are working$"), "$1 个 Agent 正在工作"),
            (regex("^([2-9]\\d*) agents are monitoring background tasks$"), "$1 个 Agent 正在监控后台任务"),
            (regex("^(\\d+) monitoring$"), "$1 个监控中"),
            (regex("^(\\d+) waiting$"), "$1 个等待中"),
            // 分组徽标（MenuPresentationPolicy:349）
            (regex("^(\\d+) working$"), "$1 个工作中"),
            (regex("^(\\d+) not reporting$"), "$1 个未上报"),
            // 电池行
            (regex("^Battery (\\d+)% · Sleep hold stops below (\\d+)%$"),
             "电量 $1% · 低于 $2% 时停止保持唤醒"),
            // 监控租约到期
            (regex("^No update in (\\d+) h · Mac can sleep$"), "$1 小时无更新 · Mac 可以睡眠"),
            // 决策原因：电量数值
            (regex("^battery (\\d+)%$"), "电量 $1%"),
        ]
    }()

    /// 中文优先，未命中的英文原样返回（上游新增字符串的优雅降级）。
    static func zh(_ english: String) -> String {
        if let mapped = exact[english] { return mapped }
        for (regex, template) in patterns {
            let range = NSRange(english.startIndex..., in: english)
            if regex.firstMatch(in: english, range: range) != nil {
                return regex.stringByReplacingMatches(
                    in: english, range: range, withTemplate: template
                )
            }
        }
        return english
    }
}
