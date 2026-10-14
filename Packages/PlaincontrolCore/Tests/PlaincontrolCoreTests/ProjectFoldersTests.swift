import Foundation
import Testing

@testable import PlaincontrolCore

@Suite struct ProjectFoldersTests {
    let old = Date(timeIntervalSince1970: 978_307_200)

    /// A root with a repository with one commit, one without commits, a plain folder with
    /// files, a hidden folder and a link to a folder elsewhere.
    func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        for name in ["committed", "empty", "notes/drafts/deeper/deepest", "notes/node_modules", ".hidden", "elsewhere"]
        {
            try FileManager.default.createDirectory(at: root.appending(path: name), withIntermediateDirectories: true)
        }
        try git(["init", "-q"], in: root.appending(path: "committed"))
        try git(
            [
                "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-q", "--allow-empty", "-m",
                "First",
            ],
            in: root.appending(path: "committed"),
            environment: ["GIT_COMMITTER_DATE": "2001-01-01T00:00:00Z"])
        try git(["init", "-q"], in: root.appending(path: "empty"))
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "linked"), withDestinationURL: root.appending(path: "elsewhere"))
        return root
    }

    func git(_ arguments: [String], in folder: URL, environment: [String: String] = [:]) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = folder
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    /// Writes a file at `path` in `root`, dated `date`.
    func write(_ path: String, in root: URL, at date: Date) throws {
        let file = root.appending(path: path)
        try "text".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path(percentEncoded: false))
    }

    /// Dates every folder inside `folder` at `date`, as writing files changed theirs.
    func dateFolders(in folder: URL, at date: Date) throws {
        let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey])
        while let item = items?.nextObject() as? URL {
            if (try item.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
                try FileManager.default.setAttributes(
                    [.modificationDate: date], ofItemAtPath: item.path(percentEncoded: false))
            }
        }
    }

    @Test func findsTheVisibleFoldersInTheRootsAndFollowsLinks() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.path(percentEncoded: false)
        try "text".write(to: root.appending(path: "README.md"), atomically: true, encoding: .utf8)
        let names = ProjectFolders.paths(in: [path]).map { ($0 as NSString).lastPathComponent }
        #expect(names == ["committed", "elsewhere", "empty", "linked", "notes"])
        #expect(ProjectFolders.paths(in: [path + "/missing"]).isEmpty)
    }

    @Test func findsTheRepositoryAroundAFolder() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let committed = root.appending(path: "committed").path(percentEncoded: false)
        #expect(ProjectFolders.repositoryRoot(containing: committed + "/deeper/still") == committed)
        #expect(
            ProjectFolders.repositoryRoot(containing: root.appending(path: "notes").path(percentEncoded: false)) == nil)
    }

    @Test func dateARepositoryByItsLastCommit() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ["committed", "empty"].map { root.appending(path: $0).path(percentEncoded: false) }
        var folders: [ProjectFolder] = []
        for await folder in ProjectFolders.scan(paths) { folders.append(folder) }
        #expect(folders.sorted { $0.path < $1.path }.map(\.lastChange) == [old, nil])
    }

    @Test func datesOtherFoldersByTheirNewestFileAFewLevelsDown() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let notes = root.appending(path: "notes")
        try write("notes/drafts/plan.md", in: root, at: old + 1000)
        try write("notes/drafts/deeper/deepest/too-deep.md", in: root, at: old + 3000)
        try write("notes/node_modules/dependency.js", in: root, at: old + 2000)
        try dateFolders(in: notes, at: old)
        #expect(ProjectFolders.newestFile(in: notes.path(percentEncoded: false)) == old + 1000)
    }

    @Test func looksThroughALinkForTheNewestFile() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("elsewhere/note.md", in: root, at: old)
        #expect(ProjectFolders.newestFile(in: root.appending(path: "linked").path(percentEncoded: false)) == old)
    }
}
