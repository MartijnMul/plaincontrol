import PlaincontrolCore
import SwiftUI

/// The menu that opens from the menu bar icon.
struct SessionMenu: View {
    let store: SessionStore
    let launcher: LauncherController
    let welcome: WelcomeWindow
    let updater: Updater
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if let problem = store.problem {
            Text(problem)
            Divider()
        }
        if let jumpProblem = store.jumpProblem {
            Text(jumpProblem)
            Divider()
        }
        if store.sessions.isEmpty {
            Text("No Claude Code sessions")
        } else {
            // Sessions in a terminal Plaincontrol cannot drive yet are shown, but disabled.
            ForEach(store.sessions) { session in
                Button("\(session.status.symbol)  \(session.displayName) — \(session.status.label)") {
                    store.jump(to: session.id)
                }
                .disabled(!store.canJump(to: session))
            }
        }
        Divider()
        Button("Open Launcher") {
            launcher.show()
        }
        if !LauncherHotkey.isAllowed {
            Button("Allow Accessibility to Use the Launcher…") {
                NSWorkspace.shared.open(LauncherHotkey.accessibilitySettings)
            }
        }
        Button("Getting Started…") {
            welcome.show()
        }
        Button("Settings…") {
            // A menu bar app is not in front, and its window would open behind the app that is.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        if let version = updater.readyVersion {
            Button("Restart to Update to \(version)") {
                updater.restartToUpdate()
            }
        } else if updater.isAvailable {
            Button("Check for Updates…") {
                NSApp.activate()
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheck)
        }
        Divider()
        Button("Quit \(AppInfo.name)") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

/// The menu bar icon: four lamps, unlit until a session waits for the user, then one lit and
/// the number of sessions waiting beside them.
struct MenuBarLabel: View {
    let store: SessionStore
    let updater: Updater

    var body: some View {
        let waiting = store.waitingCount
        let hasUpdate = updater.readyVersion != nil
        if waiting > 0 {
            Label {
                Text("\(waiting)")
            } icon: {
                icon("MenuBarWaiting", dot: hasUpdate)
            }
            .labelStyle(.titleAndIcon)
        } else {
            icon("MenuBarQuiet", dot: hasUpdate)
        }
    }

    /// The icon named `name`, with a dot at its top right while an update waits to install.
    private func icon(_ name: String, dot: Bool) -> Image {
        guard dot, let base = NSImage(named: name) else { return Image(name) }
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            let size = rect.height * 0.38
            let dot = NSRect(x: rect.maxX - size, y: rect.maxY - size, width: size, height: size)
            // A clear ring sets the dot apart from the icon under it.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        // A template, so the menu bar draws the icon and the dot in its own colour.
        image.isTemplate = true
        return Image(nsImage: image)
    }
}

extension Session {
    /// The session's title when it has one, and otherwise the name of its folder.
    var displayName: String {
        if let title, !title.isEmpty { return title }
        if let cwd { return URL(filePath: cwd).lastPathComponent }
        return "Session \(id.prefix(8))"
    }
}

extension SessionStatus {
    var label: String {
        switch self {
        case .working: "Working"
        case .waiting(.permission): "Needs permission"
        case .waiting(.question): "Has a question"
        case .waiting(.planApproval): "Plan to review"
        case .waiting(.input): "Needs input"
        case .idle: "Idle"
        case .gone: "Ended"
        }
    }

    var symbol: String {
        switch self {
        case .waiting: "●"
        case .working: "◐"
        case .idle, .gone: "○"
        }
    }
}
