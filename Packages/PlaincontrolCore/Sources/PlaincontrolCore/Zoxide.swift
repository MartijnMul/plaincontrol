import Foundation

/// Reads the folders the user visits from [zoxide](https://github.com/ajeetdsouza/zoxide), a
/// `cd` replacement that ranks folders by how often and how recently the user goes there.
///
/// zoxide is optional and only read: Plaincontrol never changes its data.
///
/// zoxide knows every folder the user visits, not only projects. ``projects(from:resolve:)``
/// turns its list into projects: a folder inside a git repository counts for the repository,
/// a folder spelled in different case or reached through a link counts once, and a folder that
/// holds several other projects, such as the folder of all repositories, is left out.
public enum Zoxide {
    /// A folder and its zoxide score, which already weighs recent visits more.
    public struct Entry: Sendable, Equatable {
        public var path: String
        public var score: Double

        public init(path: String, score: Double) {
            self.path = path
            self.score = score
        }
    }

    /// Where zoxide is installed, by the usual package managers.
    static let candidates = [
        "/opt/homebrew/bin/zoxide", "/usr/local/bin/zoxide", "~/.cargo/bin/zoxide", "~/.local/bin/zoxide",
        "~/.nix-profile/bin/zoxide", "/run/current-system/sw/bin/zoxide",
    ]

    /// The zoxide command, if it is installed in one of the usual places.
    public static func executable() -> String? {
        candidates.map { ($0 as NSString).expandingTildeInPath }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The folders zoxide knows, with their scores, or nil when zoxide could not be asked.
    public static func query(executable: String) -> [Entry]? {
        guard let output = run(executable, ["query", "--list", "--score"]) else { return nil }
        return parse(output)
    }

    /// The lines of `zoxide query --list --score`: a score, spaces, and a path.
    static func parse(_ output: String) -> [Entry] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.drop { $0 == " " }
            guard let space = trimmed.firstIndex(of: " "), let score = Double(trimmed[..<space]) else { return nil }
            let path = trimmed[space...].drop { $0 == " " }
            return path.isEmpty ? nil : Entry(path: String(path), score: score)
        }
    }

    /// Where a folder really is.
    public struct Location: Sendable, Equatable {
        /// The folder with links resolved and its true case, the same for every way to reach it.
        public var key: String
        /// The folder as the user reaches it, through the links they use, in its true case.
        public var path: String
        /// The top folder of the git repository the folder is in, if any.
        public var repository: String?

        public init(key: String, path: String, repository: String? = nil) {
            self.key = key
            self.path = path
            self.repository = repository
        }
    }

    /// The projects in zoxide's list, best scored first, each with the summed score of the
    /// folders that count for it.
    ///
    /// - Parameter resolve: Where a folder really is, or nil when it no longer exists.
    public static func projects(from entries: [Entry], resolve: (String) -> Location?) -> [Entry] {
        struct Candidate {
            var location: Location
            var score: Double
            var best: Double
        }
        var candidates: [String: Candidate] = [:]
        for entry in entries {
            guard var location = resolve(entry.path) else { continue }
            if let repository = location.repository, repository != location.path {
                guard let top = resolve(repository) else { continue }
                location = top
            }
            var candidate = candidates[location.key] ?? Candidate(location: location, score: 0, best: 0)
            candidate.score += entry.score
            // Show the folder the way the user reaches it most.
            if entry.score > candidate.best, location.repository == nil {
                candidate.location.path = location.path
                candidate.best = entry.score
            }
            candidates[location.key] = candidate
        }
        let keys = Array(candidates.keys)
        return candidates.values
            .filter { candidate in
                // A folder that holds several other projects is a container, unless it is a
                // repository itself.
                let prefix = candidate.location.key == "/" ? "/" : candidate.location.key + "/"
                return candidate.location.repository != nil || keys.count { $0.hasPrefix(prefix) } < 2
            }
            .map { Entry(path: $0.location.path, score: $0.score) }
            .sorted { ($0.score, $1.path) > ($1.score, $0.path) }
    }

    /// Where `path` really is on this Mac, or nil when it does not exist.
    public static func location(of path: String) -> Location? {
        guard let key = realPath(path) else { return nil }
        let shown = trueCase(of: (path as NSString).standardizingPath)
        let home = URL.homeDirectory.path(percentEncoded: false)
        let repository = ProjectFolders.repositoryRoot(containing: key).flatMap { root -> String? in
            // The repository as reached through the user's path, when the path leads into it.
            guard root.count > (home as NSString).standardizingPath.count else { return nil }
            if key == root { return shown }
            if key.hasPrefix(root + "/") {
                let depth = key.dropFirst(root.count).split(separator: "/").count
                var top = shown
                for _ in 0..<depth { top = (top as NSString).deletingLastPathComponent }
                return top
            }
            return root
        }
        return Location(key: key, path: shown, repository: repository)
    }

    /// `path` with each folder name in the case it has on disk, keeping links as they are.
    static func trueCase(of path: String) -> String {
        var current = "/"
        for component in path.split(separator: "/").map(String.init) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: current)) ?? []
            let name =
                names.contains(component)
                ? component : names.first { $0.caseInsensitiveCompare(component) == .orderedSame } ?? component
            current = (current as NSString).appendingPathComponent(name)
        }
        return current
    }

    private static func realPath(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard let result = realpath(path, &buffer) else { return nil }
        return String(cString: result)
    }

    private static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
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
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
