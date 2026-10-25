extends Node3D
## A pile of items left in the world: your body after death, or a cache (contents of a
## removed container, refunds that didn't fit, converted old rigs). Never moves — goods
## never teleport — and is not solid. [E] takes everything that fits; the rest stays.

const Inventory = preload("res://scripts/items/inventory.gd")
const Items = preload("res://scripts/items/items.gd")

const REACH := 2.2
const SLOTS := 48

## "body" or "cache".
var kind := "body"
var inv = Inventory.new(SLOTS, "Contents")
## Set by main on bodies: the oldest body warns that the next death destroys it.
var is_oldest := false:
	set(v):
		is_oldest = v
		_refresh_label()

var _label: Label3D


func _ready() -> void:
	add_to_group("caches")
	if kind == "body":
		add_to_group("bodies")
	var body := kind == "body"
	var pack := StandardMaterial3D.new()
	pack.albedo_color = Color(0.45, 0.32, 0.14) if body else Color(0.3, 0.33, 0.36)
	pack.roughness = 0.8
	var strap := StandardMaterial3D.new()
	strap.albedo_color = Color(0.15, 0.15, 0.16)
	var beacon := StandardMaterial3D.new()
	beacon.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beacon.albedo_color = Color(1.0, 0.72, 0.3, 0.25) if body else Color(0.5, 0.8, 1.0, 0.22)

	_box(Vector3(0.55, 0.25, 0.75) if body else Vector3(0.8, 0.5, 0.6), Vector3(0, 0.15, 0), pack)
	_box(Vector3(0.6, 0.06, 0.08), Vector3(0, 0.3, 0.15), strap)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.04
	cyl.height = 3.0
	beam.mesh = cyl
	beam.material_override = beacon
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = 1.6
	add_child(beam)
	var light := OmniLight3D.new()
	light.light_color = beacon.albedo_color
	light.light_energy = 0.8
	light.omni_range = 5.0
	light.position.y = 0.6
	add_child(light)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 1.2
	_label.font_size = 28
	_label.pixel_size = 0.004
	_label.outline_size = 8
	add_child(_label)
	inv.changed.connect(_refresh_label)
	_refresh_label()


func _refresh_label() -> void:
	if _label == null:
		return
	_label.text = ("Your body" if kind == "body" else "Cache") + "\n" + summary()
	if is_oldest:
		_label.text += "\n⚠ next death destroys this"
	_label.modulate = Color(1.0, 0.5, 0.4) if is_oldest else Color(1.0, 0.85, 0.6)


func summary() -> String:
	var totals := {}
	for s in inv.slots:
		if s:
			totals[s["id"]] = totals.get(s["id"], 0) + s["count"]
	return Items.describe(totals) if not totals.is_empty() else "empty"


func in_reach(p: Vector3) -> bool:
	return global_position.distance_to(p) < REACH


## Take everything that fits. Returns true when empty (caller frees it).
func recover(backpack) -> bool:
	return inv.move_all_to(backpack)


func get_state() -> Dictionary:
	return {"kind": kind, "pos": global_position, "slots": inv.to_data()}


func _box(size: Vector3, pos: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
