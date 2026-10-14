import Foundation

/// A project as the launcher lists it, with what it needs to rank it.
public struct LauncherItem: Sendable, Equatable, Identifiable {
    /// What the project's Claude Code sessions are doing.
    public enum Sessions: Sendable, Equatable {
        case none
        case running
        /// At least one session waits for the user.
        case waiting
    }

    public var project: Project
    public var sessions: Sessions
    /// Listed without a search: configured, or worked on recently.
    public var isActive: Bool
    /// How often and how recently the project was used, from ``ProjectUsage``.
    public var score: Double
    /// The last commit, use or session event, whichever came last.
    public var lastActivity: Date?

    public var id: String { project.id }

    public init(
        project: Project, sessions: Sessions = .none, isActive: Bool = true, score: Double = 0,
        lastActivity: Date? = nil
    ) {
        self.project = project
        self.sessions = sessions
        self.isActive = isActive
        self.score = score
        self.lastActivity = lastActivity
    }
}

/// Puts together the projects the launcher knows: the configured ones, the repositories in the
/// configured folders, and the repositories the user used elsewhere.
public enum ProjectCatalog {
    /// The repositories to ask git about: those in the roots, and those used outside them.
    public static func repositoryPaths(config: ProjectsConfig, usage: ProjectUsage) -> [String] {
        let inRoots = Repositories.paths(in: config.roots)
        let known = config.projects.map(\.path) + inRoots
        let usedElsewhere = usage.paths
            .filter { path in !known.contains { Project(path: $0).contains(path) } }
            .compactMap(Repositories.root(containing:))
        return Array(Set(inRoots + usedElsewhere)).sorted()
    }

    public static func items(
        config: ProjectsConfig,
        repositories: [Repository],
        usage: ProjectUsage,
        sessions: [Session],
        now: Date = .now
    ) -> [LauncherItem] {
        let configured = Set(config.projects.map(\.path))
        let lastCommits = Dictionary(repositories.map { ($0.path, $0.lastCommit) }, uniquingKeysWith: { a, _ in a })
        let projects =
            config.projects + repositories.map { Project(path: $0.path) }.filter { !configured.contains($0.path) }
        let activeSince = now.addingTimeInterval(-Double(config.activeDays) * 24 * 3600)
        let running = sessions.filter { $0.status != .gone }

        return projects.map { project in
            let own = running.filter { $0.cwd.map(project.contains) ?? false }
            let state: LauncherItem.Sessions =
                own.contains { $0.status.needsAttention } ? .waiting : own.isEmpty ? .none : .running
            let lastActivity = [lastCommits[project.path] ?? nil, usage.lastUse(of: project)]
                .compactMap(\.self)
                .max()
            return LauncherItem(
                project: project,
                sessions: state,
                isActive: configured.contains(project.path) || state != .none
                    || lastActivity.map { $0 >= activeSince } ?? false,
                score: usage.score(of: project, at: now),
                lastActivity: lastActivity)
        }
    }
}
