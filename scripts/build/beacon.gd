extends "res://scripts/build/building.gd"
## Respawn beacon (elevator shop blueprint): when you die, you come back at the beacon
## nearest your body instead of at the drop pod. Needs no power.

var _light: OmniLight3D
var _tip_mat: StandardMaterial3D
var _t := randf() * 3.0


func _init() -> void:
	is_power_node = false


func _build_visuals() -> void:
	var steel := mat(Color(0.3, 0.31, 0.33), 0.85, 0.4)
	var paint := mat(Color(0.8, 0.52, 0.12), 0.35, 0.55)
	for i in 3:
		var a := TAU * i / 3.0
		var leg := box(Vector3(0.08, 1.0, 0.08), Vector3(cos(a) * 0.35, 0.45, sin(a) * 0.35), steel)
		leg.rotation = Vector3(sin(a) * 0.35, 0, -cos(a) * 0.35)
	cyl(0.06, 2.0, Vector3(0, 1.4, 0), steel)
	cyl(0.14, 0.25, Vector3(0, 0.95, 0), paint)
	_tip_mat = glow(Color(0.4, 1.0, 0.6), 4.0)
	cyl(0.09, 0.18, Vector3(0, 2.45, 0), _tip_mat)
	if ghost or preview:
		return
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 2.5, 0)
	_light.light_color = Color(0.4, 1.0, 0.6)
	_light.omni_range = 6.0
	add_child(_light)


func _process(dt: float) -> void:
	# Slow heartbeat blink.
	_t += dt
	var pulse := pow(maxf(sin(_t * 2.4), 0.0), 6.0)
	_tip_mat.emission_energy_multiplier = 1.0 + 5.0 * pulse
	if _light:
		_light.light_energy = 0.3 + 1.2 * pulse


func _collision_shape() -> Shape3D:
	var b := BoxShape3D.new()
	b.size = Vector3(0.8, 2.6, 0.8)
	return b


func _collision_offset() -> Vector3:
	return Vector3(0, 1.3, 0)


## Where you stand up after respawning here.
func respawn_point() -> Vector3:
	return global_position + global_basis.z * 1.4 + Vector3(0, 1.0, 0)
