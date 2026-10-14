import Foundation
import Yams

/// What the user configures about projects, in `projects.yaml`:
///
/// ```yaml
/// zoxide: true          # also list and rank by zoxide's folders, when it is installed
/// roots:                # folders whose subfolders are projects
///   - ~/Developer
/// activeDays: 90        # a project is listed this long after its last change or use
/// projects:             # always listed, with an optional name
///   - name: My App
///     path: ~/Developer/my-app
/// ```
public struct ProjectsConfig: Sendable, Equatable {
    /// Whether to also list and rank by the folders the user visits with zoxide, when installed.
    public var zoxide = true
    /// Folders whose subfolders are projects, by their absolute paths.
    public var roots: [String] = []
    /// How long a project stays in the list after its last change or use.
    public var activeDays = 90
    /// Projects that are always listed, in the order of the file.
    public var projects: [Project] = []

    public init(zoxide: Bool = true, roots: [String] = [], activeDays: Int = 90, projects: [Project] = []) {
        self.zoxide = zoxide
        self.roots = roots.map { ($0 as NSString).standardizingPath }
        self.activeDays = activeDays
        self.projects = projects
    }
}

/// The file in which the user configures projects, by hand.
public enum ProjectsFile {
    /// `~/.config/plaincontrol/projects.yaml`, shared by the release and development builds.
    public static var defaultPath: String {
        URL.homeDirectory.appending(path: ".config/plaincontrol/projects.yaml").path(percentEncoded: false)
    }

    /// What a new projects file starts with.
    public static let template = """
        # Projects for the Plaincontrol launcher.

        # The launcher lists the folders where you start Claude Code or open projects from the
        # launcher. If you use zoxide (https://github.com/ajeetdsouza/zoxide), it also lists the
        # folders you visit most, and ranks by both. zoxide's data is only read, never changed.
        zoxide: true

        # Folders whose subfolders are projects, such as a folder of git repositories. A project
        # is listed while you work on it: a commit (in a git repository) or a changed file (in
        # any other folder), or a Claude Code session or launcher action in it, within
        # activeDays. Older ones show up when you search for them.
        roots:
        #  - ~/Developer
        activeDays: 90

        # Projects that are always listed, with an optional name; without one, a project is
        # named after its folder.
        projects:
        #  - name: My App
        #    path: ~/Developer/my-app

        """

    /// The configuration in `text`; a project listed twice counts once.
    public static func parse(_ text: String) throws(ProjectsFileError) -> ProjectsConfig {
        let file: File
        do {
            guard let node = try Yams.compose(yaml: text) else { return ProjectsConfig() }
            file = try YAMLDecoder().decode(File.self, from: node)
        } catch {
            throw ProjectsFileError(message: String(describing: error))
        }
        if let days = file.activeDays, days < 1 {
            throw ProjectsFileError(message: "activeDays must be at least 1.")
        }
        var seen = Set<String>()
        let projects = (file.projects ?? [])
            .map { Project(path: $0.path, name: $0.name) }
            .filter { seen.insert($0.path).inserted }
        return ProjectsConfig(
            zoxide: file.zoxide ?? true, roots: file.roots ?? [], activeDays: file.activeDays ?? 90, projects: projects)
    }

    /// Reads the configuration at `path`, or an empty one when there is no file yet.
    public static func load(from path: String = defaultPath) throws(ProjectsFileError) -> ProjectsConfig {
        guard FileManager.default.fileExists(atPath: path) else { return ProjectsConfig() }
        let text: String
        do {
            text = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw ProjectsFileError(message: error.localizedDescription)
        }
        return try parse(text)
    }

    /// Creates the file at `path` from ``template``, unless it exists already.
    public static func createIfMissing(at path: String = defaultPath) throws {
        guard !FileManager.default.fileExists(atPath: path) else { return }
        let url = URL(filePath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try template.write(to: url, atomically: true, encoding: .utf8)
    }

    private struct File: Decodable {
        var zoxide: Bool?
        var roots: [String]?
        var activeDays: Int?
        var projects: [Entry]?
    }

    private struct Entry: Decodable {
        var name: String?
        var path: String
    }
}

/// The projects file could not be read, with a description for the user.
public struct ProjectsFileError: Error, Equatable, Sendable {
    public var message: String
}
