extends VBoxContainer
## Scrollable grid of recipe cards with rendered models, like the build menu. Built once
## when a machine panel opens and kept: it re-reads its entries a few times a second and
## only rebuilds when the set of recipes changes, so scrolling and hover survive.
##
## entries_fn() -> Array of {id, name, desc, cost, model, state, progress, tag}
##   cost      short text under the name ("30 Fe · 12 El · 10 s")
##   model     ItemModels key for the thumbnail
##   state     "can" (click works), "cant" (greyed, red cost), "busy" (crafting, shows
##             progress), "selected" (lit border, shows progress)
## on_pick(id) is called when a "can" card is clicked.

const UI = preload("res://scripts/ui/ui_kit.gd")
const ThumbStudio = preload("res://scripts/ui/thumb_studio.gd")
const ItemModels = preload("res://scripts/ui/item_models.gd")
const Items = preload("res://scripts/items/items.gd")

const COLUMNS := 3
const CARD := Vector2(172, 190)
const THUMB := Vector2i(312, 224)  # rendered at 2x, shown at half size
const ACCENT := Color(1.0, 0.75, 0.4)
const DIM := Color(0.6, 0.6, 0.58)
const BAD := Color(0.85, 0.4, 0.32)
const SPIN_SPEED := 0.6
const REFRESH := 0.25

var entries_fn: Callable
var on_pick: Callable
var rows := 2  # visible rows before it scrolls

var _grid: GridContainer
var _info: Label
var _cards := {}  # id -> {card, thumb, name, cost, bar, fill, tag}
var _entries := {}  # id -> latest entry
var _thumbs := {}  # model key -> {viewport, pivot}
var _signature := ""
var _hovered := ""
var _t := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(COLUMNS * (CARD.x + 12) + 6, CARD.y * rows + 12 * (rows - 1) + 4)
	add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	_info = UI.label("", 14, DIM)
	_info.custom_minimum_size.y = 40
	add_child(_info)
	refresh()


func _process(dt: float) -> void:
	if _hovered != "" and _entries.has(_hovered):
		var key: String = _entries[_hovered]["model"]
		if _thumbs.has(key):
			_thumbs[key]["pivot"].rotate_y(dt * SPIN_SPEED)
	_t += dt
	if _t >= REFRESH:
		_t = 0.0
		refresh()


func refresh() -> void:
	if not entries_fn.is_valid():
		return
	var list: Array = entries_fn.call()
	var ids: Array[String] = []
	for e in list:
		ids.append(e["id"])
	var sig := ",".join(ids)
	if sig != _signature:
		_signature = sig
		_rebuild(list)
	for e in list:
		_entries[e["id"]] = e
		_update_card(e)


func _rebuild(list: Array) -> void:
	_set_hover("")
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_cards.clear()
	_entries.clear()
	for e in list:
		_entries[e["id"]] = e
		_grid.add_child(_card(e))


func _card(e: Dictionary) -> Control:
	var id: String = e["id"]
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)

	var thumb := TextureRect.new()
	thumb.texture = _thumb(e["model"])
	thumb.custom_minimum_size = Vector2(THUMB) * 0.5
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(thumb)

	# Corner tag ("UPGRADE", "SELECTED").
	var tag := UI.label("", 11, ACCENT)
	tag.autowrap_mode = TextServer.AUTOWRAP_OFF
	tag.position = Vector2(0, -2)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.add_child(tag)

	var name_l := UI.label("", 15)
	name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.clip_text = true
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_l)
	var cost_l := UI.label("", 13)
	cost_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	cost_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cost_l.clip_text = true
	cost_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(cost_l)

	# Progress bar along the bottom while it's being made.
	var bar := ColorRect.new()
	bar.color = Color(1, 1, 1, 0.08)
	bar.custom_minimum_size = Vector2(0, 4)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bar)
	var fill := ColorRect.new()
	fill.color = ACCENT
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(fill)

	card.mouse_entered.connect(func():
		_set_hover(id)
		_update_card(_entries[id]))
	card.mouse_exited.connect(func():
		if _hovered == id:
			_set_hover("")
		if _entries.has(id):
			_update_card(_entries[id]))
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if _entries.has(id) and _entries[id]["state"] == "can" and on_pick.is_valid():
				on_pick.call(id)
				refresh())
	_cards[id] = {"card": card, "thumb": thumb, "name": name_l, "cost": cost_l, "bar": bar, "fill": fill, "tag": tag}
	return card


func _update_card(e: Dictionary) -> void:
	var c: Dictionary = _cards.get(e["id"], {})
	if c.is_empty():
		return
	var state: String = e["state"]
	var hover: bool = _hovered == e["id"]
	var lit := state == "selected" or state == "busy"
	c["card"].add_theme_stylebox_override("panel", _style(hover, state))
	c["thumb"].modulate = Color(1, 1, 1, 0.45) if state == "cant" else Color.WHITE
	c["name"].text = e["name"]
	c["name"].add_theme_color_override("font_color", DIM if state == "cant" else Color(0.95, 0.93, 0.9))
	c["cost"].text = e["cost"]
	c["cost"].add_theme_color_override("font_color", BAD if state == "cant" else ACCENT)
	var tag: String = e.get("tag", "")
	if state == "busy":
		tag = "MAKING"
	elif state == "selected":
		tag = "SELECTED"
	c["tag"].text = tag
	c["bar"].visible = lit
	var bar: ColorRect = c["bar"]
	c["fill"].size = Vector2(bar.size.x * clampf(e.get("progress", 0.0), 0.0, 1.0), 4)
	if hover:
		_info.text = "%s — %s" % [e["name"], e["desc"]]


func _style(hover: bool, state: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.13, 0.14) if hover else Color(0.1, 0.1, 0.11)
	if state == "selected" or state == "busy":
		sb.border_color = ACCENT
		sb.bg_color = Color(0.16, 0.14, 0.11)
	elif hover:
		sb.border_color = ACCENT if state == "can" else Color(1, 1, 1, 0.18)
	else:
		sb.border_color = Color(1, 1, 1, 0.07)
	sb.set_border_width_all(2 if hover or state == "selected" or state == "busy" else 1)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(8)
	return sb


## "30 Fe · 10 El"
static func short_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for id in cost:
		parts.append("%d %s" % [cost[id], Items.DEFS[id]["short"]])
	return " · ".join(parts) if not parts.is_empty() else "Free"


func _thumb(key: String) -> Texture2D:
	if not _thumbs.has(key):
		_thumbs[key] = ThumbStudio.make(self, ItemModels.make(key), THUMB)
	return _thumbs[key]["viewport"].get_texture()


## The hovered card re-renders every frame while its model turns; the others stay still.
func _set_hover(id: String) -> void:
	if _hovered != "" and _entries.has(_hovered):
		var old: String = _entries[_hovered]["model"]
		if _thumbs.has(old):
			_thumbs[old]["viewport"].render_target_update_mode = SubViewport.UPDATE_DISABLED
	_hovered = id
	if id == "":
		_info.text = ""
	elif _entries.has(id):
		var key: String = _entries[id]["model"]
		if _thumbs.has(key):
			_thumbs[key]["viewport"].render_target_update_mode = SubViewport.UPDATE_ALWAYS
