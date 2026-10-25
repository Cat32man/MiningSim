extends Panel
## One inventory slot: shows its stack, supports drag-and-drop and shift-click quick move.

const Items = preload("res://scripts/items/items.gd")
const Inventory = preload("res://scripts/items/inventory.gd")

const SIZE := 64.0

var inv
var index := 0
## Shift-click sends the stack to the first of these that accepts it.
var quick_targets: Array = []
## Right-click calls this with the slot index (the backpack drops the stack on the ground).
var drop_fn: Callable

var _icon: Panel
var _short: Label
var _count: Label
var _energy: ProgressBar


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.125, 0.13, 0.95)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	add_theme_stylebox_override("panel", sb)

	_icon = Panel.new()
	_icon.position = Vector2(8, 8)
	_icon.size = Vector2(SIZE - 16, SIZE - 16)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	_short = _label(18, HORIZONTAL_ALIGNMENT_CENTER)
	_short.position = Vector2(0, 18)
	_short.size = Vector2(SIZE, 24)
	_count = _label(14, HORIZONTAL_ALIGNMENT_RIGHT)
	_count.position = Vector2(0, SIZE - 22)
	_count.size = Vector2(SIZE - 5, 20)
	_energy = ProgressBar.new()
	_energy.show_percentage = false
	_energy.max_value = Items.BATTERY_CAPACITY
	_energy.position = Vector2(6, SIZE - 10)
	_energy.size = Vector2(SIZE - 12, 5)
	_energy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.45, 1.0, 0.5)
	_energy.add_theme_stylebox_override("fill", fill)
	add_child(_energy)
	refresh()


func _label(size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func refresh() -> void:
	var s = inv.slots[index]
	_icon.visible = s != null
	_short.visible = s != null
	_count.visible = s != null and s["count"] > 1
	_energy.visible = s != null and s.has("energy")
	tooltip_text = ""
	if s == null:
		return
	var def: Dictionary = Items.DEFS[s["id"]]
	var sb := StyleBoxFlat.new()
	sb.bg_color = def["color"].darkened(0.25)
	sb.border_color = def["color"]
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	_icon.add_theme_stylebox_override("panel", sb)
	_short.text = def["short"]
	_count.text = str(s["count"])
	tooltip_text = "%s ×%d" % [def["name"], s["count"]]
	if s.has("energy"):
		_energy.value = s["energy"]
		tooltip_text = "%s — %d%% (%d kJ)" % [def["name"], roundi(s["energy"] / Items.BATTERY_CAPACITY * 100.0), roundi(s["energy"])]


func _get_drag_data(_at: Vector2) -> Variant:
	if inv.slots[index] == null:
		return null
	var preview := Panel.new()
	preview.size = Vector2(SIZE - 16, SIZE - 16)
	preview.add_theme_stylebox_override("panel", _icon.get_theme_stylebox("panel"))
	preview.modulate.a = 0.85
	set_drag_preview(preview)
	return {"inv": inv, "index": index}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("inv"):
		return false
	var s = data["inv"].slots[data["index"]]
	return s != null and inv.accepts(s["id"])


func _drop_data(_at: Vector2, data: Variant) -> void:
	Inventory.transfer(data["inv"], data["index"], inv, index)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and event.shift_pressed:
		Inventory.quick_move(inv, index, quick_targets)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT 			and drop_fn.is_valid() and inv.slots[index] != null:
		drop_fn.call(index)
		accept_event()
