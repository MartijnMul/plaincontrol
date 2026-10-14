import Foundation

/// A folder the user works in, under a name of their choosing.
public struct Project: Sendable, Equatable, Identifiable {
    public var name: String
    /// The folder's absolute path, without a trailing slash.
    public var path: String
    /// The same folder with symbolic links resolved, such as when the project folder links to
    /// a synced folder elsewhere and a session reports the linked-to path.
    public var resolvedPath: String

    public var id: String { path }

    /// - Parameters:
    ///   - path: The folder; `~` stands for the home folder.
    ///   - name: The name to show, or nil for the folder's name.
    public init(path: String, name: String? = nil) {
        self.path = (path as NSString).standardizingPath
        resolvedPath = URL(filePath: self.path).resolvingSymlinksInPath().path(percentEncoded: false)
        let name = name?.trimmingCharacters(in: .whitespaces) ?? ""
        self.name = name.isEmpty ? (self.path as NSString).lastPathComponent : name
    }

    /// Whether `directory` is the project's folder or a folder inside it, by either path.
    public func contains(_ directory: String) -> Bool {
        let directory = (directory as NSString).standardizingPath
        return [path, resolvedPath].contains { folder in
            directory == folder || directory.hasPrefix(folder == "/" ? "/" : folder + "/")
        }
    }
}
