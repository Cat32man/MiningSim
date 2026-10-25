extends "res://scripts/build/building.gd"
## Scanning tower: a cheap relay mast. The scanning table's map stays steady within
## STABLE_RADIUS of every tower, so a chain of them lets you map further out. No power.

const STABLE_RADIUS := 48.0

var _dish: Node3D
var _tip_mat: StandardMaterial3D
var _t := randf() * 4.0


func _init() -> void:
	is_power_node = false


func _ready() -> void:
	add_to_group("scan_towers")
	super()


func _build_visuals() -> void:
	var steel := mat(Color(0.3, 0.31, 0.33), 0.85, 0.4)
	var paint := mat(Color(0.8, 0.52, 0.12), 0.35, 0.55)
	for i in 3:
		var a := TAU * i / 3.0
		var leg := box(Vector3(0.1, 1.4, 0.1), Vector3(cos(a) * 0.45, 0.62, sin(a) * 0.45), steel)
		leg.rotation = Vector3(sin(a) * 0.33, 0, -cos(a) * 0.33)
	cyl(0.07, 3.6, Vector3(0, 2.0, 0), steel)
	for y in [1.2, 2.4]:
		cyl(0.12, 0.1, Vector3(0, y, 0), paint)
	# Turning dish up top.
	_dish = Node3D.new()
	_dish.position = Vector3(0, 3.7, 0)
	add_child(_dish)
	var dish := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.45
	cm.bottom_radius = 0.08
	cm.height = 0.22
	dish.mesh = cm
	dish.material_override = mat(Color(0.75, 0.76, 0.78), 0.4, 0.4)
	dish.rotation.x = deg_to_rad(70)
	dish.position = Vector3(0, 0.1, 0.12)
	_dish.add_child(dish)
	var feed := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.02
	fm.bottom_radius = 0.02
	fm.height = 0.4
	feed.mesh = fm
	feed.material_override = steel
	feed.rotation.x = deg_to_rad(70)
	feed.position = Vector3(0, 0.17, 0.32)
	_dish.add_child(feed)
	_tip_mat = glow(Color(1.0, 0.25, 0.15), 3.0)
	cyl(0.06, 0.1, Vector3(0, 3.95, 0), _tip_mat)


func _process(dt: float) -> void:
	_t += dt
	_dish.rotation.y += dt * 0.7
	_tip_mat.emission_energy_multiplier = 0.5 + 5.0 * pow(maxf(sin(_t * 2.0), 0.0), 8.0)


func _collision_shape() -> Shape3D:
	var b := BoxShape3D.new()
	b.size = Vector3(0.9, 4.0, 0.9)
	return b


func _collision_offset() -> Vector3:
	return Vector3(0, 2.0, 0)


func hover_text() -> String:
	return "Scanning tower — steadies the map within %d m" % int(STABLE_RADIUS)
