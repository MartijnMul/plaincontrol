import Foundation

/// Something the launcher can do with a project, in the order the launcher offers them.
///
/// Each action runs under the digit of its place, so the order is what the user learns. An
/// action that is missing, such as the desktop app or the editor when neither is installed,
/// leaves no gap, so the actions after it move up a digit.
public enum ProjectAction: String, CaseIterable, Codable, Sendable {
    /// A new Claude Code session in the project's folder, in a window of its own in the Claude
    /// desktop app (``ClaudeDesktop``).
    case claudeDesktop
    /// A new terminal window in the project's folder, with nothing running.
    case terminal
    /// The project's folder in the app macOS opens folders with, normally Finder.
    case finder
    /// The project's folder in the user's editor.
    case editor
    /// A new terminal window in the project's folder, running Claude Code.
    case claude
    /// A new terminal window in the project's folder, running its development server
    /// (``DevServer``). It comes last, as only some projects have one.
    case devServer

    public var title: String {
        switch self {
        case .claude: "Claude Code"
        case .terminal: "Terminal"
        case .finder: "Finder"
        case .editor: "Editor"
        case .claudeDesktop: "Claude Code Desktop"
        case .devServer: "Dev server"
        }
    }
}

/// An app the launcher opens an empty window of, without a project.
public enum AppWindow: String, CaseIterable, Sendable {
    /// A terminal window in the home folder.
    case terminal
    /// A browser window.
    case browser
    /// A Finder window on the home folder, or one of the app the user opens folders with.
    case finder
}

/// What the dev server action asks next: whether to open the server's page too.
public enum DevServerChoice: CaseIterable, Sendable {
    /// Only the dev server, in a new terminal window.
    case server
    /// The dev server, and its page in a new tab of the browser once the server listens.
    case serverAndPage
}

/// How the launcher orders a project's actions, set as `actionOrder` in the settings.
public enum ActionOrder: String, CaseIterable, Sendable {
    /// Always the order of ``ProjectAction``, with the first action selected.
    case fixed
    /// That order, with the action used most in the project selected, so Return runs it.
    case selected
    /// The actions used most in the project first, so their digits move with them.
    case usage

    /// `actions` in the order to show them for `project`.
    public func order(_ actions: [ProjectAction], for project: Project, usage: ProjectUsage) -> [ProjectAction] {
        self == .usage ? usage.rank(actions, in: project) : actions
    }

    /// The action to select when `project` opens with `actions`, or nil for the first one.
    public func selection(in actions: [ProjectAction], for project: Project, usage: ProjectUsage) -> ProjectAction? {
        self == .selected ? usage.rank(actions, in: project).first : nil
    }
}

/// What the launcher shows and how it answers the keyboard.
///
/// It starts on the list of projects: those with a running Claude Code session first (waiting
/// ones before working ones), then the active projects by how often and how recently they were
/// used. Typing searches every project by name and folder, inactive ones last; Backspace
/// edits the search and Escape clears it. Up and Down move the selection, Return or Right opens
/// the selected project, and a digit opens the project in that row. When the list is empty, or
/// a search finds nothing, Return or Right asks to find a folder to add instead
/// (``PathFinder``).
///
/// An open project lists its actions: Up and Down select one, Return or Right runs it, and a
/// digit runs the action in that row. Left or Escape goes back to the list; Escape on the list
/// without a search closes the launcher. Left on the list shows the apps it opens an empty
/// window of: Up and Down select one, Return or Left runs it, a digit runs the one in that row,
/// and Right or Escape goes back to the list. The dev server asks next whether to open its page too,
/// in the same way, when the project offers that; Left or Escape goes back to the actions.
public struct Launcher: Sendable {
    /// The actions a project offers, in the order shown.
    public typealias Actions = @Sendable (Project) -> [ProjectAction]
    /// The action selected when a project opens with these actions, or nil for the first one.
    public typealias Selection = @Sendable (Project, [ProjectAction]) -> ProjectAction?
    /// What the dev server action of a project asks next; with fewer than two choices, it runs.
    public typealias DevServerChoices = @Sendable (Project) -> [DevServerChoice]

    public enum Key: Equatable, Sendable {
        case up, down, left, right, enter, escape, backspace
        case character(Character)
    }

    public enum Screen: Equatable, Sendable {
        case projects
        case project(Project)
        /// What the dev server of the project should open.
        case devServer(Project)
        /// The apps to open an empty window of.
        case apps
    }

    /// What should happen after a key press.
    public enum Outcome: Equatable, Sendable {
        case stay
        case close
        case run(ProjectAction, Project)
        /// Start the project's dev server and open its page.
        case runDevServerWithPage(Project)
        /// Open an empty window of the app.
        case openApp(AppWindow)
        /// Find a folder to add as a project.
        case findFolder
    }

    /// How many projects the list shows at most: one for each digit.
    public static let visibleLimit = 9

    /// The digit that picks row `index` of a list, for the first nine rows.
    public static func digit(forRow index: Int) -> Character? {
        (0..<9).contains(index) ? Character(String(index + 1)) : nil
    }

    public private(set) var items: [LauncherItem]
    private let actionsOf: Actions
    private let selectionOf: Selection
    private let devServerChoicesOf: DevServerChoices
    /// The actions of the open project, in the order shown.
    public private(set) var actions: [ProjectAction] = []
    /// What the dev server of the open project asks, while it asks.
    public private(set) var devServerChoices: [DevServerChoice] = []
    /// The selected one of ``devServerChoices``.
    public private(set) var choiceSelection = 0
    /// The apps the launcher opens an empty window of, in the order shown.
    public let apps: [AppWindow]
    /// The selected one of ``apps``.
    public private(set) var appSelection = 0
    /// What the user typed to search.
    public private(set) var query = ""
    /// The selected row of ``visible``.
    public private(set) var selection = 0
    /// The selected action of the open project.
    public private(set) var actionSelection = 0
    public private(set) var screen = Screen.projects
    /// The rows of the list, in order.
    public private(set) var visible: [LauncherItem] = []

    /// - Parameter actions: The actions every project offers.
    public init(items: [LauncherItem], actions: [ProjectAction] = ProjectAction.allCases) {
        self.init(items: items) { _ in actions }
    }

    /// - Parameters:
    ///   - apps: The apps to open an empty window of; without any, Left on the list does nothing.
    ///   - actions: The actions a project offers, asked each time it opens.
    ///   - selection: The action selected when a project opens.
    ///   - devServerChoices: What the dev server action asks next, asked each time it runs.
    public init(
        items: [LauncherItem], apps: [AppWindow] = [], actions: @escaping Actions,
        selection: @escaping Selection = { _, _ in nil }, devServerChoices: @escaping DevServerChoices = { _ in [] }
    ) {
        self.items = items
        self.apps = apps
        actionsOf = actions
        selectionOf = selection
        devServerChoicesOf = devServerChoices
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
        enter(project)
    }

    public var selectedAction: ProjectAction? {
        actions.indices.contains(actionSelection) ? actions[actionSelection] : nil
    }

    public var selectedApp: AppWindow? {
        apps.indices.contains(appSelection) ? apps[appSelection] : nil
    }

    public var selectedChoice: DevServerChoice? {
        devServerChoices.indices.contains(choiceSelection) ? devServerChoices[choiceSelection] : nil
    }

    public mutating func press(_ key: Key) -> Outcome {
        switch (screen, key) {
        case (.projects, .up):
            selection = max(selection - 1, 0)
        case (.projects, .down):
            selection = min(selection + 1, max(visible.count - 1, 0))
        case (.projects, .enter), (.projects, .right):
            if visible.isEmpty { return .findFolder }
            if let selectedProject { enter(selectedProject) }
        case (.projects, .escape):
            if query.isEmpty { return .close }
            search("")
        case (.projects, .left):
            if !apps.isEmpty {
                appSelection = 0
                screen = .apps
            }
        case (.projects, .backspace):
            if !query.isEmpty { search(String(query.dropLast())) }
        case (.projects, .character(let character)) where character.isASCII && character.isNumber:
            if let row = Self.row(for: character), visible.indices.contains(row) {
                selection = row
                enter(visible[row].project)
            }
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
            if let selectedAction { return run(selectedAction, on: project) }
        case (.project, .left), (.project, .escape):
            screen = .projects
        case (.project(let project), .character(let character)):
            if let row = Self.row(for: character), actions.indices.contains(row) {
                return run(actions[row], on: project)
            }
        case (.devServer, .up):
            choiceSelection = max(choiceSelection - 1, 0)
        case (.devServer, .down):
            choiceSelection = min(choiceSelection + 1, max(devServerChoices.count - 1, 0))
        case (.devServer(let project), .enter), (.devServer(let project), .right):
            if let selectedChoice { return Self.outcome(of: selectedChoice, on: project) }
        case (.devServer(let project), .left), (.devServer(let project), .escape):
            screen = .project(project)
        case (.devServer(let project), .character(let character)):
            if let row = Self.row(for: character), devServerChoices.indices.contains(row) {
                return Self.outcome(of: devServerChoices[row], on: project)
            }
        case (.apps, .up):
            appSelection = max(appSelection - 1, 0)
        case (.apps, .down):
            appSelection = min(appSelection + 1, max(apps.count - 1, 0))
        case (.apps, .enter), (.apps, .left):
            if let selectedApp { return .openApp(selectedApp) }
        case (.apps, .right), (.apps, .escape):
            screen = .projects
        case (.apps, .character(let character)):
            if let row = Self.row(for: character), apps.indices.contains(row) { return .openApp(apps[row]) }
        case (.project, .backspace), (.devServer, .backspace), (.apps, .backspace):
            break
        }
        return .stay
    }

    /// Runs `action`, or asks first what the dev server should open.
    private mutating func run(_ action: ProjectAction, on project: Project) -> Outcome {
        guard action == .devServer else { return .run(action, project) }
        let choices = devServerChoicesOf(project)
        guard choices.count > 1 else { return .run(action, project) }
        // Back from the question, the dev server stays selected.
        actionSelection = actions.firstIndex(of: action) ?? actionSelection
        devServerChoices = choices
        choiceSelection = 0
        screen = .devServer(project)
        return .stay
    }

    private static func outcome(of choice: DevServerChoice, on project: Project) -> Outcome {
        switch choice {
        case .server: .run(.devServer, project)
        case .serverAndPage: .runDevServerWithPage(project)
        }
    }

    private mutating func enter(_ project: Project) {
        actions = actionsOf(project)
        actionSelection = selectionOf(project, actions).flatMap(actions.firstIndex) ?? 0
        screen = .project(project)
    }

    /// The row a digit picks.
    private static func row(for character: Character) -> Int? {
        character.wholeNumberValue.flatMap { $0 >= 1 ? $0 - 1 : nil }
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
