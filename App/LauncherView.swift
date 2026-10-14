import PlaincontrolCore
import SwiftUI

/// The launcher: the list of projects, or the actions of the open project.
struct LauncherView: View {
    let controller: LauncherController

    var body: some View {
        VStack(spacing: 0) {
            card
            Spacer(minLength: 0)
        }
        .padding(30)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch controller.launcher.screen {
            case .projects: projectList
            case .project(let project): actionList(for: project)
            }
            if let problem = controller.problem {
                Text(problem)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            hints
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
    }

    @ViewBuilder
    private var projectList: some View {
        let launcher = controller.launcher
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            if launcher.query.isEmpty {
                Text("Type to search all projects")
            } else {
                Text(launcher.query).foregroundStyle(.primary)
            }
            Spacer()
        }
        .font(.title3)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        if launcher.visible.isEmpty {
            if launcher.query.isEmpty {
                Text("No projects yet")
                    .font(.headline)
                    .padding(.horizontal, 10)
                Text(
                    "Projects appear here once you start Claude Code in them. To list folders before that, add them to \(LauncherController.projectsFileForDisplay), from Edit Projects in the menu bar."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
            } else {
                Text("No project matches “\(launcher.query)”")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
            }
        } else {
            VStack(spacing: 2) {
                ForEach(Array(launcher.visible.enumerated()), id: \.element.id) { index, item in
                    let selected = index == launcher.selection
                    row(selected: selected) {
                        SessionMark(sessions: item.sessions, selected: selected)
                        Text(item.project.name)
                            .font(.title3.weight(.medium))
                            .opacity(item.isActive ? 1 : 0.55)
                        Spacer()
                        Text(item.project.displayPath).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionList(for project: Project) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(project.name).font(.title3.weight(.semibold))
            Text(project.displayPath).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
        }
        .padding(.horizontal, 10)
        VStack(spacing: 2) {
            ForEach(controller.launcher.actions, id: \.self) { action in
                row(selected: action == controller.launcher.selectedAction) {
                    KeyCap(String(action.key).uppercased())
                    Text(action.title).font(.title3)
                    Spacer()
                }
            }
        }
    }

    private func row(selected: Bool, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 10, content: content)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? .white : .primary)
            .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private var hints: some View {
        HStack(spacing: 14) {
            switch controller.launcher.screen {
            case .projects:
                hint("↑↓", "Select")
                hint("↩ →", "Open")
                hint("esc", controller.launcher.query.isEmpty ? "Close" : "Clear")
            case .project:
                hint("↑↓", "Select")
                hint("↩ →", "Run")
                hint("← esc", "Back")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            KeyCap(key)
            Text(label)
        }
    }
}

/// Whether a project has Claude Code sessions, and whether one waits for the user.
private struct SessionMark: View {
    let sessions: LauncherItem.Sessions
    let selected: Bool

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .help(help)
    }

    private var color: Color {
        switch sessions {
        case .waiting: selected ? .white : .orange
        case .running: selected ? .white.opacity(0.6) : .green
        case .none: .clear
        }
    }

    private var help: String {
        switch sessions {
        case .waiting: "A session is waiting for you"
        case .running: "Claude Code is running here"
        case .none: ""
        }
    }
}

/// A key as printed on the keyboard.
private struct KeyCap: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        Text(label)
            .font(.callout.monospaced().weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(minWidth: 24)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
    }
}

extension Project {
    /// The folder, with the home folder shown as `~`.
    fileprivate var displayPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
