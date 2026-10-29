import SwiftUI

@main
struct PlaincontrolApp: App {
    @State private var store: SessionStore
    @State private var launcher: LauncherController
    @State private var settings: SettingsModel
    @State private var updater = Updater()
    private let hotkey: LauncherHotkey
    private let welcome: WelcomeWindow

    init() {
        let store = SessionStore()
        store.start()
        let launcher = LauncherController { store.registry.sessions.values.map(\.self) }
        store.onSessionStart = { folder, terminal in launcher.sessionStarted(in: folder, at: terminal) }
        hotkey = LauncherHotkey(holdKey: { launcher.holdKey }, onHold: { launcher.show() })
        let welcome = WelcomeWindow(store: store, launcher: launcher)
        self.welcome = welcome
        // On a first start the welcome window asks for Accessibility, after saying what it is for.
        let isFirstStart = WelcomeWindow.opensByItself(launcher: launcher)
        hotkey.start(asking: !isFirstStart)
        if isFirstStart {
            DispatchQueue.main.async { welcome.show() }
        }
        _store = State(initialValue: store)
        _launcher = State(initialValue: launcher)
        _settings = State(initialValue: SettingsModel(launcher: launcher))
    }

    var body: some Scene {
        MenuBarExtra {
            SessionMenu(store: store, launcher: launcher, welcome: welcome, updater: updater)
        } label: {
            MenuBarLabel(store: store)
        }
        Settings {
            SettingsView(model: settings, updater: updater)
        }
    }
}
