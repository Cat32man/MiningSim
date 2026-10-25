extends CanvasLayer
## Text editor (from the title screen): every player-facing string in the scripts, grouped by
## file, editable in place. Edits are saved as a draft to res://text_edits.json; they don't
## change the game until they're written back into the scripts (tools/apply_text_edits.py).

signal closed

const UI = preload("res://scripts/ui/ui_kit.gd")
const TextCatalog = preload("res://scripts/tools/text_catalog.gd")

const EDITS_PATH := "res://text_edits.json"
const MAX_ROWS := 250
const ACCENT := Color(1.0, 0.72, 0.3)
const DIM := Color(0.55, 0.55, 0.53)
const CHANGED := Color(0.55, 0.85, 0.5)
const BAD := Color(1.0, 0.45, 0.35)
const AUTOSAVE_DELAY := 1.0

var _entries: Array = []  # from TextCatalog.scan(), plus "text"
var _files: Array = []
var _file_filter := ""
var _search: LineEdit
var _changed_only: CheckBox
var _file_list: ItemList
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _status: Label
var _save_in := -1.0


func _ready() -> void:
	layer = 11
	_entries = TextCatalog.scan()
	for e in _entries:
		e["text"] = e["original"]
		if not _files.has(e["file"]):
			_files.append(e["file"])
	_load_draft()
	_build()
	_refresh_files()
	_rebuild_rows()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.045, 0.043, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	col.add_child(top)
	var title := UI.label("TEXT EDITOR", 28, ACCENT)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(title)
	_search = LineEdit.new()
	_search.placeholder_text = "Search text or file..."
	_search.custom_minimum_size.x = 360
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t): _rebuild_rows())
	top.add_child(_search)
	_changed_only = CheckBox.new()
	_changed_only.text = "Changed only"
	_changed_only.toggled.connect(func(_on): _rebuild_rows())
	top.add_child(_changed_only)
	top.add_child(UI.button("Save", _save))
	top.add_child(UI.button("Back", func(): _save(); closed.emit()))

	var help := UI.label("Edit any line and it saves automatically to text_edits.json in the project folder. "
		+ "Keep %d / %s / %.1f placeholders (they're filled in by the game) and write \\n for a line break. "
		+ "When you're done, ask Claude to apply the text edits.", 15, DIM)
	col.add_child(help)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 0
	col.add_child(split)
	_file_list = ItemList.new()
	_file_list.custom_minimum_size.x = 280
	_file_list.item_selected.connect(_on_file_selected)
	split.add_child(_file_list)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 10)
	_scroll.add_child(_rows)

	_status = UI.label("", 15, DIM)
	col.add_child(_status)


func _short(path: String) -> String:
	return path.trim_prefix("res://scripts/")


func _refresh_files() -> void:
	var sel := _file_list.get_selected_items()
	var keep := sel[0] if not sel.is_empty() else 0
	_file_list.clear()
	_file_list.add_item("All text  (%d · %d changed)" % [_entries.size(), _changed_count("")])
	for f in _files:
		var n := _entries.filter(func(e): return e["file"] == f).size()
		var c := _changed_count(f)
		_file_list.add_item("%s  (%d%s)" % [_short(f), n, (" · %d changed" % c) if c > 0 else ""])
		if c > 0:
			_file_list.set_item_custom_fg_color(_file_list.item_count - 1, CHANGED)
	_file_list.select(keep)


func _changed_count(file: String) -> int:
	return _entries.filter(func(e): return (file == "" or e["file"] == file) and e["text"] != e["original"]).size()


func _on_file_selected(i: int) -> void:
	_file_filter = "" if i == 0 else _files[i - 1]
	_rebuild_rows()
	_scroll.scroll_vertical = 0


func _rebuild_rows() -> void:
	UI.clear(_rows)
	var q := _search.text.strip_edges().to_lower()
	var shown := 0
	var total := 0
	for e in _entries:
		if _file_filter != "" and e["file"] != _file_filter:
			continue
		if _changed_only.button_pressed and e["text"] == e["original"]:
			continue
		if q != "" and not (e["original"].to_lower().contains(q) or e["text"].to_lower().contains(q)
				or _short(e["file"]).to_lower().contains(q)):
			continue
		total += 1
		if shown < MAX_ROWS:
			_rows.add_child(_row(e))
			shown += 1
	if total > shown:
		_rows.add_child(UI.label("…and %d more — pick a file or search to narrow it down." % (total - shown), 15, DIM))
	if total == 0:
		_rows.add_child(UI.label("Nothing matches.", 16, DIM))


func _row(e: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var where := UI.label("", 13, DIM)
	where.autowrap_mode = TextServer.AUTOWRAP_OFF
	where.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	where.clip_text = true
	box.add_child(where)

	var edit: Control
	if e["original"].length() > 70:
		var te := TextEdit.new()
		te.text = e["text"]
		te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		te.custom_minimum_size.y = 64
		te.text_changed.connect(func(): _on_edit(e, te.text, where, te))
		edit = te
	else:
		var le := LineEdit.new()
		le.text = e["text"]
		le.text_changed.connect(func(t): _on_edit(e, t, where, le))
		edit = le
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_size_override("font_size", 17)
	box.add_child(edit)

	var revert := Button.new()
	revert.text = "↺"
	revert.tooltip_text = "Back to the original"
	revert.pressed.connect(func():
		edit.set("text", e["original"])
		_on_edit(e, e["original"], where, edit))
	var line := HBoxContainer.new()
	box.remove_child(edit)
	line.add_child(edit)
	line.add_child(revert)
	box.add_child(line)
	_style_row(e, where, edit)
	return box


func _on_edit(e: Dictionary, text: String, where: Label, edit: Control) -> void:
	# Newlines typed into a box become \n so the edit fits back into a one-line literal.
	e["text"] = text.replace("\n", "\\n")
	_style_row(e, where, edit)
	_save_in = AUTOSAVE_DELAY


func _style_row(e: Dictionary, where: Label, edit: Control) -> void:
	var text: String = e["text"]
	var info := "%s:%d    %s" % [_short(e["file"]), e["line"], e["context"]]
	var color := DIM
	var want := TextCatalog.specifiers(e["original"])
	var have := TextCatalog.specifiers(text)
	if want != have:
		info = "Placeholders must stay %s (now %s)    %s" % [" ".join(want), " ".join(have) if have else "none", info]
		color = BAD
	elif text != e["original"]:
		info = "was: \"%s\"    %s" % [e["original"], info]
		color = CHANGED
	where.text = info
	where.add_theme_color_override("font_color", color)
	edit.modulate = Color(1, 1, 1) if text == e["original"] else Color(0.85, 1.0, 0.85)


func _process(dt: float) -> void:
	if _save_in > 0.0:
		_save_in -= dt
		if _save_in <= 0.0:
			_save()


func _save() -> void:
	_save_in = -1.0
	var edits: Array = []
	for e in _entries:
		if e["text"] != e["original"]:
			edits.append({"file": e["file"], "line": e["line"], "original": e["original"], "text": e["text"]})
	var f := FileAccess.open(EDITS_PATH, FileAccess.WRITE)
	if f == null:
		_status.text = "Couldn't write %s (error %d)" % [EDITS_PATH, FileAccess.get_open_error()]
		_status.add_theme_color_override("font_color", BAD)
		return
	f.store_string(JSON.stringify({
		"about": "MiningSim text edits. Strings are in source form (\\n = line break). Apply with tools/apply_text_edits.py.",
		"edits": edits,
	}, "\t"))
	f.close()
	_status.text = "%d edits saved to %s" % [edits.size(), ProjectSettings.globalize_path(EDITS_PATH)]
	_status.add_theme_color_override("font_color", CHANGED if edits.size() > 0 else DIM)
	_refresh_files()


## Re-applies a saved draft: each edit goes to the same string in the same file, nearest
## to its old line (lines shift as code changes).
func _load_draft() -> void:
	if not FileAccess.file_exists(EDITS_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(EDITS_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	for ed in data.get("edits", []):
		var best: Dictionary = {}
		var best_d := INF
		for e in _entries:
			if e["file"] == ed.get("file") and e["original"] == ed.get("original") and e["text"] == e["original"]:
				var d := absf(e["line"] - float(ed.get("line", 0)))
				if d < best_d:
					best_d = d
					best = e
		if not best.is_empty():
			best["text"] = ed.get("text", best["original"])
