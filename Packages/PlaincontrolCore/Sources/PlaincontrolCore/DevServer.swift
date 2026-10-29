import Foundation

/// Finds the command that starts a project's development server, from what the project itself
/// declares, so it works for any framework.
///
/// A `dev` target in the makefile comes first, as a project with one usually wraps the rest in
/// it: `make dev`. Then a `dev` script in `package.json`, run with the project's package
/// manager: the one its `packageManager` field names, or else the one its lockfile belongs to,
/// or else npm. Then a `run` target in the makefile, and last a Compose file, as a project with
/// anything else usually runs only its services, such as a database, in Compose.
///
/// A `start` script is left out on purpose: it often runs a built server, or one that talks
/// over its standard input, such as an MCP server, rather than one to develop with.
public enum DevServer {
    /// The command that starts the development server of the project in `folder`, if it has one.
    public static func command(in folder: String) -> String? {
        let url = URL(filePath: folder, directoryHint: .isDirectory)
        // The makefile GNU make reads, in its order.
        let makefile = ["GNUmakefile", "makefile", "Makefile"].lazy
            .compactMap { try? String(contentsOf: url.appending(path: $0), encoding: .utf8) }
            .first
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder)).map(Set.init) ?? []
        return command(
            makefile: makefile, packageJSON: try? Data(contentsOf: url.appending(path: "package.json")), files: files)
    }

    /// The port the development server of the project in `folder` listens on, to open its page:
    /// one that `command` or the `dev` script in `package.json` names, such as `next dev -p
    /// 3210`, or else the default port of the framework the script runs.
    public static func port(in folder: String, command: String?) -> Int? {
        let url = URL(filePath: folder, directoryHint: .isDirectory).appending(path: "package.json")
        return port(command: command, packageJSON: try? Data(contentsOf: url))
    }

    static func port(command: String?, packageJSON: Data?) -> Int? {
        let script = packageJSON.flatMap { try? JSONDecoder().decode(Package.self, from: $0) }?.scripts?["dev"]
        let words = [command, script].compactMap { $0?.split(whereSeparator: \.isWhitespace).map(String.init) }
        for words in words {
            if let port = namedPort(in: words) { return port }
        }
        for words in words {
            if let port = words.lazy.compactMap({ defaultPorts[($0 as NSString).lastPathComponent] }).first {
                return port
            }
        }
        return nil
    }

    /// The port a command names: `-p 3210`, `--port 3210`, `--port=3210` or `PORT=3210`.
    static func namedPort(in words: [String]) -> Int? {
        for (index, word) in words.enumerated() {
            let value: Substring?
            if ["-p", "--port"].contains(word) {
                value = words.indices.contains(index + 1) ? words[index + 1][...] : nil
            } else if let equals = word.firstIndex(of: "="), ["-p", "--port", "PORT"].contains(word[..<equals]) {
                value = word[word.index(after: equals)...]
            } else {
                value = nil
            }
            if let port = value.flatMap({ Int($0) }), (1...65535).contains(port) { return port }
        }
        return nil
    }

    /// The ports frameworks' dev servers take by default, by the command that starts them.
    static let defaultPorts = [
        "next": 3000, "nuxt": 3000, "nuxi": 3000, "vite": 5173, "react-router": 5173, "astro": 4321, "ng": 4200,
    ]

    /// Waits until something on this Mac listens on `port`, and says whether it did in time.
    public static func waitUntilListening(
        on port: Int, attempts: Int = 240, interval: Duration = .milliseconds(500),
        isListening: @Sendable (Int) -> Bool = isListening(on:)
    ) async -> Bool {
        for attempt in 0..<attempts {
            if attempt > 0 {
                do { try await Task.sleep(for: interval) } catch { return false }
            }
            if isListening(port) { return true }
        }
        return false
    }

    /// Whether something on this Mac accepts connections on `port`, over IPv4 or IPv6.
    public static func isListening(on port: Int) -> Bool {
        ["127.0.0.1", "::1"].contains { connects(to: $0, port: port) }
    }

    private static func connects(to host: String, port: Int) -> Bool {
        var hints = addrinfo()
        hints.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &result) == 0, let address = result?.pointee else { return false }
        defer { freeaddrinfo(result) }
        let socket = Darwin.socket(address.ai_family, address.ai_socktype, address.ai_protocol)
        guard socket >= 0 else { return false }
        defer { close(socket) }
        return connect(socket, address.ai_addr, address.ai_addrlen) == 0
    }

    /// The Compose files Docker Compose looks for, in its order.
    static let composeFiles = ["compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml"]

    /// The command for a project with this makefile, `package.json` and files in its folder.
    static func command(makefile: String?, packageJSON: Data?, files: Set<String>) -> String? {
        let targets = makefile.map(targets(in:)) ?? []
        if targets.contains("dev") { return "make dev" }
        if let packageJSON, let package = try? JSONDecoder().decode(Package.self, from: packageJSON),
            package.scripts?["dev"] != nil
        {
            return "\(packageManager(named: package.packageManager, files: files)) run dev"
        }
        if targets.contains("run") { return "make run" }
        if composeFiles.contains(where: files.contains) { return "docker compose up --build" }
        return nil
    }

    /// The targets a makefile defines in rules of its own, such as `dev` in `dev: install`.
    static func targets(in makefile: String) -> Set<String> {
        var targets = Set<String>()
        for line in makefile.split(whereSeparator: \.isNewline) {
            // Recipes start with a tab.
            guard !line.hasPrefix("\t"), !line.hasPrefix("#"), let colon = line.firstIndex(of: ":") else { continue }
            let names = line[..<colon]
            let rest = line[line.index(after: colon)...]
            // `dev := …` and `dev ::= …` set variables; `dev = a:b` too.
            guard !names.contains("="), !rest.hasPrefix("="), !rest.hasPrefix(":=") else { continue }
            targets.formUnion(names.split(whereSeparator: \.isWhitespace).map(String.init))
        }
        return targets
    }

    /// The package manager the project uses: the one `packageManager` names, such as
    /// `pnpm@10.0.0`, or the one whose lockfile is in `files`, or else npm.
    static func packageManager(named field: String?, files: Set<String>) -> String {
        let known = ["pnpm", "yarn", "bun", "npm"]
        if let name = field?.split(separator: "@").first.map(String.init), known.contains(name) { return name }
        let lockfiles = [
            ("pnpm-lock.yaml", "pnpm"), ("bun.lock", "bun"), ("bun.lockb", "bun"), ("yarn.lock", "yarn"),
        ]
        return lockfiles.first { files.contains($0.0) }?.1 ?? "npm"
    }

    private struct Package: Decodable {
        var packageManager: String?
        var scripts: [String: String]?
    }
}
