#!/bin/sh
# Fills a home folder with invented projects and an invented Claude Code history, for
# screenshots that show nothing of the Mac they are made on (`make demo`).
#
# Each project is a git repository with one commit, some with a dev server the launcher
# finds. Claude Code's history gets a folder per project with session files dated over the
# last weeks, so the welcome window has projects to add and the launcher ranks them.
#
# Usage: dev/demo/home.sh <empty home folder>
set -eu

home=${1:?usage: dev/demo/home.sh <empty home folder>}
mkdir -p "$home"
home="$(cd "$home" && pwd)"
now=$(date +%s)

# Name, then the number of Claude Code sessions in it, then how many days ago the last was.
projects="aurora-web 14 0
ledger-api 9 1
field-notes 6 3
pixel-garden 4 6
harbor-cli 3 10
orbit-mobile 2 20"

echo "$projects" | while read -r name sessions days; do
	folder="$home/Developer/$name"
	mkdir -p "$folder"
	case $name in
	aurora-web) printf '{\n  "name": "aurora-web",\n  "scripts": { "dev": "next dev -p 3100" }\n}\n' >"$folder/package.json" ;;
	pixel-garden) printf '{\n  "name": "pixel-garden",\n  "scripts": { "dev": "vite" }\n}\n' >"$folder/package.json" ;;
	ledger-api) printf 'dev:\n\tgo run ./cmd/server\n' >"$folder/Makefile" ;;
	esac
	printf '# %s\n' "$name" >"$folder/README.md"
	when="@$((now - days * 86400)) +0000"
	git -C "$folder" init -q
	git -C "$folder" add -A
	GIT_AUTHOR_DATE="$when" GIT_COMMITTER_DATE="$when" git -C "$folder" \
		-c user.name=Demo -c user.email=demo@example.com -c commit.gpgsign=false \
		commit -q -m "First commit"

	# Claude Code names a project's history after its path, with every other character a `-`.
	history="$home/.claude/projects/$(printf '%s' "$folder" | sed 's/[^A-Za-z0-9]/-/g')"
	mkdir -p "$history"
	i=0
	while [ "$i" -lt "$sessions" ]; do
		file="$history/session-$i.jsonl"
		: >"$file"
		touch -t "$(date -r $((now - (days + i * 2) * 86400 - i * 3600)) +%Y%m%d%H%M)" "$file"
		i=$((i + 1))
	done
done
echo "Invented projects and Claude Code history in $home"
