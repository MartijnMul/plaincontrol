import Foundation

/// What to tell the user about a session's status change, if anything.
public enum SessionAlert: Sendable, Equatable {
    /// The session started waiting for the user.
    case waiting(WaitingReason)
    /// The session finished a turn without asking anything.
    case finished

    /// How long an alert waits before it is shown. A change within that time, such as the
    /// user answering a permission prompt they were looking at, withdraws it unseen.
    public static let gracePeriod: TimeInterval = 5

    /// The alert a status change calls for: a session that starts waiting, or one that
    /// goes from working to idle. Nil for every other change.
    public init?(for change: StatusChange) {
        switch (change.from, change.to) {
        case (_, .waiting(let reason)): self = .waiting(reason)
        case (.working?, .idle): self = .finished
        default: return nil
        }
    }
}

extension StatusChange {
    /// Whether an alert already shown for the session is out of date after this change,
    /// because the session is working again or has ended.
    public var withdrawsShownAlert: Bool {
        to == .working || to == .gone
    }
}
