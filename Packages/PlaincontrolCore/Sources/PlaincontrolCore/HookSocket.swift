import Foundation

/// Where the app listens for hook events, and where the hook command sends them.
public enum HookSocket {
    /// Overrides the socket path, for development builds and tests.
    public static let environmentVariable = "PLAINCONTROL_SOCKET"

    /// The name of the app's folder in Application Support, per build.
    public static let releaseAppName = "Plaincontrol"
    public static let developmentAppName = "Plaincontrol Dev"

    /// `~/Library/Application Support/<appName>/hooks.sock`.
    public static func defaultPath(appName: String = releaseAppName) -> String {
        URL.applicationSupportDirectory
            .appending(path: appName, directoryHint: .isDirectory)
            .appending(path: "hooks.sock")
            .path(percentEncoded: false)
    }

    /// The path from ``environmentVariable`` when it is set, and the default path otherwise.
    public static func path(environment: [String: String], appName: String = releaseAppName) -> String {
        if let path = environment[environmentVariable], !path.isEmpty { return path }
        return defaultPath(appName: appName)
    }
}
