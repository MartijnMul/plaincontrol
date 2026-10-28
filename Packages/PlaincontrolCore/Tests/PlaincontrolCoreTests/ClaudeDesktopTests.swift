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
}
