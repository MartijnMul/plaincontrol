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
