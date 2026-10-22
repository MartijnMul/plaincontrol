import Foundation
import Testing

@testable import PlaincontrolCore

@Suite struct HookCommandLinkTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    var link: URL { folder.appending(path: "Support/bin/plaincontrol-hook") }

    func destination() throws -> String {
        try FileManager.default.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false))
    }

    func contents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            atPath: link.deletingLastPathComponent().path(percentEncoded: false))
    }

    /// Tells the link apart from a new one at the same path.
    func fileNumber() throws -> Int? {
        try FileManager.default.attributesOfItem(atPath: link.path(percentEncoded: false))[.systemFileNumber] as? Int
    }

    @Test func goesInTheAppsFolderInApplicationSupport() {
        #expect(
            HookCommandLink.defaultURL(appName: "Plaincontrol").path(percentEncoded: false).hasSuffix(
                "/Library/Application Support/Plaincontrol/bin/plaincontrol-hook"))
    }

    @Test func createsTheLinkAndItsFolder() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let command = folder.appending(path: "One.app/Contents/MacOS/plaincontrol-hook")
        try HookCommandLink.update(link, to: command)
        #expect(try destination() == command.path(percentEncoded: false))
    }

    @Test func pointsAnExistingLinkAtTheNewCommandWithoutLeavingAnythingBehind() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try HookCommandLink.update(link, to: folder.appending(path: "Old.app/Contents/MacOS/plaincontrol-hook"))
        let command = folder.appending(path: "New.app/Contents/MacOS/plaincontrol-hook")
        try HookCommandLink.update(link, to: command)
        #expect(try destination() == command.path(percentEncoded: false))
        #expect(try contents() == ["plaincontrol-hook"])
    }

    @Test func replacesAFileInTheLinksPlace() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "old".write(to: link, atomically: true, encoding: .utf8)
        let command = folder.appending(path: "One.app/Contents/MacOS/plaincontrol-hook")
        try HookCommandLink.update(link, to: command)
        #expect(try destination() == command.path(percentEncoded: false))
    }

    @Test func leavesALinkThatIsRightAlone() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let command = folder.appending(path: "One.app/Contents/MacOS/plaincontrol-hook")
        try HookCommandLink.update(link, to: command)
        let created = try fileNumber()
        try HookCommandLink.update(link, to: command)
        #expect(try fileNumber() == created)
    }
}
