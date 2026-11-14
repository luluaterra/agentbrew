import Foundation

/// One session observed in an external app's own data store, reduced to the
/// lifecycle facts the session store needs.
///
/// Polling adapters never read task prose, prompts, commands, or file
/// contents — only identities, states, working directories, and timestamps.
/// A state that cannot be determined from the source is reported as `nil`
/// and the synchronizer leaves any existing record untouched rather than
/// guessing (Unknown is never dressed up as Working).
public struct PolledSession: Equatable, Sendable {
    /// Stable per-session key from the source store. Untrusted: the
    /// synchronizer routes it through the session store's filename rules.
    public let key: String
    /// nil = undeterminable this tick; an existing record keeps its state.
    public let state: SessionState?
    /// Semantic detail token, never prose.
    public let detail: String?
    public let cwd: String?
    public let startedAt: Date?
    public let lastActivity: Date
    /// The task title from the source's own store, when it records one.
    public let title: String?
    /// A terminal session's record is deleted, matching what a SessionEnd
    /// hook would do.
    public let isTerminal: Bool

    public init(
        key: String,
        state: SessionState?,
        detail: String? = nil,
        cwd: String?,
        startedAt: Date?,
        lastActivity: Date,
        title: String? = nil,
        isTerminal: Bool = false
    ) {
        self.key = key
        self.state = state
        self.detail = detail
        self.cwd = cwd
        self.startedAt = startedAt
        self.lastActivity = lastActivity
        self.title = title
        self.isTerminal = isTerminal
    }
}

/// A read-only view into one external app's session store.
///
/// `sample()` returning `nil` means "could not read this tick" (a torn or
/// locked store, an unreadable file): the synchronizer keeps every existing
/// record as-is instead of treating the failure as evidence that work ended.
public protocol PollingAgentSource: Sendable {
    var agent: AgentID { get }
    func sample() -> [PolledSession]?
}

/// Mirrors external stores into the shared session storage so polling
/// adapters ride the same decision engine, visibility policy, and menu as
/// hook adapters.
///
/// Diff rules per tick:
/// - A polled session with no record gets one.
/// - A polled session with a record keeps its `startedAt` (SessionTimeline)
///   and updates state, detail, cwd, and freshness.
/// - A terminal polled session has its record deleted — the same effect a
///   SessionEnd hook produces.
/// - A record whose key no longer appears in the sample is deleted: the
///   source store is the authority for polling agents, and a vanished row
///   cannot answer a hook that will never come.
/// - `state == nil` leaves an existing record's state untouched.
///
/// Updates use plain (unordered) mutation on purpose: these agents have no
/// hooks, so no other writer contends for the record.
public struct PollingSessionSynchronizer: Sendable {
    let storage: SessionStorage

    public init(storage: SessionStorage = SessionStorage()) {
        self.storage = storage
    }

    public func apply(_ source: PollingAgentSource, now: Date) {
        let agent = source.agent
        guard let polled = source.sample() else { return }

        let polledByID = Dictionary(polled.map { polled in
            (Self.recordID(agent: agent, key: polled.key), polled)
        }, uniquingKeysWith: { first, _ in first })

        for (id, polled) in polledByID {
            let key = Self.storageKey(for: id)
            if polled.isTerminal {
                storage.delete(id: key)
                continue
            }
            let previous = storage.load(id: key)
            // An undeterminable state keeps the record as-is; Unknown is
            // never dressed up as Working.
            guard let state = polled.state ?? previous?.state else { continue }
            // The source's own start time is authoritative when it has one;
            // otherwise the session keeps its previous start (or starts now).
            let transition = SessionStateTransition.resolve(
                previous: previous, newState: state, now: now
            )
            let record = SessionRecord(
                id: id,
                tool: agent.rawValue,
                state: state,
                detail: polled.detail ?? previous?.detail,
                cwd: polled.cwd ?? previous?.cwd ?? "",
                pid: nil,
                updatedAt: max(now, polled.lastActivity),
                lastEvent: previous?.lastEvent,
                startedAt: polled.startedAt
                    ?? SessionTimeline.startedAt(previous: previous, now: now),
                stateChangedAt: transition.changedAt,
                stateTransitionID: transition.id,
                title: polled.title ?? previous?.title
            )
            try? storage.mutate(id: key) { _ in .replace(record) }
        }

        // Records the source no longer lists are gone from the source's own
        // authority — delete them, exactly as a SessionEnd would.
        for record in storage.loadAll() where record.tool == agent.rawValue {
            if polledByID[record.id] == nil {
                storage.delete(id: Self.storageKey(for: record.id))
            }
        }
    }

    /// The record identity a polled session maps to. Polling records are
    /// parent-only: these agents expose no subagent edges.
    public static func recordID(agent: AgentID, key: String) -> String {
        HookRecordID(agent: agent, parentID: key)?.encoded
            ?? "v1|1:\(agent.rawValue)|0:\(key)"
    }

    /// SessionStorage routes lookups through `safeFilename(for:)`; the same
    /// transformation must map an encoded record id to its storage key on
    /// both write and delete.
    static func storageKey(for recordID: String) -> String {
        recordID
    }
}
