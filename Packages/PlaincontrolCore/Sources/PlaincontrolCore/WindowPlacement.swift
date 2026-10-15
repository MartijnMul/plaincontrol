import CoreGraphics
import Foundation

/// How the launcher arranges the windows it opens: every screen split into columns of equal
/// width, with a gap around and between them, as a window manager such as Rectangle does. A
/// window takes one column, except the editor's, which takes several side by side.
public struct WindowLayout: Sendable, Equatable {
    /// The number of columns on the built-in screen.
    public var builtInColumns: Int
    /// The number of columns on every other screen.
    public var externalColumns: Int
    /// The space around and between the columns, in points.
    public var gap: Double
    /// How many columns the editor takes on the built-in screen.
    public var editorBuiltInColumns: Int
    /// How many columns the editor takes on every other screen.
    public var editorExternalColumns: Int

    public init(
        builtInColumns: Int = 2, externalColumns: Int = 3, gap: Double = 10, editorBuiltInColumns: Int = 2,
        editorExternalColumns: Int = 2
    ) {
        self.builtInColumns = builtInColumns
        self.externalColumns = externalColumns
        self.gap = gap
        self.editorBuiltInColumns = editorBuiltInColumns
        self.editorExternalColumns = editorExternalColumns
    }

    /// How many columns a window of `action` takes on `screen`, at most all of them.
    func span(of action: ProjectAction, on screen: WindowPlacement.Screen) -> Int {
        let columns = screen.isBuiltIn ? builtInColumns : externalColumns
        let span =
            switch action {
            case .editor: screen.isBuiltIn ? editorBuiltInColumns : editorExternalColumns
            case .claude, .terminal, .finder: 1
            }
        return min(max(span, 1), max(columns, 1))
    }
}

/// Where a new window goes.
///
/// It takes the first free columns, from left to right, as many as it spans side by side: on
/// the screen with the pointer first, then on the other external screens, nearest first, then
/// on the built-in screen. When none are free, it goes in the first columns of the built-in
/// screen, in front of what is there. A column is free while other windows cover less than a
/// quarter of it.
///
/// Frames are in global screen coordinates with the origin at the top left of the main screen
/// and y growing downwards, as window lists and AppleScript give them.
public enum WindowPlacement {
    public struct Screen: Sendable, Equatable {
        /// The part of the screen windows may use, without the menu bar and the Dock.
        public var visibleFrame: CGRect
        public var isBuiltIn: Bool

        public init(visibleFrame: CGRect, isBuiltIn: Bool) {
            self.visibleFrame = visibleFrame
            self.isBuiltIn = isBuiltIn
        }
    }

    /// How much of a column other windows may cover before it counts as taken.
    static let takenShare = 0.25

    /// The frame for a new window of `action`.
    ///
    /// - Parameters:
    ///   - current: The index in `screens` of the screen the user works on, if known.
    ///   - windows: The frames of the windows on the screens now.
    public static func frame(
        for action: ProjectAction, screens: [Screen], current: Int?, windows: [CGRect], layout: WindowLayout
    ) -> CGRect? {
        for screen in order(screens, current: current) {
            let columns = columns(of: screen, layout: layout)
            let span = layout.span(of: action, on: screen)
            guard columns.count >= span else { continue }
            for first in 0...(columns.count - span) {
                let run = columns[first..<first + span]
                if run.allSatisfy({ isFree($0, windows: windows) }) { return run.reduce(run[first]) { $0.union($1) } }
            }
        }
        let fallback =
            screens.first(where: \.isBuiltIn) ?? current.flatMap { screens.indices.contains($0) ? screens[$0] : nil }
            ?? screens.first
        guard let fallback else { return nil }
        let columns = columns(of: fallback, layout: layout)
        let span = layout.span(of: action, on: fallback)
        guard columns.count >= span else { return nil }
        return columns[0..<span].reduce(columns[0]) { $0.union($1) }
    }

    /// The columns of `screen`, from left to right, rounded to whole points.
    static func columns(of screen: Screen, layout: WindowLayout) -> [CGRect] {
        let count = max(screen.isBuiltIn ? layout.builtInColumns : layout.externalColumns, 1)
        let area = screen.visibleFrame
        let gap = layout.gap
        let width = ((area.width - gap * Double(count + 1)) / Double(count)).rounded(.down)
        let height = (area.height - gap * 2).rounded(.down)
        guard width > 0, height > 0 else { return [] }
        return (0..<count).map { index in
            CGRect(
                x: (area.minX + gap + Double(index) * (width + gap)).rounded(), y: (area.minY + gap).rounded(),
                width: width, height: height)
        }
    }

    /// The screens to try, in order: the current one, the other external ones by distance to
    /// it, then the built-in ones.
    static func order(_ screens: [Screen], current: Int?) -> [Screen] {
        let first = current.flatMap { screens.indices.contains($0) ? screens[$0] : nil }
        let rest = screens.indices.filter { $0 != current }.map { screens[$0] }
        let center = first.map { CGPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) }
        let external = rest.filter { !$0.isBuiltIn }.enumerated().sorted { a, b in
            guard let center else { return a.offset < b.offset }
            let da = distance(center, a.element.visibleFrame)
            let db = distance(center, b.element.visibleFrame)
            return da == db ? a.offset < b.offset : da < db
        }.map(\.element)
        return (first.map { [$0] } ?? []) + external + rest.filter(\.isBuiltIn)
    }

    private static func distance(_ point: CGPoint, _ frame: CGRect) -> Double {
        hypot(frame.midX - point.x, frame.midY - point.y)
    }

    private static func isFree(_ column: CGRect, windows: [CGRect]) -> Bool {
        let covered = windows.reduce(0.0) { total, window in
            let overlap = column.intersection(window)
            return overlap.isNull ? total : total + overlap.width * overlap.height
        }
        return covered < column.width * column.height * takenShare
    }

    /// The frames of the ordinary windows on screen now, on the current Space of each screen,
    /// leaving out those of the process `excluded` and small ones such as palettes. Needs no
    /// permission: window titles are not read.
    public static func windowsOnScreen(excluding excluded: pid_t) -> [CGRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { window in
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                (window[kCGWindowOwnerPID as String] as? pid_t) != excluded,
                (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds),
                frame.width >= 100, frame.height >= 100
            else { return nil }
            return frame
        }
    }
}
