#!/bin/sh
# Installs Plaincontrol from the latest GitHub release:
#
#   curl -fsSL https://raw.githubusercontent.com/MartijnMul/plaincontrol/main/install.sh | sh
#
# It downloads the disk image, checks that the app in it is signed with a Developer ID and
# notarised by Apple, copies it to /Applications (replacing an older copy only once the new one
# is in place), and opens it. Nothing else: the Claude Code plugin is installed from Claude Code
# itself.
#
# A download through curl is not marked as coming from the internet, so macOS would not check
# the app when it first opens, as it does for a disk image downloaded in a browser. The script
# runs that check itself instead.
set -eu

URL="https://github.com/MartijnMul/plaincontrol/releases/latest/download/Plaincontrol.dmg"
APP="/Applications/Plaincontrol.app"
MINIMUM_MACOS=27

if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt "$MINIMUM_MACOS" ]; then
	echo "Plaincontrol needs macOS $MINIMUM_MACOS or later." >&2
	exit 1
fi

TMP="$(mktemp -d)"
cleanup() {
	hdiutil detach -quiet "$TMP/mount" 2>/dev/null || true
	rm -rf "$TMP" "$APP.new"
}
trap cleanup EXIT

echo "Downloading Plaincontrol..."
curl -fL --progress-bar -o "$TMP/Plaincontrol.dmg" "$URL"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$TMP/mount" "$TMP/Plaincontrol.dmg"
NEW="$TMP/mount/Plaincontrol.app"

if ! codesign --verify --deep --strict "$NEW" 2>/dev/null ||
	! spctl --assess --type execute "$NEW" 2>/dev/null; then
	echo "The downloaded app is not signed and notarised as it should be; nothing was installed." >&2
	exit 1
fi

rm -rf "$APP.new"
ditto "$NEW" "$APP.new"
if pgrep -x Plaincontrol >/dev/null; then
	osascript -e 'quit app "Plaincontrol"'
	sleep 1
fi
rm -rf "$APP"
mv "$APP.new" "$APP"
open "$APP"

cat <<'EOF'
Installed in /Applications. Look for its lamps in the menu bar.

If you haven't yet, install the Claude Code plugin, which reports your sessions to it. In
Claude Code, run:

  /plugin marketplace add MartijnMul/plaincontrol
  /plugin install plaincontrol@plaincontrol
EOF
