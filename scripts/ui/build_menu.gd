extends CanvasLayer
## Build menu (tap Q): a scrollable grid of cards, each with a rendered view of the part.
## Two tabs: machines and structure pieces. Click a card or press its number (0 = 10th).
## The card under the mouse slowly turns its model.

signal selected(id: String)
signal closed

const UI = preload("res://scripts/ui/ui_kit.gd")
const Buildables = preload("res://scripts/build/buildables.gd")
const Items = preload("res://scripts/items/items.gd")
const Inventory = preload("res://scripts/items/inventory.gd")
const ThumbStudio = preload("res://scripts/ui/thumb_studio.gd")

const COLUMNS := 4
const CARD := Vector2(176, 206)
const THUMB := Vector2i(352, 264)  # rendered at 2x, shown at half size
const ACCENT := Color(1.0, 0.75, 0.4)
const DIM := Color(0.6, 0.6, 0.58)
const SPIN_SPEED := 0.6

var _player
var _tab := 0  # 0 machines, 1 structure
var _box: VBoxContainer
var _grid: GridContainer
var _info: Label
var _thumbs := {}  # id -> {viewport, pivot}
var _hovered := ""


func _ready() -> void:
	layer = 5
	visible = false
	_box = UI.panel(self, COLUMNS * (CARD.x + 12) + 54)


func open(player) -> void:
	_player = player
	visible = true
	_rebuild()


func close() -> void:
	if not visible:
		return
	visible = false
	_set_hover("")
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("build"):
		get_viewport().set_input_as_handled()
		close()
		return
	var order := _order()
	if event is InputEventKey and event.pressed:
		var i := -1
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_9:
			i = event.physical_keycode - KEY_1
		elif event.physical_keycode == KEY_0:
			i = 9
		if i >= 0 and i < order.size():
			get_viewport().set_input_as_handled()
			_pick(order[i])


func _order() -> Array:
	return Buildables.STRUCTURE_ORDER if _tab == 1 else Buildables.ORDER


func _rebuild() -> void:
	UI.clear(_box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var title := UI.label("BUILD", 26, ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	for t in 2:
		var b := UI.button(["Machines", "Structure"][t], func(): if _tab != t: _tab = t; _rebuild())
		b.custom_minimum_size = Vector2(130, 34)
		if _tab == t:
			# The open tab is lit up, the other one sits back.
			for state in ["font_color", "font_hover_color", "font_pressed_color"]:
				b.add_theme_color_override(state, ACCENT)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.16, 0.14, 0.11)
			sb.border_color = ACCENT
			sb.border_width_bottom = 2
			b.add_theme_stylebox_override("normal", sb)
			b.add_theme_stylebox_override("hover", sb)
		else:
			b.add_theme_color_override("font_color", DIM)
		head.add_child(b)
	_box.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(COLUMNS * (CARD.x + 12) + 14, CARD.y * 2 + 14)
	_box.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)

	var sources: Array = _player.cost_sources()
	var order := _order()
	for i in order.size():
		var def: Dictionary = Buildables.DEFS[order[i]]
		var locked := _locked(order[i])
		_grid.add_child(_card(order[i], (i + 1) % 10, not locked and Inventory.can_afford(sources, def["cost"]), locked))

	_info = UI.label("", 15, DIM)
	_info.autowrap_mode = TextServer.AUTOWRAP_OFF
	_info.custom_minimum_size.y = 22
	_box.add_child(_info)


## Blueprints you haven't found yet.
func _locked(id: String) -> bool:
	var need: String = Buildables.DEFS[id].get("requires", "")
	if need == "" or _player.progress == null:
		return need != ""
	if need.begins_with("bp:"):
		return not _player.progress.blueprints.has(need.trim_prefix("bp:"))
	return not _player.progress.get(need)


func _card(id: String, key: int, can: bool, locked := false) -> Control:
	var def: Dictionary = Buildables.DEFS[id]
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _card_style(false, can))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)

	var thumb := TextureRect.new()
	thumb.texture = _thumb(id)
	thumb.custom_minimum_size = Vector2(THUMB) * 0.5
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if locked:
		thumb.modulate = Color(0, 0, 0, 0.85)  # silhouette only
	elif not can:
		thumb.modulate = Color(1, 1, 1, 0.45)
	col.add_child(thumb)

	var name_l := UI.label("???" if locked else def["name"], 15, Color(0.95, 0.93, 0.9) if can else DIM)
	name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.clip_text = true
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_l)
	var cost_text: String = ("Locked · " + def.get("locked_hint", "")) if locked else _short_cost(def["cost"])
	var cost_l := UI.label(cost_text, 13, ACCENT if can else (DIM if locked else Color(0.85, 0.4, 0.32)))
	cost_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	cost_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(cost_l)

	# Number key badge in the corner.
	var badge := UI.label(str(key), 13, DIM)
	badge.autowrap_mode = TextServer.AUTOWRAP_OFF
	badge.position = Vector2(0, -2)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.add_child(badge)

	card.mouse_entered.connect(func():
		card.add_theme_stylebox_override("panel", _card_style(true, can))
		_info.text = "%s — %s" % ["???" if locked else def["name"], def.get("locked_hint", "") if locked else def["desc"]]
		_set_hover(id))
	card.mouse_exited.connect(func():
		card.add_theme_stylebox_override("panel", _card_style(false, can))
		if _hovered == id:
			_info.text = ""
			_set_hover(""))
	card.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_pick(id))
	return card


func _card_style(hover: bool, can: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.13, 0.14) if hover else Color(0.1, 0.1, 0.11)
	sb.border_color = ACCENT if hover and can else (Color(1, 1, 1, 0.18) if hover else Color(1, 1, 1, 0.07))
	sb.set_border_width_all(2 if hover else 1)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(8)
	return sb


## "30 Fe · 10 El"
static func _short_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for id in cost:
		parts.append("%d %s" % [cost[id], Items.DEFS[id]["short"]])
	return " · ".join(parts) if not parts.is_empty() else "Free"


func _pick(id: String) -> void:
	if _locked(id):
		return
	if not Inventory.can_afford(_player.cost_sources(), Buildables.DEFS[id]["cost"]):
		_info.text = "Need %s" % Items.describe(Buildables.DEFS[id]["cost"])
		return
	visible = false
	_set_hover("")
	selected.emit(id)


# --- Thumbnails -----------------------------------------------------------------------

## A rendered view of the part, made once in its own little world and kept.
func _thumb(id: String) -> Texture2D:
	if not _thumbs.has(id):
		var model: Node3D = Buildables.make(id)
		model.preview = true
		_thumbs[id] = ThumbStudio.make(self, model, THUMB)
	return _thumbs[id]["viewport"].get_texture()


## The hovered card re-renders every frame while its model turns; the others stay still.
func _set_hover(id: String) -> void:
	if _hovered != "" and _thumbs.has(_hovered):
		_thumbs[_hovered]["viewport"].render_target_update_mode = SubViewport.UPDATE_DISABLED
	_hovered = id
	if id != "" and _thumbs.has(id):
		_thumbs[id]["viewport"].render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _process(dt: float) -> void:
	if visible and _hovered != "" and _thumbs.has(_hovered):
		_thumbs[_hovered]["pivot"].rotate_y(dt * SPIN_SPEED)
