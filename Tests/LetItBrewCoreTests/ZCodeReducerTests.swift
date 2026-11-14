import Foundation
import Testing
@testable import LetItBrewCore

/// ZCode's hook vocabulary, mapped through the same reducer every adapter
/// shares. ZCode has seven events and no subagent edges, so every record is
/// parent-only.
private func reduce(
    _ event: String,
    toolName: String? = nil,
    source: String? = nil,
    isInterrupt: Bool = false
) -> HookEffect? {
    HookReducer.reduce(
        agent: .zcode,
        event: event,
        toolName: toolName,
        notificationType: nil,
        source: source,
        trigger: nil,
        isInterrupt: isInterrupt
    )
}

@Test func zcodeSessionStartIsIdleOnlyForAPromptlessRestartSource() {
    #expect(reduce("SessionStart", source: "startup") == .set(.idle, detail: nil))
    #expect(reduce("SessionStart", source: "resume") == .set(.idle, detail: nil))
    #expect(reduce("SessionStart", source: "clear") == .set(.idle, detail: nil))
    // A compaction restart may fire inside a running turn.
    #expect(reduce("SessionStart", source: "compact") == nil)
    #expect(reduce("SessionStart", source: nil) == .set(.idle, detail: nil))
}

@Test func zcodeTurnEventsHoldAndReleaseLikeClaudes() {
    #expect(reduce("UserPromptSubmit") == .set(.working, detail: nil))
    #expect(reduce("PostToolUse") == .set(.working, detail: nil))
    #expect(reduce("PreToolUse", toolName: "Bash")
        == .set(.working, detail: HookReducer.detailToken(forTool: "Bash")))
    #expect(reduce("Stop") == .set(.idle, detail: nil))
}

@Test func zcodeQuestionToolWaitsAndItsAnswerResumes() {
    #expect(reduce("PreToolUse", toolName: "AskUserQuestion")
        == .set(.waiting, detail: SessionWaitDetail.question))
    #expect(reduce("PostToolUse", toolName: "AskUserQuestion")
        == .set(.working, detail: nil))
}

@Test func zcodePermissionRequestProvesAPromptIsShown() {
    // Unlike Claude's, ZCode's PermissionRequest fires only when the person
    // is being asked, so it maps to Waiting directly. The answer arrives as
    // the tool's own PreToolUse, so no input latch is needed.
    #expect(reduce("PermissionRequest") == .set(.waiting, detail: SessionWaitDetail.approval))
    #expect(WaitAnswerLatch.answerIsSilent(SessionRecord(
        id: "zcode|s", tool: "zcode", state: .waiting, detail: SessionWaitDetail.approval,
        cwd: "/tmp", pid: nil, updatedAt: Date()
    )) == false)
}

@Test func zcodeToolFailureFollowsQwensInterruptRule() {
    #expect(reduce("PostToolUseFailure", isInterrupt: false)
        == .set(.working, detail: nil))
    // Esc during a tool fires this and no Stop.
    #expect(reduce("PostToolUseFailure", isInterrupt: true)
        == .set(.idle, detail: nil))
}

@Test func zcodeUnknownEventsChangeNothing() {
    #expect(reduce("Notification", toolName: nil) == nil)
    #expect(reduce("PreCompact") == nil)
    // SubagentStop is a known event name that maps to .end for every agent;
    // ZCode simply never fires it, so the mapping is unreachable in practice
    // but correct if a future ZCode build sends it.
    #expect(reduce("SubagentStop") == .end)
    #expect(reduce("SessionEnd") == .end)
    #expect(reduce("SubagentStart") == .set(.working, detail: nil))
}

@Test func zcodeRecordsAreParentOnly() {
    // ZCode sends no child session identity; every record is one session.
    let payload = HookPayload(sessionId: "sess_abc", cwd: "/work")
    #expect(payload.recordID(agent: .zcode, event: "UserPromptSubmit")
        == HookRecordID(agent: .zcode, parentID: "sess_abc")?.encoded)
    #expect(payload.recordID(agent: .zcode, event: "Stop")
        == HookRecordID(agent: .zcode, parentID: "sess_abc")?.encoded)
}
