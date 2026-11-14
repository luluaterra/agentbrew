import Foundation

/// The boundary around every Service Management call.
///
/// Background Task Management associates a service with the app copy that
/// contacted it. Even inspecting service state from DerivedData can move that
/// association away from the installed app, so callers must pass this check
/// before constructing or using an `SMAppService`.
public enum BackgroundServiceEligibility {
    public static let productionAppIdentifier = "com.agentbrew"
    public static let developmentAppIdentifier = "com.agentbrew.dev"
    /// The Team ID of the certificate AgentBrew is actually signed with
    /// (the user's Personal Team). RuntimeSigningIdentity reads the same
    /// value from the live signature, so dev and prod cannot impersonate
    /// one another.
    public static let expectedTeamIdentifier = "A7HHMGNNZ2"

    public static func mayManageBackgroundServices(
        bundleURL: URL,
        bundleIdentifier: String?
    ) -> Bool {
        let resolved = bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL

        guard resolved.deletingLastPathComponent() == applications,
              resolved.pathExtension == "app"
        else { return false }

        return bundleIdentifier == productionAppIdentifier
            || bundleIdentifier == developmentAppIdentifier
    }

    /// The stronger gate used immediately before any Service Management call.
    /// Location and an allow-listed identifier are insufficient on their own:
    /// the live caller must also prove that its validated Apple signature has
    /// the same identifier and AgentBrew's expected Team ID.
    public static func mayManageBackgroundServices(
        bundleURL: URL,
        bundleIdentifier: String?,
        signingIdentity: RuntimeSigningIdentity
    ) -> Bool {
        guard mayManageBackgroundServices(
            bundleURL: bundleURL,
            bundleIdentifier: bundleIdentifier
        ), let bundleIdentifier else {
            return false
        }
        return signingIdentity.identifier == bundleIdentifier
            && signingIdentity.teamIdentifier == expectedTeamIdentifier
    }
}
