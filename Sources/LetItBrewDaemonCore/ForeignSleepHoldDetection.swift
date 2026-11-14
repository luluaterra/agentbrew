import Foundation

/// Detects a system-sleep hold owned by the separately installed upstream
/// AgentBrew, so AgentBrew never fights it over the one global
/// `SleepDisabled` flag.
///
/// The flag is system-wide and a hold cannot be attributed to an owner by
/// reading it. Each app records whatever value it finds as its own restore
/// baseline, so two independent managers can strand `SleepDisabled 1`:
/// B records A's intentional `1` as B's prior, A releases to `0`, then B's
/// "restore" writes `1` back. AgentBrew therefore treats an active foreign
/// hold as a refusal condition on acquire and as a deferral condition on
/// restore, and never mutates the flag while one exists.
///
/// The upstream daemon's own restore record is the authoritative signal: it
/// exists exactly between its acquire and its confirmed release, so a
/// `.sleep-debt.json` file in its state directory proves a live (or owed)
/// foreign hold. Nothing in that directory is ever read or modified here.
public protocol ForeignSleepHoldDetecting: AnyObject, Sendable {
    /// True while a foreign restore record exists, or while its presence
    /// cannot be ruled out.
    func holdsSystemSleep() -> Bool
}

public final class ForeignSleepHoldDetector: ForeignSleepHoldDetecting {
    /// The upstream daemon's root-owned state directory. Existence checks need
    /// only a directory listing, never a file read, so mode-0600 records pose
    /// no obstacle.
    public static let upstreamStateDirectory = URL(
        fileURLWithPath: "/Library/Application Support/LetItBrew",
        isDirectory: true
    )

    public static let acquireRefusalMessage =
        "AgentBrew cannot take the closed-lid hold: AgentBrew already owns "
            + "the system sleep setting. Quit AgentBrew or turn off its "
            + "closed-lid mode, then try again."
    public static let restoreDeferralMessage =
        "AgentBrew deferred restoring the system sleep setting because Let It "
            + "Brew holds it right now. The restore retries automatically "
            + "once that version releases its hold."

    public let directory: URL

    public init(directory: URL = ForeignSleepHoldDetector.upstreamStateDirectory) {
        self.directory = directory
    }

    public func holdsSystemSleep() -> Bool {
        do {
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            return names.contains { $0.hasSuffix(ForeignSleepHoldDetector.debtSuffix) }
        } catch {
            // A missing directory is conclusive: nothing foreign was ever
            // recorded. Any other listing failure (an unreadable parent, a
            // foreign file where the directory belongs) is not evidence of
            // absence — fail closed, same as every other unreadable state
            // this codebase touches.
            return !Self.isDirectoryAbsent(error)
        }
    }

    private static let debtSuffix = ".sleep-debt.json"

    private static func isDirectoryAbsent(_ error: Error) -> Bool {
        let cocoa = error as NSError
        return cocoa.domain == NSCocoaErrorDomain
            && (cocoa.code == NSFileReadNoSuchFileError || cocoa.code == NSFileNoSuchFileError)
    }
}
