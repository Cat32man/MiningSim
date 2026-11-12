extends Node3D
## Another co-op player: a miner in a suit and helmet with a working headlamp. Moves
## smoothly between the position updates the network sends (about 20 a second).

const SMOOTH := 14.0

var label_text := "Miner"
var color := Color(0.3, 0.6, 0.9)

var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _target_pitch := 0.0
var _has_target := false
var _head: Node3D
var _lamp: SpotLight3D
var _body: Node3D
var _step := 0.0
var _last_pos := Vector3.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps moving while this game is paused
	_body = Node3D.new()
	add_child(_body)
	var suit := _mat(color.darkened(0.35), 0.0, 0.8)
	var dark := _mat(Color(0.12, 0.12, 0.13), 0.3, 0.6)
	_part(_body, _capsule(0.3, 1.1), Vector3(0, 0.95, 0), suit)  # torso + legs
	_part(_body, _box(Vector3(0.42, 0.5, 0.2)), Vector3(0, 1.15, 0.24), dark)  # backpack
	for side in [-1.0, 1.0]:
		_part(_body, _capsule(0.09, 0.6), Vector3(0.36 * side, 1.05, 0), suit)  # arms

	_head = Node3D.new()
	_head.position = Vector3(0, 1.6, 0)
	add_child(_head)
	_part(_head, _sphere(0.2), Vector3.ZERO, _mat(Color(0.75, 0.6, 0.5), 0.0, 0.7))
	var helmet := _part(_head, _sphere(0.24), Vector3(0, 0.07, 0), _mat(color, 0.2, 0.45))
	helmet.scale = Vector3(1, 0.75, 1)
	var lens := _mat(Color(1.0, 0.95, 0.8), 0.0, 0.3)
	lens.emission_enabled = true
	lens.emission = Color(1.0, 0.92, 0.7)
	lens.emission_energy_multiplier = 3.0
	_part(_head, _cylinder(0.06, 0.05), Vector3(0, 0.16, -0.2), lens).rotation.x = PI / 2
	_lamp = SpotLight3D.new()
	_lamp.position = Vector3(0, 0.16, -0.25)
	_lamp.light_color = Color(1.0, 0.93, 0.8)
	_lamp.light_energy = 2.5
	_lamp.spot_range = 18.0
	_lamp.spot_angle = 28.0
	_lamp.shadow_enabled = true
	_head.add_child(_lamp)

	var tag := Label3D.new()
	tag.text = label_text
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.font_size = 40
	tag.pixel_size = 0.005
	tag.modulate = color.lightened(0.4)
	tag.outline_size = 8
	tag.position = Vector3(0, 2.15, 0)
	add_child(tag)


## A fresh network update: where the player's feet are and where they're looking.
func target(pos: Vector3, yaw: float, pitch: float) -> void:
	_target_pos = pos
	_target_yaw = yaw
	_target_pitch = pitch
	if not _has_target:
		_has_target = true
		global_position = pos
		rotation.y = yaw
		_last_pos = pos


func _process(delta: float) -> void:
	if not _has_target:
		return
	var k := 1.0 - exp(-SMOOTH * delta)
	global_position = global_position.lerp(_target_pos, k)
	rotation.y = lerp_angle(rotation.y, _target_yaw, k)
	_head.rotation.x = lerp_angle(_head.rotation.x, _target_pitch, k)
	# Walking bob from how fast they're moving; the headlamp flickers a touch.
	var speed := Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length() / maxf(delta, 0.001)
	_last_pos = global_position
	_step += delta * clampf(speed, 0.0, 8.0) * 1.6
	_body.position.y = absf(sin(_step)) * 0.05 * clampf(speed / 4.0, 0.0, 1.0)
	_body.rotation.z = sin(_step) * 0.04 * clampf(speed / 4.0, 0.0, 1.0)
	_lamp.light_energy = 2.5 + sin(Time.get_ticks_msec() * 0.023) * 0.08


static func _mat(c: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


static func _part(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return m


static func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _cylinder(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	return m
