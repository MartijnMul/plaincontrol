import Foundation

/// A git repository on disk, and when it last had a commit.
public struct Repository: Sendable, Equatable {
    public var path: String
    public var lastCommit: Date?

    public init(path: String, lastCommit: Date?) {
        self.path = path
        self.lastCommit = lastCommit
    }
}

/// Finds git repositories and asks git when they last had a commit.
///
/// The commit date is the signal for recent work: the files in `.git` change for many other
/// reasons, such as an editor refreshing the index or a tool rewriting old commits.
public enum Repositories {
    /// The folders directly inside `roots` that are git repositories, sorted by path.
    public static func paths(in roots: [String]) -> [String] {
        let fileManager = FileManager.default
        return roots.flatMap { root in
            let names = (try? fileManager.contentsOfDirectory(atPath: root)) ?? []
            return names.map { (root as NSString).appendingPathComponent($0) }.filter(isRepository)
        }
        .sorted()
    }

    /// Whether `path` is the top folder of a git repository or worktree.
    public static func isRepository(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(".git"))
    }

    /// The top folder of the git repository that contains `path`, if any.
    public static func root(containing path: String) -> String? {
        var current = (path as NSString).standardizingPath
        while current != "/" && !current.isEmpty {
            if isRepository(current) { return current }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Each repository with its last commit date, asking git for several at a time.
    public static func scan(_ paths: [String], git: String = "/usr/bin/git") async -> [Repository] {
        await withTaskGroup(of: Repository.self) { group in
            for path in paths {
                group.addTask { Repository(path: path, lastCommit: lastCommit(at: path, git: git)) }
            }
            return await group.reduce(into: []) { $0.append($1) }.sorted { $0.path < $1.path }
        }
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
}
