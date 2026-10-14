import Foundation

/// Runs AppleScript in the current process, so macOS asks the user once for permission to
/// control each app, in the name of the app that runs it.
public enum AppleScript {
    /// The app did not allow Apple events from Plaincontrol (`errAEEventNotPermitted`).
    static let notPermitted = -1743
    /// Asking the user for permission would be needed, but was not allowed.
    static let wouldRequireConsent = -1744

    /// Runs `source` and returns its result as text, or an empty string when it has none.
    @MainActor
    public static func run(_ source: String) throws(TerminalControlError) -> String {
        guard let script = NSAppleScript(source: source) else {
            throw .failed("The script could not be compiled.")
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = errorInfo[NSAppleScript.errorNumber] as? Int
            if number == notPermitted || number == wouldRequireConsent {
                throw .notAuthorized
            }
            let message = errorInfo[NSAppleScript.errorMessage] as? String
            throw .failed(message ?? "AppleScript error \(number ?? 0)")
        }
        return result.stringValue ?? ""
    }
}
