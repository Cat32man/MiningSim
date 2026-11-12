extends Node3D
## THE ARBITER's green energy. Small bursts fly fast and straight and sting; the big bomb
## drifts slowly toward you, swelling and pulsing, and blows up on anything it touches (or
## after a while), hurting everything inside its blast.

const Sfx = preload("res://scripts/audio/sfx.gd")
const HitFx = preload("res://scripts/enemies/hit_fx.gd")

const GREEN := Color(0.35, 1.0, 0.5)
const BURST_LIFETIME := 2.0
const BOMB_LIFETIME := 5.0
const BOMB_RADIUS := 4.5  # blast radius
const BOMB_TURN := 0.9  # how hard the bomb steers toward its target (rad/s)

var velocity := Vector3.ZERO
var damage := 4.0
var big := false
var shooter: CollisionObject3D
var target: Node3D  # the bomb homes on this a little

var _age := 0.0
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _light: OmniLight3D


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = GREEN
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.emission_enabled = true
	_mat.emission = GREEN
	_mat.emission_energy_multiplier = 4.0
	_mesh = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.6 if big else 0.13
	s.height = s.radius * 2.0
	s.radial_segments = 16 if big else 8
	s.rings = 8 if big else 4
	_mesh.mesh = s
	_mesh.material_override = _mat
	if not big:
		_mesh.scale = Vector3(1.0, 1.0, 2.6)  # stretched into a streak along -Z
	add_child(_mesh)
	if big:
		# A crackling shell around the core.
		var shell := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.85
		sm.height = 1.7
		shell.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(GREEN, 0.25)
		shell.material_override = m
		add_child(shell)
		var trail := CPUParticles3D.new()
		trail.amount = 40
		trail.lifetime = 0.7
		trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		trail.emission_sphere_radius = 0.6
		trail.spread = 180.0
		trail.initial_velocity_min = 0.3
		trail.initial_velocity_max = 1.2
		trail.gravity = Vector3.ZERO
		trail.scale_amount_min = 0.05
		trail.scale_amount_max = 0.12
		var dot := SphereMesh.new()
		dot.radius = 0.5
		dot.height = 1.0
		dot.radial_segments = 6
		dot.rings = 3
		dot.material = _mat
		trail.mesh = dot
		add_child(trail)
	_light = OmniLight3D.new()
	_light.light_color = GREEN
	_light.omni_range = 7.0 if big else 2.5
	_light.light_energy = 1.6 if big else 0.8
	add_child(_light)


func _physics_process(dt: float) -> void:
	_age += dt
	if big:
		if is_instance_valid(target):
			var want: Vector3 = (target.global_position + Vector3(0, 0.9, 0) - global_position).normalized()
			var cur := velocity.normalized()
			var ang := cur.angle_to(want)
			if ang > 0.001:
				var axis := cur.cross(want).normalized()
				if axis != Vector3.ZERO:
					velocity = velocity.rotated(axis, minf(ang, BOMB_TURN * dt))
		var pulse := 1.0 + 0.15 * sin(_age * 14.0)
		_mesh.scale = Vector3.ONE * pulse
		_mat.emission_energy_multiplier = 4.0 + 3.0 * absf(sin(_age * 7.0))
	var from := global_position
	var to := from + velocity * dt
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 8)  # rock, buildings, player
	if shooter:
		q.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var c = hit["collider"]
		if big:
			_explode(hit["position"])
			return
		if c is Node and c.is_in_group("player"):
			c.take_damage(damage, from)
		HitFx.ichor(get_parent(), hit["position"], from, GREEN)
		queue_free()
		return
	global_position = to
	if not big and velocity.length_squared() > 0.01:
		look_at(to + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT)
	if _age > (BOMB_LIFETIME if big else BURST_LIFETIME):
		if big:
			_explode(global_position)
		else:
			queue_free()


## Bomb blast: full damage at the centre, falling off to nothing at the edge.
func _explode(at: Vector3) -> void:
	var parent := get_parent()
	Sfx.play_3d("shotgun", at, parent, 8.0, 0.55)
	# Only this computer's own player: in co-op every player has a copy of the bomb.
	if is_instance_valid(target) and target.is_in_group("player"):
		var d: float = (target.global_position + Vector3(0, 0.9, 0)).distance_to(at)
		if d < BOMB_RADIUS:
			target.take_damage(damage * (1.0 - d / BOMB_RADIUS * 0.7), at)
	# Flash: an expanding green shell and a burst of light.
	var flash := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	flash.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(GREEN, 0.7)
	flash.material_override = m
	parent.add_child(flash)
	flash.global_position = at
	flash.scale = Vector3.ONE * 0.5
	var light := OmniLight3D.new()
	light.light_color = GREEN
	light.omni_range = 14.0
	light.light_energy = 4.0
	flash.add_child(light)
	var tw := flash.create_tween().set_parallel()
	tw.tween_property(flash, "scale", Vector3.ONE * BOMB_RADIUS, 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.45)
	tw.tween_property(light, "light_energy", 0.0, 0.45)
	tw.chain().tween_callback(flash.queue_free)
	for i in 3:
		HitFx.ichor(parent, at, at + Vector3(randf_range(-1, 1), -1.0, randf_range(-1, 1)), GREEN)
	queue_free()
