import AppKit
import PlaincontrolCore

/// Takes the keyboard while the launcher is open, whichever app is in front.
///
/// The launcher's panel does not activate the app, and macOS keeps sending keys to the app in
/// front, so the panel never sees them. An event tap sees every key before any app does: keys
/// without Command or Control go to the launcher and no further, so they never land in the
/// terminal behind it. A click anywhere closes the launcher. Needs the Accessibility permission.
@MainActor
final class LauncherKeyTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let onKey: (Launcher.Key, _ isRepeat: Bool) -> Void
    private let onClick: () -> Void

    /// - Parameter onKey: Called with each key the launcher takes, and whether it repeats because it is held.
    init(onKey: @escaping (Launcher.Key, _ isRepeat: Bool) -> Void, onClick: @escaping () -> Void) {
        self.onKey = onKey
        self.onClick = onClick
    }

    /// Starts taking keys, and returns false when macOS does not allow it.
    func start() -> Bool {
        guard tap == nil else { return true }
        let events: [CGEventType] = [.keyDown, .keyUp, .leftMouseDown, .rightMouseDown]
        let mask = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: mask, callback: Self.callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
    }

    /// What the tap needs from an event, taken out of it before it crosses to the main actor.
    private struct Input: Sendable {
        var type: CGEventType
        var keyCode: UInt16
        var characters: String?
        var isShortcut: Bool
        var isRepeat: Bool

        init(_ type: CGEventType, _ event: CGEvent) {
            self.type = type
            keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            characters = type == .keyDown ? NSEvent(cgEvent: event)?.charactersIgnoringModifiers : nil
            isShortcut = event.flags.contains(.maskCommand) || event.flags.contains(.maskControl)
            isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        }
    }

    /// Whether the event is the launcher's, and should go no further.
    private func handle(_ input: Input) -> Bool {
        switch input.type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .leftMouseDown, .rightMouseDown:
            onClick()
            return false
        case .keyDown, .keyUp:
            guard !input.isShortcut else { return false }
            if input.type == .keyDown, let key = Launcher.Key(keyCode: input.keyCode, characters: input.characters) {
                onKey(key, input.isRepeat)
            }
            return true
        default:
            return false
        }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let keyTap = Unmanaged<LauncherKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
        let input = Input(type, event)
        // The tap's run loop source is on the main run loop.
        let swallow = MainActor.assumeIsolated { keyTap.handle(input) }
        return swallow ? nil : Unmanaged.passUnretained(event)
    }
}
