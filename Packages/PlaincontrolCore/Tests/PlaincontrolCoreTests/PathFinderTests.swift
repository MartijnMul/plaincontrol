import Foundation
import Testing

@testable import PlaincontrolCore

@Suite struct PathFinderTests {
    /// A made-up disk.
    let disk: [String: [String]] = [
        "/": ["Users"],
        "/Users": ["me"],
        "/Users/me": ["Code", "Documents", "workspaces"],
        "/Users/me/workspaces": ["client", "private", "proxy-tools"],
        "/Users/me/workspaces/private": ["homelab", "website"],
    ]

    func list(_ folder: String) -> [String] { disk[folder] ?? [] }

    func press(_ keys: Launcher.Key..., on finder: inout PathFinder) -> [PathFinder.Outcome] {
        keys.map { finder.press($0, list: list) }
    }

    func type(_ text: String) -> [Launcher.Key] { text.map(Launcher.Key.character) }

    @Test func showsTheCurrentFolderAboveTheFoldersInside() {
        let finder = PathFinder(folder: "/Users/me", list: list)
        #expect(finder.rows == [.current, .subfolder("Code"), .subfolder("Documents"), .subfolder("workspaces")])
        #expect(finder.selectedRow == .subfolder("Code"))
    }

    @Test func walksDownAndAddsAFolder() {
        var finder = PathFinder(folder: "/Users/me", list: list)
        _ = press(.down, .down, .right, on: &finder)
        #expect(finder.folder == "/Users/me/workspaces")
        for key in type("pri") { _ = finder.press(key, list: list) }
        #expect(finder.rows == [.subfolder("private")])
        _ = press(.right, on: &finder)
        #expect(finder.folder == "/Users/me/workspaces/private")
        #expect(press(.enter, on: &finder) == [.add("/Users/me/workspaces/private/homelab")])
    }

    @Test func addsTheCurrentFolder() {
        var finder = PathFinder(folder: "/Users/me/workspaces", list: list)
        #expect(press(.up, .enter, on: &finder) == [.stay, .add("/Users/me/workspaces")])
    }

    @Test func slashGoesIntoTheBestMatch() {
        var finder = PathFinder(folder: "/Users/me", list: list)
        for key in type("work/pri/") { _ = finder.press(key, list: list) }
        #expect(finder.folder == "/Users/me/workspaces/private")
    }

    @Test func listsNamesStartingWithTheFilterFirst() {
        var finder = PathFinder(folder: "/Users/me/workspaces", list: list)
        for key in type("pr") { _ = finder.press(key, list: list) }
        #expect(finder.rows == [.subfolder("private"), .subfolder("proxy-tools")])
        for key in type("o") { _ = finder.press(key, list: list) }
        #expect(finder.rows == [.subfolder("proxy-tools")])
        #expect(press(.character("z"), on: &finder) == [.stay])
        #expect(finder.rows.isEmpty)
        #expect(press(.enter, on: &finder) == [.stay])
    }

    @Test func goesUpWithTheFolderItCameFromSelected() {
        var finder = PathFinder(folder: "/Users/me/workspaces/private", list: list)
        _ = press(.left, on: &finder)
        #expect(finder.folder == "/Users/me/workspaces")
        #expect(finder.selectedRow == .subfolder("private"))
        _ = press(.backspace, on: &finder)
        #expect(finder.folder == "/Users/me")
        #expect(finder.selectedRow == .subfolder("workspaces"))
        _ = press(.left, .left, .left, on: &finder)
        #expect(finder.folder == "/")
    }

    @Test func backspaceEditsTheFilterFirst() {
        var finder = PathFinder(folder: "/Users/me/workspaces", list: list)
        _ = press(.character("c"), .character("l"), .backspace, on: &finder)
        #expect(finder.filter == "c")
        #expect(finder.folder == "/Users/me/workspaces")
    }

    @Test func escapeClearsTheFilterThenGivesUp() {
        var finder = PathFinder(folder: "/Users/me", list: list)
        _ = press(.character("c"), on: &finder)
        #expect(press(.escape, on: &finder) == [.stay])
        #expect(finder.filter.isEmpty)
        #expect(press(.escape, on: &finder) == [.cancel])
    }

    @Test func listsRealFoldersWithoutHiddenOnesAndApps() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["b-folder", "A-folder", ".hidden", "Tool.app", "folder 10", "folder 9"] {
            try FileManager.default.createDirectory(at: folder.appending(path: name), withIntermediateDirectories: true)
        }
        try "text".write(to: folder.appending(path: "file.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: folder.appending(path: "linked"), withDestinationURL: folder.appending(path: "b-folder"))
        #expect(
            ProjectFolders.subfolders(of: folder.path(percentEncoded: false))
                == ["A-folder", "b-folder", "folder 9", "folder 10", "linked"])
    }
}
