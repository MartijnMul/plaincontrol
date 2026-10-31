import Foundation

/// When Plaincontrol may restart by itself to install an update it downloaded: while the user
/// is away, so nothing closes under their hands (ADR 0008).
public enum QuietRestart {
    /// How long without keyboard or mouse input counts as away.
    public static let idleTime: TimeInterval = 10 * 60
    /// How often to look again while an update waits.
    public static let checkInterval: TimeInterval = 60

    /// Whether now is the moment: the screen is locked or the user has been away for
    /// ``idleTime``, and none of Plaincontrol's windows is open, such as the launcher or the
    /// settings, which the user may come back to.
    public static func isGoodMoment(idleFor idle: TimeInterval, screenLocked: Bool, windowOpen: Bool) -> Bool {
        !windowOpen && (screenLocked || idle >= idleTime)
    }
}
