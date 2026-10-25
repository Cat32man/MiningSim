extends CharacterBody3D
## First-person miner: movement, pickaxe, hand drill, scanner, flashlight, flares, backpack.

signal pod_opened
signal station_opened(station: Node)
signal build_menu_requested
signal building_panel_requested(building)
signal died
signal inventory_requested

const Inventory = preload("res://scripts/items/inventory.gd")
const Items = preload("res://scripts/items/items.gd")

## Valheim-style: 32 slots, and over this weight you can only walk (no sprint, jump or climb).
const BACKPACK_SLOTS := 32
const CARRY_CAPACITY := 300.0
const OVERWEIGHT_SPEED := 2.2
const OVERWEIGHT_JUMP := 0.6  # share of a normal jump while overweight
const OVERWEIGHT_CLIMB := 0.4  # share of normal climb speed while overweight
## Building, crafting and upgrades draw from your backpack plus storage this close to you.
const STORAGE_REACH := 20.0
const Flare = preload("res://scripts/items/flare.gd")
const ShredderThrow = preload("res://scripts/items/shredder_throw.gd")
const Materials = preload("res://scripts/world/materials.gd")
const Buildables = preload("res://scripts/build/buildables.gd")
const Weapons = preload("res://scripts/player/weapons.gd")
const Sfx = preload("res://scripts/audio/sfx.gd")
const Bench = preload("res://scripts/build/bench.gd")
const Refinery = preload("res://scripts/build/refinery.gd")

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.5
const JUMP_VELOCITY := 4.8

const CLIMB_SPEED := 2.6
const CLIMB_STAMINA := 4.0  # seconds of climbing
## Fire caves without a thermal suit: a few seconds' grace, then steady burns.
const HEAT_GRACE := 3.0
const HEAT_DPS := 6.0
const HEAT_TICK := 1.0
const CLIMB_REFILL := 2.0  # stamina per second on the ground
const CLIMB_REACH := 0.75
const MANTLE_UP := 4.0
const MANTLE_FORWARD := 3.0
const MOUSE_SENS := 0.0025
const CAMERA_HEIGHT := 0.7
const CAMERA_ROLL := 0.035  # radians of lean at full strafe speed (~2°)
const CAMERA_DIP := 0.015  # radians of forward lean at full speed
const INTERACT_REACH := 2.5

## Slots: miner (1 pickaxe, 2 drill), main weapon (3 laser shotgun), offhand (4 laser pistol).
enum Tool { PICKAXE, DRILL, SHOTGUN, PISTOL, DAGGER }

const MAX_HEALTH := 100.0
const REGEN_DELAY := 6.0  # seconds without damage before health regenerates
const REGEN_PER_SEC := 4.0
## Respawn debuff: max health is halved for this long.
const SHAKEN_TIME := 60.0

const PICK_MELEE := 12.0
## Crooked dagger (from the Magma Hydra's claw): brutal, but you have to be right on top of it.
const DAGGER_DAMAGE := 110.0
const DAGGER_REACH := 1.0  # + MELEE_SLACK
const DAGGER_COOLDOWN := 0.5
const DAGGER_REST := Vector3(0.24, -0.26, -0.42)
const MELEE_CONE_COS := 0.7  # ~45° either side of where you look
const MELEE_SLACK := 0.5  # extra reach for melee vs bugs
const DRILL_MELEE_PER_TICK := 2.0  # 20 dps: the drill is a poor weapon
const STEP_DISTANCE := 2.1
const SAFE_SPOT_INTERVAL := 0.5
const SAFE_SPOT_COUNT := 20  # ~10 s of trail
const UNSTUCK_SEARCH_RADIUS := 12

const PICK_RANGE := 3.0
## Pickaxe animation frames (24 fps, frame N at N/24 s in the exported clip).
const PickaxeScene = preload("res://assets/pickaxe/pickaxe.glb")
const ANIM_FPS := 24.0
const PICK_IDLE := 1.0
const PICK_READY := 4.0  # end of windup; every swing starts from this pose
const PICK_HIT_END := 14.0
const PICK_HIT_RECOVER_END := 18.0
const PICK_MISS_START := 18.0
const PICK_MISS_END := 27.0
const PICK_MISS_RECOVER_END := 32.0
const PICK_IMPACT := 9.5  # frame where the head bites the rock
enum PickState { IDLE, WINDUP, HIT, HIT_RECOVER, MISS, MISS_RECOVER, UNWIND }
const PICK_RADIUS := 1.2
const PICK_STRENGTH := 1.3

# Hand drill. Radius, strength and tank size come from the upgrade tracks in progress.gd.
const DRILL_RANGE := 3.4
const DRILL_TICK := 0.1
const DRILL_FUEL_PER_SEC := 4.0

const FLARES_MAX := 4
const FLARE_RECHARGE := 20.0

const SCAN_RADIUS := 32.0
const SCAN_COOLDOWN := 6.0
const SCAN_MARKER_TIME := 8.0
const SCAN_MAX_MARKERS := 14

const DrillScene = preload("res://assets/drill/drill.glb")
const DiamondDrillScene = preload("res://assets/drill/diamonddrill.glb")
## Vertical FOV of the Blender camera the drill was framed in: 90° horizontal at 16:9.
const DRILL_SOURCE_VFOV := 58.7
const DRILL_MODEL_SCALE := 0.1
const DRILL_ANIM := "ArmatureAction"
const DRILL_ANIM_LOOP_START := 6.0 / 24.0
const DRILL_ANIM_LOOP_END := 12.0 / 24.0
const TOOL_REST := Vector3(0.38, -0.32, -0.55)

## Q and F do one thing on a tap and another when held this long.
const HOLD_TIME := 0.3

## Set by main.
var world
var pod
var hud
var progress
var _quiet_unlocks := false
var _full_flash_t := 0.0
var builder
## Kept for compatibility with older checks; there is no drivable vehicle any more.
var vehicle = null
## Set each frame by main from the threat director, for the HUD.
var threat_label := ""
## Stays false until the terrain around the spawn is ready, so the player can't fall through.
var active := false
## False while a menu or the pod terminal is open.
var controls_enabled := true

var backpack = Inventory.new(BACKPACK_SLOTS, "Backpack")
## Worn gear. Like your tools and weapons it stays with you when you die; only the backpack drops.
var equipment = Inventory.new(1, "Suit", [Items.THERMAL_SUIT])
## Set by main (boss lairs on the scanner).
var director
var tool := Tool.PICKAXE
var fuel := 100.0
var flares := FLARES_MAX

var camera: Camera3D
var flashlight: SpotLight3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _flare_timer := 0.0
var health := MAX_HEALTH
var shaken_time := 0.0
var weapons
var _since_hit := 99.0
var _step_acc := 0.0
var _safe_spots: Array = []
var _safe_t := 0.0
var _drill_sound: AudioStreamPlayer
var climb_stamina := CLIMB_STAMINA
var climbing := false
## 0..1, eased toward 1 while you're in the fire caves (drives embers, fog, burns).
var heat := 0.0
var _heat_exposure := 0.0
var _heat_tick := 0.0
var _scan_cd := 0.0
var _pending_pitch := 0.0
var _q_state := {"down": false, "t": 0.0, "fired": false}
var _f_state := {"down": false, "t": 0.0, "fired": false}
var _drill_acc := 0.0
var _drilling := false
var _swing := 0.0
var _message := ""
var _message_time := 0.0
var _tool_root: Node3D
var _dagger_model: Node3D
var _stab := 0.0  # 1 -> 0 through a stab
var _dagger_cd := 0.0
var _pick_model: Node3D
var _pick_anim: AnimationPlayer
var _pick_state := PickState.IDLE
var _pick_t := PICK_IDLE  # animation frame
var _pick_has_miss_recovery := false
var _drill_model: Node3D
var _drill_holder: Node3D
var _viewmodel_scale := Vector3.ONE
var _drill_skins: Array = []
var _drill_anims: Array = []
var _drill_t := 0.0
var _drill_stopping := false
var _bob_phase := 0.0
var _bob_amount := 0.0
var _cam_dip := 0.0  # forward-lean part of the camera pitch (kept apart from mouse look)
var _dust: CPUParticles3D


func _ready() -> void:
	add_to_group("player")
	collision_layer = 8
	collision_mask = 3
	# Rough voxel rock: walk up steeper bumps and stay glued to uneven ground instead of
	# catching on every small lip.
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.35
	floor_constant_speed = true

	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	col.shape = capsule
	add_child(col)

	camera = Camera3D.new()
	camera.position.y = 0.7
	camera.fov = 80.0
	camera.near = 0.02  # the depth-squashed drill viewmodel sits very close to the lens
	camera.rotation.x = _pending_pitch
	add_child(camera)

	flashlight = SpotLight3D.new()
	flashlight.light_color = Color(1.0, 0.95, 0.86)
	# Low energy + gentle distance attenuation: close walls stay readable, far walls still lit.
	flashlight.light_energy = 1.3
	flashlight.spot_attenuation = 0.55
	# Fog right in front of the lens otherwise glows as a pale disc over close walls.
	flashlight.light_volumetric_fog_energy = 0.25
	flashlight.spot_range = 35.0
	flashlight.spot_angle = 28.0
	flashlight.spot_angle_attenuation = 1.6  # softer edge to the beam
	flashlight.shadow_enabled = true
	flashlight.position = Vector3(0.2, -0.15, 0.0)
	camera.add_child(flashlight)

	backpack.changed.connect(_check_unlocks)
	_build_tool_models()
	_build_dust()
	weapons = Weapons.new()
	weapons.player = self
	_tool_root.add_child(weapons)
	weapons.attach_shotgun_viewmodel(_drill_holder, _viewmodel_scale)
	_drill_sound = AudioStreamPlayer.new()
	_drill_sound.stream = Sfx.stream("drill")
	_drill_sound.volume_db = -8.0
	add_child(_drill_sound)
	_select_tool(Tool.PICKAXE)


func _input(event: InputEvent) -> void:
	# Mouse-look reads raw input so HUD controls can never swallow it.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		camera.rotate_x(-event.relative.y * MOUSE_SENS)
		camera.rotation.x = clampf(camera.rotation.x, -1.5, 1.5)


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif builder and builder.is_placing() and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			builder.try_place()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			builder.cancel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rotate_build") and builder and builder.is_placing():
		builder.rotate_step()
	elif event.is_action_pressed("deconstruct") and builder:
		builder.deconstruct()
	elif event.is_action_pressed("deploy"):
		throw_shredder()
	elif event.is_action_pressed("tool_1"):
		_select_tool(Tool.PICKAXE)
	elif event.is_action_pressed("tool_2"):
		_select_tool(Tool.DRILL)
	elif event.is_action_pressed("tool_3"):
		_select_tool(Tool.SHOTGUN)
	elif event.is_action_pressed("tool_4"):
		_select_tool(Tool.PISTOL)
	elif event.is_action_pressed("tool_5"):
		_select_tool(Tool.DAGGER)
	elif event.is_action_pressed("interact"):
		if _interact():
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		inventory_requested.emit()


## Fires on_tap when the key is released quickly, on_hold once it has been held HOLD_TIME.
## Tracking only starts on a fresh press, so a key still held from closing a menu is ignored.
func _tap_hold(action: String, st: Dictionary, delta: float, on_tap: Callable, on_hold: Callable) -> void:
	if not controls_enabled:
		st["down"] = false
		return
	if Input.is_action_just_pressed(action):
		st["down"] = true
		st["t"] = 0.0
		st["fired"] = false
	if not st["down"]:
		return
	if Input.is_action_pressed(action):
		st["t"] += delta
		if not st["fired"] and st["t"] >= HOLD_TIME:
			st["fired"] = true
			on_hold.call()
	else:
		st["down"] = false
		if not st["fired"]:
			on_tap.call()


func _physics_process(delta: float) -> void:
	if not active:
		return

	if is_on_floor():
		climb_stamina = minf(climb_stamina + CLIMB_REFILL * delta, CLIMB_STAMINA)
	else:
		velocity.y -= _gravity * delta
	if controls_enabled and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY * (OVERWEIGHT_JUMP if is_overweight() else 1.0)

	var input := Vector2.ZERO
	if controls_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (global_basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	if is_overweight():
		speed = OVERWEIGHT_SPEED
	velocity.x = move_toward(velocity.x, dir.x * speed, speed * 10.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, speed * 10.0 * delta)
	_climb(delta)
	move_and_slide()

	_record_safe_spot(delta)

	# Footsteps every couple of metres of ground travel.
	if is_on_floor():
		_step_acc += Vector2(velocity.x, velocity.z).length() * delta
		if _step_acc >= STEP_DISTANCE:
			_step_acc = 0.0
			Sfx.play("step", self, -10.0, randf_range(0.85, 1.15))

	var can_use: bool = controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		and not (builder and builder.is_placing())
	var using: bool = can_use and Input.is_action_pressed("use")
	_update_tools(delta, using)
	if can_use and Input.is_action_just_pressed("use"):
		if tool == Tool.PISTOL:
			weapons.fire_pistol()
		elif tool == Tool.SHOTGUN:
			weapons.fire_shotgun()


## Hold jump while airborne and facing rock to scramble up it. Limited by stamina,
## which refills on the ground. Topping out over a lip gives a mantle boost.
func _climb(delta: float) -> void:
	climbing = false
	if not controls_enabled or is_on_floor() or not Input.is_action_pressed("jump"):
		return
	var forward := -global_basis.z
	var chest_hit := _wall_ray(0.4, forward)
	var knee_hit := _wall_ray(-0.55, forward)
	var chest := not chest_hit.is_empty()
	var knee := not knee_hit.is_empty()
	if not (chest or knee):
		return
	# Ladders cost no stamina.
	var ladder := _is_ladder(chest_hit) or _is_ladder(knee_hit)
	if climb_stamina <= 0.0 and not ladder:
		return
	climbing = true
	if not ladder:
		climb_stamina = maxf(climb_stamina - delta, 0.0)
	if chest:
		velocity.y = CLIMB_SPEED * (OVERWEIGHT_CLIMB if is_overweight() else 1.0)
	else:
		# Chest is clear but feet still against rock: we're at the lip, hop over it.
		velocity.y = MANTLE_UP
		velocity.x = forward.x * MANTLE_FORWARD
		velocity.z = forward.z * MANTLE_FORWARD


func _wall_ray(height: float, forward: Vector3) -> Dictionary:
	var from := global_position + Vector3(0, height, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + forward * CLIMB_REACH, 3)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


static func _is_ladder(hit: Dictionary) -> bool:
	return not hit.is_empty() and hit["collider"] is Node and hit["collider"].is_in_group("ladders")


func _process(delta: float) -> void:
	# Q tap: open the build menu, or leave build mode entirely if already placing.
	_tap_hold("build", _q_state, delta, _on_build_tap, scan)
	weapons.tick(delta)
	_since_hit += delta
	shaken_time = maxf(shaken_time - delta, 0.0)
	if health > 0.0 and _since_hit >= REGEN_DELAY:
		health = minf(health + REGEN_PER_SEC * delta, max_health())
	_tap_hold("flare", _f_state, delta, throw_flare,
		func(): flashlight.visible = not flashlight.visible)
	_scan_cd = maxf(_scan_cd - delta, 0.0)
	_full_flash_t = maxf(_full_flash_t - delta, 0.0)
	if flares < flares_max():
		_flare_timer += delta
		if _flare_timer >= FLARE_RECHARGE:
			_flare_timer = 0.0
			flares += 1
	_message_time = maxf(_message_time - delta, 0.0)
	_update_heat(delta)
	_animate_tool(delta)
	_update_hud()


# --- Tools ------------------------------------------------------------------

func _on_build_tap() -> void:
	if builder and builder.is_placing():
		builder.cancel()
	else:
		build_menu_requested.emit()


func _select_tool(t: Tool) -> void:
	if t == Tool.DRILL and not (progress and progress.drill_owned):
		_flash("No hand drill yet")
		return
	if t == Tool.DAGGER and not (progress and progress.dagger_owned):
		return
	tool = t
	_pick_state = PickState.IDLE  # switching tools cancels a swing
	_pick_model.visible = t == Tool.PICKAXE
	_drill_model.visible = t == Tool.DRILL
	_dagger_model.visible = t == Tool.DAGGER
	if weapons:
		weapons.pistol_model.visible = t == Tool.PISTOL
		weapons.shotgun_model.visible = t == Tool.SHOTGUN


# --- Health -------------------------------------------------------------------

func max_health() -> float:
	return MAX_HEALTH * (0.5 if shaken_time > 0.0 else 1.0)


func take_damage(amount: float, _from: Vector3) -> void:
	if health <= 0.0 or vehicle:
		return
	health -= amount
	_since_hit = 0.0
	Sfx.play("hurt", self, -2.0, randf_range(0.9, 1.1))
	if hud:
		hud.flash_damage()
	if health <= 0.0:
		health = 0.0
		Sfx.play("death", self)
		controls_enabled = false
		velocity.x = 0.0
		velocity.z = 0.0
		# Slump to the floor: the view drops and rolls while the death screen fades in.
		var t := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(camera, "position:y", -0.55, 0.9)
		t.tween_property(camera, "rotation:z", 0.55, 0.9)
		t.tween_property(camera, "rotation:x", -0.25, 0.9)
		died.emit()


## Remembers where you last stood freely, a few times a second, for unstuck().
func _record_safe_spot(delta: float) -> void:
	_safe_t -= delta
	if _safe_t > 0.0:
		return
	_safe_t = SAFE_SPOT_INTERVAL
	if is_on_floor() and health > 0.0 and _fits(global_position):
		if _safe_spots.is_empty() or _safe_spots.back().distance_to(global_position) > 0.75:
			_safe_spots.append(global_position)
			if _safe_spots.size() > SAFE_SPOT_COUNT:
				_safe_spots.pop_front()


## Is there room for the player's capsule at `p`? Terrain collision is a hollow triangle
## mesh (a capsule buried inside rock touches no triangle), so solid rock is checked through
## the voxel densities; buildings and rock surfaces through a physics shape query.
func _fits(p: Vector3) -> bool:
	for off in [Vector3(0, -0.6, 0), Vector3(0, 0, 0), Vector3(0, 0.6, 0),
			Vector3(0.28, 0, 0), Vector3(-0.28, 0, 0), Vector3(0, 0, 0.28), Vector3(0, 0, -0.28)]:
		if world.density_interp(p + off) > 0.0:
			return false
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, p)
	q.collision_mask = 3
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _has_floor(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 2.5, 3)
	q.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Pause-menu "Unstuck": back to the latest remembered spot that's still clear, else the
## nearest open space with a floor within ~12 m. It never sends you (and your backpack)
## to the pod unless there's truly nowhere nearby. Returns a description of what happened.
func unstuck() -> String:
	for i in range(_safe_spots.size() - 1, -1, -1):
		var p: Vector3 = _safe_spots[i]
		if _fits(p):
			_teleport(p)
			return "Moved back to where you last stood"
	var here := global_position
	for r in range(1, UNSTUCK_SEARCH_RADIUS + 1):
		for dy in [0, 1, 2, -1, 3, -2, 4]:
			for k in 16:
				var a := TAU * k / 16.0
				var p := here + Vector3(cos(a) * r, dy, sin(a) * r)
				if _fits(p) and _has_floor(p):
					_teleport(p)
					return "Moved to the nearest open space (%d m)" % r
	_teleport(pod.global_position + Vector3(0, 1.5, 5.0) if pod else Vector3(0, 0, 5))
	return "Moved to the drop pod"


func _teleport(p: Vector3) -> void:
	global_position = p
	velocity = Vector3.ZERO


## Called by main after the body has been dropped.
func respawn(at: Vector3) -> void:
	global_position = at
	velocity = Vector3.ZERO
	_safe_spots.clear()  # the trail leads back to where you died
	camera.position.y = 0.7
	camera.rotation = Vector3.ZERO
	shaken_time = SHAKEN_TIME
	health = max_health()
	fuel = fuel_max()  # a fresh tank with the respawn
	_since_hit = 99.0


func _update_tools(delta: float, using: bool) -> void:
	_drilling = false
	_dagger_cd = maxf(_dagger_cd - delta, 0.0)
	match tool:
		Tool.PICKAXE:
			_update_pickaxe(delta, using)
		Tool.DAGGER:
			if using and _dagger_cd <= 0.0:
				_stab_attack()
		Tool.DRILL:
			if using:
				if fuel <= 0.0:
					_flash("Out of fuel")
				else:
					_drilling = true
					fuel = maxf(fuel - DRILL_FUEL_PER_SEC * delta, 0.0)
					_drill_acc += delta
					while _drill_acc >= DRILL_TICK:
						_drill_acc -= DRILL_TICK
						dig(DRILL_RANGE, progress.stat("size"), progress.stat("speed") * DRILL_TICK)
	if not _drilling:
		_drill_acc = 0.0
		if not _dust.one_shot:
			_dust.emitting = false
	if _drilling != _drill_sound.playing:
		_drill_sound.playing = _drilling


## Pickaxe swing, driven frame-by-frame through the artist's clip:
##   idle (1) --press--> windup 1-4 --> hit 4-14 (strikes at ~9.5) or miss 18-27
##   held:     hit -> 14-18 -> swing again from 4;  miss -> 27-32 -> swing again
##   released: same back-up segment, then the windup in reverse (4 -> 1) to idle
## Hit or miss is decided at the top of each swing by what's in reach.
func _update_pickaxe(delta: float, using: bool) -> void:
	var d := delta * ANIM_FPS
	match _pick_state:
		PickState.IDLE:
			_pick_t = PICK_IDLE
			if using:
				_pick_state = PickState.WINDUP
		PickState.WINDUP:
			_pick_t += d
			if _pick_t >= PICK_READY:
				_begin_swing()
		PickState.HIT:
			var before := _pick_t
			_pick_t += d
			if before < PICK_IMPACT and _pick_t >= PICK_IMPACT:
				dig(PICK_RANGE, PICK_RADIUS, PICK_STRENGTH)
			if _pick_t >= PICK_HIT_END:
				_pick_t = PICK_HIT_END
				_pick_state = PickState.HIT_RECOVER
		PickState.HIT_RECOVER:
			_pick_t += d
			if _pick_t >= PICK_HIT_RECOVER_END:
				_end_swing(using)
		PickState.MISS:
			_pick_t += d
			if _pick_t >= PICK_MISS_END:
				_pick_t = PICK_MISS_END
				_pick_state = PickState.MISS_RECOVER
		PickState.MISS_RECOVER:
			if _pick_has_miss_recovery:
				_pick_t += d
				if _pick_t >= PICK_MISS_RECOVER_END:
					_end_swing(using)
			else:
				# Clip has no 27-32 frames yet: lift back up along the miss arc instead.
				_pick_t -= d
				if _pick_t <= PICK_MISS_START:
					_end_swing(using)
		PickState.UNWIND:
			_pick_t -= d
			if using:
				_pick_state = PickState.WINDUP
			elif _pick_t <= PICK_IDLE:
				_pick_state = PickState.IDLE
				_pick_t = PICK_IDLE
	_pick_seek()


func _begin_swing() -> void:
	if _pick_target_in_reach():
		_pick_state = PickState.HIT
		_pick_t = PICK_READY
	else:
		_pick_state = PickState.MISS
		_pick_t = PICK_MISS_START


func _end_swing(using: bool) -> void:
	if using:
		_begin_swing()
	else:
		_pick_state = PickState.UNWIND
		_pick_t = PICK_READY


func _pick_target_in_reach() -> bool:
	if _melee_target(PICK_RANGE):
		return true
	var from := camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * PICK_RANGE, 1)
	q.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Crooked dagger: a quick lunging stab at whatever's right in front of you.
func _stab_attack() -> void:
	_dagger_cd = DAGGER_COOLDOWN
	_stab = 1.0
	Sfx.play("slash", self, -4.0, randf_range(0.9, 1.15))
	var bug = _melee_target(DAGGER_REACH)
	if bug == null:
		return
	var eye := camera.global_position
	var at: Vector3 = bug.melee_point(eye) if bug.has_method("melee_point") else bug.global_position + Vector3(0, 0.35, 0)
	var killed: bool = bug.take_damage(DAGGER_DAMAGE, eye, at)
	hud.hit_marker(killed)
	Sfx.play_3d("bug_die" if killed else "bite", at, get_parent(), 2.0, 0.8)


## Nearest live bug inside a forward cone within `reach` with nothing solid in between.
## Melee uses this instead of a thin ray, so a bug at your feet still gets hit.
func _melee_target(reach: float):
	var eye := camera.global_position
	var forward := -camera.global_basis.z
	var best = null
	var best_d := INF
	for bug in get_tree().get_nodes_in_group("bugs"):
		if bug.health <= 0.0:
			continue
		# Big bugs (the boss) measure reach to their body, not their feet.
		var aim: Vector3 = bug.melee_point(eye) if bug.has_method("melee_point") else bug.global_position + Vector3(0, 0.35, 0)
		var to := aim - eye
		var d := to.length()
		if d > reach + MELEE_SLACK or d >= best_d:
			continue
		if d > 0.3 and forward.dot(to / d) < MELEE_CONE_COS:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, aim, 1)
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue  # rock in the way
		best = bug
		best_d = d
	return best


func _pick_seek() -> void:
	if _pick_anim:
		_pick_anim.seek(clampf(_pick_t / ANIM_FPS, 0.0, _pick_anim.current_animation_length), true)


## Carves terrain where the camera is looking (or hits a bug in melee). Returns true if
## something was hit.
func dig(reach: float, radius: float, strength: float) -> bool:
	var from := camera.global_position
	var forward := -camera.global_basis.z
	# A bug in the melee cone takes the hit before any rock.
	var bug = _melee_target(reach)
	if bug:
		var at: Vector3 = bug.global_position + Vector3(0, 0.35, 0)
		var killed: bool = bug.take_damage(DRILL_MELEE_PER_TICK if tool == Tool.DRILL else PICK_MELEE, from, at)
		hud.hit_marker(killed)
		if tool == Tool.PICKAXE:
			Sfx.play_3d("bite", at, get_parent(), 0.0, 0.7)
		return true
	var q := PhysicsRayQueryParameters3D.create(from, from + forward * reach, 3)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var collider: Object = hit["collider"]
	if collider == null or not collider.has_meta("terrain"):
		return false
	if tool == Tool.PICKAXE:
		Sfx.play_3d("pick", hit["position"], get_parent(), -2.0, randf_range(0.85, 1.15))
	var point: Vector3 = hit["position"]
	# Only the drill with the bench-crafted diamond tip cuts hard rock; the pickaxe never does.
	var diamond_tipped: bool = tool == Tool.DRILL and progress != null and progress.diamond_tip
	var hit_mat: int = world.material_at(Vector3i((point + forward * 0.5).round()))
	if Materials.NEEDS_DIAMOND[hit_mat] and not diamond_tipped:
		_flash("Too hard — needs a diamond tip")
	var mined: Dictionary = world.apply_edit({
		"type": "carve_sphere",
		"center": point + forward * radius * 0.35,
		"radius": radius,
		"strength": strength,
		"diamond": diamond_tipped,
	})
	_dust.global_position = point
	if tool == Tool.DRILL:
		_dust.one_shot = false
		_dust.explosiveness = 0.0
		_dust.emitting = true
	else:
		_dust.one_shot = true
		_dust.explosiveness = 0.9
		_dust.restart()
	_collect(mined, point - forward * 0.5)
	return true


## Mined ore goes straight into the backpack while it fits, slots and weight both. What
## doesn't is left in an ore pile where you dug; [E] on it takes it anyway.
func _collect(mined: Dictionary, at: Vector3) -> void:
	var spill: Array = []
	for m in mined:
		if not Items.FROM_MATERIAL.has(m):
			continue
		var id: String = Items.FROM_MATERIAL[m]
		var n: int = mined[m]
		var w: float = Items.DEFS[id]["weight"]
		var fits: int = n if w <= 0.0 else clampi(floori((CARRY_CAPACITY - backpack.weight()) / w), 0, n)
		var left: int = n - fits + (backpack.add(id, fits) if fits > 0 else 0)
		if left > 0:
			spill.append({"id": id, "count": left})
	if spill.is_empty():
		return
	_spill(spill, at)
	if _full_flash_t <= 0.0:
		_flash("Backpack full")
		_full_flash_t = 3.0


## Takes stackable goods from `src` only until the backpack hits its weight limit (or runs
## out of slots). Returns true if `src` ended up empty.
func take_up_to_limit(src) -> bool:
	for i in src.slots.size():
		var s = src.slots[i]
		if s == null:
			continue
		var w: float = Items.DEFS[s["id"]]["weight"]
		var room: int = s["count"] if w <= 0.0 else floori((CARRY_CAPACITY - backpack.weight()) / w)
		if room <= 0:
			continue
		if Items.DEFS[s["id"]]["stack"] <= 1:
			if backpack.add_stack(s):
				src.slots[i] = null
			continue
		var n: int = mini(room, s["count"])
		var taken: int = n - backpack.add(s["id"], n)
		s["count"] -= taken
		if s["count"] <= 0:
			src.slots[i] = null
	src.changed.emit()
	return src.is_empty()


## Drops a backpack slot on the ground at your feet (joins a pile there if there is one).
func drop_slot(i: int) -> void:
	var s = backpack.slots[i]
	if s == null:
		return
	backpack.slots[i] = null
	backpack.changed.emit()
	_spill([s], global_position + Vector3(0, -0.85, 0) - global_basis.z * 0.8)
	Sfx.play("deposit", self, -8.0, 0.8)


## Adds to an ore pile within a couple of metres, or starts one.
func _spill(stacks: Array, at: Vector3) -> void:
	var pile = null
	for c in get_tree().get_nodes_in_group("caches"):
		if c.kind == "cache" and c.global_position.distance_to(at) < 2.5:
			pile = c
			break
	var rest: Array = []
	for st in stacks:
		if pile == null or not pile.inv.add_stack(st):
			rest.append(st)
	if not rest.is_empty() and builder and builder.grid and builder.grid.drop_cache.is_valid():
		builder.grid.drop_cache.call(at, rest)


func throw_flare() -> void:
	if flares <= 0:
		_flash("No flares left")
		return
	flares -= 1
	var f := Flare.new()
	get_parent().add_child(f)
	Sfx.play("flare", self, -6.0)
	var forward := -camera.global_basis.z
	f.global_position = camera.global_position + forward * 0.6
	f.linear_velocity = velocity + forward * 14.0 + Vector3.UP * 2.0
	f.angular_velocity = Vector3(randf(), randf(), randf()) * 8.0


## G: throws the best-charged SHREDDER-MK1 from the backpack. It clamps on where it lands.
func throw_shredder() -> void:
	var best := -1
	for i in backpack.slots.size():
		var s = backpack.slots[i]
		if s and s["id"] == Items.SHREDDER and (best < 0 or s["energy"] > backpack.slots[best]["energy"]):
			best = i
	if best < 0:
		_flash("No Shredder — craft one at a bench")
		return
	var stack: Dictionary = backpack.slots[best]
	backpack.slots[best] = null
	backpack.changed.emit()
	var t := ShredderThrow.new()
	t.energy = stack.get("energy", 0.0)
	t.grid = builder.grid if builder else null
	t.player = self
	get_parent().add_child(t)
	var forward := -camera.global_basis.z
	t.global_position = camera.global_position + forward * 0.6
	t.velocity = velocity + forward * 11.0 + Vector3.UP * 1.5
	Sfx.play("flare", self, -10.0, 0.6)


func fuel_max() -> float:
	return progress.stat("fuel") if progress else 100.0


## [E]: a body/cache in reach (take-all), the building under the crosshair, else the pod
## (refuel, recharge, open its storage + terminal). Returns true if something was used.
func _interact() -> bool:
	for cache in get_tree().get_nodes_in_group("caches"):
		if cache.in_reach(global_position):
			var emptied: bool = cache.recover(backpack)
			Sfx.play("deposit", self, -4.0)
			var what: String = "your body" if cache.kind == "body" else "the cache"
			if emptied:
				cache.queue_free()
				_flash("Took everything from %s" % what)
			else:
				_flash("Backpack full — some left in %s" % what)
			return true
	var b = builder.target_building() if builder else null
	if b:
		if b.hp < b.max_hp:
			if b.repair(cost_sources()):
				Sfx.play("place", self, -4.0, 1.3)
				_flash("Repaired")
			else:
				_flash("Need %s" % Items.describe(b.repair_cost()))
			return true
		if b.interact(self):
			building_panel_requested.emit(b)
		return true
	for st in get_tree().get_nodes_in_group("stations"):
		if st.is_in_reach(global_position, INTERACT_REACH):
			station_opened.emit(st)
			return true
	if not (pod and pod.is_in_reach(global_position, INTERACT_REACH)):
		return false
	fuel = fuel_max()
	weapons.refill()
	Sfx.play("click", self)
	pod_opened.emit()
	return true


func carry_capacity() -> float:
	return CARRY_CAPACITY


## Picking things up: the first of each material is noted in the corner, along with any
## recipes it completes; obsidian unlocks the materials refinery.
func _check_unlocks() -> void:
	if progress == null:
		return
	var found: Array[String] = []
	for s in backpack.slots:
		if s != null and not progress.discovered.has(s["id"]) and not found.has(Items.name_of(s["id"])):
			found.append(Items.name_of(s["id"]))
	if found.is_empty():
		return
	var before := _known_recipes()
	for s in backpack.slots:
		if s != null:
			progress.discovered[s["id"]] = true
	var blueprint := false
	if not progress.refinery_unlocked and backpack.count_of(Items.OBSIDIAN) > 0:
		progress.refinery_unlocked = true
		blueprint = true
	if _quiet_unlocks:
		return
	if hud:
		hud.notify("NEW MATERIAL", found)
		if blueprint:
			hud.notify("NEW BLUEPRINT", ["Materials refinery"], Color(0.5, 0.85, 1.0))
		var fresh: Array[String] = []
		var after := _known_recipes()
		for id in after:
			if not before.has(id):
				fresh.append(after[id])
		if not fresh.is_empty():
			hud.notify("NEW RECIPES", fresh, Color(0.55, 0.95, 0.6))
	Sfx.play("scan", self, -4.0, 1.4)


func _known_recipes() -> Dictionary:
	var out: Dictionary = Bench.available_names(progress)
	out.merge(Refinery.available_names(progress))
	return out


func _station_prompt() -> String:
	for st in get_tree().get_nodes_in_group("stations"):
		if st.is_in_reach(global_position, INTERACT_REACH):
			return st.prompt_text()
	return ""


func flares_max() -> int:
	return FLARES_MAX + (2 if progress and progress.blueprints.has("flare_pouch") else 0)


## Shop purchases that change you: a bigger backpack.
func apply_blueprints() -> void:
	if progress and progress.blueprints.has("backpack_plus") and backpack.slots.size() < BACKPACK_SLOTS + 8:
		backpack.slots.resize(BACKPACK_SLOTS + 8)
		backpack.changed.emit()


## Thermal suit worn: the fire caves can't hurt you.
func heat_protected() -> bool:
	return equipment.count_of(Items.THERMAL_SUIT) > 0


func _update_heat(delta: float) -> void:
	if world == null or not active:
		return
	var hot: bool = world.biome_at(global_position) == 2  # Generator.BIOME_FIRE
	heat = move_toward(heat, 1.0 if hot else 0.0, delta * 0.5)
	if not hot or heat_protected() or health <= 0.0:
		_heat_exposure = 0.0
		return
	_heat_exposure += delta
	if _heat_exposure < HEAT_GRACE:
		if _message_time <= 0.0:
			_flash("Too hot")
		return
	_heat_tick -= delta
	if _heat_tick <= 0.0:
		_heat_tick = HEAT_TICK
		_flash("BURNING")
		take_damage(HEAT_DPS * HEAT_TICK, global_position)


func is_overweight() -> bool:
	return backpack.weight() > CARRY_CAPACITY


## Your backpack plus every storage inventory (pod, containers) within STORAGE_REACH.
func cost_sources() -> Array:
	var out: Array = [backpack]
	if pod and pod.global_position.distance_to(global_position) <= STORAGE_REACH:
		out.append(pod.storage)
	if builder:
		for b in builder.grid.buildings:
			if b.build_id in [Buildables.STORAGE, Buildables.STORAGE_LARGE] 					and b.global_position.distance_to(global_position) <= STORAGE_REACH:
				out.append(b.inv)
	return out


## Totals across nearby storage (not the backpack), for the HUD.
func nearby_storage_summary() -> String:
	var totals := {}
	var sources := cost_sources()
	for i in range(1, sources.size()):
		for s in sources[i].slots:
			if s:
				totals[s["id"]] = totals.get(s["id"], 0) + s["count"]
	if sources.size() <= 1:
		return "none within %d m" % roundi(STORAGE_REACH)
	return Items.describe(totals) if not totals.is_empty() else "empty"


## "Deposit all ore" buttons: moves stackable resources (not batteries) into `inv`.
func deposit_ore_into(inv) -> void:
	var moved: int = inv.pull_ore_from(backpack)
	if moved > 0:
		Sfx.play("deposit", self, -4.0)
	var left := 0
	for s in backpack.slots:
		if s and Items.DEFS[s["id"]]["stack"] > 1:
			left += s["count"]
	_flash("Deposited %d ore%s" % [moved, "" if left == 0 else " — storage full"])


## Ore scanner pulse: floating markers over ore clusters, visible through rock.
func scan() -> void:
	if _scan_cd > 0.0:
		_flash("Scanner recharging (%ds)" % ceili(_scan_cd))
		return
	_scan_cd = SCAN_COOLDOWN
	Sfx.play("scan", self, -4.0)
	# The pod is always pinged, at any range, so you can find your way home. So are your bodies.
	if pod:
		var home: Vector3 = pod.global_position + Vector3(0, 6.0, 0)
		_scan_marker("▲ DROP POD\n%d m" % roundi(home.distance_to(global_position)), home,
			Color(1.0, 0.72, 0.3), 34)
	for body in get_tree().get_nodes_in_group("bodies"):
		var bp: Vector3 = body.global_position + Vector3(0, 2.0, 0)
		_scan_marker("✚ YOUR BODY\n%d m" % roundi(bp.distance_to(global_position)), bp,
			Color(1.0, 0.5, 0.4), 30)
	# Boss lairs show up from much further away.
	if director and world._main_gen:
		for dz in range(-1, 2):
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var cube := Vector3i((global_position / 128.0).floor()) + Vector3i(dx, dy, dz)
					var lair: Vector3 = world._main_gen.arena_center(cube)
					if lair != Vector3.INF and lair.distance_to(global_position) < 200.0:
						var beaten: bool = director.bosses_defeated.has(director.lair_key(lair))
						_scan_marker("%s\n%d m" % ["LAIR (cleared)" if beaten else "LAIR", roundi(lair.distance_to(global_position))],
							lair, Color(0.7, 0.6, 0.55) if beaten else Color(1.0, 0.35, 0.2), 30)
	# Your Shredders, at any range, with what they're up to.
	if builder and builder.grid:
		for b in builder.grid.buildings:
			if b.has_method("pick_up") and b.get("hopper") != null and is_instance_valid(b):
				var sp: Vector3 = b.global_position + Vector3(0, 1.2, 0)
				_scan_marker("⬢ SHREDDER\n%s\n%d m" % [b.status, roundi(sp.distance_to(global_position))], sp,
					Color(0.45, 1.0, 0.5), 26)
	var found: Array = world.scan_ores(camera.global_position, SCAN_RADIUS)
	if found.is_empty():
		_flash("Scan: no ore within %d m" % int(SCAN_RADIUS))
		return
	_flash("Scan: %d ore deposits nearby" % found.size())
	for i in mini(found.size(), SCAN_MAX_MARKERS):
		var f: Dictionary = found[i]
		var m: int = f["mat"]
		var pos: Vector3 = f["pos"]
		_scan_marker("◆ %s\n%d m" % [Materials.NAMES[m], roundi(pos.distance_to(global_position))],
			pos, Materials.COLOR[m].lightened(0.35), 28)


func _scan_marker(text: String, pos: Vector3, color: Color, size: int) -> void:
	var marker := Label3D.new()
	marker.text = text
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	marker.fixed_size = true
	marker.pixel_size = 0.0012
	marker.font_size = size
	marker.outline_size = 8
	marker.modulate = color
	get_parent().add_child(marker)
	marker.global_position = pos
	var tween := marker.create_tween()
	tween.tween_interval(SCAN_MARKER_TIME - 1.0)
	tween.tween_property(marker, "modulate:a", 0.0, 1.0)
	tween.tween_callback(marker.queue_free)


func get_state() -> Dictionary:
	return {
		"pos": global_position,
		"yaw": rotation.y,
		"pitch": camera.rotation.x - _cam_dip,
		"fuel": fuel,
		"flares": flares,
		"backpack": backpack.to_data(),
		"equipment": equipment.to_data(),
	}


## Call before adding to the tree (sets local transform) or after.
func apply_state(s: Dictionary) -> void:
	position = s.get("pos", position)
	rotation.y = s.get("yaw", 0.0)
	_pending_pitch = s.get("pitch", 0.0)
	if camera:
		camera.rotation.x = _pending_pitch
	fuel = s.get("fuel", fuel)
	flares = s.get("flares", flares)
	apply_blueprints()  # a bought backpack extension must exist before its slots load
	equipment.from_data(s.get("equipment", []))
	var pack = s.get("backpack", [])
	_quiet_unlocks = true  # a loaded backpack isn't news
	_load_backpack(pack, s)
	_quiet_unlocks = false


func _load_backpack(pack, s: Dictionary) -> void:
	if pack is Array:
		backpack.from_data(pack)
	else:
		# Saves from before the slot inventory: {material id: count} + battery charges 0..1.
		var mat_to_item := {1: Items.IRON, 2: Items.ELECTRUM, 5: Items.DIAMOND}
		for m in pack:
			if mat_to_item.has(int(m)):
				backpack.add(mat_to_item[int(m)], pack[m])
		for c in s.get("batteries", []):
			backpack.add_stack(Items.new_battery(float(c) * Items.BATTERY_CAPACITY))


# --- Presentation -------------------------------------------------------------

func _flash(text: String) -> void:
	_message = text
	_message_time = 2.5


func _update_hud() -> void:
	if hud == null:
		return
	hud.update_state({
		"tool": tool,
		"drill_owned": progress != null and progress.drill_owned,
		"dagger_owned": progress != null and progress.dagger_owned,
		"credits": progress.credits if progress else 0,
		"credits_known": progress != null and (progress.credits > 0 or not progress.blueprints.is_empty()),
		"fuel": fuel,
		"fuel_max": fuel_max(),
		"stamina": climb_stamina / CLIMB_STAMINA,
		"climbing": climbing,
		"weight": backpack.weight(),
		"capacity": CARRY_CAPACITY,
		"backpack": "%d / %d slots%s   ·   [Tab] inventory" % [backpack.used_slots(), backpack.slots.size(),
			"   OVERWEIGHT" if is_overweight() else ""],
		"flares": flares,
		"flares_max": flares_max(),
		"flare_eta": FLARE_RECHARGE - _flare_timer,
		"scan_cd": _scan_cd,
		"scan_max": SCAN_COOLDOWN,
		"zone": world.zone_name(global_position),
		"stash": nearby_storage_summary(),
		"health": health,
		"max_health": max_health(),
		"shaken": shaken_time,
		"heat": weapons.heat,
		"overheated": weapons.overheated,
		"charges": weapons.charges,
		"charges_max": weapons.SHOTGUN_MAX,
		"threat": threat_label,
	})
	var prompt := ""
	var target = builder.target_building() if builder else null
	var cache = null
	for c in get_tree().get_nodes_in_group("caches"):
		if c.in_reach(global_position):
			cache = c
	if health <= 0.0:
		prompt = ""  # dead: the death screen says what to do
	elif builder and builder.is_placing():
		prompt = "Placing %s — LMB build · R %s · RMB or Q cancel" % [Buildables.DEFS[builder.selected]["name"],
			"tilt" if Buildables.DEFS[builder.selected]["mount"] == "wall" else "rotate"]
	elif cache:
		prompt = "[E] take everything from %s" % ("your body" if cache.kind == "body" else "the cache")
	elif target:
		prompt = target.repair_prompt() if target.hp < target.max_hp else target.hover_text() + ("" if target.has_method("pick_up") else "   ·   [X] remove")
	elif _station_prompt() != "":
		prompt = _station_prompt()
	elif pod and pod.is_in_reach(global_position, INTERACT_REACH):
		prompt = "[E] Drop pod"
	hud.set_prompt(prompt)
	hud.set_message(_message if _message_time > 0.0 else "")


func _build_tool_models() -> void:
	_tool_root = Node3D.new()
	_tool_root.position = TOOL_REST
	camera.add_child(_tool_root)

	# Artist viewmodels (pickaxe, drill) are authored in Blender camera space: camera at the
	# origin looking down +Y (glTF import turns that into Godot's -Z), 90° FOV. They sit
	# straight under our camera. Squashing depth by the ratio of the two FOV tangents gives
	# exactly the Blender framing (screen = x / (z·tan)); the uniform 0.1 scale keeps the
	# models inside the near-camera space so they can't poke into rock.
	_drill_holder = Node3D.new()
	camera.add_child(_drill_holder)
	var depth_ratio := tan(deg_to_rad(DRILL_SOURCE_VFOV) * 0.5) / tan(deg_to_rad(camera.fov) * 0.5)
	var viewmodel_scale := Vector3(1.0, 1.0, depth_ratio) * DRILL_MODEL_SCALE
	_viewmodel_scale = viewmodel_scale

	_pick_model = Node3D.new()
	_pick_model.scale = viewmodel_scale
	_drill_holder.add_child(_pick_model)
	var pick: Node3D = PickaxeScene.instantiate()
	_pick_model.add_child(pick)
	_pick_anim = pick.find_child("AnimationPlayer", true, false)
	if _pick_anim:
		_pick_anim.play(_pick_anim.get_animation_list()[0])
		_pick_anim.speed_scale = 0.0  # driven manually by _update_pickaxe()
		_pick_has_miss_recovery = _pick_anim.current_animation_length >= PICK_MISS_RECOVER_END / ANIM_FPS - 0.01
		_pick_seek()

	_drill_model = Node3D.new()
	_drill_model.scale = viewmodel_scale
	_build_dagger()
	_drill_holder.add_child(_drill_model)
	for scene in [DrillScene, DiamondDrillScene]:
		var skin: Node3D = scene.instantiate()
		_drill_model.add_child(skin)
		_drill_skins.append(skin)
		var anim: AnimationPlayer = skin.find_child("AnimationPlayer", true, false)
		if anim:
			anim.play(DRILL_ANIM)
			anim.speed_scale = 0.0  # driven manually by _animate_drill()
			anim.seek(0.0, true)
			_drill_anims.append(anim)


## The crooked dagger: the hydra's curved bone claw set in a wrapped steel hilt.
func _build_dagger() -> void:
	_dagger_model = Node3D.new()
	_dagger_model.position = DAGGER_REST
	_dagger_model.visible = false
	camera.add_child(_dagger_model)
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color(0.86, 0.77, 0.58)
	bone.roughness = 0.35
	bone.clearcoat_enabled = true
	var wrap := StandardMaterial3D.new()
	wrap.albedo_color = Color(0.2, 0.12, 0.08)
	wrap.roughness = 0.9
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.62, 0.64, 0.68)
	steel.metallic = 0.85
	steel.roughness = 0.3
	var grip := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.016
	gm.bottom_radius = 0.018
	gm.height = 0.11
	grip.mesh = gm
	grip.material_override = wrap
	grip.rotation.x = PI / 2
	_dagger_model.add_child(grip)
	var guard := _box(Vector3(0.07, 0.016, 0.02), Vector3(0, 0, -0.06), steel)
	_dagger_model.add_child(guard)
	# Claw blade: tapering segments that curve up and to the side.
	var p := Vector3(0, 0, -0.065)
	var dir := Vector3(0, 0, -1)
	for i in 6:
		var seg_len := 0.045
		var r0 := 0.018 * (1.0 - i / 6.0) + 0.003
		var r1 := 0.018 * (1.0 - (i + 1) / 6.0) + 0.001
		var seg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.bottom_radius = r0
		cm.top_radius = r1
		cm.height = seg_len
		cm.radial_segments = 6
		seg.mesh = cm
		seg.material_override = bone
		var y := dir.normalized()
		var x := y.cross(Vector3.UP).normalized()
		seg.transform = Transform3D(Basis(x, y, x.cross(y)), p + y * seg_len * 0.5)
		_dagger_model.add_child(seg)
		p += y * seg_len
		dir = dir.rotated(Vector3.RIGHT, 0.16).rotated(Vector3.UP, 0.05)


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	return m


func _build_dust() -> void:
	_dust = CPUParticles3D.new()
	_dust.top_level = true
	_dust.emitting = false
	_dust.one_shot = false
	_dust.amount = 24
	_dust.lifetime = 1.2
	_dust.explosiveness = 0.0
	_dust.direction = Vector3.UP
	_dust.spread = 80.0
	_dust.initial_velocity_min = 0.5
	_dust.initial_velocity_max = 2.0
	_dust.gravity = Vector3(0, -2.0, 0)
	_dust.scale_amount_min = 0.03
	_dust.scale_amount_max = 0.09
	var quad := SphereMesh.new()
	quad.radius = 0.5
	quad.height = 1.0
	quad.radial_segments = 6
	quad.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.42, 0.38)
	mat.roughness = 1.0
	quad.material = mat
	_dust.mesh = quad
	add_child(_dust)


func _animate_tool(delta: float) -> void:
	_swing = maxf(_swing - delta * 2.2, 0.0)
	var swing_angle := sin(_swing * PI) * 0.9
	_tool_root.rotation = Vector3(-swing_angle, 0.0, 0.0)

	# Walk bob: figure-eight sway that scales with ground speed.
	var ground_speed := Vector2(velocity.x, velocity.z).length() if is_on_floor() else 0.0
	var amount := clampf(ground_speed / WALK_SPEED, 0.0, 1.6)
	_bob_phase += delta * ground_speed * 1.9
	_bob_amount = lerpf(_bob_amount, amount, minf(delta * 8.0, 1.0))
	# The head bobs now, so the tool only sways a little on top of it.
	var bob := Vector3(sin(_bob_phase) * 0.006, -absf(cos(_bob_phase)) * 0.005, 0.0) * _bob_amount
	_animate_camera(delta)

	var shake := Vector3.ZERO
	if _drilling:
		shake = Vector3(randf_range(-0.004, 0.004), randf_range(-0.004, 0.004), 0.0)
	_tool_root.position = TOOL_REST + bob + shake
	# The drill sits almost at the lens, so it sways by angle instead of offset: the same
	# screen motion as the pickaxe's bob regardless of how close the model is.
	_drill_holder.rotation = Vector3(bob.y + shake.y, -bob.x - shake.x, 0.0) * 1.8
	var diamond: bool = progress != null and progress.diamond_tip
	_drill_skins[0].visible = not diamond
	_drill_skins[1].visible = diamond
	_animate_drill(delta)
	# Dagger: a fast lunge forward and back, with the same walk bob.
	_stab = maxf(_stab - delta * 3.2, 0.0)
	var lunge := sin(_stab * PI) * (1.0 if _stab > 0.5 else 0.7)
	_dagger_model.position = DAGGER_REST + bob * 1.2 + Vector3(-0.07, 0.04, -0.24) * lunge
	_dagger_model.rotation = Vector3(-0.35 - 0.5 * lunge, 0.35 - 0.25 * lunge, 0.15)


## Head bob while walking, and a slight lean into the way you're moving: roll toward a
## strafe, a small dip when going forward.
func _animate_camera(delta: float) -> void:
	var head := Vector3(sin(_bob_phase) * 0.018, -absf(cos(_bob_phase)) * 0.03, 0.0) * _bob_amount
	camera.position = Vector3(head.x, CAMERA_HEIGHT + head.y, 0.0)
	var local: Vector3 = global_basis.inverse() * velocity
	var k := 0.0 if climbing else 1.0
	var roll := -clampf(local.x / SPRINT_SPEED, -1.0, 1.0) * CAMERA_ROLL * k
	var dip := -clampf(-local.z / SPRINT_SPEED, -1.0, 1.0) * CAMERA_DIP * k * (1.0 if is_on_floor() else 0.3)
	var t := minf(delta * 7.0, 1.0)
	camera.rotation.z = lerpf(camera.rotation.z, roll, t)
	var new_dip := lerpf(_cam_dip, dip, t)
	camera.rotation.x = clampf(camera.rotation.x - _cam_dip + new_dip, -1.5, 1.5)
	_cam_dip = new_dip


## Drill animation (24 fps): frames 0-6 spin-up, 6-12 running loop. On release the loop
## finishes back to frame 6 (identical to 12), then plays 6 -> 0 in reverse, so the bit
## never visibly spins backwards.
func _animate_drill(delta: float) -> void:
	if _drill_anims.is_empty():
		return
	var spin_up := DRILL_ANIM_LOOP_START
	var loop_end := DRILL_ANIM_LOOP_END
	if _drilling:
		_drill_t += delta
		if _drill_t >= loop_end:
			_drill_t = spin_up + fmod(_drill_t - spin_up, loop_end - spin_up)
		_drill_stopping = false
	elif _drill_t > 0.0:
		if _drill_t > spin_up and not _drill_stopping:
			# Still in the running loop: carry on to the end of the cycle first.
			_drill_t += delta
			if _drill_t >= loop_end:
				_drill_t = spin_up
				_drill_stopping = true
		else:
			_drill_stopping = true
			_drill_t = maxf(_drill_t - delta, 0.0)
	else:
		_drill_stopping = false
	for anim in _drill_anims:
		anim.seek(_drill_t, true)
