extends RefCounted
## Loads the GodotPathTrace extension; main.gd calls ensure() first thing. (Not an autoload:
## autoloads are fixed in each build, while main.gd and this DLL can arrive in an update.)
## The DLL travels inside the game's data pack, so
## the Windows build stays one file: at start-up it's copied to user://pathtrace/ beside a
## generated .gdextension and loaded from there. Windows only; elsewhere, or if anything
## fails, PathTraceEffect just doesn't exist and the game hides the option.

const SRC := "res://addons/pathtrace/bin/godot_pathtrace.dll"
const DIR := "user://pathtrace/"
const CONFIG := """[configuration]
entry_symbol = "gdext_rust_init"
compatibility_minimum = 4.4
reloadable = false

[libraries]
windows.debug.x86_64 = "godot_pathtrace.dll"
windows.release.x86_64 = "godot_pathtrace.dll"
"""


static func ensure() -> void:
	if OS.get_name() != "Windows" or ClassDB.class_exists("PathTraceEffect") or not FileAccess.file_exists(SRC):
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var dll := DIR + "godot_pathtrace.dll"
	var data := FileAccess.get_file_as_bytes(SRC)
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	h.update(data)
	if not FileAccess.file_exists(dll) or FileAccess.get_md5(dll) != h.finish().hex_encode():
		# Another copy of the game may have the old one loaded; then keep using that.
		var f := FileAccess.open(dll, FileAccess.WRITE)
		if f:
			f.store_buffer(data)
			f.close()
		elif not FileAccess.file_exists(dll):
			return
	var cfg := FileAccess.open(DIR + "pathtrace.gdextension", FileAccess.WRITE)
	if cfg:
		cfg.store_string(CONFIG)
		cfg.close()
	var status := GDExtensionManager.load_extension(DIR + "pathtrace.gdextension")
	if status != GDExtensionManager.LOAD_STATUS_OK and status != GDExtensionManager.LOAD_STATUS_ALREADY_LOADED:
		push_warning("Path tracing unavailable (extension load status %d)" % status)
