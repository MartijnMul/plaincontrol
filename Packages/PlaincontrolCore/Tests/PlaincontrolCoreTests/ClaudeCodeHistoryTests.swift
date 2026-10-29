import Foundation
import Testing

@testable import PlaincontrolCore

@Suite struct ClaudeCodeHistoryTests {
    /// A disk of folders, by their paths.
    static func listing(_ folders: [String]) -> (String) -> [String]? {
        { folder in
            let prefix = folder == "/" ? "/" : folder + "/"
            let names = folders.filter { $0.hasPrefix(prefix) }
                .map { String($0.dropFirst(prefix.count)).split(separator: "/").first.map(String.init) ?? "" }
            return Array(Set(names)).sorted()
        }
    }

    @Test func namesAFolderAsClaudeCodeDoes() {
        #expect(ClaudeCodeHistory.folderName(of: "/Users/example/my-app") == "-Users-example-my-app")
        #expect(ClaudeCodeHistory.folderName(of: "/work/.config/a b_c.d") == "-work--config-a-b-c-d")
    }

    @Test func findsTheFolderAlongTheDisk() {
        let disk = Self.listing(["/work/my-app/src", "/work/my/app", "/work/site.com", "/work/.dotfiles"])
        #expect(ClaudeCodeHistory.path(ofFolderNamed: "-work-my-app-src", listing: disk) == "/work/my-app/src")
        #expect(ClaudeCodeHistory.path(ofFolderNamed: "-work-site-com", listing: disk) == "/work/site.com")
        #expect(ClaudeCodeHistory.path(ofFolderNamed: "-work--dotfiles", listing: disk) == "/work/.dotfiles")
        // Both /work/my-app and /work/my/app give this name; the longer folder name wins.
        #expect(ClaudeCodeHistory.path(ofFolderNamed: "-work-my-app", listing: disk) == "/work/my-app")
    }

    @Test func skipsAFolderThatIsGone() {
        let disk = Self.listing(["/work/site"])
        #expect(ClaudeCodeHistory.path(ofFolderNamed: "-work-old", listing: disk) == nil)
        #expect(ClaudeCodeHistory.path(ofFolderNamed: "work-site", listing: disk) == nil)
    }

    @Test func readsTheSessionsOfEachProjectByTheirDates() throws {
        let fileManager = FileManager.default
        let root = URL(
            filePath: (fileManager.temporaryDirectory.path(percentEncoded: false) as NSString)
                .resolvingSymlinksInPath
        ).appending(path: UUID().uuidString)
        defer { try? fileManager.removeItem(at: root) }
        let app = root.appending(path: "my-app")
        try fileManager.createDirectory(at: app.appending(path: ".git"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: app.appending(path: "src"), withIntermediateDirectories: true)
        let history = root.appending(path: "history")
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        for (folder, files) in [
            (app.appending(path: "src"), ["a.jsonl", "b.jsonl", "notes.txt"]),
            (root.appending(path: "gone"), ["c.jsonl"]),
        ] {
            let entry = history.appending(path: ClaudeCodeHistory.folderName(of: folder.path(percentEncoded: false)))
            try fileManager.createDirectory(at: entry, withIntermediateDirectories: true)
            for file in files {
                let url = entry.appending(path: file)
                try Data("{}".utf8).write(to: url)
                try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: url.path(percentEncoded: false))
            }
        }
        let sessions = ClaudeCodeHistory.sessions(in: history)
        let project = app.path(percentEncoded: false)
        #expect(sessions == [.init(folder: project, date: date), .init(folder: project, date: date)])
    }
}

@Suite struct ProjectUsageMergeTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func addsEarlierUsesInOrderOnce() {
        var usage = ProjectUsage()
        usage.record("/work/app", at: now)
        let earlier = [(path: "/work/site", date: now - 100), (path: "/work/app", date: now - 50)]
        usage.merge(earlier)
        usage.merge(earlier)
        #expect(usage.uses.map(\.path) == ["/work/site", "/work/app", "/work/app"])
        #expect(usage.paths == ["/work/app", "/work/site"])
        #expect(usage.lastUse(of: Project(path: "/work/app")) == now)
    }
}
