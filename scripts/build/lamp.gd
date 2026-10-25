extends "res://scripts/build/building.gd"
## Wall lamp: sticks to rock or any building piece, draws 1 kW, lights an outpost.

const DEMAND_KW := 1.0

var _light: OmniLight3D
var _bulb: MeshInstance3D
var _on_mat := glow(Color(1.0, 0.86, 0.6), 4.0)
var _off_mat := mat(Color(0.25, 0.24, 0.22), 0.2, 0.6)
var _t := randf() * 10.0


func _init() -> void:
	connect_range = 12.0
	cable_anchor = Vector3(0, 0.1, 0)


func _build_visuals() -> void:
	var body := mat(Color(0.2, 0.2, 0.21), 0.8, 0.4)
	box(Vector3(0.3, 0.06, 0.3), Vector3(0, 0.03, 0), body)
	_bulb = box(Vector3(0.2, 0.1, 0.2), Vector3(0, 0.11, 0), _off_mat)
	for x in [-0.12, 0.12]:
		box(Vector3(0.02, 0.12, 0.24), Vector3(x, 0.12, 0), body)  # cage
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 0.35, 0)
	_light.light_color = Color(1.0, 0.86, 0.66)
	_light.omni_range = 10.0
	_light.omni_attenuation = 1.2
	_light.light_energy = 0.0
	add_child(_light)


func _collision_shape() -> Shape3D:
	var b := BoxShape3D.new()
	b.size = Vector3(0.3, 0.2, 0.3)
	return b


func _collision_offset() -> Vector3:
	return Vector3(0, 0.1, 0)


func _ready() -> void:
	super()
	if not ghost and not preview:
		add_to_group("cosmetic_listeners")
		apply_cosmetics()


## Lamp colour from the elevator shop.
func apply_cosmetics() -> void:
	if _light:
		_light.light_color = preload("res://scripts/base/shop.gd").color(grid.progress if grid else null, "lamp")


func demand_kw() -> float:
	return DEMAND_KW


func power_tick(dt: float, satisfaction: float, _load: float) -> void:
	_t += dt
	var on := satisfaction > 0.0
	_bulb.material_override = _on_mat if on else _off_mat
	# A faint buzz-flicker so the light is never perfectly still.
	var flicker := 1.0 + sin(_t * 23.0) * 0.02 + sin(_t * 7.1) * 0.03
	_light.light_energy = 1.6 * satisfaction * flicker if on else 0.0


func hover_text() -> String:
	return "Wall lamp — %s\n%s" % ["on" if power_ratio > 0.0 else "no power", power_line()]
