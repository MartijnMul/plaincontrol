import Foundation

/// A folder that is a project, and when the user last changed something in it.
public struct ProjectFolder: Sendable, Equatable {
    public var path: String
    public var lastChange: Date?

    public init(path: String, lastChange: Date?) {
        self.path = path
        self.lastChange = lastChange
    }
}

/// Finds the project folders in the configured roots, and when each last changed.
///
/// For a git repository, the last change is its last commit: the files in `.git` and the
/// working tree change for many other reasons, such as an editor refreshing the index or a
/// tool rewriting old commits. For any other folder, it is the newest file or folder a few
/// levels deep, leaving out hidden files and folders of build output and dependencies.
public enum ProjectFolders {
    /// The folders directly inside `roots`, following symbolic links, sorted by path.
    public static func paths(in roots: [String]) -> [String] {
        let fileManager = FileManager.default
        return roots.flatMap { root in
            let names = (try? fileManager.contentsOfDirectory(atPath: root)) ?? []
            return names.filter { !$0.hasPrefix(".") }
                .map { (root as NSString).appendingPathComponent($0) }
                .filter { path in
                    var isDirectory: ObjCBool = false
                    return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
                }
        }
        .sorted()
    }

    /// Whether `path` is the top folder of a git repository or worktree.
    public static func isRepository(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(".git"))
    }

    /// The top folder of the git repository that contains `path`, if any.
    public static func repositoryRoot(containing path: String) -> String? {
        var current = (path as NSString).standardizingPath
        while current != "/" && !current.isEmpty {
            if isRepository(current) { return current }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Each folder with its last change as soon as it is known, looking at several at a time.
    ///
    /// Folders come in the order they finish, so one that takes long, such as while macOS asks
    /// the user for access to it, holds up only itself.
    public static func scan(_ paths: [String], git: String = "/usr/bin/git") -> AsyncStream<ProjectFolder> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: ProjectFolder.self) { group in
                    for path in paths {
                        group.addTask { ProjectFolder(path: path, lastChange: lastChange(at: path, git: git)) }
                    }
                    for await folder in group { continuation.yield(folder) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The last commit of a repository, or the newest file in any other folder.
    public static func lastChange(at path: String, git: String = "/usr/bin/git") -> Date? {
        isRepository(path) ? lastCommit(at: path, git: git) : newestFile(in: path)
    }

    /// The commit date of the last commit in the repository at `path`, or nil when it has none.
    public static func lastCommit(at path: String, git: String = "/usr/bin/git") -> Date? {
        let process = Process()
        process.executableURL = URL(filePath: git)
        process.arguments = ["-C", path, "log", "-1", "--format=%ct"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            let seconds = TimeInterval(text)
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Folders whose contents change without the user working on the project.
    static let skippedFolders: Set<String> = [
        "node_modules", "DerivedData", "build", "dist", "Pods", "vendor", "__pycache__", "venv",
    ]

    /// The modification date of the newest file or folder in `path`, at most `depth` levels down
    /// and looking at no more than `limit` items, so a huge folder stays quick.
    public static func newestFile(in path: String, depth: Int = 3, limit: Int = 5000) -> Date? {
        let root = URL(filePath: path, directoryHint: .isDirectory).resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard
            let items = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return nil }
        var newest: Date?
        var seen = 0
        while let item = items.nextObject() as? URL, seen < limit {
            seen += 1
            let values = try? item.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if Self.skippedFolders.contains(item.lastPathComponent) {
                    items.skipDescendants()
                    continue
                }
                if items.level >= depth { items.skipDescendants() }
            }
            if let date = values?.contentModificationDate, date > (newest ?? .distantPast) {
                newest = date
            }
        }
        return newest
    }
}
