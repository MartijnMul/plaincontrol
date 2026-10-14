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
        if launcher.projects.isEmpty {
            Text("No projects yet")
                .font(.headline)
            Text("Add folders to \(LauncherController.projectsFileForDisplay), from Edit Projects in the menu bar.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 2) {
                ForEach(Array(launcher.projects.enumerated()), id: \.element.id) { index, project in
                    row(selected: index == launcher.selection) {
                        Text(project.name).font(.title3.weight(.medium))
                        Spacer()
                        Text(project.displayPath).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
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
                row(selected: false) {
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
                hint("↩", "Open")
                hint("esc", "Close")
            case .project:
                hint("esc", "Back")
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
