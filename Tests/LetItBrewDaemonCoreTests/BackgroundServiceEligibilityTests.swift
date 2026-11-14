import Foundation
import Testing
@testable import LetItBrewDaemonCore

@Test func onlyDirectApplicationsChildrenMayManageBackgroundServices() {
    #expect(BackgroundServiceEligibility.mayManageBackgroundServices(
        bundleURL: URL(fileURLWithPath: "/Applications/AgentBrew.app"),
        bundleIdentifier: "com.agentbrew"
    ))
    #expect(BackgroundServiceEligibility.mayManageBackgroundServices(
        bundleURL: URL(fileURLWithPath: "/Applications/AgentBrew Dev.app"),
        bundleIdentifier: "com.agentbrew.dev"
    ))
    #expect(!BackgroundServiceEligibility.mayManageBackgroundServices(
        bundleURL: URL(fileURLWithPath: "/tmp/AgentBrew.app"),
        bundleIdentifier: "com.agentbrew"
    ))
    #expect(!BackgroundServiceEligibility.mayManageBackgroundServices(
        bundleURL: URL(fileURLWithPath: "/Applications/Tools/AgentBrew.app"),
        bundleIdentifier: "com.agentbrew"
    ))
}

@Test func lookalikeIdentifiersAndNonAppBundlesAreRejected() {
    #expect(!BackgroundServiceEligibility.mayManageBackgroundServices(
        bundleURL: URL(fileURLWithPath: "/Applications/AgentBrew.app"),
        bundleIdentifier: "com.agentbrew.evil"
    ))
    #expect(!BackgroundServiceEligibility.mayManageBackgroundServices(
        bundleURL: URL(fileURLWithPath: "/Applications/AgentBrew"),
        bundleIdentifier: "com.agentbrew"
    ))
}

@Test func serviceManagementRequiresTheLiveExpectedSigningIdentity() {
    let productionURL = URL(fileURLWithPath: "/Applications/AgentBrew.app")
    let production = RuntimeSigningIdentity(
        identifier: "com.agentbrew",
        teamIdentifier: BackgroundServiceEligibility.expectedTeamIdentifier
    )
    #expect(BackgroundServiceEligibility.mayManageBackgroundServices(
        bundleURL: productionURL,
        bundleIdentifier: production.identifier,
        signingIdentity: production
    ))

    for identity in [
        RuntimeSigningIdentity(
            identifier: "com.agentbrew.dev",
            teamIdentifier: BackgroundServiceEligibility.expectedTeamIdentifier
        ),
        RuntimeSigningIdentity(
            identifier: "com.agentbrew",
            teamIdentifier: "ATTACKERTEAM"
        ),
    ] {
        #expect(!BackgroundServiceEligibility.mayManageBackgroundServices(
            bundleURL: productionURL,
            bundleIdentifier: "com.agentbrew",
            signingIdentity: identity
        ))
    }
}
