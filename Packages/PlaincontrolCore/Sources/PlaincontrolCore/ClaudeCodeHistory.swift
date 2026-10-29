import Foundation

/// The folders the user ran Claude Code in before Plaincontrol saw any session, from Claude
/// Code's own history, so the launcher has projects from the start.
///
/// Claude Code keeps a folder per working folder in `~/.claude/projects`, named after its path
/// with every character other than a letter or a digit made a `-`, and in it a file per
/// session. Only those names and the files' dates are read, never what is in them. As the
/// name loses which `-` was a `/`, a path is found by walking the disk along it.
public enum ClaudeCodeHistory {
    /// A session: the project it ran in and when it last wrote to its file.
    public struct Session: Sendable, Equatable {
        public var folder: String
        public var date: Date

        public init(folder: String, date: Date) {
            self.folder = folder
            self.date = date
        }
    }

    /// Where Claude Code keeps its history.
    public static var defaultDirectory: URL {
        URL.homeDirectory.appending(path: ".claude/projects")
    }

    /// Every session in Claude Code's history whose folder still exists, by project: the
    /// repository the folder is in, or the folder itself.
    public static func sessions(in directory: URL = defaultDirectory) -> [Session] {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        else { return [] }
        var folders: [String: String?] = [:]
        return names.sorted().flatMap { name -> [Session] in
            let resolved = folders[name] ?? path(ofFolderNamed: name, listing: listing)
            folders[name] = resolved
            guard let resolved else { return [] }
            let project = ProjectFolders.repositoryRoot(containing: resolved) ?? resolved
            let files =
                (try? fileManager.contentsOfDirectory(
                    at: directory.appending(path: name), includingPropertiesForKeys: [.contentModificationDateKey]))
                ?? []
            return files.filter { $0.pathExtension == "jsonl" }.compactMap { file in
                let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return date.map { Session(folder: project, date: $0) }
            }
        }
    }

    /// The name Claude Code gives the history of `path`.
    static func folderName(of path: String) -> String {
        String(path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    /// The folder whose history is `name`, found by walking the disk from `/` along it, or nil
    /// when there is none. Where several folders give the same name, such as `my-app` and `my/app`, the one with the
    /// longest folder names wins.
    ///
    /// - Parameter listing: The folders in a folder, by name, or nil when it cannot be read.
    static func path(ofFolderNamed name: String, listing: (String) -> [String]?) -> String? {
        guard name.hasPrefix("-") else { return nil }
        return walk(from: "/", rest: Substring(name.dropFirst()), listing: listing)
    }

    private static func walk(from folder: String, rest: Substring, listing: (String) -> [String]?) -> String? {
        if rest.isEmpty { return folder }
        // Longest names first, so a folder named `my-app` comes before `my` with `app` in it.
        for entry in (listing(folder) ?? []).sorted(by: { $0.count > $1.count }) {
            let encoded = folderName(of: entry)
            let path = (folder as NSString).appendingPathComponent(entry)
            if rest == encoded { return path }
            if rest.hasPrefix(encoded + "-"),
                let found = walk(from: path, rest: rest.dropFirst(encoded.count + 1), listing: listing)
            {
                return found
            }
        }
        return nil
    }

    /// The folders in `path`, by name, symbolic links to folders included.
    private static func listing(_ path: String) -> [String]? {
        let fileManager = FileManager.default
        return try? fileManager.contentsOfDirectory(atPath: path).sorted().filter { name in
            var isFolder: ObjCBool = false
            return fileManager.fileExists(
                atPath: (path as NSString).appendingPathComponent(name), isDirectory: &isFolder)
                && isFolder.boolValue
        }
    }
}
