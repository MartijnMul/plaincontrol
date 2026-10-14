import AppKit
import PlaincontrolCore

/// Opens the launcher when its hold key, such as the right Option key, is held on its own, in
/// any app.
///
/// It listens through an event tap that only reads, which sees the keys whichever app is in
/// front, Plaincontrol included. A global `NSEvent` monitor would be simpler, but while one is
/// installed, the menu bar menu does not close when the user clicks elsewhere, and swallows the
/// clicks. Like the launcher itself (``LauncherKeyTap``), it needs the Accessibility permission.
@MainActor
final class LauncherHotkey {
    private var trigger = HoldTrigger()
    private var tap: CFMachPort?
    private let holdKey: () -> HoldKey
    private let onHold: () -> Void

    /// - Parameters:
    ///   - holdKey: The key to hold, asked on every key event so a new setting takes effect.
    ///   - onHold: Called when the key has been held on its own.
    init(holdKey: @escaping () -> HoldKey, onHold: @escaping () -> Void) {
        self.holdKey = holdKey
        self.onHold = onHold
    }

    static var isAllowed: Bool { AXIsProcessTrusted() }

    static let accessibilitySettings = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// Starts watching the keyboard, asking for the Accessibility permission first if needed.
    func start() {
        guard tap == nil else { return }
        guard Self.isAllowed else {
            // The value of `kAXTrustedCheckOptionPrompt`, a global Swift 6 cannot read safely.
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            waitForPermission()
            return
        }
        let events: [CGEventType] = [.flagsChanged, .keyDown]
        let mask = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                eventsOfInterest: mask, callback: Self.callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        self.tap = tap
    }

    /// Starts once the user grants the permission in System Settings.
    private func waitForPermission() {
        Task { [weak self] in
            while !Self.isAllowed {
                try? await Task.sleep(for: .seconds(2))
            }
            self?.start()
        }
    }

    /// What the hotkey needs from an event, taken out of it before it crosses to the main actor.
    private struct Input: Sendable {
        var type: CGEventType
        var keyCode: UInt16
        var flags: UInt64

        init(_ type: CGEventType, _ event: CGEvent) {
            self.type = type
            keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            flags = event.flags.rawValue
        }
    }

    private func handle(_ input: Input) {
        switch input.type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            trigger.keyPressed()
        case .flagsChanged:
            let key = holdKey()
            if trigger.keyCode != key.keyCode { trigger = HoldTrigger(keyCode: key.keyCode) }
            // The device-dependent bits tell the right key from the left one.
            let flags = UInt(input.flags)
            let press = trigger.modifierChanged(
                keyCode: input.keyCode,
                isDown: flags & key.deviceFlag != 0,
                othersDown: flags & HoldKey.allDeviceFlags & ~key.deviceFlag != 0
                    || input.flags & CGEventFlags.maskSecondaryFn.rawValue != 0)
            if let press { fire(after: press) }
        default:
            break
        }
    }

    private func fire(after press: Int) {
        Task { [weak self, duration = trigger.duration] in
            try? await Task.sleep(for: duration)
            guard let self, self.trigger.holdElapsed(press) else { return }
            self.onHold()
        }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        if let userInfo {
            let hotkey = Unmanaged<LauncherHotkey>.fromOpaque(userInfo).takeUnretainedValue()
            let input = Input(type, event)
            // The tap's run loop source is on the main run loop.
            MainActor.assumeIsolated { hotkey.handle(input) }
        }
        return Unmanaged.passUnretained(event)
    }
}
