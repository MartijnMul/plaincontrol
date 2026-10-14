# Changelog

What changes in each release of Plaincontrol. Versions follow [Semantic Versioning](https://semver.org); while the version starts with 0, any release may change how Plaincontrol is installed or configured, and says so.

## Unreleased

- **Session list in the menu bar**: every Claude Code session that reports to Plaincontrol, with its status (working, waiting for a permission, a question, a plan review or other input, or idle), waiting sessions first. The menu bar icon shows how many sessions are waiting for you.
- **Claude Code plugin**: hooks that report each session's status to Plaincontrol over a local socket. Prompts, tool inputs and Claude's replies never leave the hook.
