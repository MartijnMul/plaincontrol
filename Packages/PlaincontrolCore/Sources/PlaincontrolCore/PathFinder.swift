import Foundation

/// Finds a folder from the keyboard, one level at a time, to add it as a project.
///
/// It shows the folders inside the current one, and above them the current folder itself; the
/// first folder inside is selected, so Return does not add a whole home folder by accident.
/// Typing filters them, Up and Down select, Right or `/` goes into the selected folder, and Left
/// (or Backspace without a filter) goes up a level. Return adds the selected folder. Escape
/// clears the filter, and without one gives up.
///
/// It does not read the disk itself: every key press takes `list`, which returns the names of
/// the folders inside a folder, so the caller decides what counts and tests can make it up.
public struct PathFinder: Sendable, Equatable {
    public enum Row: Sendable, Equatable {
        /// The current folder itself.
        case current
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

    public init(folder: String, list: (String) -> [String]) {
        self.folder = (folder as NSString).standardizingPath
        subfolders = list(self.folder)
        selection = subfolders.isEmpty ? 0 : 1
    }

    /// The current folder, unless a filter is typed, then the matching folders inside it:
    /// those whose name starts with the filter first.
    public var rows: [Row] {
        guard !filter.isEmpty else { return [.current] + subfolders.map(Row.subfolder) }
        let filter = filter.lowercased()
        let matches = subfolders.filter { $0.lowercased().contains(filter) }
        let starting = matches.filter { $0.lowercased().hasPrefix(filter) }
        return (starting + matches.filter { !$0.lowercased().hasPrefix(filter) }).map(Row.subfolder)
    }

    public var selectedRow: Row? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    /// The path of a row.
    public func path(of row: Row) -> String {
        switch row {
        case .current: folder
        case .subfolder(let name): (folder as NSString).appendingPathComponent(name)
        }
    }

    public mutating func press(_ key: Launcher.Key, list: (String) -> [String]) -> Outcome {
        switch key {
        case .up:
            selection = max(selection - 1, 0)
        case .down:
            selection = min(selection + 1, max(rows.count - 1, 0))
        case .right, .character("/"):
            if case .subfolder(let name) = selectedRow {
                open((folder as NSString).appendingPathComponent(name), list: list)
            }
        case .left:
            goUp(list: list)
        case .backspace:
            if filter.isEmpty { goUp(list: list) } else { setFilter(String(filter.dropLast())) }
        case .enter:
            if let selectedRow { return .add(path(of: selectedRow)) }
        case .escape:
            if filter.isEmpty { return .cancel }
            setFilter("")
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
        selection = subfolders.isEmpty ? 0 : 1
    }

    /// Goes to the folder above, with the folder it came from selected.
    private mutating func goUp(list: (String) -> [String]) {
        guard folder != "/" else { return }
        let from = (folder as NSString).lastPathComponent
        open((folder as NSString).deletingLastPathComponent, list: list)
        selection = rows.firstIndex(of: .subfolder(from)) ?? 0
    }

    private mutating func setFilter(_ filter: String) {
        self.filter = filter
        selection = 0
    }
}
