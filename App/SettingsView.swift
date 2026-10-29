import AppKit
import PlaincontrolCore
import SwiftUI
import UniformTypeIdentifiers

/// The settings window: a tab per part of the settings file, each change written to the file
/// at once.
struct SettingsView: View {
    let model: SettingsModel
    let updater: Updater

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                SettingsPage(model: model, height: updater.isAvailable ? 750 : 660, restore: GeneralSettings.restore) {
                    GeneralSettings(model: model, updater: updater)
                }
            }
            Tab("Projects", systemImage: "folder") {
                SettingsPage(model: model, height: 660, restore: ProjectSettings.restore) {
                    ProjectSettings(model: model)
                }
            }
            Tab("Windows", systemImage: "rectangle.split.3x1") {
                SettingsPage(model: model, height: 500, restore: WindowSettings.restore) {
                    WindowSettings(model: model)
                }
            }
            Tab("Advanced", systemImage: "gearshape.2") {
                SettingsPage(model: model, height: 220) {
                    AdvancedSettings(model: model)
                }
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

/// What Restore Defaults puts back on a tab.
private struct Restore {
    /// What stays as it is, to say before restoring, if anything.
    var keeps: String?
    /// Whether the tab's settings are all at their defaults in a configuration.
    let isDone: (LauncherConfig) -> Bool
    let apply: (inout LauncherConfig) -> Void
}

/// A tab's settings, greyed out while the file cannot be read, with the way to restore the
/// tab's defaults below them, if it has any.
private struct SettingsPage<Content: View>: View {
    let model: SettingsModel
    /// The tab's height, so every setting shows without scrolling.
    let height: CGFloat
    var restore: Restore?
    @ViewBuilder let content: Content
    @State private var isConfirmingRestore = false

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
            if let restore {
                HStack {
                    Spacer()
                    Button("Restore Defaults…") { isConfirmingRestore = true }
                        .disabled(model.problem != nil || restore.isDone(model.config))
                }
                .padding([.horizontal, .bottom], 20)
            }
        }
        .frame(height: height)
        .background(NoInitialFocus())
        .confirmationDialog("Restore the defaults on this tab?", isPresented: $isConfirmingRestore) {
            Button("Restore Defaults") { restore.map { model.change($0.apply) } }
        } message: {
            if let keeps = restore?.keeps { Text(keeps) }
        }
    }
}

/// Keeps the window from putting the keyboard focus in its first text field when it opens or
/// shows another tab, as macOS does by itself; a click or Tab still puts it there.
private struct NoInitialFocus: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { FocusClearingView() }
    func updateNSView(_ view: NSView, context: Context) {}

    final class FocusClearingView: NSView {
        private var observer: (any NSObjectProtocol)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observer.map(NotificationCenter.default.removeObserver)
            observer = nil
            guard let window else { return }
            DispatchQueue.main.async { [weak window] in window?.makeFirstResponder(nil) }
            // A window that opens now takes its first responder once it becomes key.
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let observer = self.observer else { return }
                    NotificationCenter.default.removeObserver(observer)
                    self.observer = nil
                    self.window?.makeFirstResponder(nil)
                }
            }
        }
    }
}

/// A setting: its title and note, its control, and whether it is at its default, with a
/// button that puts it back when it is not.
private struct SettingRow<Control: View>: View {
    let title: String
    var note: String?
    let isDefault: Bool
    /// The default, as the control shows it.
    let defaultValue: String
    let reset: () -> Void
    @ViewBuilder let control: Control

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                control.labelsHidden()
                DefaultMark(isDefault: isDefault, defaultValue: defaultValue, reset: reset)
            }
        } label: {
            Text(title)
            if let note { Text(note) }
        }
    }
}

/// "Default" for a setting at its default, or else a button that puts it back.
private struct DefaultMark: View {
    let isDefault: Bool
    let defaultValue: String
    let reset: () -> Void

    var body: some View {
        Group {
            if isDefault {
                Text("Default").foregroundStyle(.tertiary)
            } else {
                Button("Reset", systemImage: "arrow.uturn.backward", action: reset)
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.borderless)
                    .help("Back to the default: \(defaultValue)")
            }
        }
        .font(.caption)
        .frame(width: 56, alignment: .leading)
    }
}

extension SettingsModel {
    /// Every setting at its default.
    static let defaults = LauncherConfig()

    /// Whether `setting` is at its default.
    func isDefault<Value: Equatable>(_ setting: KeyPath<LauncherConfig, Value>) -> Bool {
        config[keyPath: setting] == Self.defaults[keyPath: setting]
    }

    /// Puts `setting` back to its default.
    func reset<Value>(_ setting: WritableKeyPath<LauncherConfig, Value>) {
        change { $0[keyPath: setting] = Self.defaults[keyPath: setting] }
    }

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
    @Bindable var updater: Updater
    @State private var isTrusted = LauncherHotkey.isAllowed

    static let restore = Restore(
        isDone: { config in
            let defaults = SettingsModel.defaults
            return config.holdKey == defaults.holdKey && config.terminal == defaults.terminal
                && config.editor == defaults.editor && config.browser == defaults.browser
                && config.claudeCommand == defaults.claudeCommand
                && config.actionOrder == defaults.actionOrder
        },
        apply: { config in
            let defaults = SettingsModel.defaults
            config.holdKey = defaults.holdKey
            config.terminal = defaults.terminal
            config.editor = defaults.editor
            config.browser = defaults.browser
            config.claudeCommand = defaults.claudeCommand
            config.actionOrder = defaults.actionOrder
        })

    var body: some View {
        let defaults = SettingsModel.defaults
        Form {
            SettingRow(
                title: "Hold to open the launcher", isDefault: model.isDefault(\.holdKey),
                defaultValue: defaults.holdKey.title, reset: { model.reset(\.holdKey) }
            ) {
                Picker("Hold to open the launcher", selection: model.binding(\.holdKey)) {
                    ForEach(HoldKey.allCases, id: \.self) { key in
                        Text(key.title).tag(key)
                    }
                }
                .fixedSize()
            }
            AppPicker(title: "Terminal", role: .terminal, setting: \.terminal, model: model)
            AppPicker(title: "Editor", role: .editor, setting: \.editor, model: model)
            AppPicker(title: "Browser", role: .browser, setting: \.browser, model: model)
            SettingRow(
                title: "Claude Code command", note: "What Claude Code in a terminal runs in the project's folder.",
                isDefault: model.isDefault(\.claudeCommand), defaultValue: defaults.claudeCommand,
                reset: { model.reset(\.claudeCommand) }
            ) {
                CommittingField("Claude Code command", value: model.config.claudeCommand, prompt: "claude") { command in
                    model.change { $0.claudeCommand = command.isEmpty ? "claude" : command }
                }
                .textFieldStyle(.roundedBorder)
                .monospaced()
                .multilineTextAlignment(.leading)
                .frame(width: 200)
            }
            Section {
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
                .labelsHidden()
            } header: {
                HStack {
                    Text("Order of a project's actions")
                    Spacer()
                    DefaultMark(
                        isDefault: model.isDefault(\.actionOrder), defaultValue: defaults.actionOrder.title,
                        reset: { model.reset(\.actionOrder) })
                }
            }
            Section {
                LabeledContent("Accessibility") {
                    if isTrusted {
                        Text("Allowed")
                    } else {
                        Button("Open System Settings…") {
                            NSWorkspace.shared.open(LauncherHotkey.accessibilitySettings)
                        }
                    }
                    Text("The launcher needs it to notice its key and to take your typing while it is open.")
                }
            }
            if updater.isAvailable {
                // Kept by Sparkle, not in the settings file, so Restore Defaults leaves it alone.
                Section {
                    Toggle(isOn: $updater.checksAutomatically) {
                        Text("Check for updates automatically")
                        Text("Once a day, Plaincontrol asks GitHub for a newer version. It sends nothing about you.")
                    }
                    LabeledContent("Updates") {
                        Button("Check Now") { updater.checkForUpdates() }
                            .disabled(!updater.canCheck)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isTrusted = LauncherHotkey.isAllowed
        }
    }
}

/// A choice of app for the terminal, the editor or the browser: automatic, one of those found
/// on this Mac, or any other.
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

        let reset = { model.change { $0[keyPath: setting] = nil } }
        return SettingRow(
            title: title, note: note(for: current == Self.automatic ? nil : current),
            isDefault: value == nil, defaultValue: automatic, reset: reset
        ) {
            Picker(title, selection: Binding(get: { current }, set: choose)) {
                Text(automatic).tag(Self.automatic)
                Divider()
                ForEach(apps, id: \.self) { app in
                    Text(label(of: app)).tag(app)
                }
                Divider()
                Text("Other…").tag(Self.other)
            }
            .fixedSize()
        }
    }

    private func label(of app: String) -> String {
        guard Apps.isInstalled(app) else {
            return Apps.app(for: app) == nil ? "“\(app)” (not found)" : app
        }
        let name = Apps.name(ofApp: app)
        return role == .terminal && !model.launcher.canOpenWindows(in: app) ? "\(name) (can't open windows yet)" : name
    }

    /// What to know about the chosen app, or about the one chosen without a setting.
    private func note(for app: String?) -> String? {
        switch role {
        case .terminal: terminalNote(for: app)
        case .editor: nil
        case .browser: browserNote(for: app ?? model.launcher.automaticApp(.browser))
        }
    }

    /// What to know about the browser `app`: whether it opens a window of its own.
    private func browserNote(for app: String?) -> String? {
        guard let app, Apps.isInstalled(app), !model.launcher.canOpenWindows(inBrowser: app) else { return nil }
        return "\(Apps.name(ofApp: app)) can't be asked for a new window, so a dev server's page opens as a link would."
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
    var title: String {
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

    static let restore = Restore(
        keeps: "Your projects and folders with projects stay.",
        isDone: { config in
            config.activeDays == SettingsModel.defaults.activeDays && config.zoxide == SettingsModel.defaults.zoxide
        },
        apply: { config in
            config.activeDays = SettingsModel.defaults.activeDays
            config.zoxide = SettingsModel.defaults.zoxide
        })

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
                let found = model.launcher.foundProjects()
                List(found) { project in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(project.name)
                            Text((project.path as NSString).abbreviatingWithTildeInPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .truncationMode(.head)
                        }
                        .help(project.path)
                        Spacer()
                        Button("Always List") {
                            model.change { $0.projects.append(Project(path: project.path)) }
                        }
                    }
                }
                .frame(height: 150)
                .overlay {
                    if found.isEmpty {
                        Text("None yet").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Found by the launcher")
                Text(
                    "Listed while you work in them: from your sessions, the launcher, zoxide and the folders below. Always List keeps one listed."
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
                SettingRow(
                    title: "Keep a project listed for", note: "After its last commit, changed file or use.",
                    isDefault: model.isDefault(\.activeDays), defaultValue: "\(SettingsModel.defaults.activeDays) days",
                    reset: { model.reset(\.activeDays) }
                ) {
                    Text("\(config.activeDays) days").monospacedDigit()
                    Stepper(
                        "Days", value: model.binding(\.activeDays), in: LauncherConfigFile.minimumActiveDays...3650)
                }
            } header: {
                Text("Folders with projects")
                Text("Their subfolders are listed while you work in them, and found by a search after that.")
            }
            Section {
                let hasZoxide = Zoxide.executable() != nil
                SettingRow(
                    title: "Use zoxide's folders",
                    note: hasZoxide
                        ? "Also list the folders you visit most with zoxide. Its data is only read."
                        : "zoxide is not installed, so this has no effect.",
                    isDefault: model.isDefault(\.zoxide), defaultValue: SettingsModel.defaults.zoxide ? "On" : "Off",
                    reset: { model.reset(\.zoxide) }
                ) {
                    Toggle("Use zoxide's folders", isOn: model.binding(\.zoxide)).toggleStyle(.switch)
                        .disabled(!hasZoxide)
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

// MARK: Advanced

/// Where the settings are kept, and the way to edit them as text.
private struct AdvancedSettings: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button("Edit as Text…") { model.openFile() }
                } label: {
                    Text("Settings file")
                    Text(LauncherController.settingsFileForDisplay)
                }
            } footer: {
                Text(
                    "The settings in this window are kept in this file, which you can also edit by hand or keep in your dotfiles. The window keeps your comments and follows the changes you save."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
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

    static let restore = Restore(
        isDone: { $0.windows == SettingsModel.defaults.windows },
        apply: { $0.windows = SettingsModel.defaults.windows })

    var body: some View {
        let layout = model.config.windows
        Form {
            Section {
                SettingRow(
                    title: "Place new windows in columns",
                    note:
                        "Every screen is split into columns, and a window the launcher opens takes a free one, nearest you first. Off, each app places its windows.",
                    isDefault: (layout != nil) == (SettingsModel.defaults.windows != nil), defaultValue: "On",
                    reset: { model.change { $0.windows = $0.windows ?? WindowLayout() } }
                ) {
                    Toggle(
                        "Place new windows in columns",
                        isOn: Binding(
                            get: { layout != nil },
                            set: { isOn in model.change { $0.windows = isOn ? $0.windows ?? WindowLayout() : nil } })
                    )
                    .toggleStyle(.switch)
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
                    SettingRow(
                        title: "Gap around and between windows", isDefault: layout.gap == WindowLayout().gap,
                        defaultValue: "\(WindowLayout().gap.formatted()) points", reset: { reset(\.gap) }
                    ) {
                        Text("\(layout.gap.formatted()) points").monospacedDigit()
                        Stepper("Gap", value: binding(\.gap), in: LauncherConfigFile.gapRange, step: 1)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func columns(_ title: String, _ setting: WritableKeyPath<WindowLayout, Int>, _ layout: WindowLayout)
        -> some View
    {
        let reset = { self.reset(setting) }
        return SettingRow(
            title: title, isDefault: layout[keyPath: setting] == WindowLayout()[keyPath: setting],
            defaultValue: Self.columns(WindowLayout()[keyPath: setting]), reset: reset
        ) {
            Text(Self.columns(layout[keyPath: setting])).monospacedDigit()
            Stepper(title, value: binding(setting), in: LauncherConfigFile.columnRange)
        }
    }

    private static func columns(_ count: Int) -> String {
        "\(count) \(count == 1 ? "column" : "columns")"
    }

    private func reset<Value>(_ setting: WritableKeyPath<WindowLayout, Value>) {
        binding(setting).wrappedValue = WindowLayout()[keyPath: setting]
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
