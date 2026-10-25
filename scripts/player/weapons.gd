extends Node3D
## Laser pistol (offhand) and laser shotgun (main weapon). Hitscan; terrain blocks shots.
## Pistol: semi-auto, builds heat, overheats (DRG-style vent). Shotgun: 8 pellets, limited
## charges that slowly regenerate and refill fully at the drop pod.

const Sfx = preload("res://scripts/audio/sfx.gd")

const PISTOL_DAMAGE := 14.0
const PISTOL_HEAT_PER_SHOT := 0.13
const PISTOL_COOL_PER_SEC := 0.45
const PISTOL_SPREAD := 0.6  # degrees
const PISTOL_COOLDOWN := 0.12
const SHOTGUN_PELLETS := 8
const SHOTGUN_DAMAGE := 7.0
const SHOTGUN_SPREAD := 6.0
const SHOTGUN_COOLDOWN := 0.9
const SHOTGUN_MAX := 12
const SHOTGUN_REGEN := 15.0  # seconds per charge
const RANGE := 60.0
const HIT_MASK := 1 | 2 | 32  # terrain, buildings, bug hurtboxes
const ShotgunScene = preload("res://assets/weapons/shotgun/shotgun.glb")
## Barrel tip in the model's own (Blender camera-space) coordinates.
const SHOTGUN_MUZZLE := Vector3(1.13, -0.8, -3.85)

## Set by the player.
var player

var heat := 0.0
var overheated := false
var charges := SHOTGUN_MAX
var pistol_model: Node3D
var shotgun_model: Node3D

var _shotgun_pivot: Node3D
var _shotgun_anim: AnimationPlayer
var _regen_t := 0.0
var _cd := 0.0
var _kick := 0.0
var _pistol_muzzle: Node3D
var _shotgun_muzzle: Node3D
var _flash: OmniLight3D
var _vent_mat: StandardMaterial3D


func _ready() -> void:
	_build_models()
	_flash = OmniLight3D.new()
	_flash.omni_range = 5.0
	_flash.light_energy = 0.0
	add_child(_flash)


func tick(dt: float) -> void:
	_cd = maxf(_cd - dt, 0.0)
	heat = maxf(heat - PISTOL_COOL_PER_SEC * dt, 0.0)
	if overheated and heat <= 0.0:
		overheated = false
	if charges < SHOTGUN_MAX:
		_regen_t += dt
		if _regen_t >= SHOTGUN_REGEN:
			_regen_t = 0.0
			charges += 1
	_kick = maxf(_kick - dt * 6.0, 0.0)
	position = Vector3(0, _kick * 0.02, _kick * 0.09)
	rotation.x = _kick * 0.25
	if _shotgun_pivot:
		# The camera-space model sits close to the lens: kick by angle, not distance.
		_shotgun_pivot.rotation.x = _kick * 0.06
	_flash.light_energy = maxf(_flash.light_energy - dt * 60.0, 0.0)
	_vent_mat.emission_energy_multiplier = heat * 4.0


func refill() -> void:
	charges = SHOTGUN_MAX


## Swaps the placeholder shotgun for the artist's model (assets/weapons/shotgun), authored in
## Blender camera space like the drill and pickaxe. `parent` is the player's camera-space
## viewmodel holder and `vm_scale` its depth-squash scale. The glTF has one clip per part;
## they're merged into a single "fire" clip that plays on every shot.
func attach_shotgun_viewmodel(parent: Node3D, vm_scale: Vector3) -> void:
	var was_visible := shotgun_model.visible
	shotgun_model.queue_free()
	_shotgun_pivot = Node3D.new()
	parent.add_child(_shotgun_pivot)
	var scaled := Node3D.new()
	scaled.scale = vm_scale
	_shotgun_pivot.add_child(scaled)
	var gun: Node3D = ShotgunScene.instantiate()
	scaled.add_child(gun)
	_shotgun_muzzle = Node3D.new()
	_shotgun_muzzle.position = SHOTGUN_MUZZLE
	gun.add_child(_shotgun_muzzle)
	_shotgun_anim = gun.find_child("AnimationPlayer", true, false)
	if _shotgun_anim:
		# Each exported clip also carries one-key "rest" tracks for the other parts; keep only
		# the track that actually moves each part, or the rest copies cancel the motion.
		var best := {}  # "path|type" -> [Animation, track index, key count]
		var fire := Animation.new()
		for clip in _shotgun_anim.get_animation_list():
			var src: Animation = _shotgun_anim.get_animation(clip)
			fire.length = maxf(fire.length, src.length)
			for t in src.get_track_count():
				var key := "%s|%d" % [src.track_get_path(t), src.track_get_type(t)]
				var n := src.track_get_key_count(t)
				if not best.has(key) or n > best[key][2]:
					best[key] = [src, t, n]
		for key in best:
			var src: Animation = best[key][0]
			if best[key][2] > 1:
				src.copy_track(best[key][1], fire)
		var lib := AnimationLibrary.new()
		lib.add_animation("fire", fire)
		_shotgun_anim.add_animation_library("merged", lib)
		_shotgun_anim.stop()  # stay in the imported rest pose until the first shot
	shotgun_model = _shotgun_pivot
	shotgun_model.visible = was_visible


func fire_pistol() -> void:
	if _cd > 0.0:
		return
	if overheated:
		Sfx.play("empty", player)
		return
	_cd = PISTOL_COOLDOWN
	heat += PISTOL_HEAT_PER_SHOT
	if heat >= 1.0:
		heat = 1.0
		overheated = true
		Sfx.play("overheat", player, -2.0)
	_shoot(_pistol_muzzle, PISTOL_SPREAD, PISTOL_DAMAGE, Color(0.4, 0.85, 1.0), 0.012)
	Sfx.play("pistol", player, -3.0, randf_range(0.95, 1.05))
	_kick = 0.6
	_muzzle_flash(_pistol_muzzle, Color(0.4, 0.85, 1.0))


func fire_shotgun() -> void:
	if _cd > 0.0:
		return
	if charges <= 0:
		Sfx.play("empty", player)
		player._flash("Out of charges")
		_cd = 0.3
		return
	_cd = SHOTGUN_COOLDOWN
	charges -= 1
	for i in SHOTGUN_PELLETS:
		_shoot(_shotgun_muzzle, SHOTGUN_SPREAD, SHOTGUN_DAMAGE, Color(1.0, 0.55, 0.2), 0.008)
	Sfx.play("shotgun", player, -1.0, randf_range(0.95, 1.05))
	_kick = 1.0
	_muzzle_flash(_shotgun_muzzle, Color(1.0, 0.55, 0.2))
	if _shotgun_anim:
		_shotgun_anim.play("merged/fire")
		_shotgun_anim.seek(0.0, true)


func _shoot(muzzle: Node3D, spread_deg: float, damage: float, color: Color, width: float) -> void:
	var cam: Camera3D = player.camera
	var basis := cam.global_basis
	var spread := deg_to_rad(spread_deg)
	var dir := (-basis.z).rotated(basis.x, randf_range(-spread, spread)).rotated(basis.y, randf_range(-spread, spread))
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * RANGE, HIT_MASK)
	q.collide_with_areas = true  # bug hurtboxes are Areas
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := from + dir * RANGE
	if not hit.is_empty():
		end = hit["position"]
		var bug = bug_of(hit["collider"])
		if bug:
			var killed: bool = bug.take_damage(damage, from, end)
			player.hud.hit_marker(killed)
		_impact(end, color)
	_beam(muzzle.global_position, end, color, width)


## The bug behind a ray hit (its hurtbox Area or its body), or null.
static func bug_of(collider: Object):
	if collider == null:
		return null
	if collider.has_meta("bug"):
		var b = collider.get_meta("bug")
		return b if is_instance_valid(b) else null
	return collider if collider.is_in_group("bugs") else null


func _beam(a: Vector3, b: Vector3, color: Color, width: float) -> void:
	var length := a.distance_to(b)
	if length < 0.05:
		return
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = width
	m.bottom_radius = width
	m.height = length
	m.radial_segments = 6
	m.rings = 1
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player.get_parent().add_child(mi)
	var dir := (b - a) / length
	mi.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), (a + b) * 0.5)
	var t := mi.create_tween()
	t.tween_property(mat, "albedo_color:a", 0.0, 0.08)
	t.tween_callback(mi.queue_free)


func _impact(at: Vector3, color: Color) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.5
	light.omni_range = 2.5
	player.get_parent().add_child(light)
	light.global_position = at
	var t := light.create_tween()
	t.tween_property(light, "light_energy", 0.0, 0.12)
	t.tween_callback(light.queue_free)


func _muzzle_flash(muzzle: Node3D, color: Color) -> void:
	_flash.global_position = muzzle.global_position
	_flash.light_color = color
	_flash.light_energy = 3.0


func _build_models() -> void:
	var gunmetal := _mat(Color(0.2, 0.21, 0.23), 0.8, 0.4)
	var polymer := _mat(Color(0.09, 0.09, 0.1), 0.0, 0.7)
	var accent := _mat(Color(0.78, 0.5, 0.12), 0.4, 0.5)
	var cyan := _glow(Color(0.4, 0.85, 1.0), 3.0)
	var orange := _glow(Color(1.0, 0.55, 0.2), 3.0)
	_vent_mat = _glow(Color(1.0, 0.35, 0.1), 0.0)

	pistol_model = Node3D.new()
	add_child(pistol_model)
	var pistol_grip := _part(pistol_model, Vector3(0.045, 0.12, 0.055), Vector3(0, -0.08, 0.04), polymer)
	pistol_grip.rotation.x = 0.25
	_part(pistol_model, Vector3(0.055, 0.075, 0.24), Vector3(0, 0, -0.06), gunmetal)
	_part(pistol_model, Vector3(0.058, 0.02, 0.1), Vector3(0, 0.045, -0.05), _vent_mat)  # heat vents
	_part(pistol_model, Vector3(0.05, 0.015, 0.05), Vector3(0, 0.0, -0.19), cyan)
	_pistol_muzzle = Node3D.new()
	_pistol_muzzle.position = Vector3(0, 0.0, -0.2)
	pistol_model.add_child(_pistol_muzzle)

	shotgun_model = Node3D.new()
	add_child(shotgun_model)
	_part(shotgun_model, Vector3(0.075, 0.095, 0.46), Vector3(0, 0, -0.12), gunmetal)
	_part(shotgun_model, Vector3(0.06, 0.08, 0.16), Vector3(0, -0.02, 0.17), polymer)  # stock
	var shotgun_grip := _part(shotgun_model, Vector3(0.05, 0.11, 0.05), Vector3(0, -0.08, 0.02), polymer)
	shotgun_grip.rotation.x = 0.3
	_part(shotgun_model, Vector3(0.08, 0.03, 0.2), Vector3(0, 0.06, -0.15), accent)
	for x in [-0.018, 0.018]:
		_part(shotgun_model, Vector3(0.025, 0.025, 0.04), Vector3(x, 0.01, -0.36), orange)
	_shotgun_muzzle = Node3D.new()
	_shotgun_muzzle.position = Vector3(0, 0.01, -0.38)
	shotgun_model.add_child(_shotgun_muzzle)


func _part(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _mat(c: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = roughness
	return m


func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m
