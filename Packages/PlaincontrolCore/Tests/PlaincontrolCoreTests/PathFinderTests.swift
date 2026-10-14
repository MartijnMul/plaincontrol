import Foundation
import Testing

@testable import PlaincontrolCore

@Suite struct PathFinderTests {
    /// A made-up disk.
    let disk: [String: [String]] = [
        "/": ["Users"],
        "/Users": ["me"],
        "/Users/me": ["Code", "Documents", "Dropbox", "workspaces"],
        "/Users/me/workspaces": ["client", "private", "proxy-tools"],
        "/Users/me/workspaces/private": ["homelab", "website"],
        "/Users/me/Dropbox": ["Personal", "Scans"],
        "/Users/me/Dropbox/Personal": ["House plans", "Taxes"],
    ]

    func list(_ folder: String) -> [String] { disk[folder] ?? [] }

    func press(_ keys: Launcher.Key..., on finder: inout PathFinder) -> [PathFinder.Outcome] {
        keys.map { finder.press($0, list: list) }
    }

    func type(_ text: String) -> [Launcher.Key] { text.map(Launcher.Key.character) }

    func finder(at folder: String) -> PathFinder {
        PathFinder(folder: folder, home: "/Users/me", list: list)
    }

    @Test func offersToAddTheCurrentFolderAboveTheFoldersInside() {
        let finder = finder(at: "/Users/me/workspaces")
        #expect(finder.rows == [.add, .subfolder("client"), .subfolder("private"), .subfolder("proxy-tools")])
        #expect(finder.selectedRow == .subfolder("client"))
    }

    @Test func returnGoesIntoAFolderInsteadOfAddingIt() {
        var finder = finder(at: "/Users/me")
        for key in type("drop") { _ = finder.press(key, list: list) }
        #expect(press(.enter, on: &finder) == [.stay])
        #expect(finder.folder == "/Users/me/Dropbox")
        #expect(press(.enter, .enter, on: &finder) == [.stay, .stay])
        #expect(finder.folder == "/Users/me/Dropbox/Personal/House plans")
        #expect(finder.rows == [.add])
    }

    @Test func addsOnlyWithTheAddRow() {
        var finder = finder(at: "/Users/me/Dropbox/Personal")
        #expect(finder.selectedRow == .subfolder("House plans"))
        #expect(press(.right, on: &finder) == [.stay])
        #expect(finder.selectedRow == .add)
        #expect(press(.right, on: &finder) == [.stay])
        #expect(press(.enter, on: &finder) == [.add("/Users/me/Dropbox/Personal/House plans")])
    }

    @Test func neverOffersToAddTheHomeFolderOrAbove() {
        #expect(!finder(at: "/Users/me").rows.contains(.add))
        #expect(!finder(at: "/Users").rows.contains(.add))
        #expect(!finder(at: "/").rows.contains(.add))
        #expect(finder(at: "/Users/me/Code").rows == [.add])
    }

    @Test func walksDownByTypingWithSlashes() {
        var finder = finder(at: "/Users/me")
        for key in type("work/pri/") { _ = finder.press(key, list: list) }
        #expect(finder.folder == "/Users/me/workspaces/private")
        #expect(finder.selectedRow == .subfolder("homelab"))
    }

    @Test func hidesTheAddRowWhileFiltering() {
        var finder = finder(at: "/Users/me/workspaces")
        for key in type("pr") { _ = finder.press(key, list: list) }
        #expect(finder.rows == [.subfolder("private"), .subfolder("proxy-tools")])
        for key in type("o") { _ = finder.press(key, list: list) }
        #expect(finder.rows == [.subfolder("proxy-tools")])
        #expect(press(.character("z"), on: &finder) == [.stay])
        #expect(finder.rows.isEmpty)
        #expect(press(.enter, on: &finder) == [.stay])
    }

    @Test func goesUpWithTheFolderItCameFromSelected() {
        var finder = finder(at: "/Users/me/workspaces/private")
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
        var finder = finder(at: "/Users/me/workspaces")
        _ = press(.character("c"), .character("l"), .backspace, on: &finder)
        #expect(finder.filter == "c")
        #expect(finder.folder == "/Users/me/workspaces")
    }

    @Test func escapeClearsTheFilterThenGivesUp() {
        var finder = finder(at: "/Users/me/workspaces")
        _ = press(.character("c"), on: &finder)
        #expect(press(.escape, on: &finder) == [.stay])
        #expect(finder.filter.isEmpty)
        #expect(finder.selectedRow == .subfolder("client"))
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

        try FileManager.default.createDirectory(
            at: folder.appending(path: "b-folder/inside"), withIntermediateDirectories: true)
        #expect(
            ProjectFolders.subfolders(of: folder.appending(path: "linked").path(percentEncoded: false)) == ["inside"])
    }
}
