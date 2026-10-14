import Foundation

/// When the user used each folder, to rank projects by how often and how recently they are
/// used ("frecency").
///
/// A use is an action from the launcher, or the start of a Claude Code session in the folder.
/// Each use counts for less as it gets older, halving every ``halfLife``, so a project used
/// every day stays ahead of one used once yesterday, while a project used all week rises fast.
public struct ProjectUsage: Codable, Sendable, Equatable {
    public struct Use: Codable, Sendable, Equatable {
        public var path: String
        public var date: Date
    }

    /// The uses, oldest first.
    public private(set) var uses: [Use] = []

    public static let halfLife: TimeInterval = 7 * 24 * 3600
    /// How many uses are kept; older ones count for almost nothing anyway.
    public static let limit = 1000

    public init() {}

    public mutating func record(_ path: String, at date: Date = .now) {
        uses.append(Use(path: (path as NSString).standardizingPath, date: date))
        if uses.count > Self.limit { uses.removeFirst(uses.count - Self.limit) }
    }

    /// The folders used, most recent first, each once.
    public var paths: [String] {
        var seen = Set<String>()
        return uses.reversed().map(\.path).filter { seen.insert($0).inserted }
    }

    /// How much `project` has been used, weighing recent uses more.
    public func score(of project: Project, at now: Date = .now) -> Double {
        uses.filter { project.contains($0.path) }
            .map { pow(0.5, max(now.timeIntervalSince($0.date), 0) / Self.halfLife) }
            .reduce(0, +)
    }

    /// The last use of `project`, if any.
    public func lastUse(of project: Project) -> Date? {
        uses.last { project.contains($0.path) }?.date
    }
}
