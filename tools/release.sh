#!/usr/bin/env bash
# Makes a release: bump application/config/version in project.godot first, then run
#   tools/release.sh            # export every build + the update, upload the update,
#                               # and put the web build on GitHub Pages
#   tools/release.sh --no-upload
# The git pre-push hook (tools/git-hooks/pre-push) runs this when a push to main carries
# a version the server doesn't have yet.
# Builds land in builds/<platform>/, the update in builds/update/. Players on an older
# version get the update from the title screen (scripts/update/updates.gd).
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/c/Users/mross/Downloads/Godot_v4.5.1-stable_win64.exe/Godot_v4.5.1-stable_win64_console.exe}"
SERVER="${SERVER:-claude@home.olympus}"
REMOTE_DIR=/var/www/miningsim

ver=$(grep -oP '^config/version="\K[0-9]+' project.godot)
echo "== MiningSim v$ver"

mkdir -p builds/windows builds/macos builds/linux builds/web builds/web_private builds/update
# GodotPathTrace: take the newest build of the extension if its project is on this PC.
PT_DLL=../GodotPathTrace/target/release/godot_pathtrace.dll
if [[ -f "$PT_DLL" && "$PT_DLL" -nt addons/pathtrace/bin/godot_pathtrace.dll ]]; then
	mkdir -p addons/pathtrace/bin && cp "$PT_DLL" addons/pathtrace/bin/
fi
touch builds/.gdignore
stamp=$(mktemp)  # every build must come out newer than this
declare -A OUT=(["Windows"]=builds/windows/MiningSim.exe ["macOS"]=builds/macos/MiningSim.zip
	["Linux"]=builds/linux/MiningSim.x86_64 ["Web"]=builds/web/index.pck ["Web (private)"]=builds/web_private/index.pck)
for preset in "Windows" "macOS" "Linux" "Web" "Web (private)"; do
	echo "-- export $preset"
	"$GODOT" --headless --path . --export-release "$preset" > builds/export.log 2>&1 || true
	if grep -iE "error|fail" builds/export.log | grep -v "BUG\|unref"; then exit 1; fi
	if [[ ! "${OUT[$preset]}" -nt "$stamp" ]]; then
		echo "Export of $preset didn't write ${OUT[$preset]}; Godot said:" >&2
		grep -vE "savepack|^\s*$" builds/export.log | tail -8 >&2
		exit 1
	fi
done
rm -f "$stamp"
rm -f builds/web/*.import builds/web_private/*.import

# The update: the macOS pack has every desktop texture format, so it suits all three.
rm -f builds/update/*
"$GODOT" --headless --path . --export-pack "macOS" builds/update/game.pck 2>&1 | grep -iE "error|fail" | grep -v "BUG\|unref" && exit 1 || true
"$GODOT" --headless --path . --script res://scripts/tools/make_update.gd -- builds/update/game.pck builds/update 2>&1 | grep -E "Wrote|ERROR"
rm builds/update/game.pck

if [[ "${1:-}" == "--no-upload" ]]; then
	echo "Not uploaded (builds/update/)."
	exit 0
fi
echo "-- upload to $SERVER:$REMOTE_DIR"
scp -q builds/update/update-"$ver".bin builds/update/manifest.json "$SERVER":/tmp/
# The update file first, the manifest last, so nobody sees a manifest for a missing file.
ssh "$SERVER" "sudo install -d -m 755 $REMOTE_DIR && \
	sudo install -m 644 /tmp/update-$ver.bin $REMOTE_DIR/ && \
	sudo install -m 644 /tmp/manifest.json $REMOTE_DIR/ && \
	rm /tmp/update-$ver.bin /tmp/manifest.json && \
	ls -t $REMOTE_DIR/update-*.bin | tail -n +4 | xargs -r sudo rm"

# GitHub Pages: the public web build (never the private one: check the key isn't inside).
if strings builds/web/index.pck | grep -qE "net/coop_key\.gd(c|\.remap)"; then
	echo "Web build contains the co-op key! Not publishing it." >&2
	exit 1
fi
echo "-- GitHub Pages"
pages=$(mktemp -d)
origin=$(git remote get-url origin)
(
	# A new commit on top of gh-pages (no force push, its history stays).
	cd "$pages"
	git init -q -b gh-pages
	git -c core.autocrlf=false fetch -q --depth 1 "$origin" gh-pages && git reset -q --soft FETCH_HEAD || true
	git rm -rq --cached . 2>/dev/null || true
	cp "$OLDPWD"/builds/web/* .
	touch .nojekyll
	git add -A
	git -c core.autocrlf=false commit -qm "Web build v$ver

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
	git push -q "$origin" gh-pages
)
rm -rf "$pages"
echo "Released v$ver."
