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
            case .claude, .terminal, .finder, .devServer: 1
            }
        return min(max(span, 1), max(columns, 1))
    }
}

/// Where a new window goes.
///
/// It takes free columns, as many as it spans side by side: on the screen with the pointer
/// first, then on the other external screens, nearest first, then on the built-in screen. A
/// column is free while other windows cover less than a quarter of it. Each screen fills from
/// the columns nearest the user, who is taken to sit in front of the built-in screen, or of
/// the main one without it: a screen in front fills from its middle, then from left to right;
/// a screen to the left fills from right to left, and one to the right from left to right.
///
/// When a screen has enough free columns but not side by side, the windows that fill columns
/// there slide over to make room, keeping their order, as few of them as possible; they keep
/// the user's preferred columns, and the new window takes the rest. That is tried on the
/// external screens before the built-in one gets the window. When no columns can
/// be had, the window goes in the best columns of the built-in screen, in front of what is
/// there.
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
        let viewer = (screens.first(where: \.isBuiltIn) ?? screens.first)?.visibleFrame.midX ?? 0
        // The current screen and the external ones come before a built-in screen the user is
        // not working on, also when making room means moving windows.
        let preferred = ordered.enumerated().filter { $0.offset == 0 || !$0.element.isBuiltIn }.map(\.element)
        let others = ordered.enumerated().filter { $0.offset != 0 && $0.element.isBuiltIn }.map(\.element)
        for screens in [preferred, others] {
            for screen in screens {
                if let frame = freeColumns(on: screen, for: action, windows: windows, layout: layout, viewer: viewer) {
                    return Placement(frame: frame)
                }
            }
            for screen in screens {
                if let placement = makeRoom(on: screen, for: action, windows: windows, layout: layout, viewer: viewer) {
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
        guard let run = runs(of: span, on: fallback, columns: columns.count, viewer: viewer).first else { return nil }
        return Placement(frame: union(columns[run]))
    }

    /// The best free columns side by side on `screen` for a window of `action`.
    private static func freeColumns(
        on screen: Screen, for action: ProjectAction, windows: [Window], layout: WindowLayout, viewer: Double
    ) -> CGRect? {
        let columns = columns(of: screen, layout: layout)
        let span = layout.span(of: action, on: screen)
        let frames = windows.map(\.frame)
        let free = runs(of: span, on: screen, columns: columns.count, viewer: viewer).first { run in
            columns[run].allSatisfy { isFree($0, windows: frames) }
        }
        return free.map { union(columns[$0]) }
    }

    /// How much the user prefers each column of `screen`, 0 for the first choice, given the
    /// user's place `viewer` along the screens.
    static func preference(on screen: Screen, columns count: Int, viewer: Double) -> [Int] {
        let order: [Int]
        if screen.visibleFrame.maxX <= viewer {
            order = Array((0..<count).reversed())
        } else if screen.visibleFrame.minX >= viewer {
            order = Array(0..<count)
        } else {
            // In front: from the middle out, the left one first of two as near.
            let middle = Double(count - 1) / 2
            order = (0..<count).sorted { a, b in
                let da = abs(Double(a) - middle)
                let db = abs(Double(b) - middle)
                return da == db ? a < b : da < db
            }
        }
        var preference = Array(repeating: 0, count: count)
        for (rank, column) in order.enumerated() { preference[column] = rank }
        return preference
    }

    /// Every run of `span` columns side by side on `screen`, the user's first choice first: the
    /// one with the most preferred column, then the next, and so on.
    static func runs(of span: Int, on screen: Screen, columns count: Int, viewer: Double) -> [Range<Int>] {
        guard span >= 1, count >= span else { return [] }
        let preference = preference(on: screen, columns: count, viewer: viewer)
        return (0...(count - span)).map { $0..<$0 + span }.sorted { a, b in
            score(a, preference).lexicographicallyPrecedes(score(b, preference))
        }
    }

    private static func score(_ run: Range<Int>, _ preference: [Int]) -> [Int] {
        run.map { preference[$0] }.sorted()
    }

    /// Room for a window of `action` on `screen`, made by sliding the windows that fill
    /// columns there, keeping their order. The arrangement that moves the fewest windows wins,
    /// then the one that keeps the user's preferred columns for the windows that were there.
    private static func makeRoom(
        on screen: Screen, for action: ProjectAction, windows: [Window], layout: WindowLayout, viewer: Double
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

        let preference = preference(on: screen, columns: columns.count, viewer: viewer)
        let runs = runs(of: span, on: screen, columns: columns.count, viewer: viewer)
        var best: (rank: [Int], run: Range<Int>, starts: [Int])?
        for starts in arrangements(of: tiles.map(\.width), in: columns.count, avoiding: Set(blocked)) {
            var taken = Set(blocked)
            for (tile, start) in zip(tiles, starts) { taken.formUnion(start..<start + tile.width) }
            guard let run = runs.first(where: { $0.allSatisfy { !taken.contains($0) } }) else { continue }
            let moved = zip(tiles, starts).filter { $0.start != $1 }.reduce(0) { $0 + $1.0.windows.count }
            let kept = zip(tiles, starts).flatMap { tile, start in
                Array(repeating: start..<start + tile.width, count: tile.windows.count).flatMap { $0 }
            }
            let rank = [moved] + kept.map { preference[$0] }.sorted() + score(run, preference)
            if best.map({ rank.lexicographicallyPrecedes($0.rank) }) ?? true {
                best = (rank, run, starts)
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
