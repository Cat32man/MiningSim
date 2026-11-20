#!/usr/bin/env bash
# Makes a release: bump application/config/version in project.godot first, then run
#   tools/release.sh            # export the desktop builds + the update, upload the update
# (No web build: the browser version was too laggy and was taken down in v10.)
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

mkdir -p builds/windows builds/macos builds/linux builds/update
# GodotPathTrace: take the newest build of the extension if its project is on this PC.
PT_DLL=../GodotPathTrace/target/release/godot_pathtrace.dll
if [[ -f "$PT_DLL" && "$PT_DLL" -nt addons/pathtrace/bin/godot_pathtrace.dll ]]; then
	mkdir -p addons/pathtrace/bin && cp "$PT_DLL" addons/pathtrace/bin/
fi
touch builds/.gdignore
stamp=$(mktemp)  # every build must come out newer than this
declare -A OUT=(["Windows"]=builds/windows/MiningSim.exe ["macOS"]=builds/macos/MiningSim.zip
	["Linux"]=builds/linux/MiningSim.x86_64)
for preset in "Windows" "macOS" "Linux"; do
	echo "-- export $preset"
	"$GODOT" --headless --path . --export-release "$preset" > builds/export.log 2>&1 || true
	# Godot's own error lines only (file names like error_screen.gd are not errors).
	if grep -E "^(SCRIPT )?ERROR|export .*failed" builds/export.log | grep -v "BUG\|unref"; then exit 1; fi
	if [[ ! "${OUT[$preset]}" -nt "$stamp" ]]; then
		echo "Export of $preset didn't write ${OUT[$preset]}; Godot said:" >&2
		grep -vE "savepack|^\s*$" builds/export.log | tail -8 >&2
		exit 1
	fi
done
rm -f "$stamp"

# The update: the macOS pack has every desktop texture format, so it suits all three.
rm -f builds/update/*
"$GODOT" --headless --path . --export-pack "macOS" builds/update/game.pck 2>&1 | grep -E "^(SCRIPT )?ERROR|export .*failed" | grep -v "BUG\|unref" && exit 1 || true
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

echo "Released v$ver."
