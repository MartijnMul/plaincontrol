import Foundation

/// Values for tests that need this Mac's own folders, which never belong in the repository.
///
/// Each value comes from an environment variable named `PLAINCONTROL_TEST_<name>`. `make test`
/// reads them from a `.env` file in the repository root, which git ignores; without a value,
/// the tests that need it are skipped. CONTRIBUTING.md lists the variables.
enum LocalTestData {
    static func value(_ name: String) -> String? {
        let value = ProcessInfo.processInfo.environment["PLAINCONTROL_TEST_\(name)"] ?? ""
        return value.isEmpty ? nil : value
    }

    /// A folder reached through a symbolic link, such as a cloud folder linked from the home
    /// folder, with folders inside.
    static var linkedFolder: String? { value("LINKED_FOLDER") }
}
