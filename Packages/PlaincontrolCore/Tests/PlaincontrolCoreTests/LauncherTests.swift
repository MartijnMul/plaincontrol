import Foundation
import Testing

@testable import PlaincontrolCore

@Suite struct LauncherTests {
    let app = Project(path: "/work/app")
    let site = Project(path: "/work/site")

    /// A launcher listing `projects` in this order.
    func makeLauncher(_ projects: [Project], actions: [ProjectAction] = ProjectAction.allCases) -> Launcher {
        let items = projects.enumerated().map { LauncherItem(project: $1, score: Double(projects.count - $0)) }
        return Launcher(items: items, actions: actions)
    }

    /// Presses each key in turn and returns the outcome of each.
    func press(_ keys: Launcher.Key..., on launcher: inout Launcher) -> [Launcher.Outcome] {
        keys.map { launcher.press($0) }
    }

    @Test func movesTheSelectionWithinTheList() {
        var launcher = makeLauncher([app, site])
        #expect(launcher.selectedProject == app)
        #expect(press(.down, on: &launcher) == [.stay])
        #expect(launcher.selectedProject == site)
        _ = press(.down, on: &launcher)
        #expect(launcher.selectedProject == site)
        _ = press(.up, .up, on: &launcher)
        #expect(launcher.selectedProject == app)
    }

    @Test func opensTheSelectedProjectAndRunsAnActionByItsDigit() {
        var launcher = makeLauncher([app, site])
        _ = press(.down, .enter, on: &launcher)
        #expect(launcher.screen == .project(site))
        let outcomes = press(.character("x"), .character("1"), .character("3"), on: &launcher)
        #expect(outcomes == [.stay, .run(.claude, site), .run(.finder, site)])
    }

    @Test func opensTheProjectInARowByItsDigit() {
        var launcher = makeLauncher([app, site])
        #expect(press(.character("3"), .character("0"), on: &launcher) == [.stay, .stay])
        #expect(launcher.screen == .projects)
        #expect(launcher.query.isEmpty)
        #expect(press(.character("2"), .character("1"), on: &launcher) == [.stay, .run(.claude, site)])
    }

    @Test func picksARowOfTheSearchResultsByItsDigit() {
        var launcher = makeLauncher([app, site])
        _ = press(.character("s"), .character("1"), on: &launcher)
        #expect(launcher.screen == .project(site))
    }

    @Test func numbersTheActionsOnOfferInOrder() {
        var launcher = makeLauncher([app], actions: [.claude, .finder])
        let outcomes = press(.enter, .character("2"), .character("3"), on: &launcher)
        #expect(outcomes == [.stay, .run(.finder, app), .stay])
    }

    @Test func numbersTheFirstNineRows() {
        #expect(Launcher.digit(forRow: 0) == "1")
        #expect(Launcher.digit(forRow: 8) == "9")
        #expect(Launcher.digit(forRow: 9) == nil)
    }

    @Test func escapeGoesBackThenCloses() {
        var launcher = makeLauncher([app, site])
        _ = press(.down, .enter, on: &launcher)
        #expect(press(.escape, on: &launcher) == [.stay])
        #expect(launcher.screen == .projects)
        #expect(launcher.selectedProject == site)
        #expect(press(.escape, on: &launcher) == [.close])
    }

    @Test func handlesAnEmptyList() {
        var launcher = makeLauncher([])
        #expect(press(.down, .enter, on: &launcher) == [.stay, .findFolder])
        #expect(launcher.screen == .projects)
        #expect(launcher.selectedProject == nil)
    }

    @Test func rightOpensAndLeftGoesBack() {
        var launcher = makeLauncher([app, site])
        _ = press(.down, .right, on: &launcher)
        #expect(launcher.screen == .project(site))
        #expect(press(.left, on: &launcher) == [.stay])
        #expect(launcher.screen == .projects)
        #expect(launcher.selectedProject == site)
        #expect(press(.left, on: &launcher) == [.stay])
        #expect(launcher.screen == .projects)
    }

    @Test func offersTheActionsOfTheOpenProject() {
        let items = [app, site].enumerated().map { LauncherItem(project: $1, score: Double(2 - $0)) }
        var launcher = Launcher(items: items) { project in
            project == app ? [.claude, .devServer] : [.claude]
        }
        _ = press(.enter, on: &launcher)
        #expect(launcher.actions == [.claude, .devServer])
        #expect(press(.character("2"), on: &launcher) == [.run(.devServer, app)])
        _ = press(.escape, .character("2"), on: &launcher)
        #expect(launcher.actions == [.claude])
        #expect(press(.character("2"), on: &launcher) == [.stay])
    }

    @Test func runsTheSelectedActionWithReturnOrRight() {
        var launcher = makeLauncher([app], actions: [.claude, .finder, .editor])
        _ = press(.enter, on: &launcher)
        #expect(launcher.selectedAction == .claude)
        #expect(press(.down, .down, .down, .enter, on: &launcher) == [.stay, .stay, .stay, .run(.editor, app)])
        #expect(press(.up, .right, on: &launcher) == [.stay, .run(.finder, app)])
    }

    @Test func opensAProjectWithTheFirstActionSelected() {
        var launcher = makeLauncher([app, site])
        _ = press(.right, .down, .left, .down, .right, on: &launcher)
        #expect(launcher.screen == .project(site))
        #expect(launcher.selectedAction == .claude)
    }

    @Test func ranksSessionsFirstThenActiveProjectsByScore() {
        let items = [
            LauncherItem(project: Project(path: "/w/often"), score: 5),
            LauncherItem(project: Project(path: "/w/rare"), score: 1),
            LauncherItem(project: Project(path: "/w/working"), sessions: .running, score: 0),
            LauncherItem(project: Project(path: "/w/asking"), sessions: .waiting, score: 0),
            LauncherItem(project: Project(path: "/w/stale"), isActive: false, score: 9),
        ]
        let launcher = Launcher(items: items)
        #expect(launcher.visible.map(\.project.name) == ["asking", "working", "often", "rare"])
    }

    @Test func breaksTiesByLastActivity() {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        let items = [
            LauncherItem(project: Project(path: "/w/earlier"), lastActivity: date),
            LauncherItem(project: Project(path: "/w/later"), lastActivity: date + 60),
            LauncherItem(project: Project(path: "/w/never")),
        ]
        #expect(Launcher(items: items).visible.map(\.project.name) == ["later", "earlier", "never"])
    }

    @Test func showsALimitedNumberOfProjects() {
        let items = (0..<20).map { LauncherItem(project: Project(path: "/w/p\($0)")) }
        #expect(Launcher(items: items).visible.count == Launcher.visibleLimit)
    }

    @Test func searchFindsInactiveProjectsLast() {
        let items = [
            LauncherItem(project: Project(path: "/w/sign-old"), isActive: false),
            LauncherItem(project: Project(path: "/w/sign-service"), score: 1),
            LauncherItem(project: Project(path: "/w/website", name: "Signage")),
            LauncherItem(project: Project(path: "/w/other"), score: 9),
        ]
        var launcher = Launcher(items: items)
        _ = press(.character("S"), .character("i"), .character("g"), .character("n"), on: &launcher)
        #expect(launcher.visible.map(\.project.name) == ["sign-service", "Signage", "sign-old"])
        #expect(launcher.selection == 0)
    }

    @Test func backspaceAndEscapeEditTheSearch() {
        var launcher = makeLauncher([app, site])
        _ = press(.character("s"), .character("i"), on: &launcher)
        #expect(launcher.visible.map(\.project) == [site])
        _ = press(.backspace, .backspace, on: &launcher)
        #expect(launcher.query.isEmpty)
        #expect(launcher.visible.map(\.project) == [app, site])
        _ = press(.character("x"), on: &launcher)
        #expect(press(.escape, on: &launcher) == [.stay])
        #expect(launcher.query.isEmpty)
        #expect(press(.escape, on: &launcher) == [.close])
    }

    @Test func opensTheSelectedSearchResult() {
        var launcher = makeLauncher([app, site])
        _ = press(.character("s"), .enter, on: &launcher)
        #expect(launcher.screen == .project(site))
    }

    @Test func keepsTheSearchAndSelectionWhenProjectsChange() {
        var launcher = makeLauncher([app, site])
        _ = press(.down, on: &launcher)
        launcher.update(items: [LauncherItem(project: site, score: 5), LauncherItem(project: app, score: 1)])
        #expect(launcher.selectedProject == site)
        #expect(launcher.selection == 0)
    }

    @Test func offersToAddAFolderWhenNothingIsListed() {
        var empty = Launcher(items: [])
        #expect(empty.offersToAddFolder)
        #expect(press(.enter, on: &empty) == [.findFolder])

        var launcher = makeLauncher([app, site])
        #expect(!launcher.offersToAddFolder)
        _ = press(.character("x"), .character("y"), on: &launcher)
        #expect(launcher.offersToAddFolder)
        #expect(press(.right, on: &launcher) == [.findFolder])
    }

    @Test func opensAnAddedProjectAndClearsTheSearch() {
        var launcher = makeLauncher([app, site])
        _ = press(.character("x"), on: &launcher)
        launcher.update(items: [LauncherItem(project: app), LauncherItem(project: site, score: 5)])
        launcher.open(site)
        #expect(launcher.query.isEmpty)
        #expect(launcher.screen == .project(site))
        #expect(launcher.selectedProject == site)
    }

    @Test func offersClaudeCodeFirst() {
        #expect(ProjectAction.allCases.first == .claude)
    }
}

@Suite struct HoldTriggerTests {
    let option = HoldKey.rightOption.keyCode
    let command: UInt16 = 54

    /// Presses the right Option key alone and returns the press.
    func pressOption(_ trigger: inout HoldTrigger) throws -> Int {
        let press = trigger.modifierChanged(keyCode: option, isDown: true, othersDown: false)
        return try #require(press)
    }

    @Test func firesWhenTheKeyIsHeldAlone() throws {
        var trigger = HoldTrigger()
        let press = try pressOption(&trigger)
        let first = trigger.holdElapsed(press)
        let second = trigger.holdElapsed(press)
        #expect(first)
        #expect(!second)
    }

    @Test func doesNotFireWhenReleasedEarly() throws {
        var trigger = HoldTrigger()
        let press = try pressOption(&trigger)
        _ = trigger.modifierChanged(keyCode: option, isDown: false, othersDown: false)
        let fired = trigger.holdElapsed(press)
        #expect(!fired)
    }

    @Test func doesNotFireWhenAnotherKeyIsPressed() throws {
        var trigger = HoldTrigger()
        let press = try pressOption(&trigger)
        trigger.keyPressed()
        let fired = trigger.holdElapsed(press)
        #expect(!fired)
    }

    @Test func doesNotFireWithAnotherModifier() throws {
        var trigger = HoldTrigger()
        let press = try pressOption(&trigger)
        _ = trigger.modifierChanged(keyCode: command, isDown: true, othersDown: true)
        let fired = trigger.holdElapsed(press)
        #expect(!fired)

        let pressWithCommand = trigger.modifierChanged(keyCode: option, isDown: true, othersDown: true)
        #expect(pressWithCommand == nil)
    }

    @Test func ignoresAnEarlierPress() throws {
        var trigger = HoldTrigger()
        let first = try pressOption(&trigger)
        _ = trigger.modifierChanged(keyCode: option, isDown: false, othersDown: false)
        let second = try pressOption(&trigger)
        let firstFired = trigger.holdElapsed(first)
        let secondFired = trigger.holdElapsed(second)
        #expect(!firstFired)
        #expect(secondFired)
    }
}
