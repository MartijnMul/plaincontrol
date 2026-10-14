import Foundation

/// Finds a folder from the keyboard, one level at a time, to add it as a project.
///
/// It shows the folders inside the current one. Typing filters them, Up and Down select, and
/// Return, Right or `/` goes into the selected folder, as in a file browser; Left (or Backspace
/// without a filter) goes up a level. Escape clears the filter, and without one gives up.
///
/// Adding is a separate row above the folders, for the folder the user is in, so it takes a
/// deliberate step: the row is selected only when there are no folders to go into. A home
/// folder and the folders above it cannot be added.
///
/// It does not read the disk itself: every key press takes `list`, which returns the names of
/// the folders inside a folder, so the caller decides what counts and tests can make it up.
public struct PathFinder: Sendable, Equatable {
    public enum Row: Sendable, Equatable {
        /// Add the current folder.
        case add
        /// A folder inside the current one, by name.
        case subfolder(String)
    }

    public enum Outcome: Sendable, Equatable {
        case stay
        case cancel
        /// Add the folder at this path.
        case add(String)
    }

    /// The folder being looked into, as an absolute path.
    public private(set) var folder: String
    public private(set) var filter = ""
    /// The selected row of ``rows``.
    public private(set) var selection = 0
    /// The names of the folders inside ``folder``.
    public private(set) var subfolders: [String]
    /// The user's home folder, which cannot be added, nor anything above it.
    public let home: String

    public init(folder: String, home: String, list: (String) -> [String]) {
        self.home = (home as NSString).standardizingPath
        self.folder = (folder as NSString).standardizingPath
        subfolders = list(self.folder)
        selectFirstFolder()
    }

    /// Whether the current folder may be added: anything below the home folder.
    public var canAdd: Bool {
        folder.hasPrefix(home == "/" ? "/" : home + "/") && folder != home
    }

    /// The add row, when allowed and no filter is typed, then the folders inside the current
    /// one, those whose name starts with the filter first.
    public var rows: [Row] {
        guard !filter.isEmpty else { return (canAdd ? [.add] : []) + subfolders.map(Row.subfolder) }
        let filter = filter.lowercased()
        let matches = subfolders.filter { $0.lowercased().contains(filter) }
        let starting = matches.filter { $0.lowercased().hasPrefix(filter) }
        return (starting + matches.filter { !$0.lowercased().hasPrefix(filter) }).map(Row.subfolder)
    }

    public var selectedRow: Row? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    public mutating func press(_ key: Launcher.Key, list: (String) -> [String]) -> Outcome {
        switch key {
        case .up:
            selection = max(selection - 1, 0)
        case .down:
            selection = min(selection + 1, max(rows.count - 1, 0))
        case .enter, .right, .character("/"):
            switch selectedRow {
            case .subfolder(let name): open((folder as NSString).appendingPathComponent(name), list: list)
            case .add: if key == .enter { return .add(folder) }
            case nil: break
            }
        case .left:
            goUp(list: list)
        case .backspace:
            if filter.isEmpty { goUp(list: list) } else { setFilter(String(filter.dropLast())) }
        case .escape:
            if filter.isEmpty { return .cancel }
            setFilter("")
            selectFirstFolder()
        case .character(let character):
            if character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol
                || character == " "
            {
                setFilter(filter + String(character))
            }
        }
        return .stay
    }

    private mutating func open(_ path: String, list: (String) -> [String]) {
        folder = path
        subfolders = list(path)
        filter = ""
        selectFirstFolder()
    }

    /// Selects the first folder inside, or the add row when there is none.
    private mutating func selectFirstFolder() {
        selection = rows.firstIndex { $0 != .add } ?? 0
    }

    /// Goes to the folder above, with the folder it came from selected.
    private mutating func goUp(list: (String) -> [String]) {
        guard folder != "/" else { return }
        let from = (folder as NSString).lastPathComponent
        open((folder as NSString).deletingLastPathComponent, list: list)
        selection = rows.firstIndex(of: .subfolder(from)) ?? selection
    }

    private mutating func setFilter(_ filter: String) {
        self.filter = filter
        selection = 0
    }
}
