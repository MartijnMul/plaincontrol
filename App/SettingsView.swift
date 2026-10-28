import AppKit
import PlaincontrolCore
import SwiftUI
import UniformTypeIdentifiers

/// The settings window: a tab per part of the settings file, each change written to the file
/// at once.
struct SettingsView: View {
    let model: SettingsModel

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                SettingsPage(model: model) { GeneralSettings(model: model) }
            }
            Tab("Projects", systemImage: "folder") {
                SettingsPage(model: model) { ProjectSettings(model: model) }
            }
            Tab("Windows", systemImage: "rectangle.split.3x1") {
                SettingsPage(model: model) { WindowSettings(model: model) }
            }
        }
        .frame(width: 600)
        .onAppear { model.startWatching() }
        .onDisappear { model.stopWatching() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reload()
        }
        .alert(
            "The settings file was written anew",
            isPresented: Binding(get: { model.backup != nil }, set: { if !$0 { model.backup = nil } })
        ) {
            Button("OK") {}
        } message: {
            let backup = model.backup.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? ""
            Text("Its text could not be changed in place, so the file as it was is kept as \(backup).")
        }
    }
}

/// A tab's settings, greyed out while the file cannot be read, with the way to edit the file
/// as text below them.
private struct SettingsPage<Content: View>: View {
    let model: SettingsModel
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let problem = model.problem {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text("\(LauncherController.settingsFileForDisplay) cannot be read: \(problem)")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Open File") { model.openFile() }
                }
                .padding([.horizontal, .top], 20)
            }
            content.disabled(model.problem != nil)
            HStack {
                Text("Saved in \(LauncherController.settingsFileForDisplay)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Edit as Text…") { model.openFile() }
            }
            .padding([.horizontal, .bottom], 20)
        }
    }
}

extension SettingsModel {
    /// A binding to one setting, which writes each change to the file.
    func binding<Value>(_ setting: WritableKeyPath<LauncherConfig, Value>) -> Binding<Value> {
        Binding {
            self.config[keyPath: setting]
        } set: { value in
            self.change { $0[keyPath: setting] = value }
        }
    }
}

// MARK: General

private struct GeneralSettings: View {
    let model: SettingsModel
    @State private var isTrusted = LauncherHotkey.isAllowed

    var body: some View {
        Form {
            Picker("Hold to open the launcher", selection: model.binding(\.holdKey)) {
                ForEach(HoldKey.allCases, id: \.self) { key in
                    Text(key.title).tag(key)
                }
            }
            AppPicker(title: "Terminal", role: .terminal, setting: \.terminal, model: model)
            AppPicker(title: "Editor", role: .editor, setting: \.editor, model: model)
            CommittingField(
                "Claude Code command", value: model.config.claudeCommand, prompt: "claude",
                note: "What Claude Code in a terminal runs in the project's folder."
            ) { command in
                model.change { $0.claudeCommand = command.isEmpty ? "claude" : command }
            }
            Picker("Order of a project's actions", selection: model.binding(\.actionOrder)) {
                ForEach(ActionOrder.allCases, id: \.self) { order in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(order.title)
                        Text(order.note).font(.callout).foregroundStyle(.secondary)
                    }
                    .tag(order)
                }
            }
            .pickerStyle(.radioGroup)
            LabeledContent("Accessibility") {
                if isTrusted {
                    Text("Allowed")
                } else {
                    Button("Open System Settings…") { NSWorkspace.shared.open(LauncherHotkey.accessibilitySettings) }
                }
                Text("The launcher needs it to notice its key and to take your typing while it is open.")
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isTrusted = LauncherHotkey.isAllowed
        }
    }
}

/// A choice of app for the terminal or the editor: automatic, one of those found on this Mac,
/// or any other.
private struct AppPicker: View {
    let title: String
    let role: AppRole
    let setting: WritableKeyPath<LauncherConfig, String?>
    let model: SettingsModel

    private static let automatic = ""
    private static let other = "\u{0}other"

    var body: some View {
        let launcher = model.launcher
        let value = model.config[keyPath: setting]
        // The setting's app, by bundle identifier where it can be found.
        let current = value.map { Apps.app(for: $0).flatMap(Apps.bundleIdentifier(of:)) ?? $0 } ?? Self.automatic
        var apps = launcher.installedApps(role).sorted {
            Apps.name(ofApp: $0).localizedStandardCompare(Apps.name(ofApp: $1)) == .orderedAscending
        }
        if current != Self.automatic, !apps.contains(current) { apps.insert(current, at: 0) }
        let automatic = launcher.automaticApp(role).map { "Automatic (\(Apps.name(ofApp: $0)))" } ?? "Automatic"

        return Picker(selection: Binding(get: { current }, set: choose)) {
            Text(automatic).tag(Self.automatic)
            Divider()
            ForEach(apps, id: \.self) { app in
                Text(label(of: app)).tag(app)
            }
            Divider()
            Text("Other…").tag(Self.other)
        } label: {
            Text(title)
            if role == .terminal, let note = terminalNote(for: current == Self.automatic ? nil : current) {
                Text(note)
            }
        }
    }

    private func label(of app: String) -> String {
        guard Apps.isInstalled(app) else {
            return Apps.app(for: app) == nil ? "“\(app)” (not found)" : app
        }
        let name = Apps.name(ofApp: app)
        return role == .terminal && !model.launcher.canOpenWindows(in: app) ? "\(name) (can't open windows yet)" : name
    }

    /// What to know about the terminal `app`, or about the one chosen without a setting.
    private func terminalNote(for app: String?) -> String? {
        let launcher = model.launcher
        guard let app, Apps.isInstalled(app), !launcher.canOpenWindows(in: app) else { return nil }
        let fallback = launcher.automaticApp(.terminal).map(Apps.name(ofApp:)) ?? "iTerm2"
        return
            "\(AppInfo.name) cannot open \(Apps.name(ofApp: app)) windows yet, so new terminal windows open in \(fallback)."
    }

    private func choose(_ choice: String) {
        switch choice {
        case Self.automatic: model.change { $0[keyPath: setting] = nil }
        case Self.other:
            // After the menu has closed.
            Task { @MainActor in
                let panel = NSOpenPanel()
                panel.directoryURL = URL(filePath: "/Applications")
                panel.allowedContentTypes = [.application]
                panel.prompt = "Choose"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                set(Apps.bundleIdentifier(of: url).map(Self.value(for:)) ?? url.path(percentEncoded: false))
            }
        default: set(Self.value(for: choice))
        }
    }

    private func set(_ value: String) {
        guard value != model.config[keyPath: setting] else { return }
        model.change { $0[keyPath: setting] = value }
    }

    /// What the settings file says for the app with `bundleIdentifier`: its name, where the
    /// name finds it, and else its bundle identifier.
    private static func value(for bundleIdentifier: String) -> String {
        guard let url = Apps.app(bundleIdentifier: bundleIdentifier) else { return bundleIdentifier }
        let name = Apps.name(of: url)
        return Apps.app(for: name).flatMap(Apps.bundleIdentifier(of:)) == bundleIdentifier ? name : bundleIdentifier
    }
}

extension HoldKey {
    fileprivate var title: String {
        switch self {
        case .rightOption: "Right Option"
        case .rightCommand: "Right Command"
        case .rightControl: "Right Control"
        case .rightShift: "Right Shift"
        }
    }
}

extension ActionOrder {
    fileprivate var title: String {
        switch self {
        case .fixed: "Always the same"
        case .selected: "Same order, most used selected"
        case .usage: "Most used first"
        }
    }

    fileprivate var note: String {
        switch self {
        case .fixed: "The first action is selected."
        case .selected: "The action you use most in a project is selected, so Return runs it."
        case .usage: "The actions you use most in a project come first; their digits move with them."
        }
    }
}

/// A text field that writes its text when the user presses Return or leaves the field, not
/// at every key.
private struct CommittingField: View {
    let title: String
    let value: String
    let prompt: String
    var note: String?
    let commit: (String) -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(_ title: String, value: String, prompt: String, note: String? = nil, commit: @escaping (String) -> Void) {
        self.title = title
        self.value = value
        self.prompt = prompt
        self.note = note
        self.commit = commit
        _text = State(initialValue: value)
    }

    var body: some View {
        TextField(text: $text, prompt: Text(prompt)) {
            Text(title)
            if let note { Text(note) }
        }
        .focused($isFocused)
        .onSubmit(save)
        .onChange(of: isFocused) { if !isFocused { save() } }
        .onChange(of: value) { if !isFocused { text = value } }
    }

    private func save() {
        let text = text.trimmingCharacters(in: .whitespaces)
        if text != value { commit(text) }
    }
}

// MARK: Projects

private struct ProjectSettings: View {
    let model: SettingsModel
    @State private var selectedProjects = Set<Project.ID>()
    @State private var selectedRoots = Set<String>()

    var body: some View {
        let config = model.config
        Form {
            Section {
                Table(config.projects, selection: $selectedProjects) {
                    TableColumn("Name") { project in
                        let folderName = (project.path as NSString).lastPathComponent
                        CommittingField(
                            "Name", value: project.name == folderName ? "" : project.name, prompt: folderName
                        ) { name in
                            change(project) { $0 = Project(path: project.path, name: name) }
                        }
                        .labelsHidden()
                    }
                    TableColumn("Folder") { project in
                        Text((project.path as NSString).abbreviatingWithTildeInPath)
                            .help(project.path)
                            .truncationMode(.head)
                    }
                    TableColumn("Dev server command") { project in
                        CommittingField(
                            "Dev server command", value: config.devCommand(for: project) ?? "",
                            prompt: DevServer.command(in: project.path) ?? "None"
                        ) { command in
                            model.change { $0.devCommands[project.resolvedPath] = command.isEmpty ? nil : command }
                        }
                        .labelsHidden()
                    }
                }
                .frame(height: 150)
                AddRemoveButtons(canRemove: !selectedProjects.isEmpty) {
                    let folders = Self.chooseFolders().filter { path in !config.projects.contains { $0.path == path } }
                    guard !folders.isEmpty else { return }
                    model.change { $0.projects += folders.map { Project(path: $0) } }
                } remove: {
                    let removed = selectedProjects
                    selectedProjects = []
                    model.change { config in
                        for project in config.projects where removed.contains(project.id) {
                            config.devCommands[project.resolvedPath] = nil
                        }
                        config.projects.removeAll { removed.contains($0.id) }
                    }
                }
            } header: {
                Text("Projects")
                Text(
                    "Always listed. An empty name is the folder's; an empty command is the one the launcher finds, shown in grey."
                )
            }
            Section {
                List(config.roots, id: \.self, selection: $selectedRoots) { root in
                    Text((root as NSString).abbreviatingWithTildeInPath).help(root)
                }
                .frame(height: 90)
                AddRemoveButtons(canRemove: !selectedRoots.isEmpty) {
                    let folders = Self.chooseFolders().filter { !config.roots.contains($0) }
                    guard !folders.isEmpty else { return }
                    model.change { $0.roots += folders }
                } remove: {
                    let removed = selectedRoots
                    selectedRoots = []
                    model.change { $0.roots.removeAll(where: removed.contains) }
                }
                Stepper(value: model.binding(\.activeDays), in: LauncherConfigFile.minimumActiveDays...3650) {
                    Text("Keep a project listed for \(config.activeDays) days")
                    Text("After its last commit, changed file or use.")
                }
            } header: {
                Text("Folders with projects")
                Text("Their subfolders are listed while you work in them, and found by a search after that.")
            }
            Section {
                Toggle(isOn: model.binding(\.zoxide)) {
                    Text("Use zoxide's folders")
                    Text(
                        Zoxide.executable() == nil
                            ? "zoxide is not installed, so this has no effect."
                            : "Also list the folders you visit most with zoxide. Its data is only read.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func change(_ project: Project, _ change: @escaping (inout Project) -> Void) {
        model.change { config in
            guard let index = config.projects.firstIndex(where: { $0.id == project.id }) else { return }
            change(&config.projects[index])
        }
    }

    /// Folders the user picks, by their paths.
    private static func chooseFolders() -> [String] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL.homeDirectory
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.map { ($0.path(percentEncoded: false) as NSString).standardizingPath }
    }
}

/// The + and − buttons below a list.
private struct AddRemoveButtons: View {
    let canRemove: Bool
    let add: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: add) { Image(systemName: "plus") }
                .help("Add a folder")
            Button(action: remove) { Image(systemName: "minus") }
                .disabled(!canRemove)
                .help("Remove the selected")
        }
        .buttonStyle(.borderless)
    }
}

// MARK: Windows

private struct WindowSettings: View {
    let model: SettingsModel

    var body: some View {
        let layout = model.config.windows
        Form {
            Section {
                Toggle(
                    isOn: Binding(
                        get: { layout != nil },
                        set: { isOn in
                            model.change { $0.windows = isOn ? $0.windows ?? WindowLayout() : nil }
                        })
                ) {
                    Text("Place new windows in columns")
                    Text(
                        "Every screen is split into columns, and a window the launcher opens takes a free one, nearest you first. Off, each app places its windows."
                    )
                }
            }
            if let layout {
                Section("Columns") {
                    columns("On the built-in screen", \.builtInColumns, layout)
                    columns("On other screens", \.externalColumns, layout)
                }
                Section("The editor takes") {
                    columns("On the built-in screen", \.editorBuiltInColumns, layout)
                    columns("On other screens", \.editorExternalColumns, layout)
                }
                Section {
                    let gap = LauncherConfigFile.gapRange
                    Stepper(value: binding(\.gap), in: gap, step: 1) {
                        Text("Gap around and between windows: \(layout.gap.formatted()) points")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func columns(_ title: String, _ setting: WritableKeyPath<WindowLayout, Int>, _ layout: WindowLayout)
        -> some View
    {
        let count = layout[keyPath: setting]
        return Stepper(value: binding(setting), in: LauncherConfigFile.columnRange) {
            Text("\(title): \(count) \(count == 1 ? "column" : "columns")")
        }
    }

    private func binding<Value>(_ setting: WritableKeyPath<WindowLayout, Value>) -> Binding<Value> {
        Binding {
            (model.config.windows ?? WindowLayout())[keyPath: setting]
        } set: { value in
            model.change { config in
                var layout = config.windows ?? WindowLayout()
                layout[keyPath: setting] = value
                config.windows = layout
            }
        }
    }
}
