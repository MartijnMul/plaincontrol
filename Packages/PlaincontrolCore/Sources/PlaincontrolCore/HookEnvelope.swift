import Foundation

/// What the hook command sends to Plaincontrol for each hook event: the reduced event,
/// where the session runs, and when the hook ran.
///
/// On the wire it is one line of JSON per event.
public struct HookEnvelope: Sendable, Equatable, Codable {
    public var event: HookEvent
    public var terminal: TerminalLocation?
    public var sentAt: Date

    public init(event: HookEvent, terminal: TerminalLocation?, sentAt: Date) {
        self.event = event
        self.terminal = terminal
        self.sentAt = sentAt
    }

    private enum CodingKeys: String, CodingKey {
        case event
        case terminal
        case sentAt = "sent_at"
    }

    /// The envelope as one line of JSON, ending in a newline.
    public func line() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self) + [0x0A]
    }

    /// Decodes one line of JSON, with or without its newline.
    public static func decode(line: Data) throws -> HookEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(HookEnvelope.self, from: line)
    }
}
