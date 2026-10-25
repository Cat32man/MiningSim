extends CharacterBody3D
## A cave bug. Kinds share one body plan and brain, with different stats:
##   swarmer — small and fast; comes in groups as threat rises.
##   gnawer  — slow, armoured; goes for machines and chews them to a breakdown.
## No pathfinding (the terrain is dynamic voxels): bugs steer straight at their goal and
## scramble up anything they run into, which suits skittering cave bugs.
##
## What a bug is after:
##   the player     — once noticed (or straight away if `aggro`, i.e. part of a swarm);
##   target_building — raiders bite a machine until it breaks, then look for the next one;
##   home           — death-swarm guards lurk around your body until you come close.

const Sfx = preload("res://scripts/audio/sfx.gd")
const HitFx = preload("res://scripts/enemies/hit_fx.gd")

## Hurtbox for weapons and melee: much bigger than the small movement sphere, so a bug is
## easy to hit without making it snag on every tunnel.
const HURTBOX_LAYER := 32
## Bugs at least this tough show a health bar once damaged.
const HEALTH_BAR_MIN := 60.0

const KINDS := {
	"swarmer": {"hp": 30.0, "run": 5.2, "wander": 1.6, "notice": 16.0, "bite": 2.7, "cooldown": 0.9,
		"machine_bite": 6.0, "wall_bite": 1.0, "climb": 3.5, "scale": 1.0},
	"gnawer": {"hp": 140.0, "run": 3.4, "wander": 1.1, "notice": 13.0, "bite": 6.0, "cooldown": 1.4,
		"machine_bite": 22.0, "wall_bite": 12.0, "climb": 2.4, "scale": 1.7},
}
const GIVE_UP_RANGE := 30.0
const AGGRO_RANGE := 55.0  # swarm bugs know where you are from this far
const BITE_RANGE := 1.4
const DESPAWN_RANGE := 70.0
const HOME_LEASH := 5.0
const DEFEND_RANGE := 7.0  # raiders turn on you when you come this close
const GNAWER_PATIENCE := 15.0  # seconds a gnawer waits at a wall before chewing in
const SPREAD_RADIUS := 1.6  # bugs try to keep this far apart
const SPREAD_WEIGHT := 1.2  # how hard that steers a moving bug
const SPREAD_NUDGE := 6.0  # sideways shuffle for bugs standing still

var kind := "swarmer"
var health := 30.0
## Set by the threat director.
var player
var director
var aggro := false
var target_building: Node3D
var home := Vector3.INF
var swarm_record = null  # the death swarm this guard belongs to

var _s: Dictionary
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _chasing := false
var _bite_cd := 0.0
var _wander_dir := Vector3.ZERO
var _blocked_t := 0.0
var _warned := false
var _unblocked_t := 0.0
var _block_normal := Vector3.FORWARD
var _flank := randf_range(-2.5, 2.5)  # metres to one side it approaches you from
var _wander_t := 0.0
var _chitter_t := 0.0
var _gait := 0.0
var _legs: Array = []
var _body: Node3D
var _dead := false
var _terrain_ready := false
var _flash_mats: Array = []
var _flash := 0.0
var _number: Label3D
var _number_time := -99.0
var _bar: Array = []


func _ready() -> void:
	_s = KINDS[kind]
	health = _s["hp"]
	var k: float = _s["scale"]
	add_to_group("bugs")
	collision_layer = 16
	collision_mask = 3
	floor_max_angle = deg_to_rad(60.0)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.32 * k
	col.shape = shape
	col.position.y = 0.32 * k
	add_child(col)

	var hurt := Area3D.new()
	hurt.collision_layer = HURTBOX_LAYER
	hurt.collision_mask = 0
	hurt.monitoring = false
	hurt.set_meta("bug", self)
	var hs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.55 * k
	cap.height = 1.3 * k
	hs.shape = cap
	hs.rotation.x = PI / 2  # lies along the body
	hs.position = Vector3(0, 0.4 * k, 0)
	hurt.add_child(hs)
	add_child(hurt)

	_build_model()
	_body.scale = Vector3.ONE * k
	if _s["hp"] >= HEALTH_BAR_MIN:
		_bar = HitFx.make_bar(self, 0.95 * k)
	_chitter_t = randf_range(1.0, 4.0)


## Sideways push away from bugs closer than SPREAD_RADIUS, stronger the closer they are.
func _separation() -> Vector3:
	var push := Vector3.ZERO
	var r: float = SPREAD_RADIUS * _s["scale"]
	for b in get_tree().get_nodes_in_group("bugs"):
		if b == self:
			continue
		var away: Vector3 = global_position - b.global_position
		away.y = 0.0
		var d := away.length()
		if d < r:
			push += (away / d if d > 0.01 else Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)) * (1.0 - d / r)
	return push


func _process(dt: float) -> void:
	# Red hit flash fades out.
	if _flash > 0.0:
		_flash = maxf(_flash - dt * 6.0, 0.0)
		for m in _flash_mats:
			m.emission_energy_multiplier = _flash * 3.0


func _physics_process(dt: float) -> void:
	if _dead or not is_instance_valid(player):
		return
	# Same rule as the player: no physics until the ground has collision.
	if not _terrain_ready:
		if not player.world.is_ready_around(global_position):
			return
		_terrain_ready = true
	var to_player: Vector3 = player.global_position - global_position
	var dist := to_player.length()
	if dist > DESPAWN_RANGE and swarm_record == null:
		queue_free()  # guards are despawned (and kept) by the director instead
		return

	var target_alive: bool = player.visible and player.health > 0.0 and player.active
	if _chasing:
		if not target_alive or dist > (AGGRO_RANGE if aggro else GIVE_UP_RANGE):
			_chasing = false
	elif target_alive and (dist < _s["notice"] or (aggro and dist < AGGRO_RANGE)
			or (_raiding() and dist < DEFEND_RANGE)):
		_chasing = true
		Sfx.play_3d("chitter", global_position, get_parent(), 2.0, randf_range(1.1, 1.3))

	_bite_cd = maxf(_bite_cd - dt, 0.0)
	var move := Vector3.ZERO
	var speed: float = _s["wander"]
	if _chasing:
		speed = _s["run"]
		# Each bug comes in from its own side instead of all down the same line.
		var side := Vector3(-to_player.z, 0.0, to_player.x).normalized()
		move = _flat(to_player + side * _flank * clampf((dist - 2.0) * 0.5, 0.0, 1.0))
		if dist < BITE_RANGE * _s["scale"]:
			move = Vector3.ZERO
			if _bite_cd <= 0.0:
				_bite_cd = _s["cooldown"]
				Sfx.play_3d("bite", global_position, get_parent())
				player.take_damage(_s["bite"], global_position)
	elif _raiding():
		speed = _s["run"] * 0.8
		var to_b := target_building.global_position - global_position
		var reach: float = target_building.bite_radius + 0.6 * _s["scale"]
		move = _flat(to_b)
		if Vector2(to_b.x, to_b.z).length() < reach:
			move = Vector3.ZERO
			_face(to_b, dt)
			if _bite_cd <= 0.0:
				_bite_cd = _s["cooldown"]
				Sfx.play_3d("gnaw", global_position, get_parent(), 0.0, randf_range(0.85, 1.15))
				target_building.take_damage(_s["machine_bite"], global_position + Vector3(0, 0.4, 0))
				if target_building.broken:
					target_building = director.next_raid_target(global_position) if director else null
					if target_building == null:
						aggro = true  # nothing left to wreck: come for you
	elif home != Vector3.INF and global_position.distance_to(home) > HOME_LEASH:
		move = _flat(home - global_position)
	else:
		_wander_t -= dt
		if _wander_t <= 0.0:
			_wander_t = randf_range(1.5, 4.0)
			_wander_dir = Vector3.ZERO if randf() < 0.35 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		move = _wander_dir

	# Keep some room from other bugs: they fan out rather than stacking in one spot.
	var push := _separation()
	if push != Vector3.ZERO:
		if move != Vector3.ZERO:
			move = (move + push * SPREAD_WEIGHT).normalized()
		else:
			velocity.x += push.x * SPREAD_NUDGE * dt  # shuffle aside while biting or idle
			velocity.z += push.z * SPREAD_NUDGE * dt
	velocity.x = move_toward(velocity.x, move.x * speed, 30.0 * dt)
	velocity.z = move_toward(velocity.z, move.z * speed, 30.0 * dt)
	var blocker := _blocking_piece() if move != Vector3.ZERO else null
	# Off the wall for a few seconds: the wait (and its warning) starts over next time.
	_unblocked_t = 0.0 if blocker else _unblocked_t + dt
	if _unblocked_t > 3.0:
		_blocked_t = 0.0
		_warned = false
	if blocker:
		# Walls and doors can't be climbed. Bugs prowl along the outside and wait; only a
		# gnawer that's waited a while starts to chew (sooner when raiding a machine inside).
		_blocked_t += dt
		if kind == "gnawer" and not _warned and _blocked_t > 0.5 and director:
			_warned = true
			director.base_threatened.emit(blocker)  # the warning comes while it waits
		var chew: bool = kind == "gnawer" and _blocked_t > GNAWER_PATIENCE * (0.4 if _raiding() else 1.0)
		if chew and _bite_cd <= 0.0:
			_bite_cd = _s["cooldown"]
			Sfx.play_3d("gnaw", global_position, get_parent(), 0.0, randf_range(0.85, 1.15))
			blocker.take_damage(_s["wall_bite"], global_position + Vector3(0, 0.4, 0) + move * 0.4)
		elif not chew:
			var along := Vector3(-_block_normal.z, 0.0, _block_normal.x).normalized() * signf(_flank + 0.01)
			velocity.x = along.x * _s["wander"] + _block_normal.x * 0.5
			velocity.z = along.z * _s["wander"] + _block_normal.z * 0.5
			if randf() < dt * 0.25:
				_flank = -_flank  # pace back the other way now and then
		if not is_on_floor():
			velocity.y -= _gravity * dt
	elif is_on_wall() and move != Vector3.ZERO:
		velocity.y = _s["climb"]  # scramble up whatever is in the way
	elif not is_on_floor():
		velocity.y -= _gravity * dt
	move_and_slide()

	if move != Vector3.ZERO:
		_face(Vector3(velocity.x, 0.0, velocity.z), dt)
	_animate(dt, Vector2(velocity.x, velocity.z).length() / _s["scale"])

	_chitter_t -= dt
	if _chitter_t <= 0.0:
		_chitter_t = randf_range(3.0, 7.0)
		Sfx.play_3d("chitter", global_position, get_parent(), -4.0, randf_range(0.9, 1.4) / sqrt(_s["scale"]))


## A wall, door or other structure piece we ran into last move (not one we're standing on).
func _blocking_piece() -> Node3D:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var o = c.get_collider()
		if o is Node3D and o.get("is_structure") and absf(c.get_normal().y) < 0.5 and is_instance_valid(o):
			_block_normal = c.get_normal()
			return o
	return null


func _raiding() -> bool:
	return is_instance_valid(target_building) and not target_building.broken


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()


func _face(dir: Vector3, dt: float) -> void:
	if Vector2(dir.x, dir.z).length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(dt * 12.0, 1.0))


## Returns true if this hit killed it. `at` is where it was struck (for the ichor spray).
func take_damage(amount: float, from: Vector3, at := Vector3.INF) -> bool:
	if _dead:
		return false
	health -= amount
	_chasing = true
	var hit_pos := at if at != Vector3.INF else global_position + Vector3(0, 0.35 * _s["scale"], 0)
	var killed := health <= 0.0
	HitFx.ichor(get_parent(), hit_pos, from)
	var now := Time.get_ticks_msec() / 1000.0
	_number = HitFx.number(get_parent(), global_position + Vector3(0, 0.6 * _s["scale"], 0), amount, _number,
		_number_time, now, killed)
	_number_time = now
	_flash = 1.0
	if not _bar.is_empty():
		HitFx.set_bar(_bar, health / _s["hp"])
	if killed:
		_die()
	else:
		Sfx.play_3d("bug_hurt", global_position, get_parent(), 0.0, randf_range(0.9, 1.2) / sqrt(_s["scale"]))
	return killed


func _die() -> void:
	_dead = true
	if swarm_record != null:
		swarm_record["count"] -= 1
	collision_layer = 0
	for c in get_children():
		if c is Area3D:
			c.collision_layer = 0  # no more hits on the corpse
	if not _bar.is_empty():
		_bar[0].visible = false
	Sfx.play_3d("bug_die", global_position, get_parent(), 2.0, randf_range(0.9, 1.1) / sqrt(_s["scale"]))
	var k: float = _s["scale"]
	var t := create_tween()
	t.tween_property(_body, "scale", Vector3(1.3, 0.1, 1.3) * k, 0.25)
	t.tween_interval(1.5)
	t.tween_property(_body, "scale", Vector3.ZERO, 0.4)
	t.tween_callback(queue_free)


func _animate(dt: float, speed: float) -> void:
	_gait += dt * (6.0 + speed * 4.0)
	for i in _legs.size():
		var phase := _gait + (PI if i % 2 == 0 else 0.0) + (i / 2) * 0.6
		var leg: Node3D = _legs[i]
		leg.rotation.y = leg.get_meta("base_yaw") + sin(phase) * 0.35 * minf(speed, 1.0)
		leg.rotation.z = leg.get_meta("base_roll") + maxf(cos(phase), 0.0) * 0.3 * minf(speed, 1.0)


func _build_model() -> void:
	_body = Node3D.new()
	add_child(_body)
	var gnawer := kind == "gnawer"
	var chitin := StandardMaterial3D.new()
	chitin.albedo_color = Color(0.2, 0.08, 0.06) if gnawer else Color(0.18, 0.15, 0.1)
	chitin.metallic = 0.3 if gnawer else 0.2
	chitin.roughness = 0.3 if gnawer else 0.35
	chitin.clearcoat_enabled = true
	var belly := StandardMaterial3D.new()
	belly.albedo_color = Color(0.36, 0.22, 0.14) if gnawer else Color(0.42, 0.33, 0.2)
	belly.roughness = 0.6
	# Hit flash: chitin and belly glow red briefly when struck.
	for m in [chitin, belly]:
		m.emission_enabled = true
		m.emission = Color(1.0, 0.12, 0.05)
		m.emission_energy_multiplier = 0.0
		_flash_mats.append(m)
	var eye := StandardMaterial3D.new()
	eye.albedo_color = Color(0.9, 0.25, 0.1)
	eye.emission_enabled = true
	eye.emission = Color(1.0, 0.25, 0.08)
	eye.emission_energy_multiplier = 1.5

	_blob(Vector3(0.36, 0.24, 0.52), Vector3(0, 0.34, 0.12), chitin)  # abdomen
	_blob(Vector3(0.3, 0.2, 0.3), Vector3(0, 0.32, -0.22), belly)  # thorax
	_blob(Vector3(0.22, 0.17, 0.2), Vector3(0, 0.33, -0.42), chitin)  # head
	for x in [-0.06, 0.06]:
		_blob(Vector3(0.04, 0.04, 0.04), Vector3(x, 0.39, -0.5), eye)
		var mandible := _blob(Vector3(0.03, 0.03, 0.12), Vector3(x * 1.4, 0.28, -0.54), chitin)
		mandible.rotation.y = -x * 4.0
	if gnawer:
		# Overlapping back plates and heavy jaws.
		for i in 3:
			_blob(Vector3(0.34 - i * 0.04, 0.1, 0.2), Vector3(0, 0.45 - i * 0.015, 0.22 - i * 0.16), chitin)
		for x in [-0.07, 0.07]:
			var jaw := _blob(Vector3(0.05, 0.05, 0.2), Vector3(x * 1.3, 0.26, -0.58), belly)
			jaw.rotation.y = -x * 5.0

	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := -0.25 + (i / 2) * 0.22
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.12, 0.32, z)
		var base_yaw := side * (PI / 2) + (z * -1.2) * side
		hip.rotation.y = base_yaw
		hip.rotation.z = side * -0.5
		hip.set_meta("base_yaw", base_yaw)
		hip.set_meta("base_roll", side * -0.5)
		_body.add_child(hip)
		var leg := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.03, 0.03, 0.42)
		leg.mesh = b
		leg.material_override = chitin
		leg.position = Vector3(0, -0.05, -0.2)
		leg.rotation.x = 0.5
		hip.add_child(leg)
		_legs.append(hip)


func _blob(size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 12
	s.rings = 6
	mi.mesh = s
	mi.scale = size
	mi.position = pos
	mi.material_override = m
	_body.add_child(mi)
	return mi
