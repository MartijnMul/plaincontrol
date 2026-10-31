import Foundation

/// When the user used each folder, to rank projects by how often and how recently they are
/// used ("frecency").
///
/// A use is an action from the launcher, or the start of a Claude Code session in the folder.
/// A launcher action also notes which action it was, to rank a project's actions the same way.
/// Each use counts for less as it gets older, halving every ``halfLife``, so a project used
/// every day stays ahead of one used once yesterday, while a project used all week rises fast.
public struct ProjectUsage: Codable, Sendable, Equatable {
    public struct Use: Codable, Sendable, Equatable {
        public var path: String
        public var date: Date
        /// The launcher action, or nil for another use, such as a session start.
        public var action: ProjectAction?
        /// How the dev server action started the dev server.
        public var devServer: DevServerStart?

        enum CodingKeys: String, CodingKey {
            case path, date, action
            case devServer = "dev_server"
        }

        init(path: String, date: Date, action: ProjectAction?, devServer: DevServerStart? = nil) {
            self.path = path
            self.date = date
            self.action = action
            self.devServer = devServer
        }

        /// Reads a use, leaving out an action or answer this version doesn't know.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            path = try container.decode(String.self, forKey: .path)
            date = try container.decode(Date.self, forKey: .date)
            action = (try? container.decodeIfPresent(ProjectAction.self, forKey: .action)) ?? nil
            devServer = (try? container.decodeIfPresent(DevServerStart.self, forKey: .devServer)) ?? nil
        }
    }

    /// The uses, oldest first.
    public private(set) var uses: [Use] = []

    public static let halfLife: TimeInterval = 7 * 24 * 3600
    /// How many uses are kept; older ones count for almost nothing anyway.
    public static let limit = 1000

    public init() {}

    /// Notes a use of `path`, by `action` when it comes from the launcher, and how it started
    /// the dev server when it did.
    public mutating func record(
        _ path: String, action: ProjectAction? = nil, devServer: DevServerStart? = nil, at date: Date = .now
    ) {
        uses.append(Use(path: (path as NSString).standardizingPath, date: date, action: action, devServer: devServer))
        if uses.count > Self.limit { uses.removeFirst(uses.count - Self.limit) }
    }

    /// Adds uses from before Plaincontrol saw them, such as the sessions in Claude Code's own
    /// history, keeping every use in order of its date. A use already noted at the same time
    /// is not noted again, so adding the same uses twice changes nothing.
    public mutating func merge(_ earlier: [(path: String, date: Date)]) {
        var known = Set(uses.map { "\($0.path)\u{0}\($0.date.timeIntervalSinceReferenceDate)" })
        let added = earlier.map { Use(path: ($0.path as NSString).standardizingPath, date: $0.date, action: nil) }
            .filter { known.insert("\($0.path)\u{0}\($0.date.timeIntervalSinceReferenceDate)").inserted }
        guard !added.isEmpty else { return }
        uses = (uses + added).enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)
        if uses.count > Self.limit { uses.removeFirst(uses.count - Self.limit) }
    }

    /// The folders used, most recent first, each once.
    public var paths: [String] {
        var seen = Set<String>()
        return uses.reversed().map(\.path).filter { seen.insert($0).inserted }
    }

    /// How much `project` has been used, weighing recent uses more.
    public func score(of project: Project, at now: Date = .now) -> Double {
        uses.filter { project.contains($0.path) }.map { weight(of: $0, at: now) }.reduce(0, +)
    }

    /// `actions` by how much each has been used in `project`, weighing recent uses more, or by
    /// their use in all projects while none of them has been used in this one. Actions used as
    /// much keep their order in `actions`.
    public func rank(_ actions: [ProjectAction], in project: Project, at now: Date = .now) -> [ProjectAction] {
        let all = uses.filter { $0.action.map(actions.contains) == true }
        let own = all.filter { project.contains($0.path) }
        var scores: [ProjectAction: Double] = [:]
        for use in own.isEmpty ? all : own {
            if let action = use.action { scores[action, default: 0] += weight(of: use, at: now) }
        }
        return actions.enumerated()
            .sorted { first, second in
                let a = scores[first.element, default: 0]
                let b = scores[second.element, default: 0]
                return a != b ? a > b : first.offset < second.offset
            }
            .map(\.element)
    }

    private func weight(of use: Use, at now: Date) -> Double {
        pow(0.5, max(now.timeIntervalSince(use.date), 0) / Self.halfLife)
    }

    /// How the dev server of `project` was started last, so the launcher can offer the same.
    public func lastDevServerStart(in project: Project) -> DevServerStart? {
        uses.last { $0.devServer != nil && project.contains($0.path) }?.devServer
    }

    /// The last use of `project`, if any.
    public func lastUse(of project: Project) -> Date? {
        uses.last { project.contains($0.path) }?.date
    }
}
