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
}
