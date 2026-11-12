extends SceneTree
## Packs a release for the in-game updater:
##   godot --headless --path . --script res://scripts/tools/make_update.gd -- <game.pck> <out dir>
## <game.pck> comes from `--export-pack "macOS"` (it has every desktop texture format, so the
## one update works on Windows, macOS and Linux). Writes update-<version>.bin (encrypted with
## the co-op secret, see scripts/update/updates.gd) and manifest.json into <out dir>.

const Updates = preload("res://scripts/update/updates.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- <game.pck> <out dir>")
		quit(1)
		return
	var k = Updates._keys()
	if k == null:
		push_error("no co-op key file")
		quit(1)
		return
	var ver := int(str(ProjectSettings.get_setting("application/config/version", "1")))
	var pck := FileAccess.get_file_as_bytes(args[0])
	if pck.is_empty():
		push_error("can't read " + args[0])
		quit(1)
		return
	var sealed := Updates.seal_update(pck, ver, k)
	if Updates.open_update(sealed, ver, k) != pck:
		push_error("round trip failed")
		quit(1)
		return
	var name := "update-%d.bin" % ver
	var f := FileAccess.open(args[1].path_join(name), FileAccess.WRITE)
	f.store_buffer(sealed)
	f.close()
	var m := FileAccess.open(args[1].path_join("manifest.json"), FileAccess.WRITE)
	m.store_string(JSON.stringify({"version": ver, "engine": Updates._engine(), "file": name,
		"size": sealed.size()}, "  "))
	m.close()
	print("Wrote %s (%d KB) and manifest.json for v%d" % [name, sealed.size() / 1024, ver])
	quit()
