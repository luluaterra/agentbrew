import Foundation
import LetItBrewCore

/// `letitbrew hook <agent> <event>`: read the payload on stdin, reduce it, update the
/// session record.
///
/// Returns 0 unconditionally, whatever happens. This runs on every tool call
/// of every agent turn; a non-zero exit is treated by Claude Code as a
/// blocking hook failure, so a bug here would break the user's agent rather
/// than merely fail to keep their Mac awake.
func runHook(
    agent: AgentID,
    event: String,
    storage: SessionStorage = SessionStorage(),
    environment: [String: String] = ProcessInfo.processInfo.environment
) -> Int32 {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    var payload = (try? JSONDecoder().decode(HookPayload.self, from: input)) ?? HookPayload()

    // ZCode carries the working directory in the environment, not in the
    // hook payload on stdin. Both variable names ZCode sets are accepted.
    if agent == .zcode, payload.cwd == nil {
        payload.cwd = environment["ZCODE_PROJECT_DIR"]
            ?? environment["CLAUDE_PROJECT_DIR"]
    }

    try? HookSessionUpdater.apply(
        event: event,
        payload: payload,
        agent: agent,
        agentPID: ProcessAncestry.hookAgentPID(),
        observedAt: Date(),
        storage: storage
    )
    return 0
}
