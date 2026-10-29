import Foundation

/// Opens a page in a new window of a browser, rather than in a tab of a window it has open.
///
/// Browsers built on Chromium and Firefox take the page and a flag on their command line. A
/// running one gets them from the new instance started with them, which hands them over and
/// quits, so it needs no permission. Other browsers have no such flag.
public enum BrowserWindow {
    /// The arguments that open `url` in a new window of the browser with `bundleIdentifier`, or
    /// nil when it takes none.
    public static func arguments(opening url: URL, in bundleIdentifier: String) -> [String]? {
        let id = bundleIdentifier.lowercased()
        if chromium.contains(where: { id == $0 || id.hasPrefix("\($0).") }) {
            return ["--new-window", url.absoluteString]
        }
        if id.hasPrefix("org.mozilla.") {
            return ["-new-window", url.absoluteString]
        }
        return nil
    }

    /// Browsers built on Chromium, by bundle identifier; their beta, dev and canary builds add
    /// a part to it.
    static let chromium = [
        "com.google.chrome", "org.chromium.chromium", "com.brave.browser", "com.microsoft.edgemac",
        "com.vivaldi.vivaldi", "com.operasoftware.opera",
    ]
}
