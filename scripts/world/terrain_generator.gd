extends RefCounted
## Pure function of world position -> density + material.
## Density > 0 is solid rock, <= 0 is air. Values are clamped to [-1, 1].
## Each worker thread creates its own instance, so no shared noise state.

const Materials = preload("res://scripts/world/materials.gd")

const MAT_ROCK := Materials.ROCK
const MAT_IRON := Materials.IRON
const MAT_ELECTRUM := Materials.ELECTRUM
const MAT_BEDROCK := Materials.BEDROCK
const MAT_HARD_ROCK := Materials.HARD_ROCK
const MAT_DIAMOND := Materials.DIAMOND
const MAT_COBALT := Materials.COBALT
const MAT_BASALT := Materials.BASALT
const MAT_OBSIDIAN := Materials.OBSIDIAN
const MAT_COAL := Materials.COAL

const BIOME_NORMAL := 0
const BIOME_HARD := 1
const BIOME_FIRE := 2

## Samples at or above this height are unmineable bedrock.
const CEILING_Y := 40
## Caves never come closer than this to the ceiling, so bedrock is only reached by digging.
const CEILING_BUFFER := 8.0

const SPAWN_CENTER := Vector3(0.0, 2.0, 0.0)
const SPAWN_RADII := Vector3(16.0, 7.0, 16.0)
const SPAWN_FLOOR_Y := -1.5

## Rock strata: caverns get flat floor plates every STRATA_HEIGHT metres.
const STRATA_HEIGHT := 22.0
const STRATA_THICKNESS := 3.0

## Biomes trend later-game with distance from spawn and depth (DESIGN.md §3).
const BIOME_DISTANCE_SCALE := 200.0
const BIOME_DEPTH_SCALE := 140.0
const HARD_ROCK_THRESHOLD := 0.62
## Fire caves: hot pockets inside the late-game zone, past hard rock.
const FIRE_THRESHOLD := 1.15
const FIRE_HEAT := 0.1
## Boss arenas: one per ARENA_REGION cube whose arena centre lands in the fire caves. A
## domed cavern with a flat floor, basalt pillars and three tunnels out. The centre is kept
## ARENA_MARGIN inside its cube so the whole thing (tunnels too) stays in that cube.
const ARENA_REGION := 128.0
const ARENA_MARGIN := 46.0
const ARENA_RADII := Vector3(20.0, 10.0, 20.0)
const ARENA_FLOOR := -4.0  # floor height relative to the centre
const ARENA_PILLARS := 4
const ARENA_PILLAR_RING := 11.0
const ARENA_PILLAR_RADIUS := 1.6
const ARENA_TUNNELS := 3
const ARENA_TUNNEL_LENGTH := 44.0
const ARENA_TUNNEL_RADIUS := 2.6

## Diamond noise cutoff in normal rock (hard rock uses 0.66, so this is far rarer).
const NORMAL_DIAMOND_THRESHOLD := 0.89

var _tunnel_a := FastNoiseLite.new()
var _tunnel_b := FastNoiseLite.new()
var _cavern := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _strata := FastNoiseLite.new()
var _biome := FastNoiseLite.new()
var _iron := FastNoiseLite.new()
var _electrum := FastNoiseLite.new()
var _diamond := FastNoiseLite.new()
var _cobalt := FastNoiseLite.new()
var _heat := FastNoiseLite.new()
var _obsidian := FastNoiseLite.new()
var _coal := FastNoiseLite.new()
var _seed := 0
var _arenas := {}  # Vector3i cube -> arena centre (or Vector3.INF), per generator instance


func _init(seed_value: int) -> void:
	_seed = seed_value
	_setup(_tunnel_a, seed_value, 0.016, 1)
	_setup(_tunnel_b, seed_value + 1, 0.016, 1)
	_setup(_cavern, seed_value + 2, 0.011, 3)
	_setup(_detail, seed_value + 3, 0.14, 2)
	_setup(_iron, seed_value + 4, 0.085, 2)
	_setup(_electrum, seed_value + 5, 0.07, 2)
	_setup(_strata, seed_value + 6, 0.006, 1)
	_setup(_biome, seed_value + 7, 0.008, 2)
	_setup(_diamond, seed_value + 8, 0.16, 1)
	_setup(_cobalt, seed_value + 9, 0.09, 2)
	_setup(_heat, seed_value + 10, 0.012, 2)
	_setup(_obsidian, seed_value + 11, 0.1, 2)
	_setup(_coal, seed_value + 12, 0.07, 2)


func _setup(n: FastNoiseLite, s: int, freq: float, octaves: int) -> void:
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	if octaves > 1:
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = octaves
	else:
		n.fractal_type = FastNoiseLite.FRACTAL_NONE


func density(x: float, y: float, z: float) -> float:
	if y >= CEILING_Y:
		return 1.0
	var detail := _detail.get_noise_3d(x, y, z)

	# Worm tunnels: where two noise fields are both near zero. Squashing y keeps them mostly horizontal.
	var a := _tunnel_a.get_noise_3d(x, y * 1.7, z)
	var b := _tunnel_b.get_noise_3d(x, y * 1.7, z)
	var tunnel := (sqrt(a * a + b * b) - 0.075) * 9.0 + detail * 0.3

	# Large open caverns, floored by flat strata plates. Tunnels still cut through the plates,
	# which gives ramps and holes between levels.
	var cavern := (0.34 - _cavern.get_noise_3d(x, y * 1.4, z)) * 5.0 + detail * 0.3
	var off := _strata.get_noise_2d(x, z) * 4.0
	var half := STRATA_HEIGHT * 0.5
	var u := fposmod(y - off - (STRATA_HEIGHT - STRATA_THICKNESS * 0.5) + half, STRATA_HEIGHT) - half
	var slab := STRATA_THICKNESS * 0.5 - absf(u)
	if u < 0.0:
		slab += detail * 0.6  # rough underside, smooth walkable top
	cavern = maxf(cavern, slab)

	var d := minf(tunnel, cavern)

	# Keep a solid slab under the spawn floor so caves can't punch holes in it.
	var flat_r := Vector2(x - SPAWN_CENTER.x, z - SPAWN_CENTER.z).length()
	var guard := minf(minf(SPAWN_FLOOR_Y - y + 0.5, y - (SPAWN_FLOOR_Y - 6.0)), SPAWN_RADII.x + 4.0 - flat_r)
	d = maxf(d, guard)

	# Spawn chamber: an ellipsoid with a flat floor.
	var e := Vector3(
		(x - SPAWN_CENTER.x) / SPAWN_RADII.x,
		(y - SPAWN_CENTER.y) / SPAWN_RADII.y,
		(z - SPAWN_CENTER.z) / SPAWN_RADII.z)
	# Smooth max of wall and floor so their crease is rounded (a hard max meshes as jagged slivers).
	var wall := (e.length() - 1.0) * SPAWN_RADII.y
	var floor_d := SPAWN_FLOOR_Y - y
	# k = 1.0 rounds only ~1 m of the crease; larger values bow the whole floor upward.
	var spawn_air := 0.5 * (wall + floor_d + sqrt((wall - floor_d) * (wall - floor_d) + 1.0))
	# Rock detail on the walls only, fading out toward the floor so it stays smooth and walkable.
	var wall_detail := clampf((y - SPAWN_FLOOR_Y) / 3.0, 0.0, 1.0)
	d = minf(d, spawn_air + detail * 0.2 * wall_detail)

	d = _arena(x, y, z, d, detail)

	# Solid buffer under the bedrock ceiling.
	d = maxf(d, y - (CEILING_Y - CEILING_BUFFER))
	return clampf(d, -1.0, 1.0)


# --- Boss arenas -------------------------------------------------------------------

## The arena in the cube holding `p`, or Vector3.INF if that cube has none.
func arena_for(p: Vector3) -> Vector3:
	return arena_center(Vector3i((p / ARENA_REGION).floor()))


## Inside an arena's dome (plus a little rock around it)?
func in_arena(p: Vector3) -> bool:
	var c := arena_for(p)
	return c != Vector3.INF and p.distance_to(c) < ARENA_RADII.x + 4.0


func arena_center(cube: Vector3i) -> Vector3:
	if _arenas.has(cube):
		return _arenas[cube]
	var span := ARENA_REGION - ARENA_MARGIN * 2.0
	var c := Vector3(cube) * ARENA_REGION + Vector3.ONE * ARENA_MARGIN + Vector3(
		_hash01(cube, 1) * span, _hash01(cube, 2) * span, _hash01(cube, 3) * span)
	var ok := c.y < CEILING_Y - CEILING_BUFFER - ARENA_RADII.y - 4.0 and biome(c.x, c.y, c.z) == BIOME_FIRE
	_arenas[cube] = c if ok else Vector3.INF
	return _arenas[cube]


func _hash01(cube: Vector3i, salt: int) -> float:
	var h := hash([cube.x, cube.y, cube.z, salt, _seed])
	return float(h & 0xFFFF) / 65535.0


## Carves the arena (if `p` is near one) into density `d`.
func _arena(x: float, y: float, z: float, d: float, detail: float) -> float:
	var p := Vector3(x, y, z)
	var cube := Vector3i((p / ARENA_REGION).floor())
	var c := arena_center(cube)
	if c == Vector3.INF:
		return d
	var rel := p - c
	var reach := ARENA_RADII.x + ARENA_TUNNEL_LENGTH
	if rel.length_squared() > reach * reach:
		return d
	var floor_y := c.y + ARENA_FLOOR
	var flat_r := Vector2(rel.x, rel.z).length()
	# Solid floor slab, so caves below can't hole it.
	var guard := minf(minf(floor_y - y + 0.5, y - (floor_y - 6.0)), ARENA_RADII.x + 3.0 - flat_r)
	d = maxf(d, guard)
	# Dome with a flat floor (smooth crease, like the spawn chamber).
	var e := Vector3(rel.x / ARENA_RADII.x, rel.y / ARENA_RADII.y, rel.z / ARENA_RADII.z)
	var wall := (e.length() - 1.0) * ARENA_RADII.y
	var floor_d := floor_y - y
	var air := 0.5 * (wall + floor_d + sqrt((wall - floor_d) * (wall - floor_d) + 1.0))
	air += detail * 0.25 * clampf((y - floor_y) / 3.0, 0.0, 1.0)
	# Pillars to break line of sight.
	var spin := _hash01(cube, 4) * TAU
	for i in ARENA_PILLARS:
		var a := spin + TAU * i / ARENA_PILLARS
		var pc := Vector2(cos(a), sin(a)) * ARENA_PILLAR_RING
		var pd := Vector2(rel.x, rel.z).distance_to(pc)
		air = maxf(air, ARENA_PILLAR_RADIUS - pd + detail * 0.3)
	d = minf(d, air)
	# Tunnels out, so the arena always joins the caves around it.
	for i in ARENA_TUNNELS:
		var a := spin + PI / ARENA_PILLARS + TAU * i / ARENA_TUNNELS
		var dir := Vector3(cos(a), 0.0, sin(a))
		var start := Vector3(0, ARENA_FLOOR + 2.4, 0) + dir * (ARENA_RADII.x - 4.0)
		var end := start + dir * ARENA_TUNNEL_LENGTH + Vector3(0, (_hash01(cube, 10 + i) - 0.5) * 12.0, 0)
		var seg := end - start
		var t := clampf((rel - start).dot(seg) / seg.length_squared(), 0.0, 1.0)
		var td := rel.distance_to(start + seg * t) - ARENA_TUNNEL_RADIUS + detail * 0.4
		d = minf(d, td)
	return d


## Where the silicon caves (next biome, not generated yet) lie: deep and far out, fixed
## per world. The scanning table already picks up their signal.
static func silicon_center(seed_value: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 1301
	var a := rng.randf() * TAU
	var dist := rng.randf_range(420.0, 520.0)
	return Vector3(cos(a) * dist, rng.randf_range(-170.0, -130.0), sin(a) * dist)


func biome(x: float, y: float, z: float) -> int:
	var score := _biome.get_noise_3d(x, y, z) * 0.6 \
		+ Vector2(x, z).length() / BIOME_DISTANCE_SCALE \
		+ maxf(-y, 0.0) / BIOME_DEPTH_SCALE
	if score > FIRE_THRESHOLD and _heat.get_noise_3d(x, y, z) > FIRE_HEAT:
		return BIOME_FIRE
	return BIOME_HARD if score > HARD_ROCK_THRESHOLD else BIOME_NORMAL


func material(x: float, y: float, z: float) -> int:
	if y >= CEILING_Y:
		return MAT_BEDROCK
	var b := biome(x, y, z)
	if b != BIOME_FIRE and in_arena(Vector3(x, y, z)):
		b = BIOME_FIRE  # the whole arena is fire cave, even where its edges poke out
	if b == BIOME_FIRE:
		# Obsidian is scarce, coal is everywhere. You need a thermal suit to work here.
		if _obsidian.get_noise_3d(x, y, z) > 0.6:
			return MAT_OBSIDIAN
		if _coal.get_noise_3d(x, y, z) > 0.4:
			return MAT_COAL
		return MAT_BASALT
	if b == BIOME_HARD:
		if _diamond.get_noise_3d(x, y, z) > 0.66:
			return MAT_DIAMOND
		# Cobalt only grows in hard rock: you need the diamond tip (or a Shredder) to reach it.
		if _cobalt.get_noise_3d(x, y, z) > 0.52:
			return MAT_COBALT
		if _iron.get_noise_3d(x, y, z) > 0.5:
			return MAT_IRON
		return MAT_HARD_ROCK
	# Rare small diamond pockets in normal rock, a little more common with depth: enough to
	# craft the diamond tip that opens up hard rock (where diamond is plentiful).
	var diamond_cut := NORMAL_DIAMOND_THRESHOLD - clampf(-y / 400.0, 0.0, 0.06)
	if _diamond.get_noise_3d(x, y, z) > diamond_cut:
		return MAT_DIAMOND
	if _iron.get_noise_3d(x, y, z) > 0.42:
		return MAT_IRON
	if _electrum.get_noise_3d(x, y, z) > 0.46:
		return MAT_ELECTRUM
	return MAT_ROCK
