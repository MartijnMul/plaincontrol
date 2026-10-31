#!/bin/sh
# Publishes a release of Plaincontrol: every step, from the version to the Homebrew cask.
#
#     make publish VERSION=0.7.1
#
# It checks first that main is clean and pushed, that the version is new and that CHANGELOG.md
# has changes under "## Unreleased", and asks once before it starts: notarising sends the app
# to Apple, and the rest goes to GitHub. Then it sets the version, turns "## Unreleased" into
# the version's section, commits, builds, signs and notarises (scripts/release.sh), tags,
# pushes, publishes the GitHub release with the disk image, Sparkle's feed and the section as
# its notes, and points the cask in the tap at it (scripts/bump-cask.sh) and pushes that.
#
# When a step fails, it says which, and what is already done. Nothing reaches GitHub before
# the release is built and notarised.
#
# TAP is the clone of the Homebrew tap, ../homebrew-tap without it.
set -eu

cd "$(dirname "$0")/.."

VERSION=${1:-}
TAP="${TAP:-../homebrew-tap}"
TAG="v$VERSION"
REPOSITORY=MartijnMul/plaincontrol
NOTES=.build/release-notes.md

fail() {
	echo "$*" >&2
	exit 1
}

# What has happened so far, for the message when a step fails.
step="checking"
done_so_far="nothing"
trap '[ $? -eq 0 ] || [ "$step" = checking ] || echo "Stopped while $step. Done so far: $done_so_far." >&2' EXIT

# Checks: nothing changes until all of them pass.
echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' ||
	fail "usage: make publish VERSION=x.y.z, such as 0.7.1"
[ "$(git branch --show-current)" = main ] || fail "Not on main"
[ -z "$(git status --porcelain)" ] || fail "The working tree has uncommitted changes"
git fetch --quiet --tags origin
[ "$(git rev-list --count HEAD..origin/main)" = 0 ] || fail "main is behind origin/main: pull first"
git rev-parse --quiet --verify "refs/tags/$TAG" >/dev/null && fail "$TAG exists already"

CURRENT="$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml)"
BUILD="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"$/\1/p' project.yml)"
[ -n "$CURRENT" ] && [ -n "$BUILD" ] || fail "Could not read the version from project.yml"
[ "$CURRENT" != "$VERSION" ] &&
	[ "$(printf '%s\n%s\n' "$CURRENT" "$VERSION" | sort -V | tail -n 1)" = "$VERSION" ] ||
	fail "$VERSION is not after the current version, $CURRENT"

# The changes under "## Unreleased", up to the next section.
section() {
	awk -v heading="$1" '
		$0 == heading || index($0, heading " ") == 1 { found = 1; next }
		found && /^## / { exit }
		found { print }
	' CHANGELOG.md | awk 'NF { if (started) while (blank-- > 0) print ""; blank = 0; started = 1; print; next } { blank++ }'
}
section "## Unreleased" | grep -q '^- ' || fail "CHANGELOG.md has no changes under ## Unreleased"

security find-identity -v -p codesigning | grep -q '"Developer ID Application: ' ||
	fail "No Developer ID Application certificate in the keychain"
gh auth status >/dev/null 2>&1 || fail "gh is not signed in: run gh auth login"
[ -f "$TAP/Casks/plaincontrol.rb" ] || fail "No Homebrew tap at $TAP: set TAP to its clone"
[ -z "$(git -C "$TAP" status --porcelain)" ] || fail "The tap at $TAP has uncommitted changes"

echo "Plaincontrol $CURRENT → $VERSION (build $((BUILD + 1))), with these release notes:"
echo
section "## Unreleased"
echo
echo "This sends the app to Apple to notarise, then pushes main and $TAG, publishes the"
echo "release on GitHub and pushes the cask to the tap."
printf "Publish %s? [y/N] " "$VERSION"
read -r answer
[ "$answer" = y ] || [ "$answer" = Y ] || fail "Nothing published."

step="setting the version"
sed -i '' -e "s/^\( *MARKETING_VERSION: \)\".*\"$/\1\"$VERSION\"/" \
	-e "s/^\( *CURRENT_PROJECT_VERSION: \)\".*\"$/\1\"$((BUILD + 1))\"/" project.yml
sed -i '' "s/^## Unreleased$/## $VERSION — $(date +%Y-%m-%d)/" CHANGELOG.md
git add project.yml CHANGELOG.md
git commit --quiet -m "build: set the version to $VERSION"
COMMIT="$(git rev-parse HEAD)"
done_so_far="the version commit, on this Mac only (undo it with git reset --hard HEAD~1)"

step="building and notarising"
scripts/release.sh
mkdir -p .build
section "## $VERSION" >"$NOTES"

step="pushing main and $TAG"
git tag -s "$TAG" -m "Plaincontrol $VERSION" "$COMMIT"
git push --quiet origin main "$TAG"
done_so_far="main and $TAG pushed"

step="publishing the GitHub release"
gh release create "$TAG" --repo "$REPOSITORY" --verify-tag --title "Plaincontrol $VERSION" \
	--notes-file "$NOTES" .build/Plaincontrol.dmg .build/appcast.xml
done_so_far="main and $TAG pushed, the release published"

step="updating the Homebrew cask"
scripts/bump-cask.sh "$TAP"
git -C "$TAP" commit --quiet -am "plaincontrol $VERSION"
git -C "$TAP" push --quiet
done_so_far="everything"

echo "Published Plaincontrol $VERSION: https://github.com/$REPOSITORY/releases/tag/$TAG"
