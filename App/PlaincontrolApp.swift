import SwiftUI

@main
struct PlaincontrolApp: App {
    @State private var store: SessionStore
    @State private var launcher: LauncherController
    @State private var settings: SettingsModel
    @State private var updater = Updater()
    private let hotkey: LauncherHotkey

    init() {
        let store = SessionStore()
        store.start()
        let launcher = LauncherController { store.registry.sessions.values.map(\.self) }
        store.onSessionStart = { folder, terminal in launcher.sessionStarted(in: folder, at: terminal) }
        hotkey = LauncherHotkey(holdKey: { launcher.holdKey }, onHold: { launcher.show() })
        hotkey.start()
        _store = State(initialValue: store)
        _launcher = State(initialValue: launcher)
        _settings = State(initialValue: SettingsModel(launcher: launcher))
    }

    var body: some Scene {
        MenuBarExtra {
            SessionMenu(store: store, launcher: launcher, updater: updater)
        } label: {
            MenuBarLabel(store: store)
        }
        Settings {
            SettingsView(model: settings, updater: updater)
        }
    }
}
