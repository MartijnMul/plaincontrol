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

    @Test func containsFoldersByTheirLinkedToPathToo() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appending(path: "synced/notes")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let link = folder.appending(path: "notes")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let project = Project(path: link.path(percentEncoded: false))
        let resolved = target.resolvingSymlinksInPath().path(percentEncoded: false)
        #expect(project.contains(resolved + "/drafts"))
        #expect(project.contains(link.path(percentEncoded: false)))
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

@Suite struct LauncherConfigFileTests {
    @Test func readsRootsDaysAndProjectsInOrder() throws {
        let config = try LauncherConfigFile.parse(
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

    @Test func readsTheLauncherSettings() throws {
        let config = try LauncherConfigFile.parse(
            """
            holdKey: rightCommand
            editor: Cursor
            claudeCommand: claude --continue
            zoxide: false
            """)
        #expect(config.holdKey == .rightCommand)
        #expect(config.editor == "Cursor")
        #expect(config.claudeCommand == "claude --continue")
        #expect(!config.zoxide)
    }

    @Test func usesTheDefaultsForMissingSettings() throws {
        let config = try LauncherConfigFile.parse("editor: \"  \"\n")
        #expect(config.holdKey == .rightOption)
        #expect(config.editor == nil)
        #expect(config.claudeCommand == "claude")
        #expect(config.zoxide)
    }

    @Test func reportsAnUnknownHoldKeyOrEmptyCommand() {
        #expect(throws: LauncherConfigError.self) { try LauncherConfigFile.parse("holdKey: capsLock\n") }
        #expect(throws: LauncherConfigError.self) { try LauncherConfigFile.parse("claudeCommand: \"\"\n") }
    }

    @Test func countsAFolderListedTwiceOnce() throws {
        let config = try LauncherConfigFile.parse(
            """
            projects:
              - path: /work/my-app
              - path: /work/my-app/
                name: Again
            """)
        #expect(config.projects.map(\.name) == ["my-app"])
    }

    @Test func readsTheWindowLayout() throws {
        #expect(try LauncherConfigFile.parse("zoxide: true\n").windows == nil)
        let config = try LauncherConfigFile.parse("windows:\n  external: 4\n")
        #expect(config.windows == WindowLayout(builtInColumns: 2, externalColumns: 4, gap: 10))
    }

    @Test func isEmptyWithoutSettings() throws {
        #expect(try LauncherConfigFile.parse("") == LauncherConfig())
        #expect(try LauncherConfigFile.parse("# nothing yet\n") == LauncherConfig())
        #expect(try LauncherConfigFile.parse(LauncherConfigFile.template) == LauncherConfig())
        #expect(LauncherConfig().activeDays == 90)
    }

    @Test func reportsMistakes() {
        #expect(throws: LauncherConfigError.self) { try LauncherConfigFile.parse("projects:\n  - name: No Path\n") }
        #expect(throws: LauncherConfigError.self) { try LauncherConfigFile.parse("activeDays: 0\n") }
        #expect(throws: LauncherConfigError.self) { try LauncherConfigFile.parse("windows:\n  external: 0\n") }
        #expect(throws: LauncherConfigError.self) { try LauncherConfigFile.parse("windows:\n  gap: -1\n") }
    }

    @Test func createsTheTemplateOnlyWhenMissing() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "nested/launcher.yaml").path(percentEncoded: false)

        #expect(try LauncherConfigFile.load(from: path) == LauncherConfig())
        try LauncherConfigFile.createIfMissing(at: path)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == LauncherConfigFile.template)

        try "projects:\n  - path: /work/my-app\n".write(toFile: path, atomically: true, encoding: .utf8)
        try LauncherConfigFile.createIfMissing(at: path)
        #expect(try LauncherConfigFile.load(from: path).projects == [Project(path: "/work/my-app")])
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

    @Test func listsRecentFoldersAndConfiguredProjectsAsActive() {
        let config = LauncherConfig(activeDays: 90, projects: [Project(path: "/work/old", name: "Old Friend")])
        let folders = [
            ProjectFolder(path: "/work/new", lastChange: now - 10 * day),
            ProjectFolder(path: "/work/stale", lastChange: now - 200 * day),
            ProjectFolder(path: "/work/old", lastChange: now - 500 * day),
            ProjectFolder(path: "/work/empty", lastChange: nil),
        ]
        let items = ProjectCatalog.items(
            config: config, folders: folders, usage: ProjectUsage(), sessions: [], now: now)
        #expect(items.count == 4)
        #expect(item(items, "/work/new")?.isActive == true)
        #expect(item(items, "/work/stale")?.isActive == false)
        #expect(item(items, "/work/empty")?.isActive == false)
        #expect(item(items, "/work/old")?.isActive == true)
        #expect(item(items, "/work/old")?.project.name == "Old Friend")
    }

    @Test func makesAStaleFolderActiveAgainOnceUsed() {
        var usage = ProjectUsage()
        usage.record("/work/stale", at: now - day)
        let items = ProjectCatalog.items(
            config: LauncherConfig(), folders: [ProjectFolder(path: "/work/stale", lastChange: now - 200 * day)],
            usage: usage, sessions: [], now: now)
        #expect(item(items, "/work/stale")?.isActive == true)
        #expect(item(items, "/work/stale")?.lastActivity == now - day)
    }

    @Test func addsTheFoldersFromTheUsersOwnHistory() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        for name in ["notes", "code/app", "code/site"] {
            try FileManager.default.createDirectory(at: home.appending(path: name), withIntermediateDirectories: true)
        }
        let base = home.path(percentEncoded: false)
        var usage = ProjectUsage()
        for path in [
            base, base + "/notes", base + "/code/app/Sources", base + "/gone",
            (base as NSString).deletingLastPathComponent,
        ] {
            usage.record(path, at: now)
        }
        let config = LauncherConfig(roots: [base + "/code"])
        let paths = ProjectCatalog.folderPaths(config: config, usage: usage, home: base)
        #expect(paths.map { $0.replacing(base, with: "~") } == ["~/code/app", "~/code/site", "~/notes"])
    }

    @Test func ranksByZoxideAndOwnUseTogether() {
        var usage = ProjectUsage()
        usage.record("/work/used", at: now)
        let folders = ["/work/used", "/work/both", "/work/neither"].map { ProjectFolder(path: $0, lastChange: now) }
        usage.record("/work/both", at: now - 7 * day)
        let zoxide = [Zoxide.Entry(path: "/work/visited", score: 200), Zoxide.Entry(path: "/work/both", score: 100)]
        let items = ProjectCatalog.items(
            config: LauncherConfig(), folders: folders, zoxide: zoxide, usage: usage, sessions: [], now: now)
        let scores = Dictionary(uniqueKeysWithValues: items.map { ($0.project.name, $0.score) })
        #expect(scores == ["used": 1, "both": 1, "visited": 1, "neither": 0])
        #expect(item(items, "/work/visited")?.isActive == true)
    }

    @Test func ranksByOwnUseWithoutZoxide() {
        var usage = ProjectUsage()
        usage.record("/work/often", at: now)
        usage.record("/work/often", at: now)
        usage.record("/work/once", at: now)
        let folders = ["/work/often", "/work/once"].map { ProjectFolder(path: $0, lastChange: nil) }
        let items = ProjectCatalog.items(
            config: LauncherConfig(), folders: folders, usage: usage, sessions: [], now: now)
        #expect(item(items, "/work/often")?.score == 1)
        #expect(item(items, "/work/once")?.score == 0.5)
    }

    @Test func marksProjectsWithSessions() {
        let folders = [
            ProjectFolder(path: "/work/a", lastChange: nil),
            ProjectFolder(path: "/work/b", lastChange: nil),
            ProjectFolder(path: "/work/c", lastChange: nil),
        ]
        let sessions = [
            session(in: "/work/a/Sources"),
            session(in: "/work/b", status: .waiting(.permission)),
            session(in: "/work/b"),
            session(in: "/work/c", status: .gone),
        ]
        let items = ProjectCatalog.items(
            config: LauncherConfig(), folders: folders, usage: ProjectUsage(), sessions: sessions, now: now)
        #expect(item(items, "/work/a")?.sessions == .running)
        #expect(item(items, "/work/a")?.isActive == true)
        #expect(item(items, "/work/b")?.sessions == .waiting)
        #expect(item(items, "/work/c")?.sessions == LauncherItem.Sessions.none)
    }
}
