import Foundation
import SQLite3
import Testing
@testable import LetItBrewCore

// MARK: - WorkBuddySource

private func makeFixtureDatabase(
    status: String,
    lastActivityMs: Int64,
    deleted: Bool = false
) -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentbrew-wb-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("workbuddy.db")

    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK else {
        fatalError("fixture db open failed")
    }
    let create = """
    CREATE TABLE sessions (
        id TEXT PRIMARY KEY, cwd TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'Pending',
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
        last_activity_at INTEGER, deleted_at INTEGER
    );
    INSERT INTO sessions (id, cwd, status, created_at, updated_at, last_activity_at, deleted_at)
    VALUES ('row-1', '/fixture/project', '\(status)', 1000, 1000, \(lastActivityMs),
            \(deleted ? "1000" : "NULL"));
    """
    guard sqlite3_exec(db, create, nil, nil, nil) == SQLITE_OK else {
        fatalError("fixture db exec failed")
    }
    sqlite3_close_v2(db)
    return url
}

private func fixtureDate() -> Date {
    // The real clock, truncated to whole seconds: session records round-trip
    // through ISO-8601 encoding, which has no sub-second precision.
    Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded())
}

private func ms(_ date: Date, offset: TimeInterval) -> Int64 {
    Int64((date.timeIntervalSince1970 + offset) * 1000)
}

@Test func workBuddyActiveFreshRowIsWorking() throws {
    let now = fixtureDate()
    let source = WorkBuddySource(
        agent: .workbuddy,
        databaseURL: makeFixtureDatabase(status: "active", lastActivityMs: ms(now, offset: -10)),
        workingFreshness: 300
    )
    let sessions = try #require(source.sample())
    #expect(sessions.count == 1)
    #expect(sessions[0].state == .working)
    #expect(sessions[0].isTerminal == false)
    #expect(sessions[0].cwd == "/fixture/project")
    #expect(sessions[0].startedAt?.timeIntervalSince1970 == 1.0)
}

@Test func workBuddyStaleActiveRowReadsAsEndedNotWorking() throws {
    let now = fixtureDate()
    let source = WorkBuddySource(
        agent: .workbuddy,
        databaseURL: makeFixtureDatabase(status: "active", lastActivityMs: ms(now, offset: -600)),
        workingFreshness: 300
    )
    let sessions = try #require(source.sample())
    #expect(sessions[0].state == nil)
    #expect(sessions[0].isTerminal == true)
}

@Test func workBuddyCompletedAndErrorRowsAreTerminal() throws {
    let now = fixtureDate()
    for status in ["completed", "error"] {
        let source = WorkBuddySource(
            agent: .workbuddy,
            databaseURL: makeFixtureDatabase(status: status, lastActivityMs: ms(now, offset: -10)),
            workingFreshness: 300
        )
        let sessions = try #require(source.sample())
        #expect(sessions[0].isTerminal == true)
    }
}

@Test func workBuddyUnknownStatusIsUndeterminableNotWorking() throws {
    let now = fixtureDate()
    let source = WorkBuddySource(
        agent: .workbuddy,
        databaseURL: makeFixtureDatabase(status: "Pending", lastActivityMs: ms(now, offset: -10)),
        workingFreshness: 300
    )
    let sessions = try #require(source.sample())
    #expect(sessions[0].state == nil)
    #expect(sessions[0].isTerminal == false)
}

@Test func workBuddyDeletedRowIsNotReported() throws {
    let now = fixtureDate()
    let source = WorkBuddySource(
        agent: .workbuddy,
        databaseURL: makeFixtureDatabase(
            status: "active", lastActivityMs: ms(now, offset: -10), deleted: true
        ),
        workingFreshness: 300
    )
    let sessions = try #require(source.sample())
    #expect(sessions.isEmpty)
}

@Test func workBuddyMissingDatabaseIsANilTickNotAnEmptyOne() {
    let source = WorkBuddySource(
        agent: .workbuddy,
        databaseURL: URL(fileURLWithPath: "/nonexistent/agentbrew/workbuddy.db")
    )
    // nil = "could not read this tick": the synchronizer must keep existing
    // records rather than read a failure as evidence work ended.
    #expect(source.sample() == nil)
}

@Test func workBuddyEditionsReadTheirOwnRoots() {
    let home = URL(fileURLWithPath: "/Users/me")
    #expect(WorkBuddySource.domestic(home: home).databaseURL.path == "/Users/me/.workbuddy/workbuddy.db")
    #expect(WorkBuddySource.domestic(home: home).agent == .workbuddy)
    #expect(WorkBuddySource.international(home: home).databaseURL.path == "/Users/me/.workbuddy-ai/workbuddy.db")
    #expect(WorkBuddySource.international(home: home).agent == .workbuddyai)
}

// MARK: - DoubaoSource

private func makeFixtureSnapshot(
    root: URL, execution: String, startedAtMs: Int64, endedAtMs: Int64?
) throws {
    let directory = root
        .appendingPathComponent("user1", isDirectory: true)
        .appendingPathComponent("conv", isDirectory: true)
        .appendingPathComponent(execution, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let ended: String = endedAtMs.map { "\($0)" } ?? "0"
    let json = """
    {"execution": {"executionKey": "\(execution)", "startedAtMs": \(startedAtMs),
     "endedAtMs": \(ended)}, "files": []}
    """
    try json.write(
        to: directory.appendingPathComponent("snap1.json"),
        atomically: true, encoding: .utf8
    )
}

@Test func doubaoRunningExecutionIsWorkingAndEndedIsTerminal() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentbrew-doubao-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let now = Date()
    try makeFixtureSnapshot(
        root: root, execution: "exec-running", startedAtMs: ms(now, offset: -60), endedAtMs: nil
    )
    try makeFixtureSnapshot(
        root: root, execution: "exec-done", startedAtMs: ms(now, offset: -600), endedAtMs: ms(now, offset: -100)
    )

    let source = DoubaoSource(snapshotRoot: root, workingFreshness: 300)
    let sessions = try #require(source.sample())
    let byKey = Dictionary(uniqueKeysWithValues: sessions.map { ($0.key, $0) })
    #expect(byKey["exec-running"]?.state == .working)
    #expect(byKey["exec-done"]?.isTerminal == true)
}

@Test func doubaoQuietExecutionReadsAsEnded() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentbrew-doubao-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let now = Date()
    try makeFixtureSnapshot(
        root: root, execution: "exec-quiet", startedAtMs: ms(now, offset: -900), endedAtMs: nil
    )
    // The snapshot file was written 10 minutes ago: make its mtime honest.
    let quiet = root
        .appendingPathComponent("user1", isDirectory: true)
        .appendingPathComponent("conv", isDirectory: true)
        .appendingPathComponent("exec-quiet", isDirectory: true)
        .appendingPathComponent("snap1.json")
    try FileManager.default.setAttributes(
        [.modificationDate: now.addingTimeInterval(-600)], ofItemAtPath: quiet.path
    )

    let source = DoubaoSource(snapshotRoot: root, workingFreshness: 300)
    let sessions = try #require(source.sample())
    #expect(sessions[0].isTerminal == true)
}

@Test func doubaoMissingRootIsEmptyNotFailure() {
    let source = DoubaoSource(
        snapshotRoot: URL(fileURLWithPath: "/nonexistent/agentbrew/snapshot")
    )
    #expect(source.sample() == [])
}

// MARK: - PollingSessionSynchronizer

private struct FixedSource: PollingAgentSource {
    let agent: AgentID
    let sessions: [PolledSession]?
    func sample() -> [PolledSession]? { sessions }
}

@Test func synchronizerMirrorsThenTerminalsThenKeepsOnNilTick() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentbrew-sync-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = SessionStorage(directory: directory)
    let synchronizer = PollingSessionSynchronizer(storage: storage)
    let now = fixtureDate()

    let working = PolledSession(
        key: "s-1", state: .working, cwd: "/tmp", startedAt: now.addingTimeInterval(-30),
        lastActivity: now
    )
    let idle = PolledSession(
        key: "s-2", state: .idle, cwd: "/tmp", startedAt: now.addingTimeInterval(-60),
        lastActivity: now
    )
    synchronizer.apply(FixedSource(agent: .workbuddy, sessions: [working, idle]), now: now)
    var records = storage.loadAll()
    #expect(records.count == 2)
    let workingRecord = try #require(records.first { $0.tool == "workbuddy" && $0.state == .working })
    #expect(workingRecord.cwd == "/tmp")
    #expect(workingRecord.effectiveStartedAt == now.addingTimeInterval(-30))
    let workingID = workingRecord.id

    // The same key keeps its startedAt across ticks instead of resetting.
    synchronizer.apply(FixedSource(agent: .workbuddy, sessions: [working, idle]), now: now.addingTimeInterval(2))
    records = storage.loadAll()
    #expect(records.first { $0.id == workingID }?.effectiveStartedAt == now.addingTimeInterval(-30))

    // A nil tick (torn read) keeps every record as-is.
    synchronizer.apply(FixedSource(agent: .workbuddy, sessions: nil), now: now.addingTimeInterval(4))
    #expect(storage.loadAll().count == 2)

    // The source's own authority: a vanished row is deleted, a terminal row
    // is deleted, and an undeterminable state leaves the record untouched.
    let vanished = PolledSession(
        key: "s-1", state: nil, cwd: nil, startedAt: nil, lastActivity: now, isTerminal: true
    )
    let undeterminable = PolledSession(
        key: "s-2", state: nil, cwd: nil, startedAt: nil, lastActivity: now, isTerminal: false
    )
    synchronizer.apply(
        FixedSource(agent: .workbuddy, sessions: [undeterminable]), now: now.addingTimeInterval(6)
    )
    records = storage.loadAll()
    #expect(records.count == 1)
    #expect(records[0].id == recordID(agent: .workbuddy, key: "s-2"))
    #expect(records[0].state == .idle)
}

private func recordID(agent: AgentID, key: String) -> String {
    PollingSessionSynchronizer.recordID(agent: agent, key: key)
}
