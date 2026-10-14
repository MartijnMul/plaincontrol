#!/bin/sh
# Plays a scenario of Claude Code hook events into Plaincontrol through the hook command,
# one event per line, so the app can be tried without running Claude Code.
#
# Usage: dev/simulate.sh <hook-command> <scenario.jsonl> [seconds-between-events]
set -eu

hook=$1
scenario=$2
delay=${3:-1.5}

while IFS= read -r line || [ -n "$line" ]; do
	[ -n "$line" ] || continue
	printf '%s\n' "$line" | PLAINCONTROL_DEBUG=1 "$hook"
	echo "$line" | sed -E 's/.*"session_id": *"([^"]*)".*"hook_event_name": *"([^"]*)".*/  \1  \2/'
	sleep "$delay"
done <"$scenario"
