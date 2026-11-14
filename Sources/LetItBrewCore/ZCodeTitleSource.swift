import Foundation
import SQLite3

/// Enriches ZCode session records with the task title ZCode itself records
/// in its session database (`~/.zcode/cli/db/db.sqlite`, `session.title`).
///
/// The hook payload carries no title, so this is the only source for the
/// "what is this task" line on the board. Titles are metadata — first line,
/// header marks stripped, bounded. Conversation content beyond the title
/// column is never read.
public struct ZCodeTitleSource: Sendable {
    public let databaseURL: URL

    public init(databaseURL: URL = ZCodeTitleSource.defaultDatabaseURL) {
        self.databaseURL = databaseURL
    }

    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zcode/cli/db/db.sqlite")
    }

    public init(databasePath: String) {
        self.databaseURL = URL(fileURLWithPath: databasePath)
    }

    /// session id → title. `nil` on any read failure: enrichment is additive
    /// and a torn read keeps the previous titles rather than clearing them.
    public func titles() -> [String: String]? {
        if let titles = query(mode: "?mode=ro") { return titles }
        return query(mode: "?immutable=1")
    }

    private func query(mode: String) -> [String: String]? {
        var db: OpaquePointer?
        let path = "file:\(databaseURL.path)\(mode)"
        guard sqlite3_open_v2(
            path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil
        ) == SQLITE_OK else {
            sqlite3_close_v2(db)
            return nil
        }
        defer { sqlite3_close_v2(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            db, "SELECT id, title FROM session WHERE title IS NOT NULL", -1,
            &statement, nil
        ) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        var titles: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = Self.text(statement, 0) else { continue }
            let title = Self.text(statement, 1)
                .flatMap(Self.cleanTitle)
            if let title { titles[id] = title }
        }
        return titles
    }

    /// Applies the titles to every ZCode record already in the store. Only
    /// the title field changes; state and lifecycle stay hook-owned.
    public func apply(to storage: SessionStorage) {
        guard let fetched = titles() else { return }
        for record in storage.loadAll() where record.tool == AgentID.zcode.rawValue {
            guard let parsed = HookRecordID(encoded: record.id) else { continue }
            guard let title = fetched[parsed.parentID], title != record.title else { continue }
            var updated = record
            updated.title = title
            try? storage.mutate(id: record.id) { _ in .replace(updated) }
        }
    }

    static func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: cString)
    }

    /// First line, markdown header marks stripped, bounded to the board row.
    static func cleanTitle(_ raw: String) -> String? {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        if title.hasPrefix("#") {
            title = title.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        }
        title = title.components(separatedBy: .newlines)[0]
            .trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return title.count <= 80 ? title : String(title.prefix(80))
    }
}
