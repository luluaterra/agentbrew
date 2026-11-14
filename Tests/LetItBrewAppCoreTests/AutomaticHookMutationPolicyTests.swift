import Foundation
import Testing
@testable import LetItBrewAppCore

@Test func directApplicationBundlesAreEligibleForAutomaticHookWrites() {
    for path in [
        "/Applications/AgentBrew.app",
        "/Applications/AgentBrew Dev.app",
        "/Applications/A Renamed AgentBrew.app",
    ] {
        #expect(AutomaticHookMutationPolicy.evaluate(
            appBundleURL: URL(fileURLWithPath: path)
        ) == .eligible)
    }
}

@Test func ephemeralNestedAndNonBundleLaunchesAreReadOnly() {
    let paths = [
        "/tmp/DerivedData/Build/Products/Debug/AgentBrew.app",
        "/Users/test/Downloads/AgentBrew.app",
        "/Volumes/AgentBrew/AgentBrew.app",
        "/private/var/folders/AppTranslocation/AgentBrew.app",
        "/Applications/Utilities/AgentBrew.app",
        "/Applications/AgentBrew.app/Contents/MacOS/LetItBrew",
        "/Applications/AgentBrew",
    ]

    for path in paths {
        let result = AutomaticHookMutationPolicy.evaluate(
            appBundleURL: URL(fileURLWithPath: path)
        )
        guard case .actionNeeded(let details) = result else {
            Issue.record("Expected read-only Action needed for \(path)")
            continue
        }
        #expect(details.joined(separator: " ").contains("/Applications"))
        #expect(details.joined(separator: " ").contains("Check Again"))
    }
}

@Test func dotSegmentsCannotMakeANestedBundleLookDirectlyInstalled() {
    let nested = URL(fileURLWithPath: "/Applications/Utilities/../Utilities/AgentBrew.app")

    #expect(AutomaticHookMutationPolicy.evaluate(appBundleURL: nested).isEligible == false)
}
