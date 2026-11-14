import Foundation

public struct RecoveryStep: Equatable, Sendable {
    public let text: String
}

public enum RecoveryAction: Equatable, Sendable {
    case openURL(URL)
    case copyDetails(String)
    case openLoginItems
    case revealApplication
}

public struct RecoveryGuidance: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let steps: [RecoveryStep]
    public let actions: [RecoveryAction]
}

public enum OperationRecoveryCatalog {
    public static func update(
        kind: OneClickUpdateFailure.Kind,
        diagnostic: String?
    ) -> RecoveryGuidance {
        switch kind {
        case .discovery:
            guidance(
                id: "update-discovery",
                title: "Could not check for updates",
                summary: "AgentBrew did not change the installed app.",
                steps: [
                    "Check your internet connection.",
                    "Open Releases and download the signed versioned DMG.",
                    "Quit AgentBrew before replacing the app in Applications.",
                    "Your AgentBrew settings stay in place.",
                ],
                actions: [.openURL(ProductLinks.releases)],
                diagnostic: diagnostic
            )
        case .download:
            guidance(
                id: "update-download",
                title: "Could not download the update",
                summary: "AgentBrew did not change the installed app.",
                steps: [
                    "Check your internet connection.",
                    "Open Releases and download the signed versioned DMG.",
                    "Quit AgentBrew before replacing the app in Applications.",
                    "Your AgentBrew settings stay in place.",
                ],
                actions: [.openURL(ProductLinks.releases)],
                diagnostic: diagnostic
            )
        case .verification:
            guidance(
                id: "update-verification",
                title: "Could not verify the update",
                summary: "AgentBrew stopped before replacing the installed app.",
                steps: [
                    "Remove only the failed download.",
                    "Open Releases and download a fresh signed versioned DMG.",
                    "Keep Gatekeeper enabled and reopen the DMG normally.",
                    "Quit AgentBrew before replacing the app in Applications. Your settings stay in place.",
                ],
                actions: [.openURL(ProductLinks.releases)],
                diagnostic: diagnostic
            )
        case .replacement:
            guidance(
                id: "update-replacement",
                title: "Could not replace AgentBrew",
                summary: "The installed app may still be the previous version.",
                steps: [
                    "Open Releases and download the signed versioned DMG.",
                    "Quit AgentBrew before replacing the app in Applications.",
                    "Replace only AgentBrew.app, then reopen it normally.",
                    "Your AgentBrew settings stay in place.",
                ],
                actions: [.openURL(ProductLinks.releases), .revealApplication],
                diagnostic: diagnostic
            )
        case .relaunch:
            guidance(
                id: "update-relaunch",
                title: "Finish the update manually",
                summary: "AgentBrew could not confirm that the updated app reopened.",
                steps: [
                    "Open Releases and download the signed versioned DMG.",
                    "Quit AgentBrew before replacing the app in Applications.",
                    "Replace only AgentBrew.app, then reopen it normally.",
                    "Your AgentBrew settings stay in place.",
                ],
                actions: [.openURL(ProductLinks.releases), .revealApplication],
                diagnostic: diagnostic
            )
        }
    }

    public static func uninstall(
        step: UninstallStep,
        failureInstruction: String? = nil,
        diagnostic: String?
    ) -> RecoveryGuidance {
        switch step {
        case .releaseHolds:
            guidance(
                id: "uninstall-release-holds",
                title: "AgentBrew is still releasing sleep holds",
                summary: "Nothing was removed.",
                steps: [
                    "Keep AgentBrew in Applications.",
                    "Quit and reopen AgentBrew, then try uninstalling again.",
                    "Do not move the app to the Trash until uninstall confirms the sleep holds are released.",
                ],
                actions: [],
                diagnostic: diagnostic
            )
        case .reconcileDaemon:
            guidance(
                id: "uninstall-reconcile-daemon",
                title: "Could not check the background service",
                summary: "Nothing was removed.",
                steps: [
                    "Keep AgentBrew in Applications.",
                    "Restart your Mac, reopen AgentBrew, then try uninstalling again.",
                    "Do not move the app to the Trash until uninstall confirms the background service is reconciled.",
                ],
                actions: [],
                diagnostic: diagnostic
            )
        case .unregisterDaemon:
            guidance(
                id: "uninstall-unregister-daemon",
                title: "Could not unregister the background service",
                summary: "Nothing was removed.",
                steps: [
                    "Keep AgentBrew installed in Applications.",
                    "Open AgentBrew from Applications and try uninstalling again.",
                    "Do not move the app to the Trash until uninstall confirms the background service is unregistered.",
                ],
                actions: [.revealApplication],
                diagnostic: diagnostic
            )
        case .removeClaudeHooks:
            hookGuidance(agent: "Claude Code", id: "claude", diagnostic: diagnostic)
        case .removeCodexHooks:
            hookGuidance(agent: "Codex", id: "codex", diagnostic: diagnostic)
        case .removeOpenCodeHooks:
            hookGuidance(agent: "OpenCode", id: "opencode", diagnostic: diagnostic)
        case .removePiHooks:
            hookGuidance(agent: "Pi", id: "pi", diagnostic: diagnostic)
        case .removeCopilotHooks:
            hookGuidance(agent: "GitHub Copilot CLI", id: "copilot", diagnostic: diagnostic)
        case .removeCursorHooks:
            hookGuidance(agent: "Cursor", id: "cursor", diagnostic: diagnostic)
        case .removeGeminiHooks:
            hookGuidance(agent: "Gemini CLI", id: "gemini", diagnostic: diagnostic)
        case .removeQwenHooks:
            hookGuidance(agent: "Qwen Code", id: "qwen", diagnostic: diagnostic)
        case .removeKimiHooks:
            hookGuidance(agent: "Kimi Code", id: "kimi", diagnostic: diagnostic)
        case .retainBundleForHookRetry:
            guidance(
                id: "uninstall-retained-app",
                title: "Keep AgentBrew installed for now",
                summary: "AgentBrew and one or more agent hooks may remain.",
                steps: [
                    "Keep AgentBrew installed in Applications.",
                    "Open AgentBrew and turn off each affected watched-agent switch.",
                    "Try uninstalling again.",
                ],
                actions: [],
                diagnostic: diagnostic
            )
        case .disableLaunchAtLogin:
            guidance(
                id: "uninstall-login-item",
                title: "Could not turn off Launch at Login",
                summary: "The AgentBrew login item may still be enabled.",
                steps: [
                    "Open Login Items & Extensions in System Settings.",
                    "Remove AgentBrew from Open at Login and turn off its App Background Activity entry if it appears.",
                ],
                actions: [.openLoginItems],
                diagnostic: diagnostic
            )
        case .deleteUserData:
            guidance(
                id: "uninstall-user-data",
                title: "Could not remove AgentBrew data",
                summary: "AgentBrew's user data may remain.",
                steps: [
                    "In Finder, choose Go → Go to Folder…",
                    "Enter ~/Library/Application Support/LetItBrew.",
                    "Move only that AgentBrew folder to the Trash.",
                ],
                actions: [],
                diagnostic: diagnostic
            )
        case .clearPreferences:
            guidance(
                id: "uninstall-preferences",
                title: "Could not remove AgentBrew preferences",
                summary: "AgentBrew preferences may remain.",
                steps: [
                    "Quit AgentBrew.",
                    failureInstruction
                        ?? "Reopen this copy of AgentBrew and try uninstalling again.",
                ],
                actions: [],
                diagnostic: diagnostic
            )
        case .trashBundle:
            guidance(
                id: "uninstall-app",
                title: "Could not move AgentBrew to the Trash",
                summary: "The background service was already handled.",
                steps: [
                    "Open Applications in Finder.",
                    "Move only AgentBrew.app to the Trash.",
                ],
                actions: [.revealApplication],
                diagnostic: diagnostic
            )
        }
    }

    private static func hookGuidance(
        agent: String,
        id: String,
        diagnostic: String?
    ) -> RecoveryGuidance {
        guidance(
            id: "uninstall-\(id)-hooks",
            title: "Could not remove the \(agent) hook",
            summary: "The AgentBrew-owned \(agent) hook may remain.",
            steps: [
                "Restore AgentBrew from the Trash if needed, then open it.",
                "Turn off the \(agent) watched-agent switch.",
                "Try uninstalling again. AgentBrew leaves foreign hooks and project settings alone.",
            ],
            actions: [],
            diagnostic: diagnostic
        )
    }

    private static func guidance(
        id: String,
        title: String,
        summary: String,
        steps: [String],
        actions: [RecoveryAction],
        diagnostic: String?
    ) -> RecoveryGuidance {
        RecoveryGuidance(
            id: id,
            title: title,
            summary: summary,
            steps: steps.map(RecoveryStep.init(text:)),
            actions: actions + (diagnostic.map { [.copyDetails($0)] } ?? [])
        )
    }
}
