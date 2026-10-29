import AppKit
import Combine
import PlaincontrolCore
import ServiceManagement
import SwiftUI

/// The window that walks a new user through setting Plaincontrol up: the Accessibility
/// permission, the Claude Code plugin, the projects from Claude Code's own history, and a first
/// try of the launcher. It opens by itself on the first start, and from the menu after that.
@MainActor
final class WelcomeWindow {
    private let store: SessionStore
    private let launcher: LauncherController
    private let settings: SettingsModel
    private var window: NSWindow?

    private static let shownKey = "hasShownWelcome"

    /// Whether the window opens by itself: once, on a first start, before the launcher has any
    /// history, so it doesn't greet someone who has used Plaincontrol for a while.
    static func opensByItself(launcher: LauncherController) -> Bool {
        !UserDefaults.standard.bool(forKey: shownKey) && launcher.isNew
    }

    init(store: SessionStore, launcher: LauncherController, settings: SettingsModel) {
        self.store = store
        self.launcher = launcher
        self.settings = settings
    }

    func show() {
        UserDefaults.standard.set(true, forKey: Self.shownKey)
        let window =
            window
            ?? {
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
                    styleMask: [.titled, .closable], backing: .buffered, defer: true)
                window.title = "Welcome to \(AppInfo.name)"
                window.isReleasedWhenClosed = false
                window.contentViewController = NSHostingController(
                    rootView: WelcomeView(store: store, launcher: launcher, settings: settings) { [weak window] in
                        window?.close()
                    })
                window.center()
                return window
            }()
        self.window = window
        // A menu bar app is not in front, and its window would open behind the app that is.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

private struct WelcomeView: View {
    let store: SessionStore
    let launcher: LauncherController
    let settings: SettingsModel
    let close: () -> Void
    @State private var isTrusted = LauncherHotkey.isAllowed
    @State private var projects = Projects.notAdded
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginProblem: String?

    private enum Projects: Equatable {
        case notAdded, adding
        case added(Int)
    }

    static let pluginCommands = """
        /plugin marketplace add MartijnMul/plaincontrol
        /plugin install plaincontrol@plaincontrol
        """

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to \(AppInfo.name)").font(.title2).bold()
                    Text("See which Claude Code session needs you, and open any project from the keyboard.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding([.horizontal, .top], 20)
            Form {
                Step(
                    number: 1, title: "Allow Accessibility", isDone: isTrusted,
                    note:
                        "The launcher needs it to notice its key and to take your typing while it is open. It does not record what you type."
                ) {
                    Button("Allow…") { LauncherHotkey.askForPermission() }
                }
                Step(
                    number: 2, title: "Connect Claude Code", isDone: store.hasHeardFromClaudeCode,
                    doneLabel: "Connected",
                    note:
                        "Install the plugin that reports your sessions: run these two commands in Claude Code. Each session you start after that shows up in the menu."
                ) {
                    Button("Copy Commands") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.pluginCommands, forType: .string)
                    }
                } detail: {
                    // A command broken over two lines is easy to copy wrong by hand.
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Self.pluginCommands.split(separator: "\n"), id: \.self) { command in
                            Text(command).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    // Small enough for both to fit, so neither shrinks on its own.
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                }
                Step(
                    number: 3, title: "Bring in your projects", isDone: projects != .notAdded && projects != .adding,
                    doneLabel: projectsLabel,
                    note: projects == .added(0)
                        ? "Claude Code has no history on this Mac yet, so there was nothing to add. Your projects show up in the launcher as you start sessions in them."
                        : "Add the projects you worked on with Claude Code to the launcher, from Claude Code's own history. Only the names of their folders and the dates of your sessions are read. macOS may ask for access to the folders they are in."
                ) {
                    if projects == .adding {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Add Projects") { addProjects() }
                    }
                } detail: {
                    if Zoxide.executable() != nil {
                        Toggle(
                            "Also list the folders you visit most with zoxide",
                            isOn: settings.binding(\.zoxide)
                        )
                        .toggleStyle(.checkbox)
                        .padding(.top, 4)
                    }
                }
                Step(
                    number: 4, title: "Try the launcher", isDone: launcher.hasOpened, doneLabel: "Done",
                    note:
                        "Hold the \(launcher.holdKey.title) key on its own for a moment. Type to search, then press a project's digit and an action's."
                ) {
                    Button("Open Launcher") { launcher.show() }.disabled(!isTrusted)
                }
                Section {
                    Toggle(
                        "Open \(AppInfo.name) when you log in",
                        isOn: Binding(get: { opensAtLogin }, set: setOpensAtLogin))
                    if let loginProblem {
                        Text(loginProblem).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Text("Getting Started… in the menu opens this window again.").foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(timer) { _ in isTrusted = LauncherHotkey.isAllowed }
    }

    private var projectsLabel: String {
        guard case .added(let count) = projects else { return "Added" }
        return switch count {
        case 0: "None found"
        case 1: "1 project added"
        default: "\(count) projects added"
        }
    }

    private func addProjects() {
        projects = .adding
        Task { projects = .added(await launcher.addClaudeCodeHistory()) }
    }

    private func setOpensAtLogin(_ isOn: Bool) {
        do {
            if isOn { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginProblem =
                SMAppService.mainApp.status == .requiresApproval
                ? "Allow \(AppInfo.name) in System Settings › General › Login Items." : nil
        } catch {
            loginProblem = "Could not change it: \(error.localizedDescription)"
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// A step of setting up: its number, or a check mark once it is done, what it is, and the
/// control that does it.
private struct Step<Control: View, Detail: View>: View {
    let number: Int
    let title: String
    let isDone: Bool
    var doneLabel = "Allowed"
    let note: String
    @ViewBuilder let control: Control
    @ViewBuilder var detail: Detail

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if isDone {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Image(systemName: "\(number).circle").foregroundStyle(.secondary)
                }
            }
            .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).bold()
                Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                detail
            }
            Spacer()
            if isDone {
                Text(doneLabel).foregroundStyle(.secondary)
            } else {
                control
            }
        }
        .padding(.vertical, 4)
    }
}

extension Step where Detail == EmptyView {
    init(
        number: Int, title: String, isDone: Bool, doneLabel: String = "Allowed", note: String,
        @ViewBuilder control: () -> Control
    ) {
        self.init(
            number: number, title: title, isDone: isDone, doneLabel: doneLabel, note: note, control: control,
            detail: { EmptyView() })
    }
}
