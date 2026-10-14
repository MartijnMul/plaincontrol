import PlaincontrolCore
import SwiftUI

@main
struct PlaincontrolApp: App {
    var body: some Scene {
        MenuBarExtra("Plaincontrol", systemImage: "rectangle.stack") {
            Text("No sessions yet")
            Divider()
            Button("Quit Plaincontrol") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
