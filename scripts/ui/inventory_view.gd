extends VBoxContainer
## Title + grid of slots for one Inventory. Updates itself when the inventory changes.

const Slot = preload("res://scripts/ui/slot.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")

var inv
var columns := 8
var quick_targets: Array = []
## Optional extra line under the title (e.g. carry weight).
var subtitle_fn: Callable
## Passed to every slot: right-click drops (see slot.gd).
var drop_fn: Callable

var _slots: Array = []
var _subtitle: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	add_child(UI.label(inv.title.to_upper(), 16, Color(1.0, 0.75, 0.4)))
	_subtitle = UI.label("", 14, Color(0.7, 0.7, 0.68))
	add_child(_subtitle)
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)
	for i in inv.slots.size():
		var s := Slot.new()
		s.inv = inv
		s.index = i
		s.quick_targets = quick_targets
		s.drop_fn = drop_fn
		grid.add_child(s)
		_slots.append(s)
	inv.changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if inv.changed.is_connected(_refresh):
		inv.changed.disconnect(_refresh)


func _refresh() -> void:
	for s in _slots:
		s.refresh()
	_subtitle.visible = subtitle_fn.is_valid()
	if subtitle_fn.is_valid():
		_subtitle.text = subtitle_fn.call()
