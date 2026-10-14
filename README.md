# Plaincontrol

A native macOS menu bar app for people who run several Claude Code sessions at once. It shows every session at a glance, tells you when one is done or waiting for you, and takes you to the right terminal pane in one click or keystroke, on any Space.

> **Status: early development.** The project builds, but it does not do anything useful yet. Watch the repository to follow along.

## What it will do

- **Sessions at a glance**: a menu bar icon with a badge for the sessions waiting on you, and a list of every session with its project, branch, status and how long it has been in that status.
- **Never miss a question**: a native notification when a session finishes or asks for input or permission.
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

`make help` lists all commands. `make check` runs the format check, the tests and the build. The Xcode project is generated from `project.yml`; run `make open` to work in Xcode.

```
App/                        SwiftUI app: menu bar, windows, settings
Packages/PlaincontrolCore/  Sessions, hook events and terminal control, with tests
project.yml                 XcodeGen project definition
```

## License

[Apache License 2.0](LICENSE).

Plaincontrol is an independent project. It is not affiliated with or endorsed by Anthropic. Claude and Claude Code are trademarks of Anthropic.
