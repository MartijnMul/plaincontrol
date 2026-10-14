# Plaincontrol

A native macOS menu bar app for people who run several Claude Code sessions at once. It shows every session at a glance, tells you when one is done or waiting for you, and takes you to the right terminal pane in one click or keystroke, on any Space.

> **Status: early development.** The session list, notifications and jumping to iTerm2 panes work; there are no releases yet. Watch the repository to follow along.

## What it will do

- **Sessions at a glance**: a menu bar icon with a badge for the sessions waiting on you, and a list of every session with its project, branch, status and how long it has been in that status.
- **Never miss a question**: a native notification when a session finishes or asks for input or permission, unless you respond within a few seconds.
- **Jump to it**: click a session, or press a global hotkey for the next one waiting, and the right window and pane come to the front.
- **Start a project in one click**: worktree, dev server and Claude Code, in your saved layout.

## How it works

Claude Code reports what each session is doing through [hooks](https://code.claude.com/docs/en/hooks). A small script passes those events to Plaincontrol over a local Unix socket. Plaincontrol keeps track of every session and drives your terminal to bring the right pane forward. iTerm2 is supported first.

## Privacy

Plaincontrol runs entirely on your Mac. It opens no network port and sends nothing anywhere. Hook events can contain your prompts and file paths: Plaincontrol keeps only what it needs to show a session's status, and never stores or logs prompt text.

## Building from source

Requirements: macOS 27 and Xcode 27, plus [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/MartijnMul/plaincontrol.git
cd plaincontrol
make run
```

`make help` lists all commands. The Xcode project is generated from `project.yml`; run `make open` to work in Xcode.

Builds are signed ad hoc, which is enough to run them on your own Mac. macOS asks again for permissions such as controlling your terminal after every rebuild, because an ad-hoc signature changes each time. To keep them, sign with your own certificate: create `Config/Local.xcconfig` (ignored by git) as described in `Config/Signing.xcconfig`.

```
App/                        SwiftUI app: menu bar, windows, settings
Packages/PlaincontrolCore/  Sessions, hook events and the local socket, with tests
  Sources/plaincontrol-hook The command Claude Code runs for each hook event
plugin/                     The Claude Code plugin that installs the hooks
dev/                        Scenarios for trying the app without Claude Code
Config/                     Build settings, such as code signing
project.yml                 XcodeGen project definition
```

## Development

Nothing needs to be installed in your Claude Code configuration to work on Plaincontrol. The development build is a separate app, **Plaincontrol Dev**, with its own socket, so it runs next to a release build without either one noticing the other.

There are three loops, from fastest to most real:

1. **Logic**: `make test` runs the core tests in seconds. Status rules, decoding and the socket live in the core, so most changes start here.
2. **The app without Claude Code**: `make run` starts Plaincontrol Dev, and `make simulate` plays a scenario of hook events into it, from `dev/scenarios/`: `SCENARIO=sessions` (several at once), `permission`, `question`, or `quick-answer` (answered within the notification grace period, so no notification should appear). Repeatable, and no need to make Claude ask for a permission.
3. **With Claude Code**: `make dev-claude` starts a Claude Code session with the plugin from this repository loaded for that session only (`claude --plugin-dir plugin`). Only that session reports to Plaincontrol Dev; your other sessions are not affected.

`make check` runs the format check, the tests and the build. Run it before every commit.

## License

[Apache License 2.0](LICENSE).

Plaincontrol is an independent project. It is not affiliated with or endorsed by Anthropic. Claude and Claude Code are trademarks of Anthropic.
