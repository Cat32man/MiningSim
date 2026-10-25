extends Node3D
## Spawn drop pod: a small storage hold, drill refuel, shotgun recharge, and the terminal
## for building/upgrading the hand drill. Origin sits at the base of the pod.

const Progress = preload("res://scripts/progression/progress.gd")
const Inventory = preload("res://scripts/items/inventory.gd")
const Items = preload("res://scripts/items/items.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")

const ROMAN := ["I", "II", "III", "IV", "V"]
const PodScene = preload("res://assets/droppod/droppod.glb")
const POD_SCALE := 2.0
const POD_YAW := 90.0  # panel (model -X) faces +Z, toward the spawn point
const POD_TILT := Vector3(6.0, 0.0, -5.0)  # degrees: crash-landed lean
const POD_SINK := 0.35  # base buried a little so the tilt doesn't leave it floating
## The pod has limited space: build storage containers for more.
const STORAGE_SLOTS := 12

## Set by main.
var progress
var storage = Inventory.new(STORAGE_SLOTS, "Drop pod storage")


func _ready() -> void:
	# The artist's pod (assets/droppod/droppod.glb): authored ~2.35 m tall with its origin at
	# the centre and the glowing control panel on its -X side. Scaled up, turned so the panel
	# faces the spawn point, tilted and sunk into the floor like it hit hard.
	var tilt := Node3D.new()
	tilt.rotation = Vector3(deg_to_rad(POD_TILT.x), deg_to_rad(POD_YAW), deg_to_rad(POD_TILT.z))
	tilt.position.y = -POD_SINK
	add_child(tilt)
	var model: Node3D = PodScene.instantiate()
	model.scale = Vector3.ONE * POD_SCALE
	model.position.y = POD_SCALE  # model origin is at its centre; lift so the base sits at y = 0
	tilt.add_child(model)

	# Collision follows the real hull (trimesh of each mesh, so the tilt is included).
	var body := StaticBody3D.new()
	body.collision_layer = 2
	add_child(body)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if mi.scale.x < 0.0 or mi.scale.y < 0.0:
			continue  # mirrored detail parts: tiny, and negative scale breaks trimesh collision
		var shape := CollisionShape3D.new()
		shape.shape = mi.mesh.create_trimesh_shape()
		body.add_child(shape)
		shape.global_transform = mi.global_transform if mi.is_inside_tree() else _relative_xform(mi)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.65)
	light.light_energy = 2.2
	light.omni_range = 22.0
	light.shadow_enabled = true
	light.position = Vector3(0, 3.0, 2.6)
	add_child(light)


## Transform of `n` relative to this pod, for nodes not yet in the tree.
func _relative_xform(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p and p != self:
		if p is Node3D:
			t = p.transform * t
		p = p.get_parent()
	return t


func is_in_reach(p: Vector3, reach: float) -> bool:
	var flat := Vector2(p.x - global_position.x, p.z - global_position.z)
	return flat.length() < reach + 1.5 and absf(p.y - global_position.y) < 4.0


func get_inventories() -> Array:
	return [storage]


## Terminal half of the pod panel: deposit button, build the drill, drill upgrades.
func ui_build(box: VBoxContainer, player) -> void:
	box.add_child(UI.label("DROP POD TERMINAL", 26, Color(1.0, 0.75, 0.4)))
	box.add_child(UI.label("Drill refuelled · Shotgun recharged", 14, Color(0.7, 0.7, 0.68)))
	box.add_child(UI.button("Deposit all ore", func(): player.deposit_ore_into(storage)))
	box.add_child(HSeparator.new())
	var sources: Array = player.cost_sources()
	if not progress.drill_owned:
		_row(box, "Hand Drill\n" + Progress.describe(Progress.DRILL_COST),
			"Build", func(): _purchased(player, progress.buy_drill(player.cost_sources())),
			Inventory.can_afford(sources, Progress.DRILL_COST))
		return
	box.add_child(UI.label("HAND DRILL UPGRADES", 18, Color(1.0, 0.75, 0.4)))
	for track in Progress.TRACKS:
		var tier: int = progress.tiers[track]
		var unit: String = Progress.TRACK_UNITS[track]
		var title := "%s  %s/V   (%s %s)" % [Progress.TRACK_NAMES[track], ROMAN[tier - 1],
			_num(progress.stat(track)), unit]
		var cost: Dictionary = progress.next_cost(track)
		if cost.is_empty():
			_row(box, title + "\nFully upgraded", "MAX", func(): pass, false)
		else:
			_row(box, "%s → %s %s\nCost: %s" % [title, _num(progress.next_stat(track)), unit, Progress.describe(cost)],
				"Upgrade", func(): _purchased(player, progress.upgrade(track, player.cost_sources())),
				Inventory.can_afford(sources, cost))


func _purchased(player, ok: bool) -> void:
	if ok:
		player.fuel = player.fuel_max()


func _row(box: VBoxContainer, text: String, button_text: String, action: Callable, enabled: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l := UI.label(text, 15)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(UI.button(button_text, action, enabled))
	box.add_child(row)


func _num(v: float) -> String:
	return str(snappedf(v, 0.01)).trim_suffix(".0")
