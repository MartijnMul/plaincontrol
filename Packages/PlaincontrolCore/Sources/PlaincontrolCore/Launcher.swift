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
/// It starts on the list of projects: the arrow keys move the selection, Return opens the
/// selected project. An open project lists its actions, each under a key; pressing that key
/// runs the action. Escape goes back from a project to the list, and from the list closes
/// the launcher.
public struct Launcher: Sendable, Equatable {
    public enum Key: Equatable, Sendable {
        case up, down, enter, escape
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
    public private(set) var selection = 0
    public private(set) var screen = Screen.projects

    public init(projects: [Project], actions: [ProjectAction] = ProjectAction.allCases) {
        self.projects = projects
        self.actions = actions
    }

    public var selectedProject: Project? {
        projects.indices.contains(selection) ? projects[selection] : nil
    }

    public mutating func press(_ key: Key) -> Outcome {
        switch (screen, key) {
        case (.projects, .up):
            selection = max(selection - 1, 0)
        case (.projects, .down):
            selection = min(selection + 1, max(projects.count - 1, 0))
        case (.projects, .enter):
            if let selectedProject { screen = .project(selectedProject) }
        case (.projects, .escape):
            return .close
        case (.project, .escape):
            screen = .projects
        case (.project(let project), .character(let character)):
            let character = Character(character.lowercased())
            if let action = actions.first(where: { $0.key == character }) {
                return .run(action, project)
            }
        case (.projects, .character), (.project, .up), (.project, .down), (.project, .enter):
            break
        }
        return .stay
    }
}
