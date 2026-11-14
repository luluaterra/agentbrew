import Testing
@testable import LetItBrewAppCore

@Test func canonicalProductLinksAreExact() {
    #expect(ProductLinks.repository.absoluteString
        == "https://github.com/luluaterra/agentbrew")
    #expect(ProductLinks.releases.absoluteString
        == "https://github.com/luluaterra/agentbrew/releases")
    #expect(ProductLinks.reportIssue.absoluteString
        == "https://github.com/luluaterra/agentbrew/issues/new/choose")
    #expect(ProductLinks.privacy.absoluteString
        == "https://github.com/luluaterra/agentbrew/blob/main/docs/PRIVACY.md")
}

@Test func verificationFailureNeverSuggestsBypassingGatekeeper() {
    let guidance = OperationRecoveryCatalog.update(
        kind: .verification,
        diagnostic: "signature rejected"
    )
    let copy = ([guidance.summary] + guidance.steps.map(\.text)).joined(separator: " ")
    #expect(!copy.localizedCaseInsensitiveContains("disable Gatekeeper"))
    #expect(guidance.actions.contains(.openURL(ProductLinks.releases)))
    #expect(guidance.actions.contains(.copyDetails("signature rejected")))
}

@Test func everyUninstallStepHasRecoveryGuidance() {
    for step in UninstallStep.allCases {
        let guidance = OperationRecoveryCatalog.uninstall(
            step: step,
            diagnostic: "detail"
        )
        #expect(!guidance.steps.isEmpty)
    }
}

@Test func retainedBundleForHookRetryNeverSuggestsTrashingTheApp() {
    let guidance = OperationRecoveryCatalog.uninstall(
        step: .retainBundleForHookRetry,
        diagnostic: "hooks remain"
    )
    let copy = ([guidance.summary] + guidance.steps.map(\.text)).joined(separator: " ")
    #expect(!copy.localizedCaseInsensitiveContains("Trash"))
    #expect(!guidance.actions.contains(.revealApplication))
}

@Test func cleanupGuidanceDoesNotClaimOnlyOneResourceRemains() {
    for step in [
        UninstallStep.removeClaudeHooks,
        .deleteUserData,
        .clearPreferences,
    ] {
        let guidance = OperationRecoveryCatalog.uninstall(step: step, diagnostic: "detail")
        #expect(!guidance.summary.localizedCaseInsensitiveContains("only"))
    }
}

@Test func preferenceRecoveryPreservesTheCurrentBundleDomainInstruction() {
    let instruction = "Open Terminal and run: defaults delete com.agentbrew.dev"
    let guidance = OperationRecoveryCatalog.uninstall(
        step: .clearPreferences,
        failureInstruction: instruction,
        diagnostic: "preferences remained"
    )

    #expect(guidance.steps.contains(RecoveryStep(text: instruction)))
    #expect(!guidance.steps.contains(RecoveryStep(
        text: "Open Terminal and run: defaults delete com.agentbrew"
    )))
}

@Test func genuineAppTrashFailureStillExplainsFinderRecovery() {
    let guidance = OperationRecoveryCatalog.uninstall(
        step: .trashBundle,
        diagnostic: "Finder refused"
    )
    let copy = ([guidance.summary] + guidance.steps.map(\.text)).joined(separator: " ")
    #expect(copy.contains("Move only AgentBrew.app to the Trash."))
    #expect(guidance.actions.contains(.revealApplication))
}
