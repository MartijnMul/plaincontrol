#!/bin/sh
# Starts Plaincontrol Dev as on its first start, to go through the welcome window again: it
# quits the development app and forgets everything it keeps (its preferences, history,
# settings and permissions), then starts it. The installed Plaincontrol is left alone.
#
# With NEW=1 the app also starts in an empty home folder, as someone who has neither Claude
# Code's history nor zoxide's would; sessions still reach it through the development socket.
#
# Usage: scripts/fresh-dev.sh <path to Plaincontrol Dev.app>
set -eu

cd "$(dirname "$0")/.."

APP=${1:?usage: scripts/fresh-dev.sh <path to Plaincontrol Dev.app>}
BUNDLE_ID=io.github.martijnmul.plaincontrol.dev
SUPPORT="$HOME/Library/Application Support/Plaincontrol Dev"
SETTINGS="$HOME/.config/plaincontrol-dev"
NEW_HOME=.build/fresh-home

pkill -x "Plaincontrol Dev" || true
pkill -x Plaincontrol || true
# Quitting is not instant, and a running app writes its preferences back.
while pgrep -x "Plaincontrol Dev" >/dev/null; do sleep 0.2; done

defaults delete "$BUNDLE_ID" 2>/dev/null || true
rm -rf "$SUPPORT" "$SETTINGS" "$NEW_HOME"
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
tccutil reset AppleEvents "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "Plaincontrol Dev forgot its preferences, history, settings and permissions"

# Started with an empty environment, as `make run` does.
if [ "${NEW:-}" = 1 ]; then
	mkdir -p "$NEW_HOME"
	home="$(cd "$NEW_HOME" && pwd)"
	env -i open --env "CFFIXED_USER_HOME=$home" --env "HOME=$home" \
		--env "PLAINCONTROL_SOCKET=$SUPPORT/hooks.sock" "$APP"
	echo "Started in an empty home folder, $NEW_HOME"
else
	env -i open "$APP"
fi
