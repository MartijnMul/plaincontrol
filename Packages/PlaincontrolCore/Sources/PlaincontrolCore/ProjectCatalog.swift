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
    /// The last change in the folder or use of the project, whichever came last.
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

/// Puts together the projects the launcher knows: the configured ones, the folders where the
/// user started Claude Code sessions or ran launcher actions, the folders in the configured
/// roots, and the folders zoxide ranks, when the user has it.
///
/// Plaincontrol's own history works for everyone without setup; zoxide and the roots are
/// optional extras. A project is ranked by both histories, each scaled to its best project, so
/// neither source outweighs the other by its units.
public enum ProjectCatalog {
    /// The folders to date: those in the roots, and those in the user's own history outside the
    /// configured projects and the roots, leaving out the home folder and the folders above it.
    public static func folderPaths(
        config: LauncherConfig, usage: ProjectUsage, home: String = NSHomeDirectory()
    ) -> [String] {
        let inRoots = ProjectFolders.paths(in: config.roots)
        let known = (config.projects.map(\.path) + inRoots).map { Project(path: $0) }
        let home = (home as NSString).standardizingPath
        let used = usage.paths.filter { path in
            path != home && !home.hasPrefix(path == "/" ? "/" : path + "/")
                && !known.contains { $0.contains(path) }
                && FileManager.default.fileExists(atPath: path)
        }
        var seen = Set<String>()
        return (inRoots + used).filter { seen.insert($0).inserted }
    }

    public static func items(
        config: LauncherConfig,
        folders: [ProjectFolder],
        zoxide: [Zoxide.Entry] = [],
        usage: ProjectUsage,
        sessions: [Session],
        now: Date = .now
    ) -> [LauncherItem] {
        let configured = Set(config.projects.map(\.path))
        let lastChanges = Dictionary(folders.map { ($0.path, $0.lastChange) }, uniquingKeysWith: { a, _ in a })
        let visits = Dictionary(zoxide.map { (Project(path: $0.path).resolvedPath, $0.score) }, uniquingKeysWith: +)
        var seen = Set<String>()
        let projects =
            (config.projects + folders.map { Project(path: $0.path) } + zoxide.map { Project(path: $0.path) })
            .filter { seen.insert($0.resolvedPath.lowercased()).inserted }
        let activeSince = now.addingTimeInterval(-Double(config.activeDays) * 24 * 3600)
        let running = sessions.filter { $0.status != .gone }
        let uses = Dictionary(projects.map { ($0.path, usage.score(of: $0, at: now)) }, uniquingKeysWith: { a, _ in a })
        let bestVisits = visits.values.max() ?? 0
        let bestUses = uses.values.max() ?? 0

        return projects.map { project in
            let own = running.filter { $0.cwd.map(project.contains) ?? false }
            let state: LauncherItem.Sessions =
                own.contains { $0.status.needsAttention } ? .waiting : own.isEmpty ? .none : .running
            let lastActivity = [lastChanges[project.path] ?? nil, usage.lastUse(of: project)]
                .compactMap(\.self)
                .max()
            let visited = visits[project.resolvedPath]
            let score =
                (bestVisits > 0 ? (visited ?? 0) / bestVisits : 0)
                + (bestUses > 0 ? (uses[project.path] ?? 0) / bestUses : 0)
            return LauncherItem(
                project: project,
                sessions: state,
                isActive: configured.contains(project.path) || state != .none || visited != nil
                    || lastActivity.map { $0 >= activeSince } ?? false,
                score: score,
                lastActivity: lastActivity)
        }
    }

    /// The projects the launcher lists without a search that the settings do not name, in the
    /// launcher's order: the ones it found itself.
    public static func found(in items: [LauncherItem], config: LauncherConfig) -> [Project] {
        let configured = Set(config.projects.map { $0.resolvedPath.lowercased() })
        return Launcher.listed(items).map(\.project).filter { !configured.contains($0.resolvedPath.lowercased()) }
    }
}
