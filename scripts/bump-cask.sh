#!/bin/sh
# Points the Homebrew cask at the release `make release` just built: its version and the
# SHA-256 of its disk image. Run it after publishing the release, then commit and push the tap.
#
# Usage: scripts/bump-cask.sh <path to a clone of MartijnMul/homebrew-tap>
set -eu

cd "$(dirname "$0")/.."

TAP=${1:?usage: scripts/bump-cask.sh <path to the homebrew-tap clone>}
CASK="$TAP/Casks/plaincontrol.rb"
APP=.build/Release/Build/Products/Release/Plaincontrol.app
DMG=.build/Plaincontrol.dmg

[ -f "$CASK" ] || { echo "No cask at $CASK" >&2; exit 1; }
[ -f "$DMG" ] || { echo "No $DMG: run make release first" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
SHA256="$(shasum -a 256 "$DMG" | cut -d ' ' -f 1)"

sed -i '' -e "s/^  version \".*\"$/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"$/  sha256 \"$SHA256\"/" "$CASK"
grep -q "version \"$VERSION\"" "$CASK" && grep -q "sha256 \"$SHA256\"" "$CASK" ||
	{ echo "Could not update $CASK" >&2; exit 1; }
echo "Cask set to $VERSION ($SHA256)"
