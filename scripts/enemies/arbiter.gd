extends CharacterBody3D
## THE ARBITER: guardian of the Seal, at the back of the chamber off the silicon caves. A
## tall hooded machine that floats with its legs hanging, a green visor across a dark face,
## energy blades along its forearms and green wisps streaming off it.
##
## Circles you at mid range and picks from four moves: a charged dash (a green line on the
## floor shows where; slam it into a pillar and it's stunned and takes extra damage), a
## blade slash up close, quick volleys of small energy bursts, and a big slow homing bomb.
## Below half health it chains three dashes and fires faster. It can't be killed: at zero
## it flees through the Seal and leaves its Advanced Plating behind.

signal died(boss: Node3D)

const Sfx = preload("res://scripts/audio/sfx.gd")
const HitFx = preload("res://scripts/enemies/hit_fx.gd")
const Shot = preload("res://scripts/enemies/arbiter_shot.gd")
const Items = preload("res://scripts/items/items.gd")

const BOSS_NAME := "THE ARBITER"
const MAX_HEALTH := 1300.0
const HURTBOX_LAYER := 32
const GREEN := Color(0.35, 1.0, 0.5)
const HOVER := 0.7  # feet this far off the floor
const ORBIT := 9.0  # preferred distance from you
const MOVE_SPEED := 5.0
const DASH_SPEED := 26.0
const DASH_DAMAGE := 14.0
const SLASH_DAMAGE := 9.0
const SLASH_RANGE := 3.2
const BURST_DAMAGE := 3.0
const BURST_SPEED := 30.0
const BOMB_DAMAGE := 20.0
const BOMB_SPEED := 8.0
const STUN_TIME := 1.8
const STUN_DAMAGE_MULT := 1.5

enum { HOVERING, WINDUP, DASH, RECOVER, STUNNED, SLASH, BURST, BOMB }

var health := MAX_HEALTH
var player
var director
var lair_key := "arbiter"
## Its arena (floor centre) and how far from it it will go. INF = roams freely.
var arena_center := Vector3.INF
var arena_radius := 15.0
## Where it flees to (the Seal); INF = straight up.
var seal_point := Vector3.INF

var _dead := false
var _enraged := false
var _terrain_ready := false
var _t := 0.0
var _state := HOVERING
var _state_t := 0.0
var _dash_dir := Vector3.FORWARD
var _dash_left := 0.0
var _dash_hit := false
var _chain := 0
var _shots_left := 0
var _shot_t := 0.0
var _dash_cd := 3.0
var _slash_cd := 0.0
var _burst_cd := 1.5
var _bomb_cd := 6.0
var _orbit_sign := 1.0
var _orbit_t := 4.0
var _floor_y := NAN
var _flash := 0.0
var _flash_mats: Array = []
var _number: Label3D
var _number_time := -99.0

var _body: Node3D
var _torso: Node3D
var _head: Node3D
var _arms: Array = []  # shoulder pivots, left then right
var _legs: Array = []
var _hands: Array = []
var _blade_mat: StandardMaterial3D
var _visor_mat: StandardMaterial3D
var _wisps: Array = []  # [base Node3D, angle, segments Array]
var _wisp_mat: StandardMaterial3D
var _orb: MeshInstance3D  # the bomb gathering above its head
var _tele: MeshInstance3D  # dash warning line on the floor
var _tele_mat: StandardMaterial3D
var _light: OmniLight3D
var _sparks: CPUParticles3D
var _hum: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("bugs")
	add_to_group("boss")
	collision_layer = 16
	collision_mask = 3
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.6
	cap.height = 2.8
	col.shape = cap
	col.position.y = 1.5
	add_child(col)
	var hurt := Area3D.new()
	hurt.collision_layer = HURTBOX_LAYER
	hurt.collision_mask = 0
	hurt.monitoring = false
	hurt.set_meta("bug", self)
	var hs := CollisionShape3D.new()
	var hc := CapsuleShape3D.new()
	hc.radius = 0.9
	hc.height = 3.4
	hs.shape = hc
	hs.position.y = 1.6
	hurt.add_child(hs)
	add_child(hurt)
	_build_model()
	Sfx.play_3d("charge", global_position + Vector3.UP * 1.6, get_parent(), 6.0, 0.6)


## Closest point on its body to `from` (melee reach is measured to this, not its feet).
func melee_point(from: Vector3) -> Vector3:
	var a := global_position + Vector3.UP * 0.3
	var b := global_position + Vector3.UP * 2.9
	var t := clampf((from - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
	var axis := a.lerp(b, t)
	var to := from - axis
	return axis + to.normalized() * minf(0.5, to.length())


func health_ratio() -> float:
	return health / MAX_HEALTH


## Where its loot lands: the floor under it.
func drop_point() -> Vector3:
	return global_position - Vector3(0, HOVER - 0.3, 0)


func loot() -> Array:
	return [{"id": Items.ADVANCED_PLATING, "count": 1}, {"id": Items.SILICON, "count": 30},
		{"id": Items.DIAMOND, "count": 15}, {"id": Items.ELECTRUM, "count": 40}]


func defeat_text() -> String:
	return "%s fled" % BOSS_NAME


func _process(dt: float) -> void:
	_t += dt
	if _flash > 0.0:
		_flash = maxf(_flash - dt * 5.0, 0.0)
		for m in _flash_mats:
			m.emission_energy_multiplier = _flash * 2.0
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
	var dir := flat / dist if dist > 0.01 else -global_basis.z
	var alive: bool = player.health > 0.0 and player.active
	_state_t += dt
	_dash_cd -= dt
	_slash_cd -= dt
	_burst_cd -= dt
	_bomb_cd -= dt
	var move := Vector3.ZERO
	var face := true

	match _state:
		HOVERING:
			if alive:
				_orbit_t -= dt
				if _orbit_t <= 0.0:
					_orbit_t = randf_range(3.0, 6.0)
					_orbit_sign = -_orbit_sign
				var radial := dir * clampf(dist - ORBIT, -1.0, 1.0) * MOVE_SPEED
				var side := dir.cross(Vector3.UP) * _orbit_sign * MOVE_SPEED * 0.6
				move = radial + side
				var sight := _can_see_player()
				if dist < SLASH_RANGE and _slash_cd <= 0.0:
					_enter(SLASH)
					Sfx.play_3d("slash", global_position + Vector3.UP * 1.4, get_parent(), 2.0, 0.7)
				elif sight and _dash_cd <= 0.0 and dist < 26.0:
					_chain = 3 if _enraged else 1
					_start_windup(0.85 if not _enraged else 0.6)
				elif sight and _bomb_cd <= 0.0 and dist > 7.0:
					_enter(BOMB)
					Sfx.play_3d("charge", global_position + Vector3.UP * 2.4, get_parent(), 4.0, 0.5)
				elif sight and _burst_cd <= 0.0 and dist > 4.0:
					_enter(BURST)
					_shots_left = 8 if _enraged else 5
					_shot_t = 0.25
		WINDUP:
			move = -dir * 1.2  # draws back
			face = _state_t < _windup_time() - 0.15  # stops tracking just before it goes
			if face and dist > 0.01:
				_dash_dir = dir
				_dash_left = clampf(dist + 5.0, 10.0, 30.0)
			_show_tele(true)
			if _state_t >= _windup_time():
				_show_tele(false)
				_enter(DASH)
				_dash_hit = false
				Sfx.play_3d("dash", global_position + Vector3.UP * 1.4, get_parent(), 6.0, randf_range(0.9, 1.1))
		DASH:
			face = false
			move = _dash_dir * DASH_SPEED
			_dash_left -= DASH_SPEED * dt
			if not _dash_hit and alive:
				var body_c := global_position + Vector3.UP * 1.6
				if body_c.distance_to(player.global_position + Vector3.UP * 0.9) < 1.9:
					_dash_hit = true
					player.take_damage(DASH_DAMAGE, global_position)
		RECOVER:
			move = -dir * 0.8
			if _state_t >= 0.8:
				_dash_cd = 2.6 if _enraged else 4.0
				_enter(HOVERING)
		STUNNED:
			face = false
			if _state_t >= STUN_TIME:
				_dash_cd = 2.6 if _enraged else 4.0
				_enter(HOVERING)
		SLASH:
			if _state_t >= 0.35 and _state_t - dt < 0.35:
				if alive and dist < SLASH_RANGE + 0.6:
					player.take_damage(SLASH_DAMAGE, global_position)
			if _state_t >= 0.7:
				_slash_cd = 1.4
				_enter(HOVERING)
		BURST:
			move = dir.cross(Vector3.UP) * _orbit_sign * MOVE_SPEED * 0.3
			_shot_t -= dt
			if _shot_t <= 0.0 and _shots_left > 0:
				_shots_left -= 1
				_shot_t = 0.09 if _enraged else 0.13
				_fire_burst()
			if _shots_left <= 0 and _shot_t <= 0.0:
				_burst_cd = 2.0 if _enraged else 3.2
				_enter(HOVERING)
		BOMB:
			if _state_t >= 1.1:
				_fire_bomb()
				_bomb_cd = 6.0 if _enraged else 9.5
				_enter(HOVERING)

	if face and dist > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(dt * 6.0, 1.0))
	# Never leaves its arena: at the edge it stops and holds there (a dash just ends).
	if arena_center != Vector3.INF:
		var off := global_position + move * dt * 4.0 - arena_center
		if Vector2(off.x, off.z).length() > arena_radius:
			if _state == DASH:
				_end_dash()
			move = Vector3.ZERO
	# Hover: feet a little off the floor, bobbing.
	var target_y := _ground_y() + HOVER + sin(_t * 1.8) * 0.12
	velocity = Vector3(move.x, (target_y - global_position.y) * 5.0, move.z)
	move_and_slide()
	if _state == DASH:
		if is_on_wall():
			_stun()
		elif _dash_left <= 0.0:
			_end_dash()


func _windup_time() -> float:
	return (0.6 if _enraged else 0.85) if _chain >= (3 if _enraged else 1) else 0.4


func _start_windup(_t0: float) -> void:
	_enter(WINDUP)
	Sfx.play_3d("charge", global_position + Vector3.UP * 1.4, get_parent(), 4.0, 1.0)
	var to: Vector3 = player.global_position - global_position
	_dash_dir = Vector3(to.x, 0.0, to.z).normalized()
	_dash_left = clampf(Vector2(to.x, to.z).length() + 5.0, 10.0, 30.0)


func _enter(s: int) -> void:
	_state = s
	_state_t = 0.0


func _end_dash() -> void:
	_chain -= 1
	if _chain > 0 and is_instance_valid(player):
		_start_windup(0.4)
	else:
		_enter(RECOVER)


## Slammed into rock: sparks, droops, and takes extra damage for a moment.
func _stun() -> void:
	_chain = 0
	_enter(STUNNED)
	Sfx.play_3d("clang", global_position + Vector3.UP * 1.4, get_parent(), 6.0, 0.6)
	Sfx.play_3d("break", global_position + Vector3.UP * 1.4, get_parent(), 0.0, 1.3)
	for i in 3:
		HitFx.ichor(get_parent(), global_position + Vector3.UP * 1.4 + _dash_dir * 0.6, global_position, GREEN)


func _ground_y() -> float:
	if arena_center != Vector3.INF:
		return arena_center.y
	# Free roaming (tests): find the floor under it now and then.
	if is_nan(_floor_y) or Engine.get_physics_frames() % 10 == 0:
		var from := global_position + Vector3.UP * 1.0
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 12.0, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			_floor_y = hit["position"].y
		elif is_nan(_floor_y):
			_floor_y = global_position.y - HOVER
	return _floor_y


func _can_see_player() -> bool:
	var from := _head.global_position if _head else global_position + Vector3.UP * 2.0
	var q := PhysicsRayQueryParameters3D.create(from, player.camera.global_position, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## One small fast bolt from alternating hands, leading you a little.
func _fire_burst() -> void:
	var hand: Node3D = _hands[_shots_left % 2]
	var from := hand.global_position
	var target: Vector3 = player.global_position + Vector3(0, 0.9, 0)
	target += player.velocity * (from.distance_to(target) / BURST_SPEED) * 0.5
	var spread := Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * 0.4
	var s := Shot.new()
	s.shooter = self
	s.damage = BURST_DAMAGE
	s.velocity = (target + spread - from).normalized() * BURST_SPEED
	get_parent().add_child(s)
	s.global_position = from
	Sfx.play_3d("pistol", from, get_parent(), 0.0, randf_range(0.6, 0.75))


func _fire_bomb() -> void:
	var from := _orb.global_position
	var s := Shot.new()
	s.big = true
	s.shooter = self
	s.target = player
	s.damage = BOMB_DAMAGE
	s.velocity = (player.global_position + Vector3(0, 1.0, 0) - from).normalized() * BOMB_SPEED
	get_parent().add_child(s)
	s.global_position = from
	Sfx.play_3d("shotgun", from, get_parent(), 4.0, 0.45)


func _show_tele(on: bool) -> void:
	_tele.visible = on
	if not on:
		return
	var a := clampf(_state_t / _windup_time(), 0.0, 1.0)
	var base := Vector3(global_position.x, _ground_y() + 0.06, global_position.z)
	_tele.global_position = base + _dash_dir * _dash_left * 0.5
	_tele.global_basis = Basis.looking_at(_dash_dir, Vector3.UP)* Basis.from_scale(Vector3(1.0, 1.0, _dash_left))
	_tele_mat.albedo_color = Color(GREEN, 0.15 + 0.45 * a * (0.7 + 0.3 * sin(_t * 30.0)))


## Returns true if this hit "killed" it (it flees instead of dying).
func take_damage(amount: float, from: Vector3, at := Vector3.INF) -> bool:
	if _dead:
		return false
	if _state == STUNNED:
		amount *= STUN_DAMAGE_MULT
	health -= amount
	var hit_pos := at if at != Vector3.INF else global_position + Vector3(0, 1.4, 0)
	HitFx.ichor(get_parent(), hit_pos, from, GREEN)
	var now := Time.get_ticks_msec() / 1000.0
	_number = HitFx.number(get_parent(), hit_pos + Vector3(0, 0.4, 0), amount, _number, _number_time, now,
		health <= 0.0)
	_number_time = now
	_flash = 1.0
	if randf() < 0.4:
		Sfx.play_3d("clang", hit_pos, get_parent(), -2.0, randf_range(0.8, 1.2))
	if not _enraged and health <= MAX_HEALTH * 0.5:
		_enraged = true
		Sfx.play_3d("charge", global_position + Vector3.UP * 1.6, get_parent(), 8.0, 0.45)
	if health <= 0.0:
		_flee()
		return true
	return false


## Beaten: it sparks, rises, and phases out through the Seal (or straight up).
func _flee() -> void:
	_dead = true
	health = 0.0
	collision_layer = 0
	collision_mask = 0
	_tele.visible = false
	_orb.visible = false
	for c in get_children():
		if c is Area3D:
			c.collision_layer = 0
	died.emit(self)
	Sfx.play_3d("break", global_position + Vector3.UP * 1.4, get_parent(), 6.0, 0.8)
	Sfx.play_3d("warp", global_position + Vector3.UP * 1.4, get_parent(), 8.0, 1.0)
	if _sparks:
		_sparks.amount = 60
	var goal := seal_point if seal_point != Vector3.INF else global_position + Vector3(0, 14.0, 0)
	var t := create_tween()
	t.tween_property(self, "global_position", global_position + Vector3(0, 2.5, 0), 0.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "global_position", goal - Vector3(0, 1.2, 0), 1.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(_body, "scale", Vector3(0.05, 1.6, 0.05), 0.25)
	t.tween_callback(queue_free)


# --- Look ---------------------------------------------------------------------------

func _animate(dt: float) -> void:
	if _body == null:
		return
	var windup := _state == WINDUP
	var dashing := _state == DASH
	var stunned := _state == STUNNED
	var slash := sin(clampf(_state_t / 0.7, 0.0, 1.0) * PI) if _state == SLASH else 0.0
	var k := minf(dt * 10.0, 1.0)
	# Torso: leans into a dash, back in a windup, slumps when stunned.
	var lean := 0.0
	if dashing:
		lean = -0.55
	elif windup:
		lean = 0.25
	elif stunned:
		lean = -0.7
	_torso.rotation.x = lerpf(_torso.rotation.x, lean, k)
	_torso.rotation.z = sin(_t * 1.1) * 0.04
	_head.rotation = Vector3(-0.15 if not stunned else 0.5, sin(_t * 0.7) * 0.2 if _state == HOVERING else 0.0, 0.0)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var arm: Node3D = _arms[i]
		# Arms hang at its sides, blades pointing down, swaying a little.
		var want := Vector3(sin(_t * 1.6 + i) * 0.08, 0.0, side * 0.12)
		if windup:
			want = Vector3(-0.4, 0.0, side * 1.1)  # spread wide
		elif dashing:
			want = Vector3(-1.5, side * 0.25, side * 0.1)  # blades thrust ahead
		elif stunned:
			want = Vector3(0.3, 0.0, side * 0.05)
		elif _state == BURST and i == _shots_left % 2:
			want = Vector3(-1.45, 0.0, side * 0.1)  # firing hand points at you
		elif _state == BOMB:
			want = Vector3(-2.7, 0.0, side * 0.35)  # both hands overhead
		if _state == SLASH and i == 1:
			want = Vector3(-1.4, 0.0, lerpf(1.3, -0.9, clampf(_state_t / 0.45, 0.0, 1.0)))
		arm.rotation = arm.rotation.lerp(want, k)
	for i in _legs.size():
		var leg: Node3D = _legs[i]
		var trail := 0.5 if dashing else 0.0
		leg.rotation.x = lerpf(leg.rotation.x, trail + sin(_t * 1.3 + i * 1.7) * 0.1, k)
	var glow := 3.0
	if windup:
		glow = 3.0 + 7.0 * clampf(_state_t / _windup_time(), 0.0, 1.0)
	elif dashing or slash > 0.0:
		glow = 9.0
	if _enraged:
		glow *= 1.3
	_blade_mat.emission_energy_multiplier = glow * (0.9 + 0.1 * sin(_t * 23.0))
	_visor_mat.emission_energy_multiplier = (1.0 if stunned and fmod(_t, 0.3) < 0.15 else 5.0) * (1.2 if _enraged else 1.0)
	_light.light_energy = 0.8 + glow * 0.12
	# The bomb swelling overhead.
	_orb.visible = _state == BOMB and not _dead
	if _orb.visible:
		_orb.scale = Vector3.ONE * clampf(_state_t / 1.1, 0.05, 1.0) * (1.0 + 0.1 * sin(_t * 20.0))
	# Wisps stream off its back and shoulders and writhe.
	var speed := 2.5 if _enraged else 1.6
	for w in _wisps:
		var base: Node3D = w[0]
		var a: float = w[1]
		var segs: Array = w[2]
		var out := Vector3(cos(a), sin(a) * 0.8 + 0.3, 0.35)
		for j in segs.size():
			var s := float(j) / segs.size()
			var p := out * s * 2.3 + Vector3(0, s * 0.8 * sin(a * 3.0) + sin(s * 3.0 - _t * speed + a) * 0.35 * s, 0)
			p += Vector3(0, 0, sin(s * 5.0 - _t * speed * 1.7 + a * 2.0) * 0.3 * s)
			if dashing:
				p.z += s * 1.2  # streams back behind it
			segs[j].position = p
	if _sparks:
		_sparks.emitting = _dead or stunned or health < MAX_HEALTH * 0.3


func _build_model() -> void:
	_body = Node3D.new()
	_body.scale = Vector3.ONE * 1.3  # built at human size, then made towering
	add_child(_body)
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.52, 0.53, 0.55)
	shell.metallic = 0.75
	shell.roughness = 0.35
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.1, 0.11)
	dark.metallic = 0.6
	dark.roughness = 0.4
	var cloth := StandardMaterial3D.new()  # the hood
	cloth.albedo_color = Color(0.3, 0.31, 0.33)
	cloth.roughness = 0.8
	for m in [shell, dark, cloth]:
		m.emission_enabled = true
		m.emission = GREEN
		m.emission_energy_multiplier = 0.0
		_flash_mats.append(m)
	_blade_mat = StandardMaterial3D.new()
	_blade_mat.albedo_color = GREEN
	_blade_mat.emission_enabled = true
	_blade_mat.emission = GREEN
	_blade_mat.emission_energy_multiplier = 3.0
	_blade_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_visor_mat = _blade_mat.duplicate()
	_wisp_mat = StandardMaterial3D.new()
	_wisp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wisp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wisp_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_wisp_mat.albedo_color = Color(GREEN, 0.8)

	# Legs hang from the hips, slightly apart, swaying.
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.17, 1.0, 0)
		_body.add_child(hip)
		_box(hip, Vector3(0.18, 0.5, 0.2), Vector3(0, -0.25, 0), shell)  # thigh
		_box(hip, Vector3(0.15, 0.5, 0.16), Vector3(0, -0.75, 0.02), shell)  # shin
		_box(hip, Vector3(0.13, 0.1, 0.24), Vector3(0, -1.02, -0.04), dark)  # foot, toes down
		_legs.append(hip)

	_torso = Node3D.new()
	_torso.position = Vector3(0, 1.0, 0)
	_body.add_child(_torso)
	_box(_torso, Vector3(0.42, 0.22, 0.26), Vector3(0, 0.08, 0), dark)  # hips
	_box(_torso, Vector3(0.48, 0.1, 0.3), Vector3(0, 0.24, 0), shell)  # belt
	_box(_torso, Vector3(0.62, 0.66, 0.36), Vector3(0, 0.6, 0), shell)  # chest
	_box(_torso, Vector3(0.5, 0.3, 0.05), Vector3(0, 0.66, -0.19), dark)  # chest plate
	var core := _box(_torso, Vector3(0.12, 0.12, 0.04), Vector3(0, 0.66, -0.22), _visor_mat)
	core.rotation.z = PI / 4

	_head = Node3D.new()
	_head.position = Vector3(0, 1.02, 0)
	_torso.add_child(_head)
	var hood := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.5
	hs.height = 1.0
	hood.mesh = hs
	hood.scale = Vector3(0.44, 0.52, 0.48)
	hood.position = Vector3(0, 0.1, 0.03)
	hood.material_override = cloth
	_head.add_child(hood)
	_box(_head, Vector3(0.3, 0.32, 0.12), Vector3(0, 0.06, -0.17), dark)  # the dark face
	# Green visor slit straight across the face, a little wider than the hood.
	_box(_head, Vector3(0.56, 0.055, 0.04), Vector3(0, 0.1, -0.24), _visor_mat)
	_box(_torso, Vector3(0.7, 0.18, 0.4), Vector3(0, 0.86, 0.04), cloth)  # hood drape on the shoulders

	for side in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * 0.41, 0.86, 0)
		_torso.add_child(shoulder)
		_box(shoulder, Vector3(0.2, 0.2, 0.24), Vector3(0, 0, 0), dark)
		_box(shoulder, Vector3(0.14, 0.42, 0.15), Vector3(0, -0.26, 0), shell)  # upper arm
		_box(shoulder, Vector3(0.13, 0.42, 0.14), Vector3(0, -0.68, 0), shell)  # forearm
		var hand := _box(shoulder, Vector3(0.12, 0.13, 0.13), Vector3(0, -0.96, 0), dark)
		_hands.append(hand)
		# The energy blade runs along the outside of the forearm and well past the hand.
		var blade := MeshInstance3D.new()
		blade.mesh = _blade_mesh()
		blade.material_override = _blade_mat
		blade.position = Vector3(side * 0.08, -0.45, 0)
		blade.scale.x = side
		shoulder.add_child(blade)
		for j in 3:  # struts holding it to the arm
			_box(shoulder, Vector3(0.06, 0.02, 0.02), Vector3(side * 0.09, -0.52 - j * 0.14, 0), _blade_mat)
		_arms.append(shoulder)

	# Wisps of green energy streaming off it.
	for i in 6:
		var base := Node3D.new()
		var a := TAU * i / 6.0 + 0.3
		base.position = Vector3(cos(a) * 0.3, 0.7 + sin(a * 2.0) * 0.25, 0.15)
		_torso.add_child(base)
		var segs: Array = []
		for j in 14:
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.11 * (1.0 - j / 16.0)
			sm.height = sm.radius * 2.0
			sm.radial_segments = 6
			sm.rings = 3
			mi.mesh = sm
			mi.material_override = _wisp_mat
			base.add_child(mi)
			segs.append(mi)
		_wisps.append([base, a, segs])

	_orb = MeshInstance3D.new()
	var om := SphereMesh.new()
	om.radius = 0.6
	om.height = 1.2
	_orb.mesh = om
	_orb.material_override = _blade_mat
	_orb.position = Vector3(0, 3.1, 0)
	_orb.visible = false
	_body.add_child(_orb)

	_light = OmniLight3D.new()
	_light.light_color = GREEN
	_light.omni_range = 6.0
	_light.position = Vector3(0, 1.7, -0.6)
	_body.add_child(_light)

	_sparks = CPUParticles3D.new()
	_sparks.emitting = false
	_sparks.amount = 20
	_sparks.lifetime = 0.5
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_sparks.emission_sphere_radius = 0.4
	_sparks.spread = 180.0
	_sparks.initial_velocity_min = 1.0
	_sparks.initial_velocity_max = 3.0
	_sparks.gravity = Vector3(0, -8, 0)
	_sparks.scale_amount_min = 0.02
	_sparks.scale_amount_max = 0.04
	var dot := SphereMesh.new()
	dot.radius = 0.5
	dot.height = 1.0
	dot.radial_segments = 4
	dot.rings = 2
	dot.material = _blade_mat
	_sparks.mesh = dot
	_sparks.position.y = 1.6
	_body.add_child(_sparks)

	_tele_mat = StandardMaterial3D.new()
	_tele_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tele_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tele_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_tele_mat.albedo_color = Color(GREEN, 0.3)
	_tele = MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(1.0, 0.04, 1.0)
	_tele.mesh = tb
	_tele.material_override = _tele_mat
	_tele.top_level = true
	_tele.visible = false
	add_child(_tele)

	if not Engine.is_editor_hint():
		_hum = Sfx.loop_3d("hum", self, -10.0, 6.0)
		_hum.pitch_scale = 2.2


## A long, thin, flat blade along -Y: narrow behind the elbow, widest by the hand,
## tapering to a point well past it.
func _blade_mesh() -> ArrayMesh:
	var outline := [Vector2(0.0, 0.3), Vector2(0.06, 0.1), Vector2(0.11, -0.45), Vector2(0.09, -0.9),
		Vector2(0.02, -1.35), Vector2(0.0, -0.9), Vector2(-0.01, -0.45), Vector2(-0.01, 0.1)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector3(0, -0.45, 0)
	for i in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		# Flat, facing forward: y along the arm, x out to the side (mirrored for the left arm).
		st.set_normal(Vector3.BACK)
		st.add_vertex(c)
		st.add_vertex(Vector3(a.x, a.y, 0))
		st.add_vertex(Vector3(b.x, b.y, 0))
	return st.commit()


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = m
	parent.add_child(mi)
	return mi
