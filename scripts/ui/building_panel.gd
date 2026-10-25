extends CanvasLayer
## The one panel for every inventory interaction: Tab (your backpack alone), or [E] on a
## machine / container / the pod / a cache, which shows its info and slots on the left and
## your backpack on the right. Drag between grids; shift-click to quick-move.
##
## A target may implement:
##   ui_build(box: VBoxContainer, player)  info + buttons, rebuilt a few times a second
##   ui_static(box: VBoxContainer, player) built once under the info (keeps its own state)
##   get_inventories() -> Array            slot grids shown under the info

signal closed

const UI = preload("res://scripts/ui/ui_kit.gd")
const InventoryView = preload("res://scripts/ui/inventory_view.gd")
const REFRESH := 0.25

var _root: Control
var _info: VBoxContainer
var _target
var _player
var _t := 0.0


func _ready() -> void:
	layer = 5
	visible = false


func open(target, player) -> void:
	_target = target
	_player = player
	if _root:
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var box := UI.panel(_root, 600)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	box.add_child(row)

	var targets: Array = []
	if target and target.has_method("get_inventories"):
		targets = target.get_inventories()
	var all: Array = targets.duplicate()
	all.append(player.backpack)

	if target:
		var left := VBoxContainer.new()
		left.add_theme_constant_override("separation", 12)
		left.custom_minimum_size.x = 560
		row.add_child(left)
		_info = VBoxContainer.new()
		_info.add_theme_constant_override("separation", 8)
		left.add_child(_info)
		if target.has_method("ui_static"):
			var fixed := VBoxContainer.new()
			left.add_child(fixed)
			target.ui_static(fixed, player)
		for inv in targets:
			left.add_child(_view(inv, [player.backpack], mini(inv.slots.size(), 8)))
		row.add_child(VSeparator.new())
	else:
		_info = null

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	row.add_child(right)
	# Worn gear first; shift-click a suit in your backpack to put it on.
	var gear := _view(player.equipment, [player.backpack], 1)
	gear.subtitle_fn = func() -> String:
		return "Heat protected" if player.heat_protected() else "Empty"
	right.add_child(gear)
	var pack := _view(player.backpack, targets + [player.equipment], 8)
	pack.drop_fn = player.drop_slot
	pack.subtitle_fn = func() -> String:
		var w: float = player.backpack.weight()
		var cap: float = player.carry_capacity()
		return "%d / %d slots   ·   %.0f / %.0f kg%s" % [player.backpack.used_slots(), player.backpack.slots.size(),
			w, cap, "   OVERWEIGHT — slowed" if w > cap else ""]
	right.add_child(pack)
	_extra_backpack_info(right)

	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_END
	close_row.add_child(UI.button("Close  [E / Tab]", close))
	box.add_child(close_row)
	visible = true
	_refresh_info()


func _view(inv, quick: Array, columns: int) -> Control:
	var v := InventoryView.new()
	v.inv = inv
	v.columns = columns
	v.quick_targets = quick
	return v


func _extra_backpack_info(box: VBoxContainer) -> void:
	box.add_child(UI.label("Drag · shift-click to send · right-click to drop", 13, Color(0.6, 0.6, 0.58)))


func close() -> void:
	if not visible:
		return
	visible = false
	if _root:
		_root.queue_free()
		_root = null
	_target = null
	closed.emit()


func _process(dt: float) -> void:
	if not visible:
		return
	if _target != null and not is_instance_valid(_target):
		close()
		return
	_t += dt
	if _t >= REFRESH:
		_t = 0.0
		_refresh_info()


func _refresh_info() -> void:
	if _info == null or _target == null or not _target.has_method("ui_build"):
		return
	UI.clear(_info)
	_target.ui_build(_info, _player)


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel")
			or event.is_action_pressed("inventory")):
		get_viewport().set_input_as_handled()
		close()
