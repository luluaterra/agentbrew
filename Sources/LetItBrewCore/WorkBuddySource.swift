import Foundation
import SQLite3

/// Reads WorkBuddy's own `sessions` table (both the domestic `~/.workbuddy`
/// and international `~/.workbuddy-ai` editions share one schema) into the
/// shared session lifecycle.
///
/// Read-only discipline, in order of preference:
/// 1. `mode=ro` — the normal reader when a `-shm` exists or no writer is
///    active.
/// 2. `immutable=1` — the store was written with WAL; without a `-shm` a
///    plain reader cannot attach. Immutable skips locking entirely: a
///    concurrent writer may hand us a torn page, so every parse is guarded
///    and a failed read reports `nil` ("no sample this tick") rather than
///    evidence that work ended.
///
/// Only lifecycle facts are read: id, cwd, status, timestamps. Titles,
/// prompts, and model fields are never touched.
///
/// Status mapping (values observed on 5.9.3/5.9.4): `active` → Working,
/// `completed`/`error` → terminal record removed, anything else (including
/// the legacy `Pending` default) → undeterminable: no record is created or
/// updated, per the Unknown-is-not-Working rule.
public struct WorkBuddySource: PollingAgentSource {
    public let agent: AgentID
    public let databaseURL: URL
    /// The store keeps `active` rows after the app quits without finalizing
    /// them, so a Working hold is only trusted while the row's own activity
    /// timestamp is this fresh. A stale row reads as the session having ended
    /// without a terminal write — the honest opposite of dressing Unknown up
    /// as Working forever.
    public let workingFreshness: TimeInterval

    public init(
        agent: AgentID,
        databaseURL: URL,
        workingFreshness: TimeInterval = 300
    ) {
        self.agent = agent
        self.databaseURL = databaseURL
        self.workingFreshness = workingFreshness
    }

    /// Domestic edition.
    public static func domestic(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> WorkBuddySource {
        WorkBuddySource(
            agent: .workbuddy,
            databaseURL: home
                .appendingPathComponent(".workbuddy/workbuddy.db")
        )
    }

    /// International edition; same schema, different root.
    public static func international(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> WorkBuddySource {
        WorkBuddySource(
            agent: .workbuddyai,
            databaseURL: home
                .appendingPathComponent(".workbuddy-ai/workbuddy.db")
        )
    }

    public func sample() -> [PolledSession]? {
        if let sessions = query(mode: "?mode=ro") { return sessions }
        return query(mode: "?immutable=1")
    }

    private func query(mode: String) -> [PolledSession]? {
        var db: OpaquePointer?
        let path = "file:\(databaseURL.path)\(mode)"
        guard sqlite3_open_v2(
            path, &db,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil
        ) == SQLITE_OK else {
            sqlite3_close_v2(db)
            return nil
        }
        defer { sqlite3_close_v2(db) }

        let statementSQL = """
        SELECT id, cwd, status, created_at, updated_at,
               COALESCE(last_activity_at, updated_at),
               COALESCE(NULLIF(custom_title, ''), NULLIF(title, ''))
        FROM sessions WHERE deleted_at IS NULL
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, statementSQL, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        var sessions: [PolledSession] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = Self.text(statement, 0),
                  let cwd = Self.text(statement, 1),
                  let status = Self.text(statement, 2)
            else { continue }
            let startedAt = Self.date(statement, 3)
            let lastActivity = Self.date(statement, 5)
                ?? startedAt
                ?? Date(timeIntervalSince1970: 0)
            // The app's own task title (custom first, then generated).
            let title = Self.text(statement, 6)

            var mapped = Self.map(status: status)
            if mapped.state == .working,
               Date().timeIntervalSince(lastActivity) > workingFreshness {
                // Stale beyond the freshness gate: treat as ended without a
                // terminal write rather than holding the Mac awake forever.
                mapped = (nil, nil, true)
            }
            sessions.append(PolledSession(
                key: id,
                state: mapped.state,
                detail: mapped.detail,
                cwd: cwd,
                startedAt: startedAt,
                lastActivity: lastActivity,
                title: Self.cleanTitle(title),
                isTerminal: mapped.isTerminal
            ))
        }
        return sessions
    }

    /// First line only, markdown header marks stripped, bounded — a board
    /// row shows one line. Never reads anything but the title column.
    static func cleanTitle(_ raw: String?) -> String? {
        guard var title = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { return nil }
        if title.hasPrefix("#") {
            title = title.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        }
        title = title.components(separatedBy: .newlines)[0]
            .trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return title.count <= 80 ? title : String(title.prefix(80))
    }

    private static func map(
        status: String
    ) -> (state: SessionState?, detail: String?, isTerminal: Bool) {
        switch status {
        case "active": (.working, nil, false)
        case "completed", "error": (nil, nil, true)
        default: (nil, nil, false)
        }
    }

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: cString)
    }

    /// The store keeps epoch milliseconds; a zero or negative column means
    /// "never", which reads as nil rather than the epoch.
    private static func date(_ statement: OpaquePointer?, _ column: Int32) -> Date? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        let milliseconds = sqlite3_column_int64(statement, column)
        guard milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }
}
