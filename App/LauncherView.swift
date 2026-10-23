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
            if let finder = controller.pathFinder {
                pathFinderList(finder)
            } else {
                switch controller.launcher.screen {
                case .projects: projectList
                case .project(let project): actionList(for: project)
                }
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
                    "Projects appear here once you start Claude Code in them. To list folders before that, add them to \(LauncherController.settingsFileForDisplay), from Launcher Settings in the menu bar."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
            } else {
                Text("No project matches “\(launcher.query)”")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
            }
            row(selected: true) {
                Image(systemName: "folder.badge.plus")
                Text("Add a folder…").font(.title3.weight(.medium))
                Spacer()
            }
        } else {
            VStack(spacing: 2) {
                ForEach(Array(launcher.visible.enumerated()), id: \.element.id) { index, item in
                    let selected = index == launcher.selection
                    row(selected: selected) {
                        DigitCap(row: index)
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
    private func pathFinderList(_ finder: PathFinder) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
            Text((finder.folder as NSString).abbreviatingWithTildeInPath + (finder.folder == "/" ? "" : "/"))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            Text(finder.filter)
            Spacer()
        }
        .font(.title3)
        .padding(.horizontal, 10)
        let rows = finder.rows
        if rows.isEmpty {
            Text(finder.filter.isEmpty ? "No folders here" : "No folder matches “\(finder.filter)”")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
        } else {
            // Show the rows around the selection, as many as the project list shows.
            let first = min(
                max(finder.selection - Launcher.visibleLimit + 1, 0), max(rows.count - Launcher.visibleLimit, 0))
            VStack(spacing: 2) {
                ForEach(first..<min(first + Launcher.visibleLimit, rows.count), id: \.self) { index in
                    row(selected: index == finder.selection) {
                        switch rows[index] {
                        case .add:
                            Image(systemName: "plus.circle.fill")
                            Text("Add “\((finder.folder as NSString).lastPathComponent)” as a project")
                                .font(.title3.weight(.medium))
                        case .subfolder(let name):
                            Image(systemName: "folder")
                            Text(name).font(.title3)
                        }
                        Spacer()
                        if case .subfolder = rows[index] {
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
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
            ForEach(Array(controller.launcher.actions.enumerated()), id: \.element) { index, action in
                row(selected: action == controller.launcher.selectedAction) {
                    DigitCap(row: index)
                    Text(controller.title(of: action)).font(.title3)
                    Spacer()
                    if let command = controller.command(of: action, in: project) {
                        Text(command).font(.body.monospaced()).opacity(0.7)
                    }
                }
            }
        }
        if let notice = controller.notice {
            Text(notice)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
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
            if controller.pathFinder != nil {
                hint("↑↓", "Select")
                hint("↩ →", "Open folder")
                hint("←", "Up")
                hint("esc", "Back")
            } else {
                launcherHints
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var launcherHints: some View {
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

/// The digit that picks a row.
private struct DigitCap: View {
    let row: Int

    var body: some View {
        KeyCap(Launcher.digit(forRow: row).map(String.init) ?? "")
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
