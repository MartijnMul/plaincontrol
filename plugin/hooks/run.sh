#!/bin/sh
# Runs Plaincontrol's hook command for a Claude Code hook event, which arrives on stdin.
#
# The command comes with the app, which links it into Application Support each time it
# starts. A checkout of the plugin may carry its own, built by `make hook`, which then goes
# first. Without either, Plaincontrol isn't installed: exit quietly, as a hook that fails
# shows up as an error in Claude Code.
hook="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/bin/plaincontrol-hook"
[ -x "$hook" ] || hook="$HOME/Library/Application Support/Plaincontrol/bin/plaincontrol-hook"
[ -x "$hook" ] || exit 0
exec "$hook"
