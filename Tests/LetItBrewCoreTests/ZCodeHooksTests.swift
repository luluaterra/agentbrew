import Foundation
import Testing
@testable import LetItBrewCore

private func jsonObject(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Test func zcodeInstallCreatesTheEventsKeyAndEnablesTheRunner() throws {
    let data = try ZCodeHooks.install(into: nil, cliPath: "/opt/agentbrew")
    let root = try jsonObject(data)

    // ZCode's config also carries mcp.servers and plugin state; a fresh
    // install adds nothing else.
    #expect(Set(root.keys) == ["hooks"])

    let hooks = try #require(root["hooks"] as? [String: Any])
    #expect(hooks["enabled"] as? Bool == true)
    let events = try #require(hooks["events"] as? [String: Any])
    #expect(Set(events.keys) == Set(ZCodeHooks.events))

    // One group per event, one command entry inside, no matcher: an omitted
    // matcher matches everything, and the reducer filters sources itself.
    for (event, value) in events {
        let groups = try #require(value as? [[String: Any]])
        #expect(groups.count == 1)
        let entries = try #require(groups[0]["hooks"] as? [[String: Any]])
        #expect(entries.count == 1)
        #expect(entries[0]["type"] as? String == "command")
        #expect(entries[0]["timeout"] as? Int == 5)
        #expect(groups[0]["matcher"] == nil)
    }
}

@Test func zcodeInstallPreservesForeignKeysAndOtherHooks() throws {
    let original = """
    {
      "mcp": {"servers": {"fs": {"command": "npx", "args": ["-y", "fs"]}}},
      "plugins": {"enabledPlugins": {"a": true}},
      "hooks": {
        "timeoutMs": 90000,
        "events": {
          "SessionStart": [
            {"matcher": "startup", "hooks": [
              {"type": "command", "command": "/bin/echo foreign"}
            ]}
          ]
        }
      }
    }
    """.data(using: .utf8)!

    let root = try jsonObject(try ZCodeHooks.install(into: original, cliPath: "/opt/agentbrew"))
    #expect(root["mcp"] != nil)
    #expect(root["plugins"] != nil)

    let hooks = try #require(root["hooks"] as? [String: Any])
    #expect(hooks["timeoutMs"] as? Int == 90000)
    let events = try #require(hooks["events"] as? [String: Any])
    for event in ZCodeHooks.events {
        #expect(events[event] != nil)
    }

    // The foreign group under SessionStart survives verbatim, after ours.
    let sessionGroups = try #require(events["SessionStart"] as? [[String: Any]])
    #expect(sessionGroups.count == 2)
    #expect(sessionGroups[0]["matcher"] as? String == "startup")
}

@Test func zcodeRemoveLeavesNothingWhenNothingElseRemains() throws {
    let installed = try ZCodeHooks.install(into: nil, cliPath: "/opt/agentbrew")
    let root = try jsonObject(try ZCodeHooks.remove(from: installed))
    // The whole hooks key goes, restoring the file this adapter never
    // touched — including the enabled flag it added.
    #expect(root.isEmpty)
}

@Test func zcodeRemoveKeepsForeignEventsAndTheirEnabledRunner() throws {
    let original = """
    {
      "hooks": {
        "enabled": false,
        "events": {
          "SessionStart": [
            {"hooks": [{"type": "command", "command": "/bin/echo foreign"}]}
          ]
        }
      }
    }
    """.data(using: .utf8)!

    let installedData = try ZCodeHooks.install(into: original, cliPath: "/opt/agentbrew")
    let installed = try jsonObject(installedData)
    // Installing enabled the runner: parked foreign hooks start running too.
    let installedHooks = try #require(installed["hooks"] as? [String: Any])
    #expect(installedHooks["enabled"] as? Bool == true)

    let removed = try jsonObject(try ZCodeHooks.remove(from: installedData))
    let removedHooks = try #require(removed["hooks"] as? [String: Any])
    let events = try #require(removedHooks["events"] as? [String: Any])
    #expect(Set(events.keys) == ["SessionStart"])
    let groups = try #require(events["SessionStart"] as? [[String: Any]])
    #expect(groups.count == 1)
}

@Test func zcodeRemoveIsRefusedOnUnreadableConfiguration() throws {
    #expect(throws: ClaudeHooks.SettingsUnreadable.self) {
        _ = try ZCodeHooks.remove(from: Data("not json".utf8))
    }
    #expect(throws: ClaudeHooks.SettingsUnreadable.self) {
        _ = try ZCodeHooks.remove(from: Data("[1,2]".utf8))
    }
    #expect(throws: ClaudeHooks.SettingsUnreadable.self) {
        _ = try ZCodeHooks.install(into: Data("{\"hooks\": 3}".utf8), cliPath: "/opt/agentbrew")
    }
    #expect(throws: ClaudeHooks.SettingsUnreadable.self) {
        _ = try ZCodeHooks.install(
            into: Data("{\"hooks\": {\"events\": 3}}".utf8), cliPath: "/opt/agentbrew")
    }
}

@Test func zcodeUnreadableConfigurationReportsAsMissing() throws {
    let report = ZCodeHooks.report(for: Data("nope".utf8), cliPath: "/opt/agentbrew")
    #expect(report.isAbsent)
}

@Test func zcodeReportClassifiesHealthyStaleAndMissing() throws {
    let installed = try ZCodeHooks.install(into: nil, cliPath: "/opt/agentbrew")
    let healthy = ZCodeHooks.report(for: installed, cliPath: "/opt/agentbrew")
    #expect(healthy.healthy == Set(ZCodeHooks.events))

    let drifted = ZCodeHooks.report(for: installed, cliPath: "/opt/elsewhere")
    #expect(drifted.stale == Set(ZCodeHooks.events))

    let report = ZCodeHooks.report(for: nil, cliPath: "/opt/agentbrew")
    #expect(report.missing == Set(ZCodeHooks.events))
}

@Test func zcodeHookCommandsRunTheCLIZeroOnAnyOutcome() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentbrew-zcode-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let helper = directory.appendingPathComponent("helper")
    let log = directory.appendingPathComponent("log")
    try "#!/bin/sh\necho \"$@\" >> '\(log.path)'\necho noisy\nexit 7\n"
        .write(to: helper, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

    let data = try ZCodeHooks.install(into: nil, cliPath: helper.path)
    let root = try jsonObject(data)
    let hooks = try #require(root["hooks"] as? [String: Any])
    let events = try #require(hooks["events"] as? [String: Any])
    for event in ZCodeHooks.events {
        let groups = try #require(events[event] as? [[String: Any]])
        let entries = try #require(groups[0]["hooks"] as? [[String: Any]])
        let command = try #require(entries[0]["command"] as? String)
        #expect(command.hasSuffix(HookFile.ownershipComment(marker: ZCodeHooks.marker)))

        // The command runs the way ZCode would, hides the helper's noisy
        // stdout, and still exits zero when the helper fails.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
    let logged = try String(contentsOf: log, encoding: .utf8)
    for event in ZCodeHooks.events {
        #expect(logged.contains("hook zcode \(event)"))
    }
}

@Test func zcodeRelativeCLIPathIsRefusedAtTheBoundary() {
    #expect(throws: ClaudeHooks.RelativeCLIPath.self) {
        _ = try ZCodeHooks.install(into: nil, cliPath: "helper")
    }
}
