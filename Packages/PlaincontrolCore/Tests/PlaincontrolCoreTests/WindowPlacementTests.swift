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

    @Test func takesTheFirstFreeColumnOfTheCurrentScreen() {
        let windows = [columns(right)[0], columns(right)[2]]
        let frame = WindowPlacement.frame(for: .claude, screens: screens, current: 2, windows: windows, layout: layout)
        #expect(frame == columns(right)[1])
    }

    @Test func movesOnToAnotherExternalScreenBeforeTheBuiltInOne() {
        let frame = WindowPlacement.frame(
            for: .claude, screens: screens, current: 2, windows: columns(right), layout: layout)
        #expect(frame == columns(left)[0])
    }

    @Test func triesTheBuiltInScreenAfterTheExternalOnes() {
        let windows = columns(right) + columns(left)
        let frame = WindowPlacement.frame(for: .claude, screens: screens, current: 2, windows: windows, layout: layout)
        #expect(frame == columns(laptop)[0])
    }

    @Test func startsOnTheBuiltInScreenWhenTheUserWorksThere() {
        let frame = WindowPlacement.frame(for: .claude, screens: screens, current: 0, windows: [], layout: layout)
        #expect(frame == columns(laptop)[0])
    }

    @Test func goesInTheFirstColumnOfTheBuiltInScreenWhenAllAreTaken() {
        let windows = columns(right) + columns(left) + columns(laptop)
        let frame = WindowPlacement.frame(for: .claude, screens: screens, current: 2, windows: windows, layout: layout)
        #expect(frame == columns(laptop)[0])
    }

    @Test func triesTheNearestExternalScreenFirst() {
        let far = WindowPlacement.Screen(
            visibleFrame: CGRect(x: -5360, y: -1410, width: 2560, height: 1410), isBuiltIn: false)
        let order = WindowPlacement.order([laptop, far, left, right], current: 3)
        #expect(order == [right, left, far, laptop])
    }

    @Test func countsAColumnAsTakenFromAQuarterCovered() {
        let column = columns(right)[0]
        let small = CGRect(x: column.minX, y: column.minY, width: column.width / 5, height: column.height)
        let frame = WindowPlacement.frame(for: .claude, screens: screens, current: 2, windows: [small], layout: layout)
        #expect(frame == column)
        let wide = CGRect(x: column.minX, y: column.minY, width: column.width / 3, height: column.height)
        #expect(
            WindowPlacement.frame(for: .claude, screens: screens, current: 2, windows: [wide], layout: layout)
                == columns(right)[1])
    }

    @Test func countsOneWindowOverSeveralColumnsForEach() {
        let full = right.visibleFrame
        let frame = WindowPlacement.frame(for: .claude, screens: screens, current: 2, windows: [full], layout: layout)
        #expect(frame == columns(left)[0])
    }

    @Test func givesTheEditorTwoColumnsOfAnExternalScreen() {
        let frame = WindowPlacement.frame(for: .editor, screens: screens, current: 2, windows: [], layout: layout)
        #expect(frame == columns(right)[0].union(columns(right)[1]))
    }

    @Test func givesTheEditorTheNextTwoFreeColumnsSideBySide() {
        let frame = WindowPlacement.frame(
            for: .editor, screens: screens, current: 2, windows: [columns(right)[0]], layout: layout)
        #expect(frame == columns(right)[1].union(columns(right)[2]))
        let split = [columns(right)[1], columns(left)[1]]
        let elsewhere = WindowPlacement.frame(
            for: .editor, screens: screens, current: 2, windows: split, layout: layout)
        #expect(elsewhere == columns(laptop)[0].union(columns(laptop)[1]))
    }

    @Test func givesTheEditorTheWholeBuiltInScreen() {
        let frame = WindowPlacement.frame(for: .editor, screens: screens, current: 0, windows: [], layout: layout)
        #expect(frame == CGRect(x: 10, y: 50, width: 1580, height: 880))
    }

    @Test func givesOtherActionsOneColumn() {
        for action in [ProjectAction.claude, .terminal, .finder] {
            let frame = WindowPlacement.frame(for: action, screens: screens, current: 2, windows: [], layout: layout)
            #expect(frame == columns(right)[0])
        }
    }

    @Test func managesWithoutABuiltInScreen() {
        let windows = columns(right) + columns(left)
        let frame = WindowPlacement.frame(
            for: .claude, screens: [left, right], current: 1, windows: windows, layout: layout)
        #expect(frame == columns(right)[0])
    }
}
