import Foundation
import Testing

@testable import PlaincontrolCore

@Suite struct ClaudeDesktopTests {
    /// The folder the desktop app reads from the link, as a web form decodes it.
    func folder(in url: URL) -> String? {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? ""
        #expect(query.hasPrefix("folder="))
        return String(query.dropFirst("folder=".count)).replacing("+", with: " ").removingPercentEncoding
    }

    @Test func asksForANewSessionInTheFolder() {
        let url = ClaudeDesktop.newSessionURL(in: "/Users/someone/Code/app")
        #expect(url.absoluteString == "claude://code/new?folder=/Users/someone/Code/app")
    }

    @Test func keepsAnyFolderNameIntact() {
        let path = "/Users/someone/Client work/a+b & c=d #1 100%/Café"
        #expect(folder(in: ClaudeDesktop.newSessionURL(in: path)) == path)
    }

    @Test func findsTheMenuTitleInEveryLanguage() throws {
        let app = FileManager.default.temporaryDirectory.appending(path: "ClaudeDesktopTests-\(UUID()).app")
        defer { try? FileManager.default.removeItem(at: app) }
        let resources = app.appending(path: "Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let files = [
            "nl.json": #"{"U//bQDu9Yk": "Nieuwe sessie in nieuw venster", "other": "Bestand"}"#,
            "de-DE.json": #"{"U//bQDu9Yk": "Neue Sitzung in neuem Fenster"}"#,
            "fr-FR.json": #"{"other": "Fichier"}"#,
            "broken.json": "not json",
            "list.json": #"["U//bQDu9Yk"]"#,
        ]
        for (name, text) in files {
            try text.write(to: resources.appending(path: name), atomically: true, encoding: .utf8)
        }

        #expect(
            ClaudeDesktop.newWindowMenuTitles(inAppAt: app) == [
                "New Session in New Window", "Nieuwe sessie in nieuw venster", "Neue Sitzung in neuem Fenster",
            ])
    }

    @Test func findsTheMenuTitleInTheAppsArchive() throws {
        let app = FileManager.default.temporaryDirectory.appending(path: "ClaudeDesktopTests-\(UUID()).app")
        defer { try? FileManager.default.removeItem(at: app) }
        try writeAsar(
            [
                "resources/i18n/nl.json": #"{"U//bQDu9Yk": "Nieuwe sessie in nieuw venster"}"#,
                "resources/i18n/de-DE.json": #"{"U//bQDu9Yk": "Neue Sitzung in neuem Fenster"}"#,
                "resources/other/fr-FR.json": #"{"U//bQDu9Yk": "Nouvelle session dans une nouvelle fenêtre"}"#,
            ], to: app.appending(path: "Contents/Resources/app.asar"))

        #expect(
            ClaudeDesktop.newWindowMenuTitles(inAppAt: app) == [
                "New Session in New Window", "Nieuwe sessie in nieuw venster", "Neue Sitzung in neuem Fenster",
            ])
    }

    @Test func findsTheFolderButtonLabelInEveryLanguage() throws {
        let app = FileManager.default.temporaryDirectory.appending(path: "ClaudeDesktopTests-\(UUID()).app")
        defer { try? FileManager.default.removeItem(at: app) }
        try writeAsar(
            [
                "i18n/de-DE.json": #"{"hSyWJr4x1N": "Ordner: {value}"}"#,
                "i18n/ja-JP.json": #"{"hSyWJr4x1N": "フォルダー：{value}"}"#,
                "i18n/dynamic/fr-FR.json": #"{"hSyWJr4x1N": "Dossier : {value}"}"#,
            ], to: app.appending(path: "Contents/Resources/ion-dist.asar"))

        #expect(
            ClaudeDesktop.folderButtonLabels(inAppAt: app) == ["Folder: {value}", "Ordner: {value}", "フォルダー：{value}"])
    }

    @Test func tellsTheFolderButtonByItsLabel() {
        let labels: Set = ["Folder: {value}", "Dossier : {value}", "{value} (folder)"]
        #expect(ClaudeDesktop.isFolderButton(described: "Folder: Choose folder…", labels: labels))
        #expect(ClaudeDesktop.isFolderButton(described: "Folder: ~/Code/app", labels: labels))
        #expect(ClaudeDesktop.isFolderButton(described: "Dossier : Choisir…", labels: labels))
        #expect(ClaudeDesktop.isFolderButton(described: "~/Code/app (folder)", labels: labels))
        #expect(!ClaudeDesktop.isFolderButton(described: "Folder: ", labels: labels))
        #expect(!ClaudeDesktop.isFolderButton(described: "Environment: This computer", labels: labels))
        #expect(!ClaudeDesktop.isFolderButton(described: "Folder: ~/Code/app", labels: ["Folder"]))
    }

    @Test func readsFilesFromAnArchive() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "ClaudeDesktopTests-\(UUID()).asar")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeAsar(["a.txt": "first", "dir/b.txt": "second", "dir/sub/c.txt": "third"], to: url)

        let asar = try #require(Asar(contentsOf: url))
        #expect(asar.contents(of: "a.txt") == Data("first".utf8))
        #expect(asar.contents(of: "dir/sub/c.txt") == Data("third".utf8))
        #expect(asar.files(in: "dir") == ["b.txt"])
        #expect(asar.contents(of: "dir/missing.txt") == nil)
        #expect(asar.contents(of: "dir") == nil)
    }

    @Test func refusesWhatIsNoArchive() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "ClaudeDesktopTests-\(UUID()).asar")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not an archive at all".utf8).write(to: url)
        #expect(Asar(contentsOf: url) == nil)
        #expect(Asar(contentsOf: URL(filePath: "/nonexistent/app.asar")) == nil)
    }

    @Test func knowsTheEnglishMenuTitleWithoutTranslations() {
        let app = URL(filePath: "/nonexistent/Claude.app")
        #expect(ClaudeDesktop.newWindowMenuTitles(inAppAt: app) == ["New Session in New Window"])
    }

    @Test func readsFoldersAsTheWindowShowsThem() {
        let home = "/Users/someone"
        #expect(ClaudeDesktop.folder(shownAs: "~/Code/app", home: home) == "/Users/someone/Code/app")
        #expect(ClaudeDesktop.folder(shownAs: "/Users/someone/Code/app", home: home + "/") == "/Users/someone/Code/app")
        #expect(ClaudeDesktop.folder(shownAs: "~", home: home) == "/Users/someone")
        #expect(ClaudeDesktop.folder(shownAs: "/srv/app/", home: home) == "/srv/app")
        #expect(ClaudeDesktop.folder(shownAs: "Choose a folder", home: home) == nil)
    }

    /// Writes an archive as Electron does: the index as JSON in a pickle, then the files.
    func writeAsar(_ files: [String: String], to url: URL) throws {
        var tree: [String: Any] = [:]
        var body = Data()
        for (path, text) in files.sorted(by: { $0.key < $1.key }) {
            let data = Data(text.utf8)
            let names = path.split(separator: "/").map(String.init)
            func insert(into node: [String: Any], _ names: ArraySlice<String>) -> [String: Any] {
                var node = node
                var children = node["files"] as? [String: Any] ?? [:]
                if names.count == 1 {
                    children[names[names.startIndex]] = ["size": data.count, "offset": String(body.count)]
                } else {
                    let child = children[names[names.startIndex]] as? [String: Any] ?? [:]
                    children[names[names.startIndex]] = insert(into: child, names.dropFirst())
                }
                node["files"] = children
                return node
            }
            tree = insert(into: tree, names[...])
            body.append(data)
        }
        let json = try JSONSerialization.data(withJSONObject: tree)
        let padded = (json.count + 3) / 4 * 4
        func word(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }
        var archive = word(4) + word(padded + 8) + word(padded + 4) + word(json.count) + json
        archive.append(Data(count: padded - json.count))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (archive + body).write(to: url)
    }
}
