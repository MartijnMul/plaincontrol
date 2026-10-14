import Foundation

/// Something the launcher can do with a project.
public enum ProjectAction: String, CaseIterable, Sendable {
    /// A new iTerm2 window in the project's folder, running Claude Code.
    case claude
    /// The project's folder in Finder.
    case finder
    /// The project's folder in Visual Studio Code.
    case vsCode

    /// The key that runs the action, once a project is open in the launcher.
    public var key: Character {
        switch self {
        case .claude: "c"
        case .finder: "f"
        case .vsCode: "v"
        }
    }

    public var title: String {
        switch self {
        case .claude: "Claude Code in iTerm2"
        case .finder: "Finder"
        case .vsCode: "VS Code"
        }
    }
}

/// What the launcher shows and how it answers the keyboard.
///
/// It starts on the list of projects: those with a running Claude Code session first (waiting
/// ones before working ones), then the active projects by how often and how recently they were
/// used. Typing searches every project by name and folder, inactive ones last; Backspace
/// edits the search and Escape clears it. Up and Down move the selection, Return or Right opens
/// the selected project. When the list is empty, or a search finds nothing, Return or Right
/// asks to find a folder to add instead (``PathFinder``).
///
/// An open project lists its actions: Up and Down select one, Return or Right runs it, and each
/// action also runs straight from its own key. Left or Escape goes back to the list; Escape on
/// the list without a search closes the launcher.
public struct Launcher: Sendable, Equatable {
    public enum Key: Equatable, Sendable {
        case up, down, left, right, enter, escape, backspace
        case character(Character)
    }

    public enum Screen: Equatable, Sendable {
        case projects
        case project(Project)
    }

    /// What should happen after a key press.
    public enum Outcome: Equatable, Sendable {
        case stay
        case close
        case run(ProjectAction, Project)
        /// Find a folder to add as a project.
        case findFolder
    }

    /// How many projects the list shows at most.
    public static let visibleLimit = 9

    public private(set) var items: [LauncherItem]
    /// The actions on offer, in the order shown.
    public let actions: [ProjectAction]
    /// What the user typed to search.
    public private(set) var query = ""
    /// The selected row of ``visible``.
    public private(set) var selection = 0
    /// The selected action of the open project.
    public private(set) var actionSelection = 0
    public private(set) var screen = Screen.projects
    /// The rows of the list, in order.
    public private(set) var visible: [LauncherItem] = []

    public init(items: [LauncherItem], actions: [ProjectAction] = ProjectAction.allCases) {
        self.items = items
        self.actions = actions
        visible = Self.rank(items, query: query)
    }

    /// Replaces the projects, such as when git reports newer commits, keeping the search and
    /// the selected project when it is still listed.
    public mutating func update(items: [LauncherItem]) {
        let selected = selectedItem?.id
        self.items = items
        visible = Self.rank(items, query: query)
        selection = visible.firstIndex { $0.id == selected } ?? 0
    }

    public var selectedItem: LauncherItem? {
        visible.indices.contains(selection) ? visible[selection] : nil
    }

    public var selectedProject: Project? { selectedItem?.project }

    /// Whether the list offers to find a folder to add, because it shows no projects.
    public var offersToAddFolder: Bool { screen == .projects && visible.isEmpty }

    /// Opens `project`, such as one just added, clearing the search.
    public mutating func open(_ project: Project) {
        if !query.isEmpty { search("") }
        selection = visible.firstIndex { $0.project == project } ?? 0
        actionSelection = 0
        screen = .project(project)
    }

    public var selectedAction: ProjectAction? {
        actions.indices.contains(actionSelection) ? actions[actionSelection] : nil
    }

    public mutating func press(_ key: Key) -> Outcome {
        switch (screen, key) {
        case (.projects, .up):
            selection = max(selection - 1, 0)
        case (.projects, .down):
            selection = min(selection + 1, max(visible.count - 1, 0))
        case (.projects, .enter), (.projects, .right):
            if visible.isEmpty { return .findFolder }
            if let selectedProject {
                actionSelection = 0
                screen = .project(selectedProject)
            }
        case (.projects, .escape):
            if query.isEmpty { return .close }
            search("")
        case (.projects, .backspace):
            if !query.isEmpty { search(String(query.dropLast())) }
        case (.projects, .character(let character)):
            if character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol
                || character == " "
            {
                search(query + String(character))
            }
        case (.project, .up):
            actionSelection = max(actionSelection - 1, 0)
        case (.project, .down):
            actionSelection = min(actionSelection + 1, max(actions.count - 1, 0))
        case (.project(let project), .enter), (.project(let project), .right):
            if let selectedAction { return .run(selectedAction, project) }
        case (.project, .left), (.project, .escape):
            screen = .projects
        case (.project(let project), .character(let character)):
            let character = Character(character.lowercased())
            if let action = actions.first(where: { $0.key == character }) {
                return .run(action, project)
            }
        case (.projects, .left), (.project, .backspace):
            break
        }
        return .stay
    }

    private mutating func search(_ query: String) {
        self.query = query
        visible = Self.rank(items, query: query)
        selection = 0
    }

    /// The rows for `query`: without one, the projects with sessions and the active ones; with
    /// one, every project whose name or folder contains it.
    static func rank(_ items: [LauncherItem], query: String) -> [LauncherItem] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        let candidates =
            query.isEmpty
            ? items.filter(\.isActive)
            : items.filter { item in
                item.project.name.lowercased().contains(query)
                    || (item.project.path as NSString).lastPathComponent.lowercased().contains(query)
            }
        return Array(candidates.sorted(by: ranksBefore).prefix(visibleLimit))
    }

    private static func ranksBefore(_ a: LauncherItem, _ b: LauncherItem) -> Bool {
        if a.group != b.group { return a.group < b.group }
        if a.score != b.score { return a.score > b.score }
        if a.lastActivity != b.lastActivity {
            return (a.lastActivity ?? .distantPast) > (b.lastActivity ?? .distantPast)
        }
        return a.project.name.localizedStandardCompare(b.project.name) == .orderedAscending
    }
}

extension LauncherItem {
    /// Waiting sessions first, then working ones, then active projects, then the rest.
    fileprivate var group: Int {
        switch sessions {
        case .waiting: 0
        case .running: 1
        case .none: isActive ? 2 : 3
        }
    }
}
