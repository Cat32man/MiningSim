extends RigidBody3D
## Thrown flare: a short-lived red light source.

const LIFETIME := 45.0
const FADE_TIME := 5.0
const BASE_ENERGY := 2.6

const Sfx = preload("res://scripts/audio/sfx.gd")

var _age := 0.0
var _light: OmniLight3D
var _hiss: AudioStreamPlayer3D


func _ready() -> void:
	collision_layer = 4
	collision_mask = 3
	mass = 0.3
	continuous_cd = true
	angular_damp = 2.0

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.06
	shape.shape = sphere
	add_child(shape)

	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.025
	cyl.height = 0.22
	mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.2, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.15)
	mat.emission_energy_multiplier = 6.0
	mesh.material_override = mat
	mesh.rotation.x = PI / 2
	add_child(mesh)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.36, 0.2)
	_light.light_energy = BASE_ENERGY
	_light.omni_range = 14.0
	_light.shadow_enabled = true
	add_child(_light)

	_hiss = Sfx.loop_3d("flare_loop", self, -14.0, 2.0)
	_hiss.play()


func _process(delta: float) -> void:
	_age += delta
	var fade := clampf((LIFETIME - _age) / FADE_TIME, 0.0, 1.0)
	_light.light_energy = BASE_ENERGY * fade * randf_range(0.85, 1.1)
	_hiss.volume_db = -14.0 + linear_to_db(maxf(fade, 0.001))
	if _age >= LIFETIME or global_position.y < -1000.0:
		queue_free()
