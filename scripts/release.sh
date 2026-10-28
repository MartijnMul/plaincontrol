#!/bin/sh
# Builds a release of Plaincontrol and packs it in a disk image for GitHub Releases: the app
# next to a link to Applications. The name carries no version, so
# releases/latest/download/Plaincontrol.dmg always points at the newest one.
#
# With a "Developer ID Application" certificate in the keychain, the app and the disk image
# are signed with it and notarised by Apple, so macOS opens the app after a single
# confirmation. Notarising needs credentials stored once with:
#
#     xcrun notarytool store-credentials notary
#
# Without the certificate the app is signed ad hoc and not notarised: fine for trying the
# script, not for publishing. SIGN_IDENTITY picks a certificate when there are several, and
# NOTARY_PROFILE a keychain profile other than "notary".
set -eu

cd "$(dirname "$0")/.."

DERIVED=.build/Release
APP="$DERIVED/Build/Products/Release/Plaincontrol.app"
HOOK="$APP/Contents/MacOS/plaincontrol-hook"
DMG=.build/Plaincontrol.dmg
STAGING=.build/dmg
ENTITLEMENTS=App/Plaincontrol.entitlements
NOTARY_PROFILE="${NOTARY_PROFILE:-notary}"
# The certificate goes by its SHA-1 hash: codesign fails to match a name with an accent in
# it, which a personal certificate carries when its owner's name has one.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning |
	sed -n 's/.*) \([0-9A-F]\{40\}\) "Developer ID Application: .*"/\1/p' |
	head -n 1)}"

if [ -n "$(git status --porcelain)" ]; then
	echo "Warning: the working tree has uncommitted changes, which this build includes"
fi

# A clean build, so nothing from an earlier one ends up in the release.
rm -rf "$DERIVED"
xcodegen generate --quiet
xcodebuild -project Plaincontrol.xcodeproj -scheme Plaincontrol -configuration Release \
	-destination "generic/platform=macOS" -derivedDataPath "$DERIVED" \
	CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= -quiet build
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"

# A release without Sparkle's public key could never be updated through Sparkle.
if [ -n "$IDENTITY" ] && [ -z "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")" ]; then
	echo "SPARKLE_PUBLIC_KEY in project.yml is empty: run Sparkle's generate_keys and set it first" >&2
	exit 1
fi

# Signed again from scratch with only the app's own entitlements: the build adds
# get-task-allow, for debugging, which notarisation refuses. The hardened runtime and a secure
# timestamp are what notarisation asks for. Everything inside the app goes first, innermost
# first, as each signature covers what is inside it: Sparkle's helpers (its downloader keeps
# its own entitlements), Sparkle, and the hook command, which needs no entitlements. Signed ad
# hoc, the app goes without the hardened runtime: its library validation would refuse Sparkle,
# as ad hoc signatures have no team to match.
sign() {
	if [ -n "$IDENTITY" ]; then
		codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"
	else
		codesign --force --sign - "$@"
	fi
}
[ -z "$IDENTITY" ] || echo "Signing with $IDENTITY"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
sign "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
sign "$SPARKLE/Versions/B/Autoupdate"
sign "$SPARKLE/Versions/B/Updater.app"
sign "$SPARKLE"
sign "$HOOK"
sign --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict --deep "$APP"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -quiet -volname Plaincontrol -srcfolder "$STAGING" -fs HFS+ -format UDZO "$DMG"
rm -rf "$STAGING"

if [ -n "$IDENTITY" ]; then
	codesign --timestamp --sign "$IDENTITY" "$DMG"
	# Notarising the disk image covers the app inside it too. The ticket is stapled to the
	# disk image, so it opens without a lookup at Apple.
	xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
	xcrun stapler staple "$DMG"
	spctl --assess --type open --context context:primary-signature -v "$DMG"
else
	echo "No Developer ID certificate found: the app is signed ad hoc, not notarised"
fi

echo "Packed $DMG, version $VERSION: attach it to release v$VERSION"
shasum -a 256 "$DMG"
