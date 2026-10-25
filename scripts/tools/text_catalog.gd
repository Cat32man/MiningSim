extends RefCounted
## Finds the player-facing string literals in the game's scripts, for the text editor.
## Strings are kept in their source form (escapes like \n stay as typed), so an edit can be
## written straight back over the literal. tools/apply_text_edits.py does that.

const ROOT := "res://scripts"
const SKIP_FILES := ["res://scripts/ui/text_editor.gd", "res://scripts/tools/text_catalog.gd"]
## Lines that only carry code-facing strings (paths, ids, debug output, test failures).
const SKIP_LINE := ["preload(", "load(", "_meta(", "find_child(", "get_node(", "Input.", "is_action",
	"print(", "push_error(", "push_warning(", "_fail(", "Sfx.", "tween_property(", "add_theme_",
	"shader_type", "get_animation(", "has_animation(", "InputMap."]

static var _ident := RegEx.create_from_string("^[a-z0-9_:/.\\-]+$")
static var _camel := RegEx.create_from_string("^[A-Za-z0-9_]*[a-z][A-Z][A-Za-z0-9_]*$|^[A-Za-z_]+[0-9]+[A-Za-z]*$")
static var _roman := RegEx.create_from_string("^[IVX]+$")
static var _letter := RegEx.create_from_string("[A-Za-z]")
static var _spec := RegEx.create_from_string("%[-+ 0#]*[0-9]*(\\.[0-9]+)?[sdfxXc%]")


## Every entry: {file, line (1-based), original, context}.
static func scan() -> Array:
	var out: Array = []
	for path in _scripts(ROOT):
		if path in SKIP_FILES:
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var lines := f.get_as_text().split("\n")
		for i in lines.size():
			var line: String = lines[i]
			var code := line.strip_edges()
			if code.begins_with("#") or code.begins_with("##"):
				continue
			if SKIP_LINE.any(func(s): return line.contains(s)):
				continue
			for raw in strings_in_line(line):
				if is_player_text(raw):
					out.append({"file": path, "line": i + 1, "original": raw, "context": code})
	return out


static func _scripts(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_scripts(dir.path_join(sub)))
	out.sort()
	return out


## The contents of each quoted literal on the line, as written (escapes untouched).
## Stops at a comment; skips StringName (&"") and NodePath (^"", $"") literals.
static func strings_in_line(line: String) -> Array:
	var out: Array = []
	var i := 0
	var n := line.length()
	while i < n:
		var c := line[i]
		if c == "#":
			break
		if c == "\"" or c == "'":
			var j := i + 1
			while j < n and line[j] != c:
				if line[j] == "\\":
					j += 1
				j += 1
			var prefix := line[i - 1] if i > 0 else ""
			if prefix not in ["&", "^", "$"]:
				out.append(line.substr(i + 1, j - i - 1))
			i = j + 1
			continue
		i += 1
	return out


static func is_player_text(raw: String) -> bool:
	if raw.length() < 2 or raw.begins_with("res://") or raw.begins_with("user://") or raw.begins_with("--"):
		return false
	if not _letter.search(_spec.sub(raw, "", true)):
		return false  # only numbers / format specifiers / symbols
	if _roman.search(raw):
		return false  # tier numerals
	if _ident.search(raw):
		return false
	if _camel.search(raw):
		return false
	return true


## The format specifiers (%d, %s, %.1f...) a string uses, in order.
static func specifiers(raw: String) -> Array:
	return _spec.search_all(raw).map(func(m): return m.get_string()).filter(func(s): return s != "%%")
