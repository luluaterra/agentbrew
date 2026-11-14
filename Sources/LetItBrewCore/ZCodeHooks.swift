import Foundation

/// ZCode's user-level hook configuration.
///
/// ZCode is a Node engine (`zcode.cjs`) inside an Electron shell. Its hook
/// runner reads the top-level `hooks` key of `~/.zcode/cli/config.json` —
/// the same file that carries `mcp.servers` and plugin state, so every
/// foreign key here belongs to something else and must survive. The inner
/// group shape is the one `HookFile` already models (`event -> [group]`,
/// each group holding a `hooks` array of `command` entries); ZCode only
/// nests it one level deeper, under `hooks.events`.
///
/// Two ZCode-specific rules shape this adapter:
///
/// 1. Configuration-file hooks are **disabled by default**: the runner only
///    starts when `hooks.enabled` is `true`. Installing sets it. That is a
///    visible side effect on other config-file hooks the user parked with
///    `enabled: false` — they start running too. Removal restores the
///    pre-install state by removing the whole `hooks` key when nothing
///    survives; while foreign events remain, `enabled` stays as the user
///    has effectively been living with it.
/// 2. A command hook's `timeout` is in **seconds**, matching `HookFile.entry`.
///
/// The vendor event names match the names `HookReducer` maps one for one,
/// so no event-name translation is needed.
public enum ZCodeHooks {
    /// Ownership marker. Frozen: released versions must recognize each
    /// other's entries, so changing this orphans every existing install.
    public static let marker = "__agentbrew_zcode_hook"

    /// Exactly the seven events ZCode's hook runner supports. The runner
    /// rejects any other name, and `Notification`, `SubagentStop`, and
    /// `PreCompact` do not exist in ZCode.
    public static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
        "PostToolUse", "PostToolUseFailure", "Stop",
    ]

    /// ZCode command hooks take `timeout` in seconds.
    static let timeoutSeconds = 5

    public static func configURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home
            .appendingPathComponent(".zcode", isDirectory: true)
            .appendingPathComponent("cli", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    /// The fail-open shell command for one ZCode event: absolute paths, the
    /// trailing `:` pinning exit 0 (ZCode treats non-zero as a hook failure
    /// and `2` as a deliberate block, which an observational hook must never
    /// send), and the ownership sentinel as the exact end of the string.
    public static func hookCommand(event: String, cliPath: String) throws -> String {
        guard cliPath.hasPrefix("/") else { throw ClaudeHooks.RelativeCLIPath(cliPath) }
        return "c=\(ClaudeHooks.shellSingleQuoted(cliPath)); "
            + "[ -x \"$c\" ] || c=\(ClaudeHooks.shellSingleQuoted(ClaudeHooks.fallbackCLIPath)); "
            + "\"$c\" hook zcode \(event) >/dev/null 2>&1; "
            + HookFile.ownershipComment(marker: marker)
    }

    /// The `hooks` value from a parsed root, shared with Claude's rules: `[:]`
    /// if absent, the dictionary if the expected shape, a throw otherwise.
    private static func hooksDictionary(_ root: [String: Any]) throws -> [String: Any] {
        try ClaudeHooks.hooksDictionary(root)
    }

    /// The `hooks.events` value: `[:]` if absent, the dictionary if the
    /// expected shape, a throw otherwise.
    private static func eventsDictionary(_ hooks: [String: Any]) throws -> [String: Any] {
        guard let value = hooks["events"] else { return [:] }
        guard let events = value as? [String: Any] else {
            throw ClaudeHooks.SettingsUnreadable()
        }
        try ClaudeHooks.requireEventArrays(events)
        return events
    }

    /// Merges one entry per supported event, preserving every foreign key —
    /// `mcp.servers`, plugin state, and any other hook events — verbatim.
    /// Sweeping ours out of every event first makes reinstall idempotent and
    /// self-healing for a baked path that no longer resolves.
    public static func install(into data: Data?, cliPath: String) throws -> Data {
        var root = try ClaudeHooks.parseRoot(data)
        var hooks = try hooksDictionary(root)
        var events = try eventsDictionary(hooks)
        events = HookFile.sweep(events, marker: marker)
        for event in ZCodeHooks.events.sorted() {
            var groups = (events[event] as? [Any]) ?? []
            groups.append(HookFile.entry(
                command: try hookCommand(event: event, cliPath: cliPath),
                timeout: timeoutSeconds,
                matcher: nil
            ))
            events[event] = groups
        }
        hooks["events"] = events
        // ZCode's hook runner is off unless configuration-file hooks say so.
        // See the type doc comment for what this means for parked foreign
        // hooks.
        hooks["enabled"] = true
        root["hooks"] = hooks
        return try ClaudeHooks.serialize(root)
    }

    /// Removes exactly the entries carrying our marker. When nothing of ours
    /// remains anywhere, the whole `hooks` key goes with them — restoring the
    /// file ZCode had before this adapter ever touched it. Foreign events
    /// survive, and with them the enabled runner they have been using.
    public static func remove(from data: Data?) throws -> Data {
        var root = try ClaudeHooks.parseRoot(data)
        let hooks = try hooksDictionary(root)
        let events = try eventsDictionary(hooks)
        let swept = HookFile.sweep(events, marker: marker)
        if swept.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            var kept = hooks
            kept["events"] = swept
            root["hooks"] = kept
        }
        return try ClaudeHooks.serialize(root)
    }

    /// Classifies the current install, event by event. Unreadable
    /// configuration reports as fully missing rather than throwing: this
    /// drives a status display that must always render something, whereas
    /// `install` is the path that genuinely has to refuse.
    public static func report(for data: Data?, cliPath: String) -> HookInstallReport {
        let events: [String: Any]? = try? {
            let hooks = try hooksDictionary(try ClaudeHooks.parseRoot(data))
            return try eventsDictionary(hooks)
        }()
        return HookFile.report(
            hooks: events,
            events: ZCodeHooks.events,
            marker: marker,
            expectedCommand: { (try? hookCommand(event: $0, cliPath: cliPath)) ?? "" }
        )
    }
}
