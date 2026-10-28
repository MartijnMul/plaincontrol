# Plaincontrol

[![Latest release](https://img.shields.io/github/v/release/MartijnMul/plaincontrol)](https://github.com/MartijnMul/plaincontrol/releases/latest)
[![License: Apache-2.0](https://img.shields.io/github/license/MartijnMul/plaincontrol)](LICENSE)
![Platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey)
![Swift 6](https://img.shields.io/badge/Swift-6-lightgrey?logo=swift&logoColor=white)

A native macOS menu bar app for people who run several Claude Code sessions at once. It shows every session at a glance, tells you when one is done or waiting for you, and takes you to the right terminal pane in one click, on any Space. A keyboard launcher opens any project in Claude Code, your terminal, editor or Finder, with new windows placed in columns across your screens.

> **Status: early.** The session list, notifications, jumping to iTerm2 panes, the project launcher and its settings work. Expect rough edges, and settings that may still change between releases; the [changelog](CHANGELOG.md) says when they do.

## What it does

- **Sessions at a glance**: a menu bar icon with a badge for the sessions waiting on you, and a list of every session with its status, waiting ones first.
- **Never miss a question**: a native notification when a session finishes or asks for input or permission, unless you respond within a few seconds.
- **Jump to it**: click a session, or its notification, and its iTerm2 window, tab and pane come to the front, on any Space.
- **Projects from the keyboard**: hold the right Option key for a launcher with the projects you work on, and open one in Claude Code (in the Claude desktop app or a terminal), Finder or your editor, or start its dev server, with a single key.
- **Windows in their place**: every window the launcher opens takes a free column on your screens, nearest you first, as a window manager would place it.

Planned: a hotkey for the next waiting session, terminals other than iTerm2, and starting a project with its worktree and window layout in one go.

## Requirements

macOS 27 or later, and [Claude Code](https://code.claude.com). Jumping to a session works in iTerm2; sessions in other terminals are listed, but cannot be opened from Plaincontrol yet.

## Install

Paste this into Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/MartijnMul/plaincontrol/main/install.sh | sh
```

It downloads the latest release, puts Plaincontrol in your Applications folder and opens it. Run it again to update. The [script](install.sh) is short; read it first if you like.

Or download [`Plaincontrol.dmg`](https://github.com/MartijnMul/plaincontrol/releases/latest/download/Plaincontrol.dmg) yourself, open it and drag Plaincontrol onto the Applications shortcut. The app is signed and notarised by Apple; the first time, macOS asks whether you are sure you want to open an app downloaded from the internet: choose **Open**.

Then:

1. **Install the Claude Code plugin**, which tells Plaincontrol what each session is doing. In Claude Code, run:

   ```
   /plugin marketplace add MartijnMul/plaincontrol
   /plugin install plaincontrol@plaincontrol
   ```

   Sessions you start from then on show up in the menu bar.
2. **Hold the right Option key** on its own to open the launcher. The first time, macOS asks for the Accessibility permission, which the launcher needs to notice the key and take your typing: turn Plaincontrol on in System Settings › Privacy & Security › Accessibility.
3. **Click a session** in the menu to jump to it. The first time, macOS asks whether Plaincontrol may control iTerm2.

The plugin only needs an update when the [changelog](CHANGELOG.md) says so; the command it runs comes with the app.

### Uninstall

Quit Plaincontrol from its menu and drag it from Applications to the Bin. In Claude Code, run `/plugin uninstall plaincontrol@plaincontrol`. To remove your settings and history too, delete `~/.config/plaincontrol` and `~/Library/Application Support/Plaincontrol`.

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

Every row shows its digit, and digits pick rows, so a search can't contain one. An open project offers, in this order:

| Key | Action |
| --- | --- |
| 1 | Claude Code in the Claude desktop app, in a window of its own (when the app is installed) |
| 2 | A terminal window in the project's folder |
| 3 | The folder in Finder, or the app you open folders with, such as Path Finder |
| 4 | The folder in your editor |
| 5 | Claude Code in a new terminal window in the folder |
| 6 | The project's dev server in a new terminal window, when it has one |

So **4** then **1** starts Claude Code in the fourth project without looking. Without the desktop app or an editor, the actions after it move up a digit. With `actionOrder` in the settings, an open project can instead select the action you use most there, so Return runs it, or list the actions you use most first.

**Claude Code in the desktop app** opens a new session as you would by hand: File › New Session in New Window, then the project's folder in that window's folder picker. That works for any folder Claude Code has worked in, without the app asking whether to trust it; a folder it has never worked in opens in the app's main window instead, after that question. When the app's main window shows a chat, it first goes to a new Claude Code session, as only there does the menu have the item. If a step fails, for instance after a change to the app, Plaincontrol beeps and leaves the window for you to choose the folder.

**The dev server** is the first of these the project has: `make dev` (a `dev` target in its makefile); its `package.json` `dev` script, run with its package manager (the one `packageManager` names, else the one its lockfile belongs to, else npm); `make run`; or `docker compose up --build` (a Compose file). A `start` script doesn't count, as it often runs a built server or an MCP server. For anything else, such as a Python server, set `devCommand` on the project in the settings. The action shows the command it runs.

**Which projects it lists.** The folders where you start Claude Code sessions and the projects you open from the launcher, ranked by how often and how recently you used them, with running sessions first. Nothing to set up: the list fills as you work. If you use [zoxide](https://github.com/ajeetdsouza/zoxide), the folders you visit most are listed from day one; Plaincontrol only reads zoxide's data. When the list is empty, or a search finds nothing, Return offers to add a folder: walk to it from your home folder (Return or Right to go into a folder, Left to go up), then choose the Add row at the top.

**Which apps it opens.** Without settings, the launcher opens the terminal you run Claude Code in most; Plaincontrol can open iTerm2 windows so far, and says so when you mostly use another terminal. The editor is the one you use most lately, such as Xcode, Cursor or Zed, so when you switch editors the launcher follows within days. Before you have used one, it is the app your Mac opens code files with (TextEdit and Xcode don't count there, as macOS often sets them by itself), or else Visual Studio Code. Folders open in Finder, or in the app you chose for folders.

## Settings

Choose Settings… in the menu, or press Command-comma while Plaincontrol is in front. You can set:

- the key to hold: right Option, Command, Control or Shift;
- the terminal and the editor, any app such as Cursor or Zed, instead of the ones the launcher picks;
- the command that starts Claude Code in a terminal;
- how a project's actions are ordered: always the same, the one you use most selected, or the ones you use most first;
- projects that are always listed, with the command that starts their dev server if the launcher doesn't find it, and folders whose subfolders are projects, such as a folder of git repositories;
- how new windows are placed, or that each app places its own.

Each setting says whether it is at its default, with a Reset button where it is not, and Restore Defaults… puts a whole tab back.

The settings live in `~/.config/plaincontrol/settings.yaml`, which you can also edit as text, keep in your dotfiles, or copy to another Mac; Edit as Text… opens it. The window changes only the setting you change and keeps the rest of the file as you wrote it, comments included. (A file it cannot change in place, such as YAML with anchors, is kept as `settings.yaml.backup` and written anew.) Next to it, Plaincontrol keeps `settings.schema.json` up to date: editors with the YAML language server, such as Zed, or Visual Studio Code with Red Hat's YAML extension, complete the settings and flag mistakes as you type.

## Where new windows go

The launcher splits every screen into columns, as a window manager such as Rectangle does: two on the built-in screen and three on others, with a 10-point gap; the settings change both. A new terminal, Finder or Claude desktop app window takes one free column, the editor two side by side.

- **Which screen**: the one with the pointer, then the other external screens, then the built-in one.
- **Which column**: nearest you first, taking you to sit in front of the built-in screen. A screen in front of you fills from its middle out, one to your left from right to left, one to your right from left to right.
- **Making room**: when an external screen has enough free columns but not side by side, the windows that fill columns there slide aside, as few as possible, before the built-in screen is used. Windows that do not fill a column are never moved.
- **No room**: the window goes on the built-in screen, on the left.

Finder and the editor are moved once their new window appears; a window they had open already stays where it is. To let each app place its windows instead, turn off Place new windows in columns in the settings.

## Privacy

Plaincontrol runs entirely on your Mac. It opens no network port and sends nothing anywhere.

- **Claude Code sessions**: hook events can contain your prompts and file paths. Plaincontrol keeps only what it needs to show a session's status, and never stores or logs prompt text.
- **The keyboard**: to notice the launcher's key, Plaincontrol watches which modifier keys go down in any app, and whether another key is pressed meanwhile; it does not record what you type. While the launcher is open, it takes every key without Command or Control, so your typing reaches the launcher and not the app behind it. Both need the Accessibility permission, which macOS asks for once; the launcher does not work without it. The same permission lets it move the windows it opens, and, in the Claude desktop app, choose New Session in New Window and the project's folder in that window; it does nothing else in other apps.
- **Your folders and apps**: the launcher remembers which folders you used it and Claude Code in, and which action you ran, which terminal or editor your sessions ran in, and when you brought an editor to the front (only which one, at most once an hour), and reads when each project folder last changed. With zoxide, it reads zoxide's list of folders, but never changes it. This history stays in `~/Library/Application Support/Plaincontrol`.

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
install.sh                  Installs the latest release, checking its signature
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

## Contributing

Bug reports, ideas and pull requests are welcome: [CONTRIBUTING.md](CONTRIBUTING.md) says how, and what keeps Plaincontrol small and trustworthy. Report a security problem privately, as [SECURITY.md](SECURITY.md) describes.

## License

[Apache License 2.0](LICENSE).

Plaincontrol is an independent project. It is not affiliated with or endorsed by Anthropic. Claude and Claude Code are trademarks of Anthropic.
