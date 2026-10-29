<p align="center"><img src="docs/images/icon.svg" width="128" alt=""></p>

<h1 align="center">Plaincontrol</h1>

<p align="center"><strong>See which session needs you.</strong><br>A macOS menu bar app for running several Claude Code sessions at once.</p>

<p align="center">
  <a href="https://github.com/MartijnMul/plaincontrol/releases/latest"><img src="https://img.shields.io/github/v/release/MartijnMul/plaincontrol" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/MartijnMul/plaincontrol" alt="License: Apache-2.0"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2027-lightgrey" alt="Platform: macOS 27">
</p>

<p align="center"><img src="docs/images/menu.png" width="437" alt="The Plaincontrol menu, listing four Claude Code sessions: one needs permission, one has a question, one is working and one is idle."></p>

- **See every session** in the menu bar, with the ones waiting on you counted and listed first.
- **Get a notification** when a session finishes or asks you something.
- **Jump to it** in one click: its window, tab and pane come to the front in iTerm2 or Terminal, on any Space.
- **Open any project from the keyboard**: hold the right Option key, pick a project, and start Claude Code, a terminal, your editor or its dev server, in a free spot on your screens.

> **Early days.** It works, with rough edges. Jumping to sessions and opening terminals work in iTerm2 and Terminal only so far. Settings may still change; the [changelog](CHANGELOG.md) says when.

## Install

Needs macOS 27 or later and [Claude Code](https://code.claude.com). With [Homebrew](https://brew.sh):

```sh
brew install --cask martijnmul/tap/plaincontrol
```

`brew upgrade` keeps it up to date. Or download [`Plaincontrol.dmg`](https://github.com/MartijnMul/plaincontrol/releases/latest/download/Plaincontrol.dmg) and drag the app to Applications; it asks on its second launch whether to update itself.

Then install the Claude Code plugin, which reports your sessions to the app. In Claude Code:

```
/plugin marketplace add MartijnMul/plaincontrol
/plugin install plaincontrol@plaincontrol
```

Without the plugin, the launcher still works, but Plaincontrol sees no sessions: no list, no notifications, and only the projects you open from the launcher, zoxide or your settings.

macOS asks for two permissions the first time they are needed: **Accessibility** for the launcher, and **control of your terminal**, iTerm2 or Terminal, to jump to a session and open its windows.

**Uninstall**: quit Plaincontrol and run `brew uninstall --cask plaincontrol`, or drag it to the Bin; then run `/plugin uninstall plaincontrol@plaincontrol` in Claude Code. Your settings and history are in `~/.config/plaincontrol` and `~/Library/Application Support/Plaincontrol`; `brew uninstall --cask --zap plaincontrol` removes them too.

## The launcher

Hold the right Option key on its own, or choose Open Launcher in the menu. Type to search, then press a project's digit; in a project, press an action's digit. Arrows and Return work too; Escape goes back, then closes.

<p align="center"><img src="docs/images/launcher.png" width="569" alt="The launcher, listing six projects with a digit each; the ones with running sessions first."></p>

| Key | Action |
| --- | --- |
| 1 | Claude Code in the Claude desktop app, in a new window |
| 2 | A terminal in the project's folder |
| 3 | The folder in Finder |
| 4 | The folder in your editor |
| 5 | Claude Code in a new terminal window |
| 6 | The dev server, when the project has one |

So **4** then **5** starts Claude Code in the fourth project. Actions for apps you don't have are left out. **←** on the list of projects opens an empty window of your terminal, browser or Finder instead.

- **Projects** come from where you use Claude Code and the launcher, most used first, and from [zoxide](https://github.com/ajeetdsouza/zoxide) if you use it. Nothing to set up.
- **The dev server** is `make dev`, the `dev` script in `package.json`, `make run` or `docker compose up`, whichever the project has first. Set your own per project in the settings. When the launcher knows the port, it asks whether to open the page in your browser too.
- **Apps**: the terminal and editor you use most, until you choose others in the settings.
- **New windows** go in columns across your screens, like a window manager, starting with the screen under the pointer. The settings set the columns, or turn it off.

## Settings

Settings… in the menu (Command-comma). Every setting shows whether it is at its default and can be reset. They are stored in `~/.config/plaincontrol/settings.yaml`, which you can also edit by hand or keep in your dotfiles; the window keeps your comments, and a schema next to it gives completion in editors with the YAML language server.

<p align="center"><img src="docs/images/settings.png" width="473" alt="The settings window's General tab: the key that opens the launcher, the terminal, the editor, the Claude Code command and the order of a project's actions, each marked Default."></p>

## Privacy

Plaincontrol sends nothing about you off your Mac. Its one network request is the update check, and only if you allow it.

- Of each Claude Code event it keeps only the session, its folder, its status and its terminal pane. Prompts are never stored or logged.
- The Accessibility permission lets it notice the launcher key and take your typing while the launcher is open, and move the windows it opens. It does not record what you type.
- Your launcher history stays in `~/Library/Application Support/Plaincontrol`. zoxide's data is only read.
- On its second launch, Plaincontrol asks whether to check for updates automatically. If you agree, it asks GitHub once a day for the latest version, which tells GitHub your IP address and Plaincontrol's version, as any download from GitHub does. Change your mind in Settings.

[SECURITY.md](SECURITY.md) has the details, and how to check that your copy is genuine.

## Contributing

Bug reports, ideas and pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) explains how to build it and work on it.

## License

[Apache License 2.0](LICENSE). Plaincontrol is an independent project, not affiliated with or endorsed by Anthropic. Claude and Claude Code are trademarks of Anthropic.
