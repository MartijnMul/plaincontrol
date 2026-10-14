import Foundation
import Testing

@testable import PlaincontrolCore

@Suite struct RepositoriesTests {
    /// A folder with a repository that has one commit, one without commits, and a plain folder.
    func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        for name in ["committed", "empty", "plain/sub"] {
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

    @Test func findsRepositoriesInTheRoots() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.path(percentEncoded: false)
        let paths = Repositories.paths(in: [path]).map { ($0 as NSString).lastPathComponent }
        #expect(paths == ["committed", "empty"])
        #expect(Repositories.paths(in: [path + "/missing"]).isEmpty)
    }

    @Test func findsTheRepositoryAroundAFolder() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let committed = root.appending(path: "committed").path(percentEncoded: false)
        #expect(Repositories.root(containing: committed + "/deeper/still") == committed)
        #expect(Repositories.root(containing: root.appending(path: "plain/sub").path(percentEncoded: false)) == nil)
    }

    @Test func readsTheLastCommitDate() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repositories = await Repositories.scan(Repositories.paths(in: [root.path(percentEncoded: false)]))
        #expect(repositories.map(\.lastCommit) == [Date(timeIntervalSince1970: 978_307_200), nil])
    }
}
