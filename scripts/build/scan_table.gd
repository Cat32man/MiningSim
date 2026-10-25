extends "res://scripts/build/building.gd"
## Scanning table: [E] opens a hologram map of the caves around it (see ui/scan_view.gd).
## The map is steady near the table and near scanning towers, and wobbles apart further out.
## Tags big hidden ore veins and the silicon caves' signal. Needs no power.

## Metres around the table where the map is steady.
const STABLE_RADIUS := 64.0

var _holo: Node3D
var _sweep: MeshInstance3D
var _rings: Array = []
var _light: OmniLight3D
var _t := randf() * 5.0


func _init() -> void:
	is_power_node = false


func _build_visuals() -> void:
	var steel := mat(Color(0.26, 0.27, 0.29), 0.8, 0.4)
	var dark := mat(Color(0.1, 0.1, 0.11), 0.6, 0.35)
	var paint := mat(Color(0.8, 0.52, 0.12), 0.35, 0.55)
	for x in [-0.85, 0.85]:
		for z in [-0.5, 0.5]:
			box(Vector3(0.1, 0.9, 0.1), Vector3(x, 0.45, z), steel)
	box(Vector3(2.0, 0.12, 1.3), Vector3(0, 0.95, 0), steel)
	box(Vector3(1.8, 0.03, 1.1), Vector3(0, 1.02, 0), dark)  # glass top
	box(Vector3(2.04, 0.05, 0.06), Vector3(0, 0.98, 0.66), paint)
	box(Vector3(2.04, 0.05, 0.06), Vector3(0, 0.98, -0.66), paint)
	cyl(0.18, 0.08, Vector3(0, 1.07, 0), glow(Color(1.0, 0.6, 0.2), 2.0))  # projector

	# A little hologram above it: stacked contour rings and a sweeping scan line.
	_holo = Node3D.new()
	_holo.position = Vector3(0, 1.1, 0)
	add_child(_holo)
	var holo_mat := glow(Color(1.0, 0.62, 0.22), 2.5)
	holo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	holo_mat.albedo_color.a = 0.5
	holo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 5:
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.5 - i * 0.08
		t.outer_radius = t.inner_radius + 0.015
		t.rings = 24
		ring.mesh = t
		ring.material_override = holo_mat
		ring.position.y = 0.08 + i * 0.08
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_holo.add_child(ring)
		_rings.append(ring)
	_sweep = MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(1.1, 0.004, 1.1)
	_sweep.mesh = plane
	_sweep.material_override = holo_mat
	_sweep.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_holo.add_child(_sweep)
	if ghost or preview:
		return
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 1.5, 0)
	_light.light_color = Color(1.0, 0.6, 0.25)
	_light.omni_range = 4.5
	add_child(_light)


func _process(dt: float) -> void:
	_t += dt
	_holo.rotation.y += dt * 0.4
	for i in _rings.size():
		_rings[i].position.y = 0.08 + i * 0.08 + sin(_t * 1.3 + i) * 0.015
	_sweep.position.y = 0.05 + (sin(_t * 1.1) * 0.5 + 0.5) * 0.4
	if _light:
		_light.light_energy = 0.6 + 0.15 * sin(_t * 23.0) * sin(_t * 7.0)


func _collision_shape() -> Shape3D:
	var b := BoxShape3D.new()
	b.size = Vector3(2.0, 1.05, 1.3)
	return b


func _collision_offset() -> Vector3:
	return Vector3(0, 0.52, 0)


func interact(player) -> bool:
	var view = get_tree().get_first_node_in_group("scan_view")
	if view:
		view.open(self, player)
	return false


func hover_text() -> String:
	return "Scanning table\n[E] open map"
