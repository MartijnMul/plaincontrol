import AppKit
import SwiftUI

/// A floating panel over every app and Space, which never takes the focus from the app in
/// front; ``LauncherKeyTap`` brings it the keys.
final class LauncherPanel: NSPanel {
    init(content: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        // The window is transparent; the SwiftUI view draws the card and its shadow.
        contentView = NSHostingView(rootView: content)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    /// Shows the panel near the top of the screen with the mouse pointer.
    func present() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            setFrameTopLeftPoint(
                NSPoint(x: visible.midX - frame.width / 2, y: visible.maxY - visible.height * 0.18))
        }
        orderFrontRegardless()
    }
}
