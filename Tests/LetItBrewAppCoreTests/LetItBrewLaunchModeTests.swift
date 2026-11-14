import Testing
@testable import LetItBrewAppCore

@Test func commandAndPreviewModesNeverConstructOrdinaryScenes() {
    let cases: [(String, LetItBrewLaunchMode)] = [
        ("--register-daemon", .registerDaemon),
        ("--unregister-daemon", .unregisterDaemon),
        ("--probe-daemon", .probeDaemon),
        ("--prepare-update", .prepareUpdate),
        ("--prepare-daemon-upgrade", .prepareDaemonUpgrade),
        ("--hold-daemon", .holdDaemon),
        ("--probe-lid-display", .probeLidDisplay),
        ("--design-preview", .designPreview),
        ("--design-preview-settings", .designPreviewSettings),
    ]

    for (argument, expected) in cases {
        let mode = LetItBrewLaunchMode(
            arguments: ["AgentBrew", argument],
            allowsDesignPreview: true
        )

        #expect(mode == expected)
        #expect(!mode.constructsOrdinaryScenes)
    }
}

@Test func anOrdinaryLaunchConstructsTheOnlyMenuBarScene() {
    let mode = LetItBrewLaunchMode(
        arguments: ["AgentBrew"],
        allowsDesignPreview: true
    )

    #expect(mode == .ordinary)
    #expect(mode.constructsOrdinaryScenes)
}

@Test func releaseBuildsDoNotRecognizeTheDebugDesignPreviewFlag() {
    let mode = LetItBrewLaunchMode(
        arguments: ["AgentBrew", "--design-preview"],
        allowsDesignPreview: false
    )

    #expect(mode == .ordinary)
    #expect(mode.constructsOrdinaryScenes)
}

@Test func releaseBuildsDoNotRecognizeTheSettingsPreviewFlag() {
    let mode = LetItBrewLaunchMode(
        arguments: ["AgentBrew", "--design-preview-settings"],
        allowsDesignPreview: false
    )

    #expect(mode == .ordinary)
    #expect(mode.constructsOrdinaryScenes)
}

@Test func aDiagnosticCommandWinsOverUnrelatedArguments() {
    let mode = LetItBrewLaunchMode(
        arguments: ["AgentBrew", "--unknown", "--probe-daemon"],
        allowsDesignPreview: true
    )

    #expect(mode == .probeDaemon)
    #expect(!mode.constructsOrdinaryScenes)
}
