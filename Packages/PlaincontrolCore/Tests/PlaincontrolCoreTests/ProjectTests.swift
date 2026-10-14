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
    @Test func readsRootsDaysAndProjectsInOrder() throws {
        let config = try ProjectsFile.parse(
            """
            roots:
              - /work
            activeDays: 30
            projects:
              - name: My App
                path: /work/my-app
              - path: /elsewhere/website
            """)
        #expect(config.roots == ["/work"])
        #expect(config.activeDays == 30)
        #expect(
            config.projects == [Project(path: "/work/my-app", name: "My App"), Project(path: "/elsewhere/website")])
    }

    @Test func countsAFolderListedTwiceOnce() throws {
        let config = try ProjectsFile.parse(
            """
            projects:
              - path: /work/my-app
              - path: /work/my-app/
                name: Again
            """)
        #expect(config.projects.map(\.name) == ["my-app"])
    }

    @Test func isEmptyWithoutSettings() throws {
        #expect(try ProjectsFile.parse("") == ProjectsConfig())
        #expect(try ProjectsFile.parse("# nothing yet\n") == ProjectsConfig())
        #expect(try ProjectsFile.parse(ProjectsFile.template) == ProjectsConfig())
        #expect(ProjectsConfig().activeDays == 90)
    }

    @Test func reportsMistakes() {
        #expect(throws: ProjectsFileError.self) { try ProjectsFile.parse("projects:\n  - name: No Path\n") }
        #expect(throws: ProjectsFileError.self) { try ProjectsFile.parse("activeDays: 0\n") }
    }

    @Test func createsTheTemplateOnlyWhenMissing() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "nested/projects.yaml").path(percentEncoded: false)

        #expect(try ProjectsFile.load(from: path) == ProjectsConfig())
        try ProjectsFile.createIfMissing(at: path)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == ProjectsFile.template)

        try "projects:\n  - path: /work/my-app\n".write(toFile: path, atomically: true, encoding: .utf8)
        try ProjectsFile.createIfMissing(at: path)
        #expect(try ProjectsFile.load(from: path).projects == [Project(path: "/work/my-app")])
    }
}

@Suite struct ProjectUsageTests {
    let app = Project(path: "/work/app")
    let site = Project(path: "/work/site")
    let now = Date(timeIntervalSinceReferenceDate: 1_000_000_000)
    let day: TimeInterval = 24 * 3600

    @Test func weighsRecentUsesMore() {
        var usage = ProjectUsage()
        usage.record("/work/app", at: now)
        usage.record("/work/site", at: now - 7 * day)
        #expect(usage.score(of: app, at: now) == 1)
        #expect(usage.score(of: site, at: now) == 0.5)
    }

    @Test func keepsAProjectUsedEveryDayAheadOfOneUsedOnceToday() {
        var usage = ProjectUsage()
        for daysAgo in 1...10 { usage.record("/work/app", at: now - Double(daysAgo) * day) }
        usage.record("/work/site", at: now)
        #expect(usage.score(of: app, at: now) > usage.score(of: site, at: now))
    }

    @Test func countsUsesInFoldersInsideTheProject() {
        var usage = ProjectUsage()
        usage.record("/work/app/Sources", at: now)
        #expect(usage.score(of: app, at: now) == 1)
        #expect(usage.lastUse(of: app) == now)
        #expect(usage.lastUse(of: site) == nil)
    }

    @Test func listsEachFolderOnceMostRecentFirst() {
        var usage = ProjectUsage()
        usage.record("/work/app", at: now)
        usage.record("/work/site", at: now + 1)
        usage.record("/work/app", at: now + 2)
        #expect(usage.paths == ["/work/app", "/work/site"])
    }

    @Test func keepsALimitedNumberOfUses() {
        var usage = ProjectUsage()
        for index in 0..<(ProjectUsage.limit + 5) { usage.record("/work/app", at: now + Double(index)) }
        #expect(usage.uses.count == ProjectUsage.limit)
        #expect(usage.uses.first?.date == now + 5)
    }

    @Test func survivesEncoding() throws {
        var usage = ProjectUsage()
        usage.record("/work/app", at: now)
        let decoded = try JSONDecoder().decode(ProjectUsage.self, from: JSONEncoder().encode(usage))
        #expect(decoded == usage)
    }
}

@Suite struct ProjectCatalogTests {
    let now = Date(timeIntervalSinceReferenceDate: 1_000_000_000)
    let day: TimeInterval = 24 * 3600

    func session(in cwd: String, status: SessionStatus = .idle) -> Session {
        Session(id: UUID().uuidString, status: status, statusSince: now, lastEventAt: now, cwd: cwd)
    }

    func item(_ items: [LauncherItem], _ path: String) -> LauncherItem? {
        items.first { $0.project.path == path }
    }

    @Test func listsRecentRepositoriesAndConfiguredProjectsAsActive() {
        let config = ProjectsConfig(activeDays: 90, projects: [Project(path: "/work/old", name: "Old Friend")])
        let repositories = [
            Repository(path: "/work/new", lastCommit: now - 10 * day),
            Repository(path: "/work/stale", lastCommit: now - 200 * day),
            Repository(path: "/work/old", lastCommit: now - 500 * day),
            Repository(path: "/work/empty", lastCommit: nil),
        ]
        let items = ProjectCatalog.items(
            config: config, repositories: repositories, usage: ProjectUsage(), sessions: [], now: now)
        #expect(items.count == 4)
        #expect(item(items, "/work/new")?.isActive == true)
        #expect(item(items, "/work/stale")?.isActive == false)
        #expect(item(items, "/work/empty")?.isActive == false)
        #expect(item(items, "/work/old")?.isActive == true)
        #expect(item(items, "/work/old")?.project.name == "Old Friend")
    }

    @Test func makesAStaleRepositoryActiveAgainOnceUsed() {
        var usage = ProjectUsage()
        usage.record("/work/stale", at: now - day)
        let items = ProjectCatalog.items(
            config: ProjectsConfig(), repositories: [Repository(path: "/work/stale", lastCommit: now - 200 * day)],
            usage: usage, sessions: [], now: now)
        #expect(item(items, "/work/stale")?.isActive == true)
        #expect(item(items, "/work/stale")?.lastActivity == now - day)
    }

    @Test func marksProjectsWithSessions() {
        let repositories = [
            Repository(path: "/work/a", lastCommit: nil),
            Repository(path: "/work/b", lastCommit: nil),
            Repository(path: "/work/c", lastCommit: nil),
        ]
        let sessions = [
            session(in: "/work/a/Sources"),
            session(in: "/work/b", status: .waiting(.permission)),
            session(in: "/work/b"),
            session(in: "/work/c", status: .gone),
        ]
        let items = ProjectCatalog.items(
            config: ProjectsConfig(), repositories: repositories, usage: ProjectUsage(), sessions: sessions, now: now)
        #expect(item(items, "/work/a")?.sessions == .running)
        #expect(item(items, "/work/a")?.isActive == true)
        #expect(item(items, "/work/b")?.sessions == .waiting)
        #expect(item(items, "/work/c")?.sessions == LauncherItem.Sessions.none)
    }
}
