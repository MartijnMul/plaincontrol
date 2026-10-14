import Foundation

/// When each project was last used, so the launcher can show the most recent first.
///
/// A project counts as used when the user runs an action on it from the launcher, and when a
/// Claude Code session in its folder reports an event.
public struct ProjectRecency: Codable, Sendable, Equatable {
    /// The last use from the launcher, per project path.
    public private(set) var lastUsed: [String: Date] = [:]

    public init() {}

    public mutating func markUsed(_ project: Project, at date: Date = .now) {
        lastUsed[project.path] = date
    }

    /// The most recent use of `project`, from the launcher or a session, if any.
    public func lastUse(of project: Project, sessions: [Session]) -> Date? {
        let sessionUse =
            sessions
            .filter { session in session.cwd.map(project.contains) ?? false }
            .map(\.lastEventAt)
            .max()
        return [lastUsed[project.path], sessionUse].compactMap(\.self).max()
    }

    /// `projects` with the most recently used first; projects never used keep their order, last.
    public func ordered(_ projects: [Project], sessions: [Session]) -> [Project] {
        projects.enumerated()
            .map { (index: $0.offset, project: $0.element, used: lastUse(of: $0.element, sessions: sessions)) }
            .sorted { a, b in
                switch (a.used, b.used) {
                case (let x?, let y?) where x != y: x > y
                case (.some, nil): true
                case (nil, .some): false
                default: a.index < b.index
                }
            }
            .map(\.project)
    }
}
