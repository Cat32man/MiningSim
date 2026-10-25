extends Node3D
## Local threat and bug spawning (DESIGN.md §7). Threat is per 32 m region and grows with
## what you dig out of it, plus a world baseline (distance from spawn, depth) and your
## tool tier. It never decays. Higher threat = more frequent spawns, bigger groups and a
## higher cap on live bugs (the cap grows quadratically, i.e. it runs away late game).
##
## Each spawn roll sends either a hunting group at you or a raid on a nearby machine
## (running machines draw raids). Groups of 3+ are announced by a rumble a few seconds
## before they arrive. Dying leaves a death swarm guarding your body.

signal raid_started(building: Node3D)
## A gnawer has reached your walls and is waiting to chew in.
signal base_threatened(piece: Node3D)
## The fire-cave boss showed up / is gone (killed = true if you beat it).
signal boss_appeared(boss: Node3D)
signal boss_gone(boss: Node3D, killed: bool)

const Bug = preload("res://scripts/enemies/bug.gd")
const Hydra = preload("res://scripts/enemies/hydra.gd")
const Sfx = preload("res://scripts/audio/sfx.gd")

const REGION := 32.0
const SPAWN_INTERVAL := 25.0
const MINED_PER_THREAT := 9000.0  # samples dug out of one region for +1.0 threat
const MINED_THREAT_MAX := 1.0  # digging can add at most this much
const MINED_COOLDOWN := 300.0  # samples per minute a region forgets (full +1.0 cools in 30 min)
const SPAWN_MIN_DIST := 14.0
const SPAWN_MAX_DIST := 24.0
const SWARM_WARNING := 4.0  # seconds of rumble before a group of 3+ arrives
const WARN_SIZE := 3
const RAID_RANGE := 45.0  # machines this close to you can be raided
const RAID_CHANCE := 0.15
## After a wave (a warned swarm) or a raid, the next one waits a random 10 min to 1 h. In
## the meantime nothing spawns near your base, and only stragglers (1-2 bugs) elsewhere.
const WAVE_GAP_MIN := 600.0
const WAVE_GAP_MAX := 3600.0
const BASE_RANGE := 45.0  # share of rolls that go for a machine (when one is in range)
const DEATH_SWARM_SPAWN := 45.0  # guards appear when you come this close to your body
const DEATH_SWARM_DESPAWN := 60.0
const DEATH_SWARM_SPILL := 180.0  # seconds before guards drift off to wreck nearby machines
const DEATH_SWARM_MAX := 10
const MAX_NEARBY := 8  # never more bugs than this within NEARBY_RANGE of a spawn
const NEARBY_RANGE := 40.0
## One Magma Hydra lives in each fire-cave arena (terrain_generator.gd, one per
## BOSS_REGION cube). It wakes when you step into the arena; beaten lairs stay empty.
const BOSS_REGION := 128.0
const BOSS_LEASH := 50.0  # goes back to sleep if you get this far from its arena
const BOSS_RETRY := 5.0

## Set by main.
var world
var player
var progress
var grid

var mined := {}  # Vector3i region -> samples removed
## Bugs guarding each body: {pos, count, age, spawned, spilled}.
var death_swarms: Array = []
var boss: Node3D
var bosses_defeated := {}  # lair key -> true
var _boss_cd := 0.0
var _arena_light: OmniLight3D
var _arena_t := 0.0
var _timer := 20.0
var wave_cd := 0.0  # seconds until the next wave or raid is allowed (saved)
var _cool_t := 0.0
var _pending := {}  # group waiting out its warning: {at, size, target, t}


func on_carved(center: Vector3, removed: int) -> void:
	var r := region_of(center)
	mined[r] = mined.get(r, 0) + removed


## Dug-out regions calm down again over time (and old saves lose their runaway counts).
func _cool_regions(dt: float) -> void:
	_cool_t += dt
	if _cool_t < 1.0:
		return
	var forget := MINED_COOLDOWN * _cool_t / 60.0
	_cool_t = 0.0
	for r in mined.keys():
		var left: float = minf(float(mined[r]), MINED_PER_THREAT * MINED_THREAT_MAX) - forget
		if left <= 0.0:
			mined.erase(r)
		else:
			mined[r] = left


static func region_of(p: Vector3) -> Vector3i:
	return Vector3i((p / REGION).floor())


func threat_at(p: Vector3) -> float:
	var base := Vector2(p.x, p.z).length() / 300.0 + maxf(-p.y, 0.0) / 220.0
	var local: float = minf(mined.get(region_of(p), 0) / MINED_PER_THREAT, MINED_THREAT_MAX)
	var tier := 0.0
	if progress:
		tier = (progress.tiers.values().max() - 1) * 0.06 + (0.12 if progress.diamond_tip else 0.0)
	return base + local + tier


static func label(t: float) -> String:
	if t < 0.15:
		return "Calm"
	if t < 0.4:
		return "Low"
	if t < 0.8:
		return "Elevated"
	if t < 1.5:
		return "High"
	return "Extreme"


func _process(dt: float) -> void:
	if player == null:
		return
	_cool_regions(dt)
	_tick_death_swarms(dt)
	_tick_boss(dt)
	if not player.active:
		return
	wave_cd = maxf(wave_cd - dt, 0.0)
	if not _pending.is_empty():
		_pending["t"] -= dt
		if _pending["t"] <= 0.0:
			_send(_pending)
			_pending = {}
		return
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = SPAWN_INTERVAL * randf_range(0.7, 1.3)
	var at: Vector3 = player.global_position
	if wave_cd > 0.0 and _near_base(at):
		return  # a quiet spell at home after the last wave
	var t := threat_at(at)
	var live := _bugs_near(at)
	var cap := mini(1 + floori(pow(t * 2.0, 2.0)), MAX_NEARBY)
	if live >= cap:
		return
	if randf() > clampf(t * 1.5, 0.08, 1.0):
		return
	var size := clampi(1 + roundi(t * randf_range(2.0, 5.0)), 1, cap - live)
	if wave_cd > 0.0:
		size = mini(size, WARN_SIZE - 1)
	var group := {"at": at, "size": size, "target": null, "t": 0.0, "threat": t}
	var machine := _pick_raid_target(at) if wave_cd <= 0.0 else null
	if machine and randf() < RAID_CHANCE:
		group["at"] = machine.global_position
		group["target"] = machine
	if size >= WARN_SIZE or group["target"] != null:
		wave_cd = randf_range(WAVE_GAP_MIN, WAVE_GAP_MAX)
	if size >= WARN_SIZE:
		group["t"] = SWARM_WARNING
		_pending = group
		Sfx.play("swarm_warn", player, -2.0, randf_range(0.9, 1.1))
	else:
		_send(group)


## Spawns a group: out of sight around its target, all within a couple of metres.
func _send(group: Dictionary) -> void:
	var target = group["target"]
	if target != null and not is_instance_valid(target):
		return
	var center := _find_spawn(group["at"], SPAWN_MIN_DIST * (0.6 if target else 1.0), SPAWN_MAX_DIST)
	if center == Vector3.INF:
		return
	var t: float = group["threat"]
	for i in group["size"]:
		var kind := "gnawer" if randf() < _gnawer_share(t, target != null) else "swarmer"
		var b := spawn_bug(_near(center), kind)
		if target:
			b.target_building = target
		else:
			b.aggro = group["size"] > 1  # groups come straight for you
	if target:
		raid_started.emit(target)


## Gnawers show up from Elevated threat on, and lead raids.
static func _gnawer_share(t: float, raid: bool) -> float:
	var s := clampf((t - 0.4) * 0.5, 0.0, 0.35)
	return minf(s * 2.0 + 0.15, 0.6) if raid and t >= 0.25 else s


func _bugs_near(p: Vector3) -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group("bugs"):
		if b.global_position.distance_to(p) < NEARBY_RANGE:
			n += 1
	return n


func spawn_bug(pos: Vector3, kind := "swarmer") -> Node3D:
	var b := Bug.new()
	b.kind = kind
	b.player = player
	b.director = self
	add_child(b)
	b.global_position = pos
	return b


## A running machine near you (they make noise), else any intact one.
func _pick_raid_target(around: Vector3) -> Node3D:
	if grid == null:
		return null
	var running: Array = []
	var any: Array = []
	for b in grid.buildings:
		if b.is_structure or b.broken or b.global_position.distance_to(around) > RAID_RANGE:
			continue
		any.append(b)
		if b.is_running():
			running.append(b)
	if not running.is_empty():
		return running.pick_random()
	return any.pick_random() if not any.is_empty() else null


## For a raider whose machine just broke: the nearest intact machine within 25 m.
func next_raid_target(from: Vector3) -> Node3D:
	if grid == null:
		return null
	var best: Node3D = null
	var best_d := 25.0
	for b in grid.buildings:
		var d: float = b.global_position.distance_to(from)
		if not b.is_structure and not b.broken and d < best_d:
			best_d = d
			best = b
	return best


# --- Boss ---------------------------------------------------------------------------

static func lair_key(p: Vector3) -> String:
	var k := Vector3i((p / BOSS_REGION).floor())
	return "%d,%d,%d" % [k.x, k.y, k.z]


func _tick_boss(dt: float) -> void:
	if boss != null and not is_instance_valid(boss):
		boss = null
	var gen = world._main_gen if world else null
	var arena: Vector3 = gen.arena_for(player.global_position) if gen else Vector3.INF
	_update_arena_light(arena)
	if boss:
		# Run far enough from its arena and it goes back to sleep (it'll be there next time).
		var home: Vector3 = boss.arena_center if boss.arena_center != Vector3.INF else boss.global_position
		if boss.health > 0.0 and player.global_position.distance_to(home) > BOSS_LEASH:
			var b := boss
			boss = null
			_boss_cd = BOSS_RETRY
			boss_gone.emit(b, false)
			b.queue_free()
		return
	_boss_cd -= dt
	if _boss_cd > 0.0 or arena == Vector3.INF or not player.active or player.health <= 0.0:
		return
	var key := lair_key(arena)
	if bosses_defeated.has(key):
		return
	# Wakes when you step onto the arena floor; rises on the far side from you.
	var rel: Vector3 = player.global_position - arena
	if Vector2(rel.x, rel.z).length() > gen.ARENA_RADII.x - 3.0 or absf(rel.y - gen.ARENA_FLOOR) > 6.0:
		return
	var away := -Vector3(rel.x, 0.0, rel.z).normalized()
	if away == Vector3.ZERO:
		away = Vector3.FORWARD
	var at := arena + away * 9.0 + Vector3(0, gen.ARENA_FLOOR + 0.4, 0)
	var h := spawn_boss(at, key)
	h.arena_center = arena + Vector3(0, gen.ARENA_FLOOR, 0)
	h.arena_radius = gen.ARENA_RADII.x - 3.0


## A big warm light hangs in an arena while you're near it (the lava glow itself doesn't
## light the room).
func _update_arena_light(arena: Vector3) -> void:
	var near: bool = arena != Vector3.INF and player.global_position.distance_to(arena) < 60.0
	if not near:
		if _arena_light:
			_arena_light.queue_free()
			_arena_light = null
		return
	if _arena_light == null:
		_arena_light = OmniLight3D.new()
		_arena_light.light_color = Color(1.0, 0.45, 0.18)
		_arena_light.omni_range = 34.0
		_arena_light.omni_attenuation = 1.4
		_arena_light.shadow_enabled = true
		add_child(_arena_light)
	_arena_light.global_position = arena + Vector3(0, 3.0, 0)
	_arena_t += get_process_delta_time()
	_arena_light.light_energy = 1.1 + 0.15 * sin(_arena_t * 1.7) + 0.08 * sin(_arena_t * 5.3)


func spawn_boss(at: Vector3, key: String) -> Node3D:
	var h := Hydra.new()
	h.player = player
	h.director = self
	h.lair_key = key
	add_child(h)
	h.global_position = at
	h.died.connect(_on_boss_died)
	boss = h
	boss_appeared.emit(h)
	return h


func _on_boss_died(b: Node3D) -> void:
	bosses_defeated[b.lair_key] = true
	boss = null
	boss_gone.emit(b, true)


# --- Death swarm -------------------------------------------------------------------

func add_death_swarm(pos: Vector3) -> void:
	var count := mini(3 + floori(threat_at(pos) * 4.0), DEATH_SWARM_MAX)
	death_swarms.append({"pos": pos, "count": count, "age": 0.0, "spawned": false, "spilled": false})


## Guards exist only while you're near your body; away from it they're kept as a count.
func _tick_death_swarms(dt: float) -> void:
	for rec in death_swarms.duplicate():
		rec["age"] += dt
		if rec["count"] <= 0:
			death_swarms.erase(rec)
			continue
		var d: float = player.global_position.distance_to(rec["pos"])
		if not rec["spawned"] and d < DEATH_SWARM_SPAWN and player.active and world.is_ready_around(rec["pos"]):
			rec["spawned"] = true
			# Only as many as the area has room for; the rest wait for the next visit.
			for i in mini(rec["count"], MAX_NEARBY - _bugs_near(rec["pos"])):
				var at := _find_spawn(rec["pos"], 1.5, 7.0, false)
				var b := spawn_bug(_near(at if at != Vector3.INF else rec["pos"] + Vector3.UP * 0.5),
					"gnawer" if i == 0 and rec["count"] >= 6 else "swarmer")
				b.home = rec["pos"]
				b.swarm_record = rec
		elif rec["spawned"] and d > DEATH_SWARM_DESPAWN:
			rec["spawned"] = false
			for b in _guards(rec):
				b.queue_free()
		if rec["spawned"] and not rec["spilled"] and rec["age"] > DEATH_SWARM_SPILL:
			rec["spilled"] = true
			var m := next_raid_target(rec["pos"])
			if m:
				for b in _guards(rec):
					b.target_building = m
				raid_started.emit(m)


func _guards(rec: Dictionary) -> Array:
	return get_tree().get_nodes_in_group("bugs").filter(
		# get(): the boss is in "bugs" too but isn't part of any death swarm.
		func(b): return b.get("swarm_record") == rec and not b.is_queued_for_deletion())


func get_swarms_state() -> Array:
	return death_swarms.map(func(r): return {"pos": r["pos"], "count": r["count"], "age": r["age"]})


func load_swarms_state(list: Array) -> void:
	for r in list:
		death_swarms.append({"pos": r["pos"], "count": r["count"], "age": r.get("age", 0.0),
			"spawned": false, "spilled": false})


# --- Placement ---------------------------------------------------------------------

## Open floor between min_d and max_d from `around`, out of the player's sight if possible.
func _find_spawn(around: Vector3, min_d: float, max_d: float, hidden := true) -> Vector3:
	var fallback := Vector3.INF
	var space := get_world_3d().direct_space_state
	var eye: Vector3 = player.camera.global_position
	for attempt in 40:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		var p := around + dir * randf_range(min_d, max_d) + Vector3(0, randf_range(-4.0, 4.0), 0)
		var s := Vector3i(p.round())
		if not _open_floor(s) or _near_structure(Vector3(s)):
			continue
		if not hidden:
			return Vector3(s)
		var q := PhysicsRayQueryParameters3D.create(eye, Vector3(s) + Vector3(0, 0.5, 0), 1)
		if space.intersect_ray(q).is_empty():
			fallback = Vector3(s)  # visible: only if nothing better turns up
			continue
		return Vector3(s)
	return fallback


func _near_base(p: Vector3) -> bool:
	if grid == null:
		return false
	for b in grid.buildings:
		if b.global_position.distance_to(p) < BASE_RANGE:
			return true
	return false


## Never spawn inside or right next to a base: bugs come from the caves.
func _near_structure(p: Vector3) -> bool:
	if grid == null:
		return false
	for b in grid.buildings:
		if b.is_structure and b.global_position.distance_to(p) < 8.0:
			return true
	return false


func _open_floor(s: Vector3i) -> bool:
	return world.density_at(s) <= 0.0 and world.density_at(s + Vector3i.UP) <= 0.0 \
		and world.density_at(s + Vector3i.DOWN) > 0.0


## A spot next to `center` for one member of a group.
func _near(center: Vector3) -> Vector3:
	for attempt in 6:
		var p := center + Vector3(randf_range(-1.8, 1.8), 0.0, randf_range(-1.8, 1.8))
		if world.density_at(Vector3i(p.round())) <= 0.0:
			return p
	return center
