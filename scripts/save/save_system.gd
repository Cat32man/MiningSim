extends RefCounted
## Save slots on disk: user://saves/slot_N.save, zstd-compressed Godot binary Variants.
## Writes go to a temp file first so a crash mid-save can't corrupt the existing slot.

const DIR := "user://saves"
const FORMAT_VERSION := 1


static func path(slot: int) -> String:
	return "%s/slot_%d.save" % [DIR, slot]


static func exists(slot: int) -> bool:
	return FileAccess.file_exists(path(slot))


static func write(slot: int, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	data["version"] = FORMAT_VERSION
	var tmp := path(slot) + ".tmp"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_error("Save failed: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_var(data)
	f.close()
	if exists(slot):
		DirAccess.remove_absolute(path(slot))
	return DirAccess.rename_absolute(tmp, path(slot)) == OK


static func read(slot: int) -> Dictionary:
	if not exists(slot):
		return {}
	var f := FileAccess.open_compressed(path(slot), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var data = f.get_var()
	if typeof(data) != TYPE_DICTIONARY or data.get("version", 0) > FORMAT_VERSION:
		return {}
	return data


static func delete(slot: int) -> void:
	if exists(slot):
		DirAccess.remove_absolute(path(slot))
