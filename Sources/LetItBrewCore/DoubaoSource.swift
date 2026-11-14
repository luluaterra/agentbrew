import Foundation

/// Polls Doubao's (豆包) agent execution snapshots into the shared session
/// lifecycle.
///
/// The desktop client exposes no hooks, CLI, or local API. Its structured
/// on-disk trace of agent executions lives under
/// `~/Library/Application Support/Doubao/coding/snapshot/<user>/<conversation>/<execution>/<snapshot>.json`
/// where each snapshot carries `execution.startedAtMs` / `execution.endedAtMs`
/// plus per-file metadata. These are internal, undocumented formats that
/// change with the app's weekly updates, so this source degrades by design:
///
/// - Only files whose required fields parse are reported; anything missing
///   or reshaped is skipped rather than guessed.
/// - `fileContents` (full user file captures) is never opened.
/// - `output.log` files under `agent_infra` are never read; the source uses
///   only the snapshot JSONs.
///
/// Two signals feed the lifecycle, because snapshots are written when an
/// execution ENDS: the newest snapshot JSON gates a finished execution, and
/// a `task_outputs/<task>/output.log` heartbeat (its modification time)
/// gates a running one. A quiet heartbeat reads as ended via the freshness
/// gate. Only file metadata is stat'd — log contents are never opened.
public struct DoubaoSource: PollingAgentSource {
    public let agent: AgentID
    public let snapshotRoot: URL
    /// Same freshness gate as WorkBuddySource: an execution without an end
    /// timestamp whose newest snapshot went quiet is treated as ended.
    public let workingFreshness: TimeInterval
    /// Injected for tests; nil auto-detects the real runtime roots.
    let taskRuntimeRootsOverride: [URL]?

    public init(
        snapshotRoot: URL = DoubaoSource.defaultSnapshotRoot,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        workingFreshness: TimeInterval = 300,
        taskRuntimeRoots: [URL]? = nil
    ) {
        self.agent = .doubao
        self.snapshotRoot = snapshotRoot
        self.workingFreshness = workingFreshness
        self.taskRuntimeRootsOverride = taskRuntimeRoots
    }

    /// The agent-mode workspace every interactive run executes inside —
    /// the honest cwd fallback when the client records no project path.
    static var agentWorkspacePath: String {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(
                "Doubao/Default/.doubao/agent_mode/workspace", isDirectory: true
            )
            .path
    }

    public static var defaultSnapshotRoot: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Doubao/coding/snapshot", isDirectory: true)
    }

    /// A snapshot JSON has `execution` (identity + timestamps) and `files`
    /// (per-file change metadata). Only the fields named here are decoded.
    private struct SnapshotEnvelope: Decodable {
        struct Execution: Decodable {
            let executionKey: String?
            let startedAtMs: Int?
            let endedAtMs: Int?
        }

        let execution: Execution
    }

    /// The runtime roots holding per-task output heartbeats and per-task
    /// working directories (`to/lr_<hash>/`).
    static func defaultTaskRuntimeRoots(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let runtimeRoot = base
            .appendingPathComponent("Doubao/Default/agent_infra/to", isDirectory: true)
        let children = (try? FileManager.default.contentsOfDirectory(
            at: runtimeRoot, includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        return children.filter { $0.lastPathComponent.hasPrefix("lr_") }
    }

    /// One heartbeat-fresh runtime instance is ONE Working session. The
    /// client spawns a `lr_<hash>/` runtime per agent session and records
    /// every sub-task's output under it, so per-task rows would flood the
    /// board with one session's internals; the runtime instance is the
    /// session grain the process tree shows (one `file_utils_host` per
    /// session). The most recently active sub-task's working directory
    /// (`non_interactive_cwd_<task>.txt` — a file whose whole purpose is to
    /// hold that path, so reading it is metadata) names the session's cwd.
    func sampleTaskHeartbeats(now: Date) -> [PolledSession] {
        var sessions: [PolledSession] = []
        for runtime in taskRuntimeRootsOverride ?? Self.defaultTaskRuntimeRoots() {
            let outputs = runtime.appendingPathComponent("task_outputs", isDirectory: true)
            guard let tasks = try? FileManager.default.contentsOfDirectory(
                at: outputs, includingPropertiesForKeys: nil
            ) else { continue }

            var freshest: (task: String, modified: Date)?
            for task in tasks {
                let log = task.appendingPathComponent("output.log")
                let attributes = try? FileManager.default.attributesOfItem(
                    atPath: log.path
                )
                guard let modified = attributes?[.modificationDate] as? Date else { continue }
                if freshest?.modified ?? .distantPast < modified {
                    freshest = (task.lastPathComponent, modified)
                }
            }
            guard let freshest, now.timeIntervalSince(freshest.modified) <= workingFreshness
            else { continue }

            let cwdURL = runtime.appendingPathComponent(
                "non_interactive_cwd_\(freshest.task).txt"
            )
            var cwd = (try? String(contentsOf: cwdURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if cwd?.isEmpty != false {
                // Interactive sessions write no cwd file (or "/"): fall back
                // to the agent workspace that genuinely hosts the run, so
                // the board shows "workspace" rather than "/".
                cwd = DoubaoSource.agentWorkspacePath
            }
            sessions.append(PolledSession(
                key: "runtime-\(runtime.lastPathComponent)",
                state: .working,
                detail: nil,
                cwd: cwd,
                startedAt: nil,
                lastActivity: freshest.modified,
                isTerminal: false
            ))
        }
        return sessions
    }

    public func sample() -> [PolledSession]? {
        var merged = sampleSnapshots() ?? []
        merged.append(contentsOf: sampleTaskHeartbeats(now: Date()))
        return merged
    }

    private func sampleSnapshots() -> [PolledSession]? {
        let enumerator = FileManager.default.enumerator(
            at: snapshotRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        // A missing root (Doubao never used for agent tasks) simply means
        // nothing to report — not a failed tick.
        guard let enumerator else { return FileManager.default.fileExists(atPath: snapshotRoot.path) ? nil : [] }

        // Newest snapshot per execution directory.
        var newest: [String: (url: URL, modified: Date)] = [:]
        for case let url as URL in enumerator {
            guard url.pathExtension == "json" else { continue }
            let executionID = url.deletingLastPathComponent().lastPathComponent
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if newest[executionID]?.modified ?? .distantPast < modified {
                newest[executionID] = (url, modified)
            }
        }

        var sessions: [PolledSession] = []
        for (executionID, entry) in newest {
            guard let data = try? Data(contentsOf: entry.url),
                  let envelope = try? JSONDecoder().decode(SnapshotEnvelope.self, from: data),
                  let startedAtMs = envelope.execution.startedAtMs,
                  startedAtMs > 0
            else { continue }

            let startedAt = Date(timeIntervalSince1970: Double(startedAtMs) / 1000)
            let endedAtMs = envelope.execution.endedAtMs ?? 0
            var isTerminal = endedAtMs > 0
            let lastActivity = isTerminal
                ? Date(timeIntervalSince1970: Double(endedAtMs) / 1000)
                : entry.modified
            if !isTerminal,
               Date().timeIntervalSince(lastActivity) > workingFreshness {
                isTerminal = true
            }

            sessions.append(PolledSession(
                key: executionID,
                state: isTerminal ? nil : .working,
                detail: nil,
                cwd: snapshotRoot.deletingLastPathComponent().path,
                startedAt: startedAt,
                lastActivity: lastActivity,
                isTerminal: isTerminal
            ))
        }
        return sessions
    }
}
