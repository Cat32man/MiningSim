extends CharacterBody3D
## MAGMA HYDRA: fire-cave boss. A tall serpentine bug reared up on a coiled tail, with a
## spined hood, two scythe arms and a belly that glows like the lava veins around it.
##
## Keeps to mid range spitting volleys of burning spines (it needs line of sight), and
## slashes with its scythes up close. Below half health it enrages: calls in swarmers,
## spits wider volleys, moves faster. One per fire-cave lair (see threat_director.gd).

signal died(boss: Node3D)

const Sfx = preload("res://scripts/audio/sfx.gd")
const HitFx = preload("res://scripts/enemies/hit_fx.gd")
const Spine = preload("res://scripts/enemies/spine.gd")

const BOSS_NAME := "MAGMA HYDRA"
const MAX_HEALTH := 1400.0
const HURTBOX_LAYER := 32
const MOVE_SPEED := 3.0
const ENRAGED_SPEED := 4.2
const KEEP_DISTANCE := 9.0
const MELEE_RANGE := 3.4
const MELEE_DAMAGE := 8.0
const MELEE_COOLDOWN := 1.6
const VOLLEY_COOLDOWN := 2.6
const ENRAGED_VOLLEY_COOLDOWN := 1.7
const SPINE_SPEED := 24.0
const CLIMB_SPEED := 3.0

var health := MAX_HEALTH
var player
var director
var lair_key := ""
## Its arena (floor centre) and how far from it it will go. INF = roams freely.
var arena_center := Vector3.INF
var arena_radius := 17.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _dead := false
var _enraged := false
var _terrain_ready := false
var _t := 0.0
var _volley_cd := 2.0
var _melee_cd := 0.0
var _rear := 0.0  # 0..1: rearing back before a volley
var _swipe := 0.0  # 1 -> 0 during a scythe swipe
var _flash := 0.0
var _flash_mats: Array = []
var _number: Label3D
var _number_time := -99.0

var _body: Node3D
var _torso: Node3D
var _head: Node3D
var _tail: Array = []
var _arms: Array = []
var _belly_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("bugs")
	add_to_group("boss")
	collision_layer = 16
	collision_mask = 3
	floor_max_angle = deg_to_rad(55.0)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.7
	cap.height = 2.6
	col.shape = cap
	col.position.y = 1.3
	add_child(col)

	# Generous hurtbox: the reared torso plus the coiled tail.
	var hurt := Area3D.new()
	hurt.collision_layer = HURTBOX_LAYER
	hurt.collision_mask = 0
	hurt.monitoring = false
	hurt.set_meta("bug", self)
	for spec in [[1.0, 3.4, Vector3(0, 1.8, -0.2), Vector3.ZERO], [0.8, 3.0, Vector3(0, 0.5, 1.2), Vector3(PI / 2, 0, 0)]]:
		var hs := CollisionShape3D.new()
		var c := CapsuleShape3D.new()
		c.radius = spec[0]
		c.height = spec[1]
		hs.shape = c
		hs.position = spec[2]
		hs.rotation = spec[3]
		hurt.add_child(hs)
	add_child(hurt)
	_build_model()
	Sfx.play_3d("roar", global_position + Vector3.UP * 2.0, get_parent(), 6.0, 1.0)


## Closest point on its body to `from` (melee reach is measured to this, not its feet).
func melee_point(from: Vector3) -> Vector3:
	var a := global_position + Vector3.UP * 0.5
	var b := global_position + Vector3.UP * 3.0
	var t := clampf((from - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
	var axis := a.lerp(b, t)
	var to := from - axis
	return axis + to.normalized() * minf(0.9, to.length())


func health_ratio() -> float:
	return health / MAX_HEALTH


func _process(dt: float) -> void:
	_t += dt
	if _flash > 0.0:
		_flash = maxf(_flash - dt * 5.0, 0.0)
		for m in _flash_mats:
			m.emission_energy_multiplier = _flash * 2.5
	if _belly_mat:
		_belly_mat.emission_energy_multiplier = (2.2 if _enraged else 1.4) * (0.8 + 0.2 * sin(_t * 3.0))
	_animate(dt)


func _physics_process(dt: float) -> void:
	if _dead or not is_instance_valid(player):
		return
	if not _terrain_ready:
		if not player.world.is_ready_around(global_position):
			return
		_terrain_ready = true
	var to_player: Vector3 = player.global_position - global_position
	var flat := Vector3(to_player.x, 0.0, to_player.z)
	var dist := flat.length()
	var alive: bool = player.health > 0.0 and player.active
	_volley_cd -= dt
	_melee_cd -= dt

	var move := Vector3.ZERO
	if alive:
		var speed := ENRAGED_SPEED if _enraged else MOVE_SPEED
		var sight := _can_see_player()
		if dist > KEEP_DISTANCE or not sight:
			move = flat.normalized() * speed
		elif dist < KEEP_DISTANCE * 0.5:
			move = flat.normalized() * speed * 0.6  # closes in to slash
		# Never leaves its arena: at the edge it stops and holds there.
		if arena_center != Vector3.INF:
			var off := global_position + move * 0.5 - arena_center
			if Vector2(off.x, off.z).length() > arena_radius:
				var back := arena_center - global_position
				move = Vector3(back.x, 0.0, back.z).normalized() * speed * 0.5 if Vector2(back.x, back.z).length() > arena_radius else Vector3.ZERO
		if dist < MELEE_RANGE and _melee_cd <= 0.0:
			_melee_cd = MELEE_COOLDOWN
			_swipe = 1.0
			Sfx.play_3d("bite", global_position + Vector3.UP * 1.5, get_parent(), 4.0, 0.6)
			player.take_damage(MELEE_DAMAGE, global_position)
		elif sight and dist > MELEE_RANGE and _volley_cd <= 0.0:
			_volley_cd = ENRAGED_VOLLEY_COOLDOWN if _enraged else VOLLEY_COOLDOWN
			_volley()
		var face := atan2(-flat.x, -flat.z)
		rotation.y = lerp_angle(rotation.y, face, minf(dt * 4.0, 1.0))

	velocity.x = move_toward(velocity.x, move.x, 20.0 * dt)
	velocity.z = move_toward(velocity.z, move.z, 20.0 * dt)
	if is_on_wall() and move != Vector3.ZERO:
		velocity.y = CLIMB_SPEED
	elif not is_on_floor():
		velocity.y -= _gravity * dt
	move_and_slide()


func _can_see_player() -> bool:
	var from := _head.global_position if _head else global_position + Vector3.UP * 2.5
	var q := PhysicsRayQueryParameters3D.create(from, player.camera.global_position, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Rears back, then spits a fan of spines, leading the target a little.
func _volley() -> void:
	_rear = 1.0
	Sfx.play_3d("spit", global_position + Vector3.UP * 2.5, get_parent(), 2.0, randf_range(0.9, 1.1))
	var mouth: Vector3 = _head.global_position + (-global_basis.z) * 0.6
	var target: Vector3 = player.global_position + Vector3(0, 0.4, 0)
	var t := mouth.distance_to(target) / SPINE_SPEED
	target += player.velocity * t * 0.6
	var dir := (target - mouth).normalized()
	var count := 5 if _enraged else 3
	var spread := 0.09
	for i in count:
		var s := Spine.new()
		s.shooter = self
		var yaw := (i - (count - 1) * 0.5) * spread
		s.velocity = dir.rotated(Vector3.UP, yaw) * SPINE_SPEED + Vector3.UP * 0.6
		get_parent().add_child(s)
		s.global_position = mouth


## Returns true if this hit killed it.
func take_damage(amount: float, from: Vector3, at := Vector3.INF) -> bool:
	if _dead:
		return false
	health -= amount
	var hit_pos := at if at != Vector3.INF else global_position + Vector3(0, 1.6, 0)
	HitFx.ichor(get_parent(), hit_pos, from, Color(1.0, 0.55, 0.15))
	var now := Time.get_ticks_msec() / 1000.0
	_number = HitFx.number(get_parent(), hit_pos + Vector3(0, 0.4, 0), amount, _number, _number_time, now,
		health <= 0.0)
	_number_time = now
	_flash = 1.0
	if not _enraged and health <= MAX_HEALTH * 0.5:
		_enrage()
	if health <= 0.0:
		_die()
		return true
	if randf() < 0.3:
		Sfx.play_3d("bug_hurt", hit_pos, get_parent(), 2.0, 0.45)
	return false


func _enrage() -> void:
	_enraged = true
	Sfx.play_3d("roar", global_position + Vector3.UP * 2.0, get_parent(), 8.0, 0.85)
	if director:
		for i in 4:
			var a := TAU * i / 4.0
			director.spawn_bug(global_position + Vector3(cos(a), 0.3, sin(a)) * 2.5, "swarmer").aggro = true


func _die() -> void:
	_dead = true
	health = 0.0
	collision_layer = 0
	for c in get_children():
		if c is Area3D:
			c.collision_layer = 0
	Sfx.play_3d("roar", global_position + Vector3.UP * 2.0, get_parent(), 6.0, 0.6)
	Sfx.play_3d("bug_die", global_position + Vector3.UP, get_parent(), 6.0, 0.5)
	died.emit(self)
	var t := create_tween()
	t.tween_property(_torso, "rotation:x", 1.3, 1.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.tween_interval(3.0)
	t.tween_property(_body, "scale", Vector3(1.2, 0.05, 1.2), 1.5)
	t.tween_callback(queue_free)


# --- Look ---------------------------------------------------------------------------

func _animate(dt: float) -> void:
	if _body == null or _dead:
		return
	_rear = maxf(_rear - dt * 1.6, 0.0)
	_swipe = maxf(_swipe - dt * 3.0, 0.0)
	var sway := sin(_t * 1.4) * 0.07
	_torso.rotation = Vector3(-0.15 - sin(_rear * PI) * 0.35, 0.0, sway)
	_head.rotation = Vector3(0.25 + sin(_rear * PI) * 0.4, sin(_t * 0.9) * 0.15, 0.0)
	for i in _tail.size():
		var seg: Node3D = _tail[i]
		seg.position.x = sin(_t * 2.0 - i * 0.8) * 0.12 * i
	for i in _arms.size():
		var side := -1.0 if i == 0 else 1.0
		var arm: Node3D = _arms[i]
		var idle := sin(_t * 2.2 + i) * 0.1
		arm.rotation = Vector3(-0.6 + idle - sin(_swipe * PI) * 1.6, side * 0.35, side * (0.5 + sin(_swipe * PI) * 0.3))


func _build_model() -> void:
	_body = Node3D.new()
	add_child(_body)
	var chitin := StandardMaterial3D.new()
	chitin.albedo_color = Color(0.16, 0.07, 0.05)
	chitin.metallic = 0.35
	chitin.roughness = 0.3
	chitin.clearcoat_enabled = true
	var plate := StandardMaterial3D.new()
	plate.albedo_color = Color(0.28, 0.12, 0.07)
	plate.metallic = 0.3
	plate.roughness = 0.35
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color(0.82, 0.72, 0.55)
	bone.roughness = 0.5
	for m in [chitin, plate]:
		m.emission_enabled = true
		m.emission = Color(1.0, 0.15, 0.05)
		m.emission_energy_multiplier = 0.0
		_flash_mats.append(m)
	_belly_mat = StandardMaterial3D.new()
	_belly_mat.albedo_color = Color(0.6, 0.18, 0.04)
	_belly_mat.emission_enabled = true
	_belly_mat.emission = Color(1.0, 0.35, 0.06)
	_belly_mat.emission_energy_multiplier = 1.4
	var eye := StandardMaterial3D.new()
	eye.albedo_color = Color(1.0, 0.8, 0.3)
	eye.emission_enabled = true
	eye.emission = Color(1.0, 0.7, 0.2)
	eye.emission_energy_multiplier = 4.0

	# Coiled tail trailing behind.
	for i in 6:
		var seg := Node3D.new()
		seg.position = Vector3(0, 0.45 - i * 0.04, 0.4 + i * 0.6)
		_body.add_child(seg)
		var r := 0.62 - i * 0.08
		_blob(seg, Vector3(r * 2.0, r * 1.5, r * 2.0), Vector3.ZERO, chitin)
		_blob(seg, Vector3(r * 1.4, r * 0.6, r * 1.6), Vector3(0, r * 0.65, 0), plate)
		_tail.append(seg)

	# Reared torso, pivoting at the base.
	_torso = Node3D.new()
	_torso.position = Vector3(0, 0.6, 0)
	_body.add_child(_torso)
	for i in 4:
		var h := 0.25 + i * 0.55
		var r := 0.6 - i * 0.06
		_blob(_torso, Vector3(r * 2.0, 0.75, r * 1.8), Vector3(0, h, -i * 0.08), chitin)
		_blob(_torso, Vector3(r * 1.3, 0.62, 0.3), Vector3(0, h, -r * 0.85 - i * 0.08), _belly_mat)  # glowing belly
		_blob(_torso, Vector3(r * 1.6, 0.3, r * 1.2), Vector3(0, h + 0.2, r * 0.3 - i * 0.08), plate)

	_head = Node3D.new()
	_head.position = Vector3(0, 2.35, -0.35)
	_torso.add_child(_head)
	_blob(_head, Vector3(0.6, 0.45, 0.85), Vector3(0, 0, -0.2), chitin)
	# Flared hood with spines.
	_blob(_head, Vector3(1.7, 1.3, 0.2), Vector3(0, 0.25, 0.25), plate)
	for i in 7:
		var a := -1.2 + i * 0.4
		var spike := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.05
		cm.height = 0.55
		cm.radial_segments = 5
		spike.mesh = cm
		spike.material_override = bone
		spike.position = Vector3(sin(a) * 0.8, 0.25 + cos(a) * 0.65, 0.3)
		spike.rotation = Vector3(0.3, 0, -a)
		_head.add_child(spike)
	for x in [-0.14, 0.14]:
		_blob(_head, Vector3(0.09, 0.07, 0.09), Vector3(x, 0.12, -0.55), eye)
		var fang := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.top_radius = 0.0
		fm.bottom_radius = 0.04
		fm.height = 0.35
		fang.mesh = fm
		fang.material_override = bone
		fang.position = Vector3(x, -0.25, -0.55)
		fang.rotation.x = PI * 0.92
		_head.add_child(fang)

	# Scythe arms from the upper torso.
	for side in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * 0.55, 1.75, -0.2)
		_torso.add_child(shoulder)
		_blob(shoulder, Vector3(0.22, 0.22, 0.9), Vector3(0, 0, -0.4), chitin)
		var scythe := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.06, 0.14, 1.3)
		scythe.mesh = sb
		scythe.material_override = bone
		scythe.position = Vector3(0, -0.35, -1.1)
		scythe.rotation.x = 0.9
		shoulder.add_child(scythe)
		_arms.append(shoulder)


func _blob(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 14
	s.rings = 7
	mi.mesh = s
	mi.scale = size
	mi.position = pos
	mi.material_override = m
	parent.add_child(mi)
	return mi
