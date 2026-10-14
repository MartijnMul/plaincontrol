import Foundation
import Testing

@testable import PlaincontrolCore

@Suite struct ProjectTests {
    @Test func isNamedAfterItsFolderWithoutAName() {
        #expect(Project(path: "/work/my-app").name == "my-app")
        #expect(Project(path: "/work/my-app", name: "  ").name == "my-app")
        #expect(Project(path: "/work/my-app", name: "My App").name == "My App")
    }

    @Test func expandsTheHomeFolderAndDropsATrailingSlash() {
        #expect(Project(path: "~/work/my-app/").path == NSHomeDirectory() + "/work/my-app")
    }

    @Test func containsItsFolderAndFoldersInside() {
        let project = Project(path: "/work/my-app")
        #expect(project.contains("/work/my-app"))
        #expect(project.contains("/work/my-app/"))
        #expect(project.contains("/work/my-app/Sources/App"))
        #expect(!project.contains("/work/my-app-2"))
        #expect(!project.contains("/work"))
    }
}

@Suite struct ProjectsFileTests {
    @Test func readsNamesAndPathsInOrder() throws {
        let projects = try ProjectsFile.parse(
            """
            projects:
              - name: My App
                path: /work/my-app
              - path: /work/website
            """)
        #expect(projects == [Project(path: "/work/my-app", name: "My App"), Project(path: "/work/website")])
    }

    @Test func countsAFolderListedTwiceOnce() throws {
        let projects = try ProjectsFile.parse(
            """
            projects:
              - path: /work/my-app
              - path: /work/my-app/
                name: Again
            """)
        #expect(projects.map(\.name) == ["my-app"])
    }

    @Test func hasNoProjectsWhenEmpty() throws {
        #expect(try ProjectsFile.parse("").isEmpty)
        #expect(try ProjectsFile.parse("# nothing yet\n").isEmpty)
        #expect(try ProjectsFile.parse(ProjectsFile.template).isEmpty)
    }

    @Test func reportsAnEntryWithoutAPath() {
        #expect(throws: ProjectsFileError.self) {
            try ProjectsFile.parse("projects:\n  - name: No Path\n")
        }
    }

    @Test func createsTheTemplateOnlyWhenMissing() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "nested/projects.yaml").path(percentEncoded: false)

        #expect(try ProjectsFile.load(from: path).isEmpty)
        try ProjectsFile.createIfMissing(at: path)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == ProjectsFile.template)

        try "projects:\n  - path: /work/my-app\n".write(toFile: path, atomically: true, encoding: .utf8)
        try ProjectsFile.createIfMissing(at: path)
        #expect(try ProjectsFile.load(from: path) == [Project(path: "/work/my-app")])
    }
}

@Suite struct ProjectRecencyTests {
    let app = Project(path: "/work/app")
    let site = Project(path: "/work/site")
    let docs = Project(path: "/work/docs")
    let start = Date(timeIntervalSinceReferenceDate: 0)

    func session(in cwd: String, at date: Date) -> Session {
        Session(id: UUID().uuidString, status: .idle, statusSince: date, lastEventAt: date, cwd: cwd)
    }

    @Test func keepsTheFileOrderForProjectsNeverUsed() {
        #expect(ProjectRecency().ordered([app, site, docs], sessions: []) == [app, site, docs])
    }

    @Test func putsTheMostRecentlyUsedFirst() {
        var recency = ProjectRecency()
        recency.markUsed(site, at: start)
        recency.markUsed(docs, at: start + 60)
        #expect(recency.ordered([app, site, docs], sessions: []) == [docs, site, app])
    }

    @Test func countsSessionsInTheProjectFolderAsUse() {
        var recency = ProjectRecency()
        recency.markUsed(site, at: start)
        let sessions = [session(in: "/work/docs/guide", at: start + 60), session(in: "/elsewhere", at: start + 120)]
        #expect(recency.ordered([app, site, docs], sessions: sessions) == [docs, site, app])
    }

    @Test func survivesEncoding() throws {
        var recency = ProjectRecency()
        recency.markUsed(app, at: start)
        let decoded = try JSONDecoder().decode(ProjectRecency.self, from: JSONEncoder().encode(recency))
        #expect(decoded == recency)
    }
}
