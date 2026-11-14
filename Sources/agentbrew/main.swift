import Foundation
import LetItBrewCore

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "hook":
    guard arguments.count == 3,
          let agent = AgentID(rawValue: arguments[1])
    else { exit(0) }
    exit(runHook(agent: agent, event: arguments[2]))
case "install":
    if arguments.count == 1 {
        exit(runInstall())
    }
    guard arguments.count == 2, let agent = AgentID(rawValue: arguments[1]) else {
        FileHandle.standardError.write(Data("Usage: agentbrew install [claude|codex|opencode|copilot|pi|cursor|gemini|qwen|kimi|zcode]\n".utf8))
        exit(1)
    }
    exit(runInstall(agents: [agent]))
case "uninstall":
    if arguments.count == 1 {
        exit(runUninstall())
    }
    guard arguments.count == 2, let agent = AgentID(rawValue: arguments[1]) else {
        FileHandle.standardError.write(Data("Usage: agentbrew uninstall [claude|codex|opencode|copilot|pi|cursor|gemini|qwen|kimi|zcode]\n".utf8))
        exit(1)
    }
    exit(runUninstall(agents: [agent]))
case "doctor":
    exit(runDoctor())
case "prepare-exact":
    guard arguments.count == 2, let agent = AgentID(rawValue: arguments[1]) else { exit(1) }
    exit(runPrepareExact(agent: agent, input: FileHandle.standardInput.readDataToEndOfFile()))
case "watch":
    exit(runWatch(lidClosed: arguments.contains("--lid-closed")))
case "status":
    exit(runStatus(json: arguments.contains("--json")))
case "repair":
    exit(runRepair())
case "--version":
    print("agentbrew 0.1.0")
    exit(0)
default:
    print("""
    agentbrew - keep your Mac awake while AI agents work

    Usage:
      agentbrew install [claude|codex|opencode|copilot|pi|cursor|gemini|qwen|kimi|zcode]
                              install hooks for all agents, or one agent
      agentbrew uninstall [claude|codex|opencode|copilot|pi|cursor|gemini|qwen|kimi|zcode]
                              remove hooks for all agents, or one agent
      agentbrew doctor         report install health per event
      agentbrew watch          hold the Mac awake while agents work
      agentbrew watch --lid-closed
                              also keep it awake with the lid shut (asks for
                              your password once, at startup)
      agentbrew status [--json]  one-shot board
      agentbrew repair          clear a sleep-watchdog lease left by a dead
                              watchdog loop (see `agentbrew doctor`)
      agentbrew hook <agent> <event>
                              internal: called by agent lifecycle hooks
      agentbrew --version

    Testing only:
      LETITBREW_TEST_HOME      redirect agent config paths beneath this
                              directory instead of the real home directory.
                              Takes precedence over agent home overrides. Must be an
                              absolute path.
    """)
    exit(1)
}
