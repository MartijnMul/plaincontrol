import Foundation
import Testing

@testable import PlaincontrolCore

@Suite struct ZoxideTests {
    @Test func readsScoresAndPaths() {
        let output = """
             196.0 /home/user/work/notes
              12.5 /home/user/code/my app
            garbage
               0.8 /home/user
            """
        #expect(
            Zoxide.parse(output) == [
                Zoxide.Entry(path: "/home/user/work/notes", score: 196),
                Zoxide.Entry(path: "/home/user/code/my app", score: 12.5),
                Zoxide.Entry(path: "/home/user", score: 0.8),
            ])
    }

    /// A small file system: `code` holds two repositories, `work` holds folders without git,
    /// and `Code` is the same folder as `code` in another case.
    func resolve(_ path: String) -> Zoxide.Location? {
        let folders: [String: Zoxide.Location] = [
            "/u/code": .init(key: "/u/code", path: "/u/code"),
            "/u/Code": .init(key: "/u/code", path: "/u/code"),
            "/u/code/app": .init(key: "/u/code/app", path: "/u/code/app", repository: "/u/code/app"),
            "/u/Code/app": .init(key: "/u/code/app", path: "/u/code/app", repository: "/u/code/app"),
            "/u/code/app/docs": .init(key: "/u/code/app/docs", path: "/u/code/app/docs", repository: "/u/code/app"),
            "/u/code/site": .init(key: "/u/code/site", path: "/u/code/site", repository: "/u/code/site"),
            "/u/work": .init(key: "/u/work", path: "/u/work"),
            "/u/work/notes": .init(key: "/u/work/notes", path: "/u/work/notes"),
            "/u/work/client/plan": .init(key: "/u/work/client/plan", path: "/u/work/client/plan"),
            "/u/work/linked": .init(key: "/u/cloud/linked", path: "/u/work/linked"),
            "/u/cloud/linked": .init(key: "/u/cloud/linked", path: "/u/cloud/linked"),
            "/u/servers": .init(key: "/u/servers", path: "/u/servers"),
            "/u/servers/vault": .init(key: "/u/servers/vault", path: "/u/servers/vault"),
        ]
        return folders[path]
    }

    @Test func turnsVisitedFoldersIntoProjects() {
        let entries = [
            Zoxide.Entry(path: "/u/code", score: 70),
            Zoxide.Entry(path: "/u/code/app", score: 10),
            Zoxide.Entry(path: "/u/Code/app", score: 4),
            Zoxide.Entry(path: "/u/code/app/docs", score: 2),
            Zoxide.Entry(path: "/u/code/site", score: 20),
            Zoxide.Entry(path: "/u/work", score: 3),
            Zoxide.Entry(path: "/u/work/notes", score: 5),
            Zoxide.Entry(path: "/u/work/client/plan", score: 1),
            Zoxide.Entry(path: "/u/work/linked", score: 3),
            Zoxide.Entry(path: "/u/cloud/linked", score: 1),
            Zoxide.Entry(path: "/u/gone", score: 50),
            Zoxide.Entry(path: "/u/servers", score: 6),
            Zoxide.Entry(path: "/u/servers/vault", score: 0.5),
        ]
        #expect(
            Zoxide.projects(from: entries, resolve: resolve) == [
                Zoxide.Entry(path: "/u/code/site", score: 20),
                Zoxide.Entry(path: "/u/code/app", score: 16),
                Zoxide.Entry(path: "/u/servers", score: 6),
                Zoxide.Entry(path: "/u/work/notes", score: 5),
                Zoxide.Entry(path: "/u/work/linked", score: 4),
                Zoxide.Entry(path: "/u/work/client/plan", score: 1),
                Zoxide.Entry(path: "/u/servers/vault", score: 0.5),
            ])
    }

    @Test func findsWhereAFolderReallyIs() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = root.appending(path: "Code/App")
        try FileManager.default.createDirectory(
            at: repository.appending(path: "Docs"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: repository.appending(path: ".git"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "shortcut"), withDestinationURL: repository)
        let base = root.path(percentEncoded: false)

        let lowercase = try #require(Zoxide.location(of: base + "/code/app/docs"))
        let proper = try #require(Zoxide.location(of: base + "/Code/App/Docs"))
        #expect(lowercase.key == proper.key)
        #expect(lowercase.path.hasSuffix("/Code/App/Docs"))
        #expect(lowercase.repository?.hasSuffix("/Code/App") == true)

        let linked = try #require(Zoxide.location(of: base + "/SHORTCUT"))
        #expect(linked.key == proper.repository.flatMap { Zoxide.location(of: $0)?.key })
        #expect(linked.path.hasSuffix("/shortcut"))
        #expect(Zoxide.location(of: base + "/missing") == nil)
    }
}
