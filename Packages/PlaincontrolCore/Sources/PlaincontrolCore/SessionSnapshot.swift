import Foundation
import PlaincontrolHooks

/// The sessions as Plaincontrol saves them when it quits, to show them again when it starts
/// soon after, as it does to install an update.
///
/// Without it, a restarted Plaincontrol would know a session only from its next hook event,
/// and a session waiting for the user sends none until the user answers. Only a restart is
/// covered: after a longer stop, a session may have moved on without Plaincontrol hearing,
/// so a snapshot older than ``maximumAge`` is not used.
public struct SessionSnapshot: Codable, Sendable, Equatable {
    /// A session with the process it runs in, which tells whether it still runs.
    public struct Entry: Codable, Sendable, Equatable {
        public var session: Session
        public var process: SessionProcess

        public init(session: Session, process: SessionProcess) {
            self.session = session
            self.process = process
        }
    }

    public var savedAt: Date
    public var entries: [Entry]

    /// How old a snapshot may be and still be used: long enough for a restart.
    public static let maximumAge: TimeInterval = 5 * 60

    /// The sessions in `registry` whose process is known, as it ends, leaving out ended ones.
    public init(_ registry: SessionRegistry, processes: [String: SessionProcess], at date: Date = .now) {
        savedAt = date
        entries = registry.sessions.values
            .filter { $0.status != .gone }
            .compactMap { session in processes[session.id].map { Entry(session: session, process: $0) } }
            .sorted { $0.session.id < $1.session.id }
    }

    /// The sessions to show again at `date`: none when the snapshot is too old, and of the
    /// rest, those whose process still runs.
    public func restorable(
        at date: Date = .now, isRunning: (SessionProcess) -> Bool = \.isRunning
    ) -> [Entry] {
        let age = date.timeIntervalSince(savedAt)
        guard age >= 0, age <= Self.maximumAge else { return [] }
        return entries.filter { isRunning($0.process) }
    }
}
