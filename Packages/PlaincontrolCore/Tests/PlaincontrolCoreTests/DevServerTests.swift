import Foundation
import Testing

@testable import PlaincontrolCore

@Suite struct DevServerTests {
    func package(_ json: String) -> Data { Data(json.utf8) }

    @Test func prefersTheMakefileDevTarget() {
        let makefile = "help:\n\t@grep -E '^[a-z]+:' Makefile\n\ndev:              ## live reload\n\tpnpm astro dev\n"
        let command = DevServer.command(
            makefile: makefile, packageJSON: package(#"{"scripts": {"dev": "astro dev"}}"#), files: ["pnpm-lock.yaml"])
        #expect(command == "make dev")
    }

    @Test func runsThePackageDevScriptWithTheNamedPackageManager() {
        let json = package(#"{"packageManager": "pnpm@10.0.0+sha512.abc", "scripts": {"dev": "next dev"}}"#)
        // A stray npm lockfile does not outweigh the field.
        #expect(DevServer.command(makefile: nil, packageJSON: json, files: ["package-lock.json"]) == "pnpm run dev")
    }

    @Test func fallsBackToMakeRunThenCompose() {
        let makefile = "run:\n\tgo run ./cmd/server\n"
        let json = package(#"{"scripts": {"dev": "vite"}}"#)
        #expect(DevServer.command(makefile: makefile, packageJSON: json, files: ["compose.yaml"]) == "npm run dev")
        #expect(DevServer.command(makefile: makefile, packageJSON: nil, files: ["compose.yaml"]) == "make run")
        let compose = DevServer.command(makefile: nil, packageJSON: nil, files: ["docker-compose.yml"])
        #expect(compose == "docker compose up --build")
    }

    @Test func leavesOutTheStartScript() {
        let json = package(#"{"scripts": {"start": "node build/index.js"}}"#)
        #expect(DevServer.command(makefile: nil, packageJSON: json, files: ["package-lock.json"]) == nil)
    }

    @Test func takesThePackageManagerFromTheLockfile() {
        #expect(DevServer.packageManager(named: nil, files: ["yarn.lock"]) == "yarn")
        #expect(DevServer.packageManager(named: nil, files: ["bun.lockb"]) == "bun")
        #expect(DevServer.packageManager(named: nil, files: ["pnpm-lock.yaml"]) == "pnpm")
        #expect(DevServer.packageManager(named: nil, files: []) == "npm")
        #expect(DevServer.packageManager(named: "deno@2", files: ["yarn.lock"]) == "yarn")
    }

    @Test func findsNothingWithoutADevTargetOrScript() {
        let makefile = "build:\n\tswift build\n.PHONY: dev\n"
        let json = package(#"{"scripts": {"build": "vite build"}}"#)
        #expect(DevServer.command(makefile: makefile, packageJSON: json, files: []) == nil)
        #expect(DevServer.command(makefile: nil, packageJSON: package("not json"), files: []) == nil)
        #expect(DevServer.command(makefile: nil, packageJSON: nil, files: []) == nil)
    }

    @Test func readsTargetsButNotVariablesOrRecipes() {
        let makefile = """
            PORT := 4321
            dev := yes
            URL = http://localhost:4321
            serve dev: install
            check:: lint
            \techo "deploy: later"
            # test: commented out
            """
        #expect(DevServer.targets(in: makefile) == ["serve", "dev", "check"])
    }

    @Test func takesThePortTheDevScriptNames() {
        func port(_ script: String, command: String? = "pnpm run dev") -> Int? {
            DevServer.port(command: command, packageJSON: package(#"{"scripts": {"dev": "\#(script)"}}"#))
        }
        #expect(port("infisical run -- next dev -p 3210") == 3210)
        #expect(port("rimraf .next && next dev --port 3458") == 3458)
        #expect(port("vite --port=5180") == 5180)
        #expect(port("PORT=4000 node server.js") == 4000)
        #expect(port("next dev") == 3000)
        #expect(port("astro dev") == 4321)
        #expect(port("./node_modules/.bin/vite") == 5173)
        #expect(port("node server.js") == nil)
        #expect(port("next dev -p next") == 3000)
    }

    @Test func takesThePortOfTheCommandFirst() {
        let json = package(#"{"scripts": {"dev": "next dev"}}"#)
        #expect(DevServer.port(command: "uv run fastapi dev --port 8000", packageJSON: json) == 8000)
        #expect(DevServer.port(command: "uv run fastapi dev", packageJSON: nil) == nil)
        #expect(DevServer.port(command: "make dev", packageJSON: json) == 3000)
    }

    @Test func waitsForThePortToListen() async {
        let looks = Counter()
        #expect(await DevServer.waitUntilListening(on: 3000, interval: .zero) { _ in looks.next() >= 2 })
        #expect(looks.count == 3)
        #expect(!(await DevServer.waitUntilListening(on: 3000, attempts: 3, interval: .zero) { _ in false }))
    }

    @Test func seesAPortThatListens() throws {
        #expect(!DevServer.isListening(on: 1))
    }

    /// Counts calls across the concurrent closures of a test.
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        var count: Int { lock.withLock { value } }

        /// The count before this call.
        func next() -> Int {
            lock.withLock {
                defer { value += 1 }
                return value
            }
        }
    }

    @Test func asksBrowsersThatCanForANewWindow() {
        let url = URL(string: "http://localhost:3210")!
        #expect(BrowserWindow.arguments(opening: url, in: "com.google.Chrome") == ["--new-window", url.absoluteString])
        #expect(BrowserWindow.arguments(opening: url, in: "com.google.Chrome.canary") != nil)
        #expect(
            BrowserWindow.arguments(opening: url, in: "org.mozilla.firefox") == ["-new-window", url.absoluteString])
        #expect(BrowserWindow.arguments(in: "com.google.Chrome") == ["--new-window"])
        #expect(BrowserWindow.arguments(opening: url, in: "com.apple.Safari") == nil)
        #expect(BrowserWindow.arguments(opening: url, in: "com.google.chromecast") == nil)
    }

    @Test func readsTheProjectFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(DevServer.command(in: folder.path) == nil)
        try Data(#"{"scripts": {"dev": "vite"}}"#.utf8).write(to: folder.appending(path: "package.json"))
        try Data().write(to: folder.appending(path: "bun.lock"))
        #expect(DevServer.command(in: folder.path) == "bun run dev")
        try "dev:\n\tbun run dev\n".write(to: folder.appending(path: "Makefile"), atomically: true, encoding: .utf8)
        #expect(DevServer.command(in: folder.path) == "make dev")
    }
}
