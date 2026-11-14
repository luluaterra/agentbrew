import Foundation

public enum AutomaticHookMutationDecision: Equatable, Sendable {
    case eligible
    case actionNeeded(details: [String])

    public var isEligible: Bool {
        if case .eligible = self { return true }
        return false
    }
}

/// Hook definitions embed the running helper's absolute path. Persisting a
/// path from Downloads, a DMG, App Translocation, DerivedData, or `/tmp`
/// immediately makes the integration stale and invalidates Codex approval.
/// Only a `.app` installed as a direct child of `/Applications` is stable
/// enough for AgentBrew to write agent configuration automatically.
public enum AutomaticHookMutationPolicy {
    public static func evaluate(appBundleURL: URL) -> AutomaticHookMutationDecision {
        let bundle = appBundleURL.resolvingSymlinksInPath().standardizedFileURL
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
            .standardizedFileURL
        guard bundle.pathExtension.lowercased() == "app",
              bundle.deletingLastPathComponent() == applications
        else {
            return .actionNeeded(details: [
                "AgentBrew can connect agents automatically after it is installed in /Applications.",
                "Move the app there, reopen it, then choose Check Again.",
            ])
        }
        return .eligible
    }
}
