import Foundation
import Yams

/// The file in which the user lists their projects, by hand:
///
/// ```yaml
/// projects:
///   - name: My App
///     path: ~/Developer/my-app
///   - path: ~/Developer/website   # named after its folder
/// ```
public enum ProjectsFile {
    /// `~/.config/plaincontrol/projects.yaml`, shared by the release and development builds.
    public static var defaultPath: String {
        URL.homeDirectory.appending(path: ".config/plaincontrol/projects.yaml").path(percentEncoded: false)
    }

    /// What a new projects file starts with.
    public static let template = """
        # Projects for the Plaincontrol launcher. A project is a folder, with an optional name;
        # without one, it is named after its folder.
        projects:
        #  - name: My App
        #    path: ~/Developer/my-app
        #  - path: ~/Developer/website

        """

    /// The projects in `text`, in the order of the file; a folder listed twice counts once.
    public static func parse(_ text: String) throws(ProjectsFileError) -> [Project] {
        let file: File
        do {
            guard let node = try Yams.compose(yaml: text) else { return [] }
            file = try YAMLDecoder().decode(File.self, from: node)
        } catch {
            throw ProjectsFileError(message: String(describing: error))
        }
        var seen = Set<String>()
        return (file.projects ?? [])
            .map { Project(path: $0.path, name: $0.name) }
            .filter { seen.insert($0.path).inserted }
    }

    /// Reads the projects at `path`, or none when there is no file yet.
    public static func load(from path: String = defaultPath) throws(ProjectsFileError) -> [Project] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
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
