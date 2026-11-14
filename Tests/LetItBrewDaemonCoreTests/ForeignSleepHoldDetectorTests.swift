import Foundation
import Testing
@testable import LetItBrewDaemonCore

@Test func absentForeignDirectoryMeansNoForeignHold() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentbrew-foreign-\(UUID().uuidString)")
    let detector = ForeignSleepHoldDetector(directory: directory)

    #expect(!detector.holdsSystemSleep())
}

@Test func aForeignSleepDebtRecordProvesAForeignHold() throws {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentbrew-foreign-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let detector = ForeignSleepHoldDetector(directory: base)

    #expect(!detector.holdsSystemSleep())
    try Data().write(to: base.appendingPathComponent("com.ruban24.letitbrew.daemon.sleep-debt.json"))
    #expect(detector.holdsSystemSleep())

    try FileManager.default.removeItem(
        at: base.appendingPathComponent("com.ruban24.letitbrew.daemon.sleep-debt.json")
    )
    #expect(!detector.holdsSystemSleep())
}

@Test func unrelatedForeignFilesAreNotAHold() throws {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentbrew-foreign-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let detector = ForeignSleepHoldDetector(directory: base)

    try Data().write(to: base.appendingPathComponent("com.ruban24.letitbrew.daemon.power-mode-debt.json"))
    try Data().write(to: base.appendingPathComponent("notes.txt"))
    try FileManager.default.createDirectory(
        at: base.appendingPathComponent("sleep-debt.json.d"),
        withIntermediateDirectories: true
    )

    #expect(!detector.holdsSystemSleep())
}

@Test func anUnreadableForeignDirectoryFailsClosed() throws {
    // Root reads through any mode bits, so the fixture cannot be made
    // unreadable there and the expectation below would be vacuous-false.
    guard geteuid() != 0 else { return }
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentbrew-foreign-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    let detector = ForeignSleepHoldDetector(directory: base)

    guard setchmod(base.path, 0o000) == 0 else {
        Issue.record("Could not make the fixture directory unreadable")
        try? setchmod(base.path, 0o755)
        return
    }
    defer { _ = setchmod(base.path, 0o755); try? FileManager.default.removeItem(at: base) }

    // "Cannot rule out" is the same as "holds": refuse rather than guess,
    // matching every other unreadable state this codebase touches.
    #expect(detector.holdsSystemSleep())
}

/// `chmod(2)` as a free function so the defer above can run even on failure.
private func setchmod(_ path: String, _ mode: mode_t) -> Int32 {
    chmod(path, mode)
}
