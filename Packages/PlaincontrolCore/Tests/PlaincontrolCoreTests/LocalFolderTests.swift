import Foundation
import Testing

@testable import PlaincontrolCore

/// Tests against this Mac's own folders, set in `.env` (see ``LocalTestData``).
@Suite struct LocalFolderTests {
    @Test(.enabled(if: LocalTestData.linkedFolder != nil, "Set PLAINCONTROL_TEST_LINKED_FOLDER in .env"))
    func goesIntoAFolderThroughALink() throws {
        let linked = try #require(LocalTestData.linkedFolder)
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: linked)
        #expect(!destination.isEmpty, "The folder should be a symbolic link")

        let subfolders = ProjectFolders.subfolders(of: linked)
        #expect(!subfolders.isEmpty)

        var finder = PathFinder(folder: linked, home: NSHomeDirectory(), list: ProjectFolders.subfolders(of:))
        #expect(finder.press(.enter, list: ProjectFolders.subfolders(of:)) == .stay)
        #expect(finder.folder == (linked as NSString).appendingPathComponent(subfolders[0]))
    }
}
