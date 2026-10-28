# Security

Plaincontrol runs entirely on your Mac and makes no network connections. What it touches, and why:

- **Claude Code hook events.** The plugin runs a small command for every event in every session. It passes on only what Plaincontrol shows (the session, its folder, its status and its terminal pane) over a Unix socket in `~/Library/Application Support/Plaincontrol/`, which only your user can open. Prompts, tool inputs and Claude's replies never leave the command.
- **Accessibility.** The launcher watches which modifier keys go down to notice its key, takes the keys while its panel is open, and moves the windows it opens. In the Claude desktop app, it chooses New Session in New Window and the project's folder in that window. It does not record what you type.
- **Automation.** Plaincontrol controls iTerm2 through AppleScript, to bring a session's pane to the front and to open windows.
- **Files.** It reads `~/.config/plaincontrol/settings.yaml`, the folders you list there, and zoxide's list of folders when zoxide is installed. It writes its settings, a schema for them, and your launcher history, and nothing outside its own folders.

## Reporting a vulnerability

Please do not open a public issue. Report it privately through [GitHub's vulnerability reporting](https://github.com/MartijnMul/plaincontrol/security/advisories/new) instead, with what you found and how to reproduce it. You will get an answer within a week.

Of interest above all: anything that lets another process or user read hook events or send events into the app, makes Plaincontrol run something it should not, or uses its Accessibility permission for more than the above.

## Getting a genuine copy

Only the latest release gets fixes. Get Plaincontrol from this repository's [releases](https://github.com/MartijnMul/plaincontrol/releases), or with [`install.sh`](install.sh), which refuses an app that is not signed with the Developer ID below and notarised by Apple. To check a copy yourself:

```sh
spctl --assess --verbose /Applications/Plaincontrol.app
codesign -dv /Applications/Plaincontrol.app 2>&1 | grep TeamIdentifier
```

The first should say `accepted` and `source=Notarized Developer ID`; the second should show the team `JSR6PF58J7`.
