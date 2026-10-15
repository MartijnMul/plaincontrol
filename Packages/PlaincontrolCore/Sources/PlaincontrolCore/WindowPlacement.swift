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
/// on the built-in screen. A column is free while other windows cover less than a quarter of
/// it. When a screen has enough free columns but not side by side, the windows that fill
/// columns there slide over to make room, keeping their order, as few of them as possible;
/// that is tried on the external screens before the built-in one gets the window. When no
/// columns can be had, the window goes in the first columns of the built-in screen, in front
/// of what is there.
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

    /// A window on screen, as the window list gives it.
    public struct Window: Sendable, Equatable {
        public var frame: CGRect
        /// The process the window belongs to.
        public var processIdentifier: pid_t

        public init(frame: CGRect, processIdentifier: pid_t) {
            self.frame = frame
            self.processIdentifier = processIdentifier
        }
    }

    /// Where a new window goes, and which windows move first to make room for it.
    public struct Placement: Sendable, Equatable {
        public var frame: CGRect
        public var moves: [Move]

        public init(frame: CGRect, moves: [Move] = []) {
            self.frame = frame
            self.moves = moves
        }
    }

    public struct Move: Sendable, Equatable {
        public var window: Window
        public var frame: CGRect

        public init(window: Window, frame: CGRect) {
            self.window = window
            self.frame = frame
        }
    }

    /// How much of a column other windows may cover before it counts as taken.
    static let takenShare = 0.25
    /// How far, in points, a window's edges may be off a column's for the window to fill it.
    /// Terminals round their size to whole characters.
    static let fitTolerance = 16.0

    /// Where a new window of `action` goes.
    ///
    /// - Parameters:
    ///   - current: The index in `screens` of the screen the user works on, if known.
    ///   - windows: The windows on the screens now.
    public static func placement(
        for action: ProjectAction, screens: [Screen], current: Int?, windows: [Window], layout: WindowLayout
    ) -> Placement? {
        let ordered = order(screens, current: current)
        // The current screen and the external ones come before a built-in screen the user is
        // not working on, also when making room means moving windows.
        let preferred = ordered.enumerated().filter { $0.offset == 0 || !$0.element.isBuiltIn }.map(\.element)
        let others = ordered.enumerated().filter { $0.offset != 0 && $0.element.isBuiltIn }.map(\.element)
        for screens in [preferred, others] {
            for screen in screens {
                if let frame = freeColumns(on: screen, for: action, windows: windows, layout: layout) {
                    return Placement(frame: frame)
                }
            }
            for screen in screens {
                if let placement = makeRoom(on: screen, for: action, windows: windows, layout: layout) {
                    return placement
                }
            }
        }
        let fallback =
            screens.first(where: \.isBuiltIn) ?? current.flatMap { screens.indices.contains($0) ? screens[$0] : nil }
            ?? screens.first
        guard let fallback else { return nil }
        let columns = columns(of: fallback, layout: layout)
        let span = layout.span(of: action, on: fallback)
        guard columns.count >= span else { return nil }
        return Placement(frame: union(columns[0..<span]))
    }

    /// The first free columns side by side on `screen` for a window of `action`.
    private static func freeColumns(
        on screen: Screen, for action: ProjectAction, windows: [Window], layout: WindowLayout
    ) -> CGRect? {
        let columns = columns(of: screen, layout: layout)
        let span = layout.span(of: action, on: screen)
        let frames = windows.map(\.frame)
        guard columns.count >= span else { return nil }
        for first in 0...(columns.count - span) {
            let run = columns[first..<first + span]
            if run.allSatisfy({ isFree($0, windows: frames) }) { return union(run) }
        }
        return nil
    }

    /// Room for a window of `action` on `screen`, made by sliding the windows that fill
    /// columns there, keeping their order. The arrangement that moves the fewest windows wins,
    /// then the one that slides them furthest to the left.
    private static func makeRoom(
        on screen: Screen, for action: ProjectAction, windows: [Window], layout: WindowLayout
    ) -> Placement? {
        let columns = columns(of: screen, layout: layout)
        let span = layout.span(of: action, on: screen)
        guard span > 1, columns.count >= span else { return nil }
        let onScreen = windows.filter { !$0.frame.intersection(screen.visibleFrame).isNull }

        // Windows that fill a run of columns move together with the others on the same run;
        // any other window blocks the columns it covers.
        var tiles: [Tile] = []
        var loose: [CGRect] = []
        for window in onScreen {
            guard let run = fittingRun(of: window.frame, in: columns) else {
                loose.append(window.frame)
                continue
            }
            if let index = tiles.firstIndex(where: { $0.start == run.lowerBound && $0.width == run.count }) {
                tiles[index].windows.append(window)
            } else {
                tiles.append(Tile(start: run.lowerBound, width: run.count, windows: [window]))
            }
        }
        tiles.sort { $0.start < $1.start }
        for (a, b) in zip(tiles, tiles.dropFirst()) where a.start + a.width > b.start { return nil }
        let blocked = columns.indices.filter { !isFree(columns[$0], windows: loose) }

        var best: (rank: [Int], run: Range<Int>, starts: [Int])?
        for starts in arrangements(of: tiles.map(\.width), in: columns.count, avoiding: Set(blocked)) {
            var taken = Set(blocked)
            for (tile, start) in zip(tiles, starts) { taken.formUnion(start..<start + tile.width) }
            guard
                let first = (0...(columns.count - span)).first(where: { first in
                    (first..<first + span).allSatisfy { !taken.contains($0) }
                })
            else { continue }
            let moved = zip(tiles, starts).filter { $0.start != $1 }.reduce(0) { $0 + $1.0.windows.count }
            let rank = [moved, starts.reduce(0, +), first]
            if best.map({ rank.lexicographicallyPrecedes($0.rank) }) ?? true {
                best = (rank, first..<first + span, starts)
            }
        }
        guard let best else { return nil }
        let moves = zip(tiles, best.starts).filter { $0.start != $1 }.flatMap { tile, start in
            tile.windows.map { Move(window: $0, frame: union(columns[start..<start + tile.width])) }
        }
        return Placement(frame: union(columns[best.run]), moves: moves)
    }

    /// Windows that fill the same run of columns.
    private struct Tile {
        var start: Int
        var width: Int
        var windows: [Window]
    }

    /// The run of columns `frame` fills, give or take ``fitTolerance``.
    private static func fittingRun(of frame: CGRect, in columns: [CGRect]) -> Range<Int>? {
        for start in columns.indices {
            for end in start..<columns.count {
                let run = union(columns[start...end])
                let edges = [
                    frame.minX - run.minX, frame.maxX - run.maxX, frame.minY - run.minY, frame.maxY - run.maxY,
                ]
                if edges.allSatisfy({ abs($0) <= fitTolerance }) { return start..<end + 1 }
            }
        }
        return nil
    }

    /// Every way to put runs of `widths` columns in `count` columns, in this order, without
    /// overlap or a blocked column: the first column of each.
    private static func arrangements(of widths: [Int], in count: Int, avoiding blocked: Set<Int>) -> [[Int]] {
        var result: [[Int]] = []
        func place(from first: Int, _ remaining: ArraySlice<Int>, _ starts: [Int]) {
            guard let width = remaining.first else {
                result.append(starts)
                return
            }
            guard first + width <= count else { return }
            for start in first...(count - width) where (start..<start + width).allSatisfy({ !blocked.contains($0) }) {
                place(from: start + width, remaining.dropFirst(), starts + [start])
            }
        }
        place(from: 0, widths[...], [])
        return result
    }

    private static func union(_ columns: some Collection<CGRect>) -> CGRect {
        columns.dropFirst().reduce(columns.first ?? .null) { $0.union($1) }
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

    /// The ordinary windows on screen now, on the current Space of each screen, leaving out
    /// those of the process `excluded` and small ones such as palettes. Needs no permission:
    /// window titles are not read.
    public static func windowsOnScreen(excluding excluded: pid_t) -> [Window] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { window in
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                let owner = window[kCGWindowOwnerPID as String] as? pid_t, owner != excluded,
                (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds),
                frame.width >= 100, frame.height >= 100
            else { return nil }
            return Window(frame: frame, processIdentifier: owner)
        }
    }
}
