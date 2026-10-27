import CoreGraphics
import Testing

@testable import PlaincontrolCore

@Suite struct WindowPlacementTests {
    // A laptop below two wide screens, side by side; the right one sits above the laptop.
    // Frames start at the top left of the laptop, which is the main screen.
    let laptop = WindowPlacement.Screen(visibleFrame: CGRect(x: 0, y: 40, width: 1600, height: 900), isBuiltIn: true)
    let left = WindowPlacement.Screen(
        visibleFrame: CGRect(x: -2800, y: -1410, width: 2560, height: 1410), isBuiltIn: false)
    let right = WindowPlacement.Screen(
        visibleFrame: CGRect(x: -240, y: -1410, width: 2560, height: 1410), isBuiltIn: false)
    let layout = WindowLayout(builtInColumns: 2, externalColumns: 3, gap: 10)

    var screens: [WindowPlacement.Screen] { [laptop, left, right] }

    /// Where a new window of `action` goes, with `windows` on screen.
    func frame(
        for action: ProjectAction, screens: [WindowPlacement.Screen], current: Int?, windows: [CGRect]
    ) -> CGRect? {
        placement(for: action, screens: screens, current: current, windows: windows)?.frame
    }

    func placement(
        for action: ProjectAction, screens: [WindowPlacement.Screen], current: Int?, windows: [CGRect]
    ) -> WindowPlacement.Placement? {
        WindowPlacement.placement(
            for: action, screens: screens, current: current, windows: windows.map(window), layout: layout)
    }

    func window(_ frame: CGRect) -> WindowPlacement.Window {
        WindowPlacement.Window(frame: frame, processIdentifier: 7)
    }

    func columns(_ screen: WindowPlacement.Screen) -> [CGRect] {
        WindowPlacement.columns(of: screen, layout: layout)
    }

    @Test func splitsAScreenIntoColumnsWithGaps() {
        #expect(
            columns(right) == [
                CGRect(x: -230, y: -1400, width: 840, height: 1390),
                CGRect(x: 620, y: -1400, width: 840, height: 1390),
                CGRect(x: 1470, y: -1400, width: 840, height: 1390),
            ])
        #expect(columns(laptop).map(\.width) == [785, 785])
    }

    @Test func fillsTheScreenInFrontFromTheMiddleThenFromLeftToRight() {
        var windows: [CGRect] = []
        for expected in [1, 0, 2] {
            let placed = frame(for: .claude, screens: screens, current: 2, windows: windows)
            #expect(placed == columns(right)[expected])
            windows.append(columns(right)[expected])
        }
    }

    @Test func fillsAScreenToTheLeftFromRightToLeft() {
        var windows = columns(right)
        for expected in [2, 1, 0] {
            let placed = frame(for: .claude, screens: screens, current: 2, windows: windows)
            #expect(placed == columns(left)[expected])
            windows.append(columns(left)[expected])
        }
    }

    @Test func fillsAScreenToTheRightFromLeftToRight() {
        let far = WindowPlacement.Screen(
            visibleFrame: CGRect(x: 2320, y: -1410, width: 2560, height: 1410), isBuiltIn: false)
        #expect(WindowPlacement.preference(on: far, columns: 3, viewer: 800) == [0, 1, 2])
        #expect(WindowPlacement.preference(on: left, columns: 3, viewer: 800) == [2, 1, 0])
        #expect(WindowPlacement.preference(on: right, columns: 3, viewer: 800) == [1, 0, 2])
        #expect(WindowPlacement.preference(on: right, columns: 4, viewer: 800) == [2, 0, 1, 3])
    }

    @Test func fillsTheBuiltInScreenFromLeftToRight() {
        let windows = columns(right) + columns(left)
        #expect(frame(for: .claude, screens: screens, current: 2, windows: windows) == columns(laptop)[0])
        let next = frame(for: .claude, screens: screens, current: 2, windows: windows + [columns(laptop)[0]])
        #expect(next == columns(laptop)[1])
    }

    @Test func startsOnTheBuiltInScreenWhenTheUserWorksThere() {
        let placed = frame(for: .claude, screens: screens, current: 0, windows: [])
        #expect(placed == columns(laptop)[0])
    }

    @Test func goesInTheFirstColumnOfTheBuiltInScreenWhenAllAreTaken() {
        let windows = columns(right) + columns(left) + columns(laptop)
        let placed = frame(for: .claude, screens: screens, current: 2, windows: windows)
        #expect(placed == columns(laptop)[0])
    }

    @Test func triesTheNearestExternalScreenFirst() {
        let far = WindowPlacement.Screen(
            visibleFrame: CGRect(x: -5360, y: -1410, width: 2560, height: 1410), isBuiltIn: false)
        let order = WindowPlacement.order([laptop, far, left, right], current: 3)
        #expect(order == [right, left, far, laptop])
    }

    @Test func countsAColumnAsTakenFromAQuarterCovered() {
        let column = columns(right)[1]
        let small = CGRect(x: column.minX, y: column.minY, width: column.width / 5, height: column.height)
        let placed = frame(for: .claude, screens: screens, current: 2, windows: [small])
        #expect(placed == column)
        let wide = CGRect(x: column.minX, y: column.minY, width: column.width / 3, height: column.height)
        #expect(
            frame(for: .claude, screens: screens, current: 2, windows: [wide])
                == columns(right)[0])
    }

    @Test func countsOneWindowOverSeveralColumnsForEach() {
        let full = right.visibleFrame
        let placed = frame(for: .claude, screens: screens, current: 2, windows: [full])
        #expect(placed == columns(left)[2])
    }

    @Test func givesTheEditorTheMiddleAndTheColumnBesideItNearestTheUser() {
        let placed = frame(for: .editor, screens: screens, current: 2, windows: [])
        #expect(placed == columns(right)[0].union(columns(right)[1]))
        let onTheLeft = frame(for: .editor, screens: screens, current: 1, windows: [])
        #expect(onTheLeft == columns(left)[1].union(columns(left)[2]))
    }

    @Test func givesTheEditorTheNextTwoFreeColumnsSideBySide() {
        let placed = frame(for: .editor, screens: screens, current: 2, windows: [columns(right)[0]])
        #expect(placed == columns(right)[1].union(columns(right)[2]))
    }

    @Test func slidesAWindowFromTheMiddleToItsNextChoiceToMakeRoomForTheEditor() {
        let middle = columns(right)[1]
        let result = placement(for: .editor, screens: screens, current: 2, windows: [middle, columns(left)[1]])
        #expect(result?.frame == columns(right)[1].union(columns(right)[2]))
        #expect(result?.moves == [WindowPlacement.Move(window: window(middle), frame: columns(right)[0])])
    }

    @Test func slidesWindowsTowardsTheUserOnAScreenToTheLeft() {
        let middle = columns(left)[1]
        let result = placement(for: .editor, screens: screens, current: 1, windows: [middle, columns(right)[1]])
        #expect(result?.frame == columns(left)[0].union(columns(left)[1]))
        #expect(result?.moves == [WindowPlacement.Move(window: window(middle), frame: columns(left)[2])])
    }

    @Test func usesFreeColumnsElsewhereBeforeMovingWindows() {
        let result = placement(for: .editor, screens: screens, current: 2, windows: [columns(right)[1]])
        #expect(result == WindowPlacement.Placement(frame: columns(left)[1].union(columns(left)[2])))
    }

    @Test func makesRoomOnAnExternalScreenBeforeUsingTheBuiltInOne() {
        let windows = [columns(right)[1], columns(left)[0], columns(left)[2]]
        let result = placement(for: .editor, screens: screens, current: 2, windows: windows)
        #expect(result?.frame == columns(right)[1].union(columns(right)[2]))
        #expect(result?.moves.map(\.frame) == [columns(right)[0]])
    }

    @Test func movesAStackOfWindowsInAColumnTogether() {
        let middle = columns(right)[1]
        let nudged = middle.offsetBy(dx: 2, dy: 0).insetBy(dx: 0, dy: 4)
        let result = placement(for: .editor, screens: screens, current: 2, windows: [middle, nudged, columns(left)[1]])
        #expect(result?.moves.map(\.window) == [window(middle), window(nudged)])
        #expect(result?.moves.map(\.frame) == [columns(right)[0], columns(right)[0]])
    }

    @Test func leavesWindowsOutsideTheColumnsWhereTheyAre() {
        // Each covers the middle column of its screen, and a little of one beside it.
        let loose = [
            CGRect(x: 400, y: -1200, width: 900, height: 800), CGRect(x: -2000, y: -1200, width: 900, height: 800),
        ]
        let result = placement(for: .editor, screens: screens, current: 2, windows: loose)
        #expect(result == WindowPlacement.Placement(frame: columns(laptop)[0].union(columns(laptop)[1])))
    }

    @Test func givesTheEditorTheWholeBuiltInScreen() {
        let placed = frame(for: .editor, screens: screens, current: 0, windows: [])
        #expect(placed == CGRect(x: 10, y: 50, width: 1580, height: 880))
    }

    @Test func givesOtherActionsOneColumn() {
        for action in [ProjectAction.claude, .terminal, .finder, .claudeDesktop] {
            let placed = frame(for: action, screens: screens, current: 2, windows: [])
            #expect(placed == columns(right)[1])
        }
    }

    @Test func managesWithoutABuiltInScreen() {
        let windows = columns(right) + columns(left)
        let placed = frame(for: .claude, screens: [left, right], current: 1, windows: windows)
        #expect(placed == columns(right)[0])
    }
}
