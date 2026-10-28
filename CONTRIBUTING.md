# Contributing

Thanks for wanting to make Plaincontrol better. Bug reports, ideas and pull requests are all welcome.

## Reporting a bug

[Open an issue](https://github.com/MartijnMul/plaincontrol/issues/new/choose) and pick the bug report. It asks for:

- your macOS version, the Plaincontrol version (Finder › Applications › Plaincontrol › Get Info) and the Claude Code version (`claude --version`);
- the terminal you run Claude Code in, and whether it runs inside tmux;
- what you did, what you expected, and what happened instead.

For a session that does not show up or keeps the wrong status, the app's log helps. Run this in Terminal right after it happens, read it, and paste what is useful:

```sh
log show --last 5m --predicate 'subsystem == "io.github.martijnmul.plaincontrol"'
```

Plaincontrol never logs prompts, but the log can hold folder names; leave out what you would rather not share. A security problem goes through [SECURITY.md](SECURITY.md) instead, not a public issue.

## Building

You need macOS 27, Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/MartijnMul/plaincontrol.git
cd plaincontrol
make run
```

The Xcode project is generated from `project.yml`; `make open` opens it, and `make help` lists every command. Development builds are a separate app, **Plaincontrol Dev**, with its own socket and history, so they never get in the way of an installed Plaincontrol (`make run` does quit it, as both would listen for the same key). Nothing is installed in your own Claude Code configuration.

There are three ways to try a change, from fastest to most real:

```sh
make test         # the core's tests, in seconds; most changes start here
make run          # builds and starts Plaincontrol Dev
make simulate     # plays hook events into it, without Claude Code (SCENARIO= a file in dev/scenarios/)
make dev-claude   # one Claude Code session with this repository's plugin, reporting to Plaincontrol Dev only
make check        # formatting, tests and the build: run it before every commit
```

Builds are signed ad hoc, so macOS asks for permissions again after every rebuild. To keep them, sign with your own certificate: create `Config/Local.xcconfig` (ignored by git) as `Config/Signing.xcconfig` describes.

A few tests need folders on your own Mac. Their paths are personal, so they go in a `.env` file in the repository root, which git ignores; without one, those tests are skipped:

```sh
PLAINCONTROL_TEST_LINKED_FOLDER=~/Dropbox   # a folder reached through a symbolic link, with folders inside
```

`make release` builds the release app into `.build/Plaincontrol.dmg`. With a Developer ID Application certificate in the keychain it also signs and notarises it (with credentials stored once by `xcrun notarytool store-credentials notary`); `scripts/release.sh` explains the steps.

## How the code is laid out

| Where | What it holds |
| --- | --- |
| `Packages/PlaincontrolCore/Sources/PlaincontrolHooks` | Hook events and the local socket: everything the hook command needs, and nothing more. |
| `Packages/PlaincontrolCore/Sources/plaincontrol-hook` | The command Claude Code runs for each hook event. |
| `Packages/PlaincontrolCore/Sources/PlaincontrolCore` | Everything else: sessions and their status, terminal control, the launcher, its projects and settings, window placement. |
| `App/` | The SwiftUI app: the menu bar, the launcher panel, the settings window, notifications. It shows state and turns input into calls on the core. |
| `plugin/`, `.claude-plugin/` | The Claude Code plugin and the marketplace entry that installs it. |

Tests live in `Packages/PlaincontrolCore/Tests`, written with Swift Testing.

## Ground rules

These keep Plaincontrol small and trustworthy. A pull request that breaks one needs a good reason in its description.

- **Nothing leaves the Mac.** No network connections, no telemetry, no update checks that phone home.
- **Hook events are private.** They can hold prompts and file paths. Keep only what a feature needs, and never store or log prompt text.
- **Logic goes in the core, with tests.** The app stays a thin layer. The hook module stays small and does not depend on the rest of the core: it runs for every event in every session.
- **No new permissions without a reason.** Plaincontrol asks for Accessibility (the launcher's key, its typing, moving windows) and for control of iTerm2. A feature that needs more says why in its pull request.
- **Few dependencies.** System frameworks, and Yams for YAML. A new one needs a reason and a licence compatible with Apache 2.0.
- **It works for anyone.** Something only one setup needs goes behind a setting, with a default that works without it.
- **Comments explain why,** not what. Look at the existing doc comments for the tone.

## Pull requests

- One change per pull request; small is easier to review.
- Commit messages in [Conventional Commits](https://www.conventionalcommits.org), as in the history: `feat: …`, `fix: …`, `docs: …`. Explain the reason in the body when it is not obvious.
- A change someone using the app would notice gets a line under `## Unreleased` in [CHANGELOG.md](CHANGELOG.md), in the same commit, and the README follows when it describes the change.
- `make check` passes.
- Describe how you tested it in the app: what you did, on which macOS and with which terminal. Much of Plaincontrol (hotkeys, windows, other apps) cannot be tested automatically. The pull request template has a checklist.
- For a larger change, a new terminal or a new permission, open an issue first, so we can agree on the approach before you spend time on it.

## License

Plaincontrol is licensed under the [Apache License 2.0](LICENSE). By opening a pull request you agree that your contribution is licensed under it too.
