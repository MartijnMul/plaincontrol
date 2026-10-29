import Foundation
import PlaincontrolHooks

// The command Claude Code runs for every hook event. It reads the event from stdin, keeps
// only the fields Plaincontrol needs, adds where the session runs and which Claude Code
// process it runs in, and sends it to the app.
//
// It always exits 0 and stays silent: a hook must never block or slow down Claude Code,
// whether or not Plaincontrol is running. Set PLAINCONTROL_DEBUG=1 to see errors on stderr.

let environment = ProcessInfo.processInfo.environment

do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let event = try JSONDecoder().decode(HookEvent.self, from: input)
    let process = SessionProcess(environment: environment)
    var terminal = TerminalLocation(environment: environment)
    terminal?.tty = process?.terminalDevice
    let envelope = HookEnvelope(event: event, terminal: terminal, process: process, sentAt: .now)
    try HookClient.send(envelope, to: HookSocket.path(environment: environment))
} catch {
    if environment["PLAINCONTROL_DEBUG"] == "1" {
        FileHandle.standardError.write(Data("plaincontrol-hook: \(error)\n".utf8))
    }
}
exit(0)
