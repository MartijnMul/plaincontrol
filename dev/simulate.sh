#!/bin/sh
# Plays a scenario of Claude Code hook events into Plaincontrol through the hook command,
# so the app can be tried without running Claude Code.
#
# A scenario has one hook event per line, as JSON. A line with only a number pauses for that
# many seconds, for example to let a notification's grace period pass.
#
# Usage: dev/simulate.sh <hook-command> <scenario.jsonl> [seconds-between-events]
set -eu

hook=$1
scenario=$2
delay=${3:-1.5}

while IFS= read -r line || [ -n "$line" ]; do
	case $line in
	"") continue ;;
	*[!0-9.]*) ;;
	*)
		echo "  (pause ${line}s)"
		sleep "$line"
		continue
		;;
	esac
	printf '%s\n' "$line" | PLAINCONTROL_DEBUG=1 "$hook"
	echo "$line" | sed -E 's/.*"session_id": *"([^"]*)".*"hook_event_name": *"([^"]*)".*/  \1  \2/'
	sleep "$delay"
done <"$scenario"
