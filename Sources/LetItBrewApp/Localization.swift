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
        // 设置页 tab（SettingsPane.title）
        "General": "通用",
        "Agents": "Agent",
        "Power": "电源",
        "Closed Lid": "闭盖",
        "About": "关于",
        // 更新状态（SettingsView.updateStatus）
        "Check for Updates…": "检查更新…",
        "Checks for updates daily. Nothing installs until you choose.": "每天自动检查更新。未经你确认不会安装。",
        "Update ready. Restarting AgentBrew…": "更新就绪。正在重启 AgentBrew…",
        "The last update check didn\u{2019}t finish.": "上次更新检查未完成。",
        "AgentBrew will download and verify the signed update, briefly quit, safely transition its background service if present, and relaunch. Your settings and session records stay in place.": "AgentBrew 将下载并校验签名更新，短暂退出并安全切换后台服务后重启。你的设置与会话记录保持不变。",
        "Checking for updates…": "正在检查更新…",
        "Checking…": "检查中…",
        "AgentBrew is up to date.": "已是最新版本。",
        "Downloading and verifying update…": "正在下载并校验更新…",
        "Finish the update manually": "手动完成更新",
        "Keep AgentBrew in Applications.": "请把 AgentBrew 保留在“应用程序”内。",
        "Keep AgentBrew installed for now": "暂时保留 AgentBrew 安装",
        "Keep AgentBrew installed in Applications.": "请把 AgentBrew 保留在“应用程序”内。",
        "Keep Gatekeeper enabled and reopen the DMG normally.": "保持 Gatekeeper 开启，正常重新打开 DMG。",
        "Remove only the failed download.": "只删除失败的下载。",
        "Open Releases and download a fresh signed versioned DMG.": "打开 Releases 重新下载带版本的签名 DMG。",
        "Open Releases and download the signed versioned DMG.": "打开 Releases 下载带版本的签名 DMG。",
        "Replace only AgentBrew.app, then reopen it normally.": "只替换 AgentBrew.app，然后正常重新打开。",
        "Quit AgentBrew before replacing the app in Applications.": "替换“应用程序”里的 App 前请先退出 AgentBrew。",
        "Quit AgentBrew before replacing the app in Applications. Your settings stay in place.": "替换“应用程序”里的 App 前请先退出 AgentBrew。你的设置保持不变。",
        "The installed app may still be the previous version.": "已安装的 App 可能仍是旧版本。",
        "Could not check for updates": "无法检查更新",
        "Could not download the update": "无法下载更新",
        "Could not verify the update": "无法校验更新",
        "Could not replace AgentBrew": "无法替换 AgentBrew",
        "Install AgentBrew update?": "安装 AgentBrew 更新？",
        // 卸载引导（OperationRecoveryGuidance）
        "AgentBrew did not change the installed app.": "AgentBrew 未改动已安装的 App。",
        "AgentBrew stopped before replacing the installed app.": "AgentBrew 在替换已安装的 App 之前停止了。",
        "AgentBrew and one or more agent hooks may remain.": "AgentBrew 和部分 Agent 钩子可能残留。",
        "AgentBrew preferences may remain.": "AgentBrew 偏好设置可能残留。",
        "AgentBrew's user data may remain.": "AgentBrew 的用户数据可能残留。",
        "AgentBrew is still releasing sleep holds": "AgentBrew 仍在释放保持唤醒",
        "Nothing was removed.": "没有删除任何内容。",
        "The background service was already handled.": "后台服务已被处理。",
        "Could not move AgentBrew to the Trash": "无法把 AgentBrew 移入废纸篓",
        "Could not remove AgentBrew data": "无法删除 AgentBrew 数据",
        "Could not remove AgentBrew preferences": "无法删除 AgentBrew 偏好设置",
        "Could not turn off Launch at Login": "无法关闭登录时启动",
        "Could not unregister the background service": "无法注销后台服务",
        "Could not check the background service": "无法检查后台服务",
        "Do not move the app to the Trash until uninstall confirms the background service is reconciled.": "卸载确认后台服务已对账之前，不要把 App 移入废纸篓。",
        "Do not move the app to the Trash until uninstall confirms the background service is unregistered.": "卸载确认后台服务已注销之前，不要把 App 移入废纸篓。",
        "Do not move the app to the Trash until uninstall confirms the sleep holds are released.": "卸载确认保持唤醒已释放之前，不要把 App 移入废纸篓。",
        "Open Applications in Finder.": "在 Finder 中打开“应用程序”。",
        "Open AgentBrew and turn off each affected watched-agent switch.": "打开 AgentBrew，关闭每个受影响 Agent 的监控开关。",
        "Open AgentBrew from Applications and try uninstalling again.": "从“应用程序”打开 AgentBrew 后重试卸载。",
        "Open Login Items & Extensions in System Settings.": "在系统设置中打开“登录项与扩展”。",
        "Quit and reopen AgentBrew, then try uninstalling again.": "退出并重新打开 AgentBrew 后重试卸载。",
        "Reopen this copy of AgentBrew and try uninstalling again.": "重新打开这份 AgentBrew 后重试卸载。",
        "Restart your Mac, reopen AgentBrew, then try uninstalling again.": "重启 Mac，重新打开 AgentBrew 后重试卸载。",
        "Restore AgentBrew from the Trash if needed, then open it.": "如需要，先从废纸篓恢复 AgentBrew 再打开。",
        "Try uninstalling again. AgentBrew leaves foreign hooks and project settings alone.": "重试卸载。AgentBrew 不会动外来钩子和项目设置。",
        "Try uninstalling again.": "重试卸载。",
        "Move only AgentBrew.app to the Trash.": "只把 AgentBrew.app 移入废纸篓。",
        "Move only that AgentBrew folder to the Trash.": "只把那个 AgentBrew 文件夹移入废纸篓。",
        "Enter ~/Library/Application Support/AgentBrew.": "前往 ~/Library/Application Support/AgentBrew。",
        "In Finder, choose Go → Go to Folder…": "在 Finder 中选择“前往 → 前往文件夹…”。",
        "The AgentBrew login item may still be enabled.": "AgentBrew 的登录项可能仍处于开启状态。",
        "Your AgentBrew settings stay in place.": "你的 AgentBrew 设置保持不变。",
        "Check your internet connection.": "检查网络连接。",
        // 连接健康状态（AgentConnectionState.rawValue）
        "Connecting": "连接中",
        "Connected": "已连接",
        "Action needed": "需要处理",
        "Couldn’t connect": "无法连接",
        "Not watched": "未监控",
        "Development": "开发版",
        // Agent 连接健康与诊断（Agents 页每行详情）
        "AgentBrew's connection is healthy.": "AgentBrew 连接正常。",
        "AgentBrew's connection needs repair.": "AgentBrew 连接需要修复。",
        "No AgentBrew connection is installed.": "未安装 AgentBrew 连接。",
        "Unknown project": "未知项目",
        "AgentBrew could not inspect this selected connection.": "AgentBrew 无法检查这个选中的连接。",
        "AgentBrew did not prepare this selected connection.": "AgentBrew 未对这个选中的连接完成准备。",
        "AgentBrew did not receive a preparation result.": "AgentBrew 未收到准备结果。",
        "AgentBrew could not verify Codex hook approval.": "AgentBrew 无法确认 Codex 钩子授权。",
        "Approve AgentBrew in Codex, then try again.": "先在 Codex 中批准 AgentBrew，然后重试。",
        "AgentBrew will not change this invalid connection. Fix it, then choose Check Again.": "此连接无效，AgentBrew 不会改动它。修复后再点“再次检查”。",
        "AgentBrew's hooks are still present, so disconnect did not finish.": "AgentBrew 的钩子仍然存在，断开未完成。",
        "Choose Retry Disconnect to remove them, or Connect to keep using this agent.": "选择“重试断开”以移除它们，或选择“连接”继续使用该 Agent。",
        "Disconnected. Choose Connect to use this agent with AgentBrew.": "已断开。选择“连接”可让 AgentBrew 监控该 Agent。",
        "Fix or restore that file, then choose Check Again.": "修复或恢复该文件后，再点“再次检查”。",
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
            (regex("^Could not remove the (.+) hook$"), "无法移除 $1 的钩子"),
            (regex("^The AgentBrew-owned (.+) hook may remain.$"), "AgentBrew 的 $1 钩子可能残留。"),
            (regex("^Turn off the (.+) watched-agent switch.$"), "关闭 $1 的监控开关。"),
            (regex("^Watch (.+)$"), "监控 $1"),
            (regex("^Version (.+) is available.$"), "新版本 $1 可用。"),
            (regex("^AgentBrew could not safely read its recorded agent target: (.+)$"),
             "AgentBrew 无法安全读取其记录的 Agent 目标：$1"),
            (regex("^AgentBrew will not change this unreadable or unowned configuration: (.+)$"),
             "此配置不可读或非 AgentBrew 所有，AgentBrew 不会改动它：$1"),
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
