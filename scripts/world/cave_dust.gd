extends GPUParticles3D
## "Stagnant air": dust motes that hang around the player and wander on slow, shifting air
## currents. They're lit like everything else (not glowing), so they show up where light
## falls — hanging in the flashlight beam, around the pod and flares — and vanish in the dark.
## Keeps the scene alive even when nothing else is moving.

const BOX := Vector3(18.0, 8.0, 18.0)

## Node to follow (the player). Particles live in world space, so moving the emitter just
## spawns new motes around you while old ones drift where they were.
var follow: Node3D

## 0..1: in the fire caves, glowing embers drift up through the dust.
var heat := 0.0

var _mat: ParticleProcessMaterial
var _t := 0.0
var _embers: GPUParticles3D


func _ready() -> void:
	amount = 1400
	lifetime = 14.0
	preprocess = 14.0
	local_coords = false
	visibility_aabb = AABB(-BOX, BOX * 2.0)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_mat = ParticleProcessMaterial.new()
	_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_mat.emission_box_extents = BOX * 0.5
	_mat.direction = Vector3(1, 0, 0)
	_mat.spread = 180.0
	_mat.initial_velocity_min = 0.02
	_mat.initial_velocity_max = 0.12
	_mat.gravity = Vector3.ZERO
	_mat.damping_min = 0.0
	_mat.damping_max = 0.02
	# Air currents: a slowly evolving noise field nudges each mote along.
	_mat.turbulence_enabled = true
	_mat.turbulence_noise_strength = 0.6
	_mat.turbulence_noise_scale = 6.0
	_mat.turbulence_noise_speed = Vector3(0.02, 0.01, 0.02)
	_mat.turbulence_noise_speed_random = 0.3
	_mat.turbulence_influence_min = 0.02
	_mat.turbulence_influence_max = 0.06
	_mat.scale_min = 0.6
	_mat.scale_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.15, Color(1, 1, 1, 1))
	fade.add_point(0.85, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	_mat.color_ramp = ramp
	process_material = _mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.03)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true  # carries the fade-in/out alpha
	m.albedo_color = Color(0.95, 0.9, 0.82, 0.8)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX  # lit by the scene, so dust shows in light
	m.roughness = 1.0
	# Soft round mote instead of a hard square.
	var dot := Gradient.new()
	dot.set_color(0, Color(1, 1, 1, 1))
	dot.set_color(1, Color(1, 1, 1, 0))
	var dot_tex := GradientTexture2D.new()
	dot_tex.gradient = dot
	dot_tex.fill = GradientTexture2D.FILL_RADIAL
	dot_tex.fill_from = Vector2(0.5, 0.5)
	dot_tex.fill_to = Vector2(1.0, 0.5)
	dot_tex.width = 32
	dot_tex.height = 32
	m.albedo_texture = dot_tex
	# Motes right in front of the lens would read as big blotches: fade them out up close.
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 0.4
	m.distance_fade_max_distance = 1.4
	quad.material = m
	draw_pass_1 = quad
	_make_embers()


func _make_embers() -> void:
	_embers = GPUParticles3D.new()
	_embers.amount = 260
	_embers.lifetime = 6.0
	_embers.local_coords = false
	_embers.emitting = false
	_embers.visibility_aabb = AABB(-BOX, BOX * 2.0)
	_embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(BOX.x * 0.5, 1.0, BOX.z * 0.5)
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, 0.15, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.5
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.75, 0.3, 0.0))
	fade.add_point(0.1, Color(1.0, 0.6, 0.2, 1.0))
	fade.set_color(fade.get_point_count() - 1, Color(0.8, 0.15, 0.05, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	_embers.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # embers glow
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = draw_pass_1.material.albedo_texture
	q.material = m
	_embers.draw_pass_1 = q
	_embers.position = Vector3(0, -BOX.y * 0.4, 0)
	add_child(_embers)


func _process(dt: float) -> void:
	_t += dt
	if is_instance_valid(follow):
		global_position = follow.global_position + Vector3(0, 0.6, 0)
	# The prevailing draft slowly swings around, so the whole cloud drifts one way, then another.
	_mat.gravity = Vector3(cos(_t * 0.05), sin(_t * 0.031) * 0.3, sin(_t * 0.04)) * 0.012
	if _embers:
		_embers.emitting = heat > 0.02
		_embers.amount_ratio = heat
