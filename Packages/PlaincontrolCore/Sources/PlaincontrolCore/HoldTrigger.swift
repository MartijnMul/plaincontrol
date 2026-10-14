/// Recognises holding one modifier key on its own, such as the right Option key, for a moment.
///
/// A hold only counts when nothing else happens while the key is down: pressing another key
/// or modifier means the user is typing a shortcut, so the hold is cancelled. The caller feeds
/// in the keyboard events, waits ``duration`` after a press starts, and then asks
/// ``holdElapsed(_:)`` whether that press is still going.
public struct HoldTrigger: Sendable {
    /// The virtual key code of the modifier to hold (61 is the right Option key).
    public let keyCode: UInt16
    public let duration: Duration
    /// The press being held, if any.
    private var current: Int?
    private var presses = 0

    public static let rightOption: UInt16 = 61

    public init(keyCode: UInt16 = HoldTrigger.rightOption, duration: Duration = .milliseconds(350)) {
        self.keyCode = keyCode
        self.duration = duration
    }

    /// A modifier key went down or up.
    ///
    /// - Parameters:
    ///   - keyCode: The modifier that changed.
    ///   - isDown: Whether that modifier is now down.
    ///   - othersDown: Whether any other modifier is down.
    /// - Returns: The press that started, to pass to ``holdElapsed(_:)`` after ``duration``.
    public mutating func modifierChanged(keyCode: UInt16, isDown: Bool, othersDown: Bool) -> Int? {
        current = nil
        guard keyCode == self.keyCode, isDown, !othersDown else { return nil }
        presses += 1
        current = presses
        return presses
    }

    /// Any other key went down.
    public mutating func keyPressed() {
        current = nil
    }

    /// Whether `press` has been held without interruption, so the hold should take effect.
    /// A press takes effect at most once.
    public mutating func holdElapsed(_ press: Int) -> Bool {
        guard current == press else { return false }
        current = nil
        return true
    }
}
