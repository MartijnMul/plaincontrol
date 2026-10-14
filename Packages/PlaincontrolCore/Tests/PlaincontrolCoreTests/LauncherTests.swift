import Testing

@testable import PlaincontrolCore

@Suite struct LauncherTests {
    let app = Project(path: "/work/app")
    let site = Project(path: "/work/site")

    /// Presses each key in turn and returns the outcome of each.
    func press(_ keys: Launcher.Key..., on launcher: inout Launcher) -> [Launcher.Outcome] {
        keys.map { launcher.press($0) }
    }

    @Test func movesTheSelectionWithinTheList() {
        var launcher = Launcher(projects: [app, site])
        #expect(launcher.selectedProject == app)
        #expect(press(.down, on: &launcher) == [.stay])
        #expect(launcher.selectedProject == site)
        _ = press(.down, on: &launcher)
        #expect(launcher.selectedProject == site)
        _ = press(.up, .up, on: &launcher)
        #expect(launcher.selectedProject == app)
    }

    @Test func opensTheSelectedProjectAndRunsAnActionByItsKey() {
        var launcher = Launcher(projects: [app, site])
        _ = press(.down, .enter, on: &launcher)
        #expect(launcher.screen == .project(site))
        let outcomes = press(.character("x"), .character("c"), .character("F"), on: &launcher)
        #expect(outcomes == [.stay, .run(.claude, site), .run(.finder, site)])
    }

    @Test func runsNoActionFromTheList() {
        var launcher = Launcher(projects: [app])
        #expect(press(.character("c"), on: &launcher) == [.stay])
    }

    @Test func offersOnlyTheGivenActions() {
        var launcher = Launcher(projects: [app], actions: [.claude, .finder])
        #expect(press(.enter, .character("v"), on: &launcher) == [.stay, .stay])
    }

    @Test func escapeGoesBackThenCloses() {
        var launcher = Launcher(projects: [app, site])
        _ = press(.down, .enter, on: &launcher)
        #expect(press(.escape, on: &launcher) == [.stay])
        #expect(launcher.screen == .projects)
        #expect(launcher.selectedProject == site)
        #expect(press(.escape, on: &launcher) == [.close])
    }

    @Test func handlesAnEmptyList() {
        var launcher = Launcher(projects: [])
        #expect(press(.down, .enter, on: &launcher) == [.stay, .stay])
        #expect(launcher.screen == .projects)
        #expect(launcher.selectedProject == nil)
    }

    @Test func rightOpensAndLeftGoesBack() {
        var launcher = Launcher(projects: [app, site])
        _ = press(.down, .right, on: &launcher)
        #expect(launcher.screen == .project(site))
        #expect(press(.left, on: &launcher) == [.stay])
        #expect(launcher.screen == .projects)
        #expect(launcher.selectedProject == site)
        #expect(press(.left, on: &launcher) == [.stay])
        #expect(launcher.screen == .projects)
    }

    @Test func runsTheSelectedActionWithReturnOrRight() {
        var launcher = Launcher(projects: [app], actions: [.claude, .finder, .vsCode])
        _ = press(.enter, on: &launcher)
        #expect(launcher.selectedAction == .claude)
        #expect(press(.down, .down, .down, .enter, on: &launcher) == [.stay, .stay, .stay, .run(.vsCode, app)])
        #expect(press(.up, .right, on: &launcher) == [.stay, .run(.finder, app)])
    }

    @Test func opensAProjectWithTheFirstActionSelected() {
        var launcher = Launcher(projects: [app, site])
        _ = press(.right, .down, .left, .down, .right, on: &launcher)
        #expect(launcher.screen == .project(site))
        #expect(launcher.selectedAction == .claude)
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
