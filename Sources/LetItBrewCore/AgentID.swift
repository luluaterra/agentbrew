public enum AgentID: String, CaseIterable, Codable, Sendable {
    case claude
    case codex
    case opencode
    case copilot
    case pi
    case cursor
    case gemini
    case qwen
    case kimi
    case zcode
    case workbuddy
    case workbuddyai
    case doubao

    /// Owned executable adapters must never follow a same-name file symlink.
    public var ownsWholeConfigurationFile: Bool {
        self == .opencode || self == .pi
    }

    /// Subagents are records in their parent's family: a parent's terminal
    /// marker ends them both when hooks write and when storage reads. Both
    /// sides must agree, or an interrupted cleanup leaves children Working.
    public var tracksSubagentFamilies: Bool {
        self == .claude || self == .codex
    }

    /// Polling adapters read an external app's own session store instead of
    /// installed lifecycle hooks. There is nothing to install for them: their
    /// connection is the data root existing on disk.
    public var isPollingAdapter: Bool {
        self == .workbuddy || self == .workbuddyai || self == .doubao
    }

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .opencode: "OpenCode"
        case .copilot: "GitHub Copilot CLI"
        case .pi: "Pi"
        case .cursor: "Cursor"
        case .gemini: "Gemini CLI"
        case .qwen: "Qwen Code"
        case .kimi: "Kimi Code"
        case .zcode: "ZCode"
        case .workbuddy: "WorkBuddy"
        case .workbuddyai: "WorkBuddy AI"
        case .doubao: "Doubao Z"
        }
    }
}
