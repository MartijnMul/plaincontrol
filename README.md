# Plaincontrol

A native macOS menu bar app for people who run several Claude Code sessions at once. It shows every session at a glance, tells you when one is done or waiting for you, and takes you to the right terminal pane in one click or keystroke, on any Space.

> **Status: early development.** The session list, notifications, jumping to iTerm2 panes and the project launcher work; there are no releases yet. Watch the repository to follow along.

## What it does

- **Sessions at a glance**: a menu bar icon with a badge for the sessions waiting on you, and a list of every session with its status, waiting ones first.
- **Never miss a question**: a native notification when a session finishes or asks for input or permission, unless you respond within a few seconds.
- **Jump to it**: click a session, or its notification, and its iTerm2 window, tab and pane come to the front, on any Space.
- **Projects from the keyboard**: hold the right Option key for a launcher with the projects you work on, and open one in Claude Code (in a terminal or the Claude desktop app), Finder or your editor, or start its dev server, with a single key.

Planned: a hotkey for the next waiting session, terminals other than iTerm2, and starting a project with its worktree and window layout in one go.

## How it works

Claude Code reports what each session is doing through [hooks](https://code.claude.com/docs/en/hooks). A small command that comes with the app passes those events to Plaincontrol over a local Unix socket; the Claude Code plugin in this repository runs it for every event, and does nothing when Plaincontrol isn't installed. Plaincontrol keeps track of every session and drives your terminal to bring the right pane forward. iTerm2 is supported first.

## The launcher

Hold the right Option key on its own for a moment, or choose Open Launcher in the menu. Everything works from the keyboard:

| Key | In the list of projects | In a project |
| --- | --- | --- |
| Type | Search all projects | |
| 1 to 9 | Open the project in that row | Run the action in that row |
| Up, Down | Select a project | Select an action |
| Return, Right | Open the project | Run the action |
| Left | | Back to the list |
| Escape | Clear the search, then close | Back to the list |

Every row shows its digit. An open project offers **1** for Claude Code in a new terminal window in its folder, **2** for a plain terminal window there, **3** for Finder (or the app you open folders with, such as Path Finder) and **4** for your editor, always in that order, so **4** then **1** starts Claude Code in the fourth project without looking. With the Claude desktop app installed, **5** starts a new Claude Code session in the project's folder in the app's Code tab. A project with a dev server also offers the next digit, which starts it in a new terminal window, showing the command it runs: `make dev` when the makefile has a `dev` target; or else the `dev` script in `package.json`, run with the project's package manager (the one its `packageManager` field names, or else the one its lockfile belongs to, or else npm); or else `make run`; or else `docker compose up --build` when the project has a Compose file. A `start` script doesn't count, as it often runs a built server or an MCP server. For anything else, such as a Python server, set `devCommand` on the project in the settings. Digits pick rows, so a search can't contain one.

**Which projects it lists.** The folders where you start Claude Code sessions and the projects you open from the launcher, ranked by how often and how recently you used them, with running sessions first. Nothing to set up: the list fills as you work. If you use [zoxide](https://github.com/ajeetdsouza/zoxide), the folders you visit most are listed from day one; Plaincontrol only reads zoxide's data. When the list is empty, or a search finds nothing, Return offers to add a folder: walk to it from your home folder (Return or Right to go into a folder, Left to go up), then choose the Add row at the top.

**Which apps it opens.** Without settings, the launcher opens the terminal you run Claude Code in most; Plaincontrol can open iTerm2 windows so far, and says so when you mostly use another terminal. The editor is the one you use most lately, such as Xcode, Cursor or Zed, so when you switch editors the launcher follows within days. Before you have used one, it is the app your Mac opens code files with (TextEdit and Xcode don't count there, as macOS often sets them by itself), or else Visual Studio Code. Folders open in Finder, or in the app you chose for folders.

**Settings** live in `~/.config/plaincontrol/launcher.yaml`; Launcher Settings in the menu creates it, with every setting explained. You can choose the key to hold (right Option, Command, Control or Shift), the terminal and the editor (any app, such as Cursor or Zed), the command that starts Claude Code, projects that are always listed (with the command that starts their dev server, if the launcher doesn't find it), and folders whose subfolders are always projects, such as a folder of git repositories.

**Where new windows go.** Set `windows` in the settings and the launcher splits every screen into columns, as a window manager such as Rectangle does: two on the built-in screen and three on others by default, with a 10-point gap. A new iTerm2 or Finder window takes a free column on the screen with the pointer, then on the other external screens, then on the built-in one; the editor takes two columns side by side, so two thirds of an external screen or all of the built-in one. Each screen fills from the columns nearest you, taking you to sit in front of the built-in screen: a screen in front of you from its middle, then from left to right; a screen to your left from right to left, and one to your right from left to right. When an external screen has enough free columns but not side by side, such as one window in the middle of three, the windows that fill columns there slide aside to make room, as few as possible, keeping the columns nearest you, before the built-in screen is used. Windows that do not fill columns are never moved. When no columns are free, a window goes on the built-in screen, on the left. Finder and the editor are moved once their new window appears; when they show a window they had open already, it stays where it is.

## Privacy

Plaincontrol runs entirely on your Mac. It opens no network port and sends nothing anywhere.

- **Claude Code sessions**: hook events can contain your prompts and file paths. Plaincontrol keeps only what it needs to show a session's status, and never stores or logs prompt text.
- **The keyboard**: to notice the launcher's key, Plaincontrol watches which modifier keys go down in any app, and whether another key is pressed meanwhile; it does not record what you type. While the launcher is open, it takes every key without Command or Control, so your typing reaches the launcher and not the app behind it. Both need the Accessibility permission, which macOS asks for once; the launcher does not work without it.
- **Your folders and apps**: the launcher remembers which folders you used it and Claude Code in, which terminal or editor your sessions ran in, and when you brought an editor to the front (only which one, at most once an hour), and reads when each project folder last changed. With zoxide, it reads zoxide's list of folders, but never changes it. This history stays in `~/Library/Application Support/Plaincontrol`.

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
Packages/PlaincontrolCore/  The logic, with tests, in two modules:
  Sources/PlaincontrolHooks Hook events and the local socket: all the hook command needs
  Sources/PlaincontrolCore  Sessions, terminal control and the project launcher
  Sources/plaincontrol-hook The command Claude Code runs for each hook event
plugin/                     The Claude Code plugin that installs the hooks
.claude-plugin/             Lists the plugin, so Claude Code can install it from this repository
dev/                        Scenarios for trying the app without Claude Code
scripts/                    Release packaging
Config/                     Build settings, such as code signing
project.yml                 XcodeGen project definition
```

## Development

Nothing needs to be installed in your Claude Code configuration to work on Plaincontrol. The development build is a separate app, **Plaincontrol Dev**, with its own socket, so it runs next to a release build without either one noticing the other.

There are three loops, from fastest to most real:

1. **Logic**: `make test` runs the core tests in seconds. Status rules, decoding and the socket live in the core, so most changes start here.
2. **The app without Claude Code**: `make run` starts Plaincontrol Dev (and quits Plaincontrol, if it runs, as both would open the launcher on the same key), and `make simulate` plays a scenario of hook events into it, from `dev/scenarios/`: `SCENARIO=sessions` (several at once), `permission`, `question`, or `quick-answer` (answered within the notification grace period, so no notification should appear). Repeatable, and no need to make Claude ask for a permission.
3. **With Claude Code**: `make dev-claude` starts a Claude Code session with the plugin from this repository loaded for that session only (`claude --plugin-dir plugin`). Only that session reports to Plaincontrol Dev; your other sessions are not affected. It runs the hook command that `make hook` builds into `plugin/bin/`; an installed plugin, which has no `plugin/bin/`, runs the one inside the Plaincontrol app instead, through a link the app keeps in `~/Library/Application Support/Plaincontrol/bin/`.

`make check` runs the format check, the tests and the build. Run it before every commit.

A few tests need folders on your own Mac, such as a cloud folder reached through a link. Their paths are personal, so they never go in the repository: put them in a `.env` file in the repository root, which git ignores, and `make test` passes them on. Without a value, those tests are skipped.

```sh
# .env
PLAINCONTROL_TEST_LINKED_FOLDER=~/Dropbox   # a folder reached through a symbolic link, with folders inside
```

### Releases

`make release` builds the release app and packs it in `.build/Plaincontrol.dmg`. With a Developer ID Application certificate in the keychain, it signs the app and the disk image with it and has Apple notarise them, using notary credentials stored once with `xcrun notarytool store-credentials notary`; without one, it signs ad hoc and skips notarising. `scripts/release.sh` explains the steps.

## License

[Apache License 2.0](LICENSE).

Plaincontrol is an independent project. It is not affiliated with or endorsed by Anthropic. Claude and Claude Code are trademarks of Anthropic.
