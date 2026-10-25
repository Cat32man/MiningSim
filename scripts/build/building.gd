extends StaticBody3D
## Base class for placed buildings. Subclasses override the hooks below.
##
## Power model (solved by power_grid.gd every frame, per connected network):
##   supply_kw()  what this building can produce right now
##   demand_kw()  what it wants right now
##   power_tick(dt, satisfaction, load)  satisfaction = share of demand met (0..1),
##                                       load = share of supply used (0..1)

const UI = preload("res://scripts/ui/ui_kit.gd")
const Materials = preload("res://scripts/world/materials.gd")
const Items = preload("res://scripts/items/items.gd")
const Inventory = preload("res://scripts/items/inventory.gd")
const BATTERY_CAPACITY := Items.BATTERY_CAPACITY
const HitFx = preload("res://scripts/enemies/hit_fx.gd")
const SfxLib = preload("res://scripts/audio/sfx.gd")
## Iron per this much missing HP when repairing.
const HP_PER_IRON := 15.0

var build_id := ""
## Placement preview: no collision, no grid, translucent.
var ghost := false
## Build-menu thumbnail: looks real, but no collision, sound or behaviour.
var preview := false
var grid
var network_id := -1
## Last satisfaction from the grid, for display.
var power_ratio := 0.0

## Power-node settings. Two nodes connect when within the larger of their ranges.
var is_power_node := true
var connect_range := 12.0
var cable_anchor := Vector3(0, 1.5, 0)
## Consumers that set this get a battery slot: it covers whatever the grid can't supply,
## so a machine runs with no generator at all if you drag a charged battery in.
var battery_inv

## Walls, floors, doors and so on (structure.gd): no power, not raided, destroyed at 0 HP.
var is_structure := false

## Bug damage: at 0 HP the machine breaks down and does nothing until repaired (E).
var max_hp := 100.0
var hp := 100.0
var broken := false
## Bugs bite it from within this far of its centre.
var bite_radius := 1.0

var _ghost_mat: StandardMaterial3D
var _broken_fx: Node3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	_build_visuals()
	if preview:
		set_process(false)
		set_physics_process(false)
		return
	if ghost:
		_make_ghost()
	else:
		for cs in _collision_shapes():
			var col := CollisionShape3D.new()
			col.shape = cs[0]
			col.transform = cs[1]
			add_child(col)


# --- Overridables ---------------------------------------------------------------

func _build_visuals() -> void:
	pass


## [shape, local transform] pairs. Most buildings are one box (the two hooks below).
func _collision_shapes() -> Array:
	return [[_collision_shape(), Transform3D(Basis.IDENTITY, _collision_offset())]]


func _collision_shape() -> Shape3D:
	var b := BoxShape3D.new()
	b.size = Vector3(1, 1, 1)
	return b


func _collision_offset() -> Vector3:
	return Vector3(0, 0.5, 0)


func supply_kw() -> float:
	return 0.0


func demand_kw() -> float:
	return 0.0


func power_tick(_dt: float, _satisfaction: float, _load: float) -> void:
	pass


## [E] on the building. Return true to open the building panel (ui_build + inventories).
func interact(_player) -> bool:
	return not get_inventories().is_empty()


## Slot grids shown in the building panel (Satisfactory-style machine slots).
func get_inventories() -> Array:
	return [battery_inv] if battery_inv else []


## Called by the grid after it computes `satisfaction`; draws the shortfall from the battery.
## Returns the satisfaction the machine actually runs at.
func battery_assist(satisfaction: float, dt: float) -> float:
	var want := demand_kw()
	if battery_inv == null or want <= 0.0 or satisfaction >= 1.0 or dt <= 0.0:
		return satisfaction
	var b = battery_inv.slots[0]
	if b == null or b.get("energy", 0.0) <= 0.0:
		return satisfaction
	var need: float = want * (1.0 - satisfaction) * dt  # kJ this frame
	var take: float = minf(need, b["energy"])
	b["energy"] -= take
	return satisfaction + (take / dt) / want


func battery_line() -> String:
	if battery_inv == null:
		return ""
	var b = battery_inv.slots[0]
	if b == null:
		return "Battery: none"
	var minutes: float = b["energy"] / maxf(demand_kw(), 0.001) / 60.0 if demand_kw() > 0.0 else 0.0
	return "Battery: %d%%%s" % [roundi(b["energy"] / BATTERY_CAPACITY * 100.0),
		"  (~%.1f min at this load)" % minutes if demand_kw() > 0.0 else ""]


## Fills the building panel. Called again on refresh.
func ui_build(_box: VBoxContainer, _player) -> void:
	pass


func hover_text() -> String:
	return display_name()


## Subclasses extend these; the base saves every inventory from get_inventories().
func get_state() -> Dictionary:
	var invs: Array = []
	for inv in get_inventories():
		invs.append(inv.to_data())
	return {"inventories": invs}


func apply_state(s: Dictionary) -> void:
	var data: Array = s.get("inventories", [])
	var invs := get_inventories()
	for i in mini(data.size(), invs.size()):
		invs[i].from_data(data[i])


## Everything inside (dropped as a cache when the building is removed).
func contents() -> Array:
	var out: Array = []
	for inv in get_inventories():
		for st in inv.slots:
			if st:
				out.append(st.duplicate())
	return out


## Running machines make noise: bugs pick these first for raids.
func is_running() -> bool:
	return supply_kw() > 0.0 or (demand_kw() > 0.0 and power_ratio > 0.0)


# --- Damage and repair -------------------------------------------------------------

func take_damage(amount: float, at: Vector3) -> void:
	if ghost or broken:
		return
	hp = maxf(hp - amount, 0.0)
	HitFx.ichor(get_parent(), at, global_position + (at - global_position) * 2.0, Color(1.0, 0.7, 0.3))
	if hp <= 0.0:
		set_broken(true)
		SfxLib.play_3d("break", global_position, get_parent(), 4.0)
	if grid:
		grid.building_attacked.emit(self)


func repair_cost() -> Dictionary:
	return {Items.IRON: maxi(1, ceili((max_hp - hp) / HP_PER_IRON))}


## Pays from `sources` and restores full HP. Returns false if you can't afford it.
func repair(sources: Array) -> bool:
	if hp >= max_hp or not Inventory.pay(sources, repair_cost()):
		return false
	hp = max_hp
	set_broken(false)
	return true


## Prompt shown instead of hover_text() while damaged.
func repair_prompt() -> String:
	var state := "BROKEN" if broken else "%d%%" % roundi(hp / max_hp * 100.0)
	return "%s — %s   ·   [E] repair (%s)" % [display_name(), state, Items.describe(repair_cost())]


func set_broken(on: bool) -> void:
	if broken != on and grid and is_inside_tree():
		broken = on
		grid.rebuild()  # a broken pole or machine drops out of its network (cables go)
	broken = on
	if not on:
		if _broken_fx:
			_broken_fx.queue_free()
			_broken_fx = null
		return
	if _broken_fx:
		return
	_broken_fx = Node3D.new()
	_broken_fx.position = cable_anchor * 0.8
	add_child(_broken_fx)
	var smoke := CPUParticles3D.new()
	smoke.amount = 14
	smoke.lifetime = 2.5
	smoke.direction = Vector3.UP
	smoke.spread = 15.0
	smoke.initial_velocity_min = 0.4
	smoke.initial_velocity_max = 0.9
	smoke.gravity = Vector3(0, 0.3, 0)
	smoke.scale_amount_min = 0.25
	smoke.scale_amount_max = 0.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	smoke.scale_amount_curve = curve
	var fade := Gradient.new()
	fade.set_color(0, Color(0.12, 0.11, 0.1, 0.7))
	fade.set_color(1, Color(0.2, 0.2, 0.2, 0.0))
	smoke.color_ramp = fade
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1.0
	puff.radial_segments = 8
	puff.rings = 4
	var pm := StandardMaterial3D.new()
	pm.vertex_color_use_as_albedo = true
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = pm
	smoke.mesh = puff
	_broken_fx.add_child(smoke)
	var sparks := CPUParticles3D.new()
	sparks.amount = 10
	sparks.lifetime = 0.6
	sparks.explosiveness = 0.8  # crackling bursts
	sparks.direction = Vector3.UP
	sparks.spread = 70.0
	sparks.initial_velocity_min = 1.5
	sparks.initial_velocity_max = 3.5
	sparks.gravity = Vector3(0, -9.8, 0)
	sparks.scale_amount_min = 0.02
	sparks.scale_amount_max = 0.04
	var spark := SphereMesh.new()
	spark.radius = 0.5
	spark.height = 1.0
	spark.radial_segments = 4
	spark.rings = 2
	spark.material = glow(Color(1.0, 0.6, 0.2), 6.0)
	sparks.mesh = spark
	_broken_fx.add_child(sparks)


# --- Helpers --------------------------------------------------------------------

func display_name() -> String:
	return preload("res://scripts/build/buildables.gd").DEFS[build_id]["name"]


func power_line() -> String:
	if grid == null:
		return ""
	var st: Vector2 = grid.network_stats(network_id)
	return "Network %d / %d kW" % [roundi(st.y), roundi(st.x)]


func set_ghost_valid(valid: bool) -> void:
	if _ghost_mat:
		_ghost_mat.albedo_color = Color(0.3, 1.0, 0.45, 0.35) if valid else Color(1.0, 0.3, 0.25, 0.35)


func _make_ghost() -> void:
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.albedo_color = Color(0.3, 1.0, 0.45, 0.35)
	_apply_ghost(self)


func _apply_ghost(n: Node) -> void:
	if n is MeshInstance3D:
		n.material_override = _ghost_mat
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif n is Light3D or n is GPUParticles3D or n is CPUParticles3D:
		n.visible = false
	for c in n.get_children():
		_apply_ghost(c)


static func mat(color: Color, metallic := 0.6, roughness := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


static func glow(color: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func box(size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	return mi


func cyl(radius: float, height: float, pos: Vector3, m: Material, top_radius := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = radius if top_radius < 0.0 else top_radius
	c.height = height
	c.radial_segments = 16
	mi.mesh = c
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	return mi
