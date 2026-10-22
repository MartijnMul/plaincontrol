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

# Signed again from scratch with only the app's own entitlements: the build adds
# get-task-allow, for debugging, which notarisation refuses. The hardened runtime and a secure
# timestamp are what notarisation asks for. The hook command inside goes first, as the app's
# signature covers it; it needs no entitlements.
if [ -n "$IDENTITY" ]; then
	echo "Signing with $IDENTITY"
	codesign --force --options runtime --timestamp --sign "$IDENTITY" "$HOOK"
	codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" \
		--sign "$IDENTITY" "$APP"
else
	codesign --force --options runtime --sign - "$HOOK"
	codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign - "$APP"
fi
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
