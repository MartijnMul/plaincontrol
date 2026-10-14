# Changelog

What changes in each release of Plaincontrol. Versions follow [Semantic Versioning](https://semver.org); while the version starts with 0, any release may change how Plaincontrol is installed or configured, and says so.

## Unreleased

- **Sessions that crash disappear**: a session also leaves the list, and its notification is removed, when its Claude Code process exits without ending the session, such as after a crash or when it is killed.
- **Jump to a session**: click a session in the menu, or its notification, and its iTerm2 window, tab and pane come to the front, on whichever Space they are. macOS asks once for permission to control iTerm2. Sessions in other terminals, or inside tmux, are listed but cannot be opened yet.
- **Notifications** when a session starts waiting for you (with a sound) or finishes a turn. Each waits 5 seconds and is dropped if the session moves on in the meantime, such as when you answer a permission prompt you were looking at. Each session has at most one notification, removed once the session works again or ends.
- **Session list in the menu bar**: every Claude Code session that reports to Plaincontrol, with its status (working, waiting for a permission, a question, a plan review or other input, or idle), waiting sessions first. The menu bar icon shows how many sessions are waiting for you.
- **Claude Code plugin**: hooks that report each session's status to Plaincontrol over a local socket. Prompts, tool inputs and Claude's replies never leave the hook.
