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
/// It starts on the list of projects: Up and Down move the selection, Return or Right opens
/// the selected project. An open project lists its actions: Up and Down select one, Return or
/// Right runs it, and each action also runs straight from its own key. Left or Escape goes
/// back from a project to the list; Escape on the list closes the launcher.
public struct Launcher: Sendable, Equatable {
    public enum Key: Equatable, Sendable {
        case up, down, left, right, enter, escape
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
    }

    public let projects: [Project]
    /// The actions on offer, in the order shown.
    public let actions: [ProjectAction]
    /// The selected project in the list.
    public private(set) var selection = 0
    /// The selected action of the open project.
    public private(set) var actionSelection = 0
    public private(set) var screen = Screen.projects

    public init(projects: [Project], actions: [ProjectAction] = ProjectAction.allCases) {
        self.projects = projects
        self.actions = actions
    }

    public var selectedProject: Project? {
        projects.indices.contains(selection) ? projects[selection] : nil
    }

    public var selectedAction: ProjectAction? {
        actions.indices.contains(actionSelection) ? actions[actionSelection] : nil
    }

    public mutating func press(_ key: Key) -> Outcome {
        switch (screen, key) {
        case (.projects, .up):
            selection = max(selection - 1, 0)
        case (.projects, .down):
            selection = min(selection + 1, max(projects.count - 1, 0))
        case (.projects, .enter), (.projects, .right):
            if let selectedProject {
                actionSelection = 0
                screen = .project(selectedProject)
            }
        case (.projects, .escape):
            return .close
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
        case (.projects, .left), (.projects, .character):
            break
        }
        return .stay
    }
}
