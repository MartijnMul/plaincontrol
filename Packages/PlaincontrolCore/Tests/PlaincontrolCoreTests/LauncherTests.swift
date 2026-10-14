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

    @Test func opensTheSelectedProjectAndRunsAnActionByItsKey() {
        var launcher = makeLauncher([app, site])
        _ = press(.down, .enter, on: &launcher)
        #expect(launcher.screen == .project(site))
        let outcomes = press(.character("x"), .character("c"), .character("F"), on: &launcher)
        #expect(outcomes == [.stay, .run(.claude, site), .run(.finder, site)])
    }

    @Test func searchesInsteadOfRunningAnActionFromTheList() {
        var launcher = makeLauncher([app])
        #expect(press(.character("c"), on: &launcher) == [.stay])
        #expect(launcher.query == "c")
        #expect(launcher.screen == .projects)
    }

    @Test func offersOnlyTheGivenActions() {
        var launcher = makeLauncher([app], actions: [.claude, .finder])
        #expect(press(.enter, .character("v"), on: &launcher) == [.stay, .stay])
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
        #expect(press(.down, .enter, on: &launcher) == [.stay, .stay])
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

    @Test func runsTheSelectedActionWithReturnOrRight() {
        var launcher = makeLauncher([app], actions: [.claude, .finder, .vsCode])
        _ = press(.enter, on: &launcher)
        #expect(launcher.selectedAction == .claude)
        #expect(press(.down, .down, .down, .enter, on: &launcher) == [.stay, .stay, .stay, .run(.vsCode, app)])
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

    @Test func actionKeysAreDistinct() {
        #expect(Set(ProjectAction.allCases.map(\.key)).count == ProjectAction.allCases.count)
    }
}

@Suite struct HoldTriggerTests {
    let option = HoldTrigger.rightOption
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
