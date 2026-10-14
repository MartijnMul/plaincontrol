import SwiftUI

@main
struct PlaincontrolApp: App {
    @State private var store: SessionStore

    init() {
        let store = SessionStore()
        store.start()
        _store = State(initialValue: store)
    }

    var body: some Scene {
        MenuBarExtra {
            SessionMenu(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
    }
}
