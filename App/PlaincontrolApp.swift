import SwiftUI

@main
struct PlaincontrolApp: App {
    @State private var store: SessionStore
    @State private var launcher: LauncherController
    private let hotkey: LauncherHotkey

    init() {
        let store = SessionStore()
        store.start()
        let launcher = LauncherController { store.registry.sessions.values.map(\.self) }
        store.onSessionStart = { folder in launcher.sessionStarted(in: folder) }
        hotkey = LauncherHotkey(holdKey: { launcher.holdKey }, onHold: { launcher.show() })
        hotkey.start()
        _store = State(initialValue: store)
        _launcher = State(initialValue: launcher)
    }

    var body: some Scene {
        MenuBarExtra {
            SessionMenu(store: store, launcher: launcher)
        } label: {
            MenuBarLabel(store: store)
        }
    }
}
