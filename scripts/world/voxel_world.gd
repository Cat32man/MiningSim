extends Node3D
## Streams, stores, edits and meshes the voxel terrain.
##
## All terrain changes go through apply_edit(op). Ops are small, replayable dictionaries,
## which is what co-op will eventually send over the network instead of voxel data.

const Generator = preload("res://scripts/world/terrain_generator.gd")
const Materials = preload("res://scripts/world/materials.gd")
const Mesher = preload("res://scripts/world/surface_nets.gd")
const RockShader = preload("res://scripts/world/rock.gdshader")
const Crystals = preload("res://scripts/world/crystals.gd")

## Solid samples turned to air by an edit (drives local threat).
signal carved(center: Vector3, removed: int)

const S := 16
const S3 := S * S * S
const P := S + 2
const VIEW_RADIUS_H := 4
const VIEW_RADIUS_V := 3
const MAX_MESH_APPLY_PER_FRAME := 8


class Chunk extends RefCounted:
	var cpos: Vector3i
	var density := PackedFloat32Array()
	var mats := PackedByteArray()
	var generated := false
	## Edited since generation; only these go into save files.
	var modified := false
	var meshed := false
	var mesh_version := 0
	var applied_version := 0
	var mesh_instance: MeshInstance3D
	var shape: CollisionShape3D
	var crystal_nodes := {}  # material -> MultiMeshInstance3D


var world_seed := 1337
## Node whose position drives streaming (the player).
var focus: Node3D

var _chunks := {}  # Vector3i -> Chunk
## Densities from a save file, applied when each chunk is (re)generated. Materials never
## change when digging, so they are regenerated from the seed instead of saved.
var _saved_density := {}  # Vector3i -> PackedFloat32Array
var _main_gen  # main-thread generator for queries
var _results: Array = []
var _results_mutex := Mutex.new()
var _material: ShaderMaterial
var _crystal_meshes := {}  # material -> Mesh
var _last_center := Vector3i(1 << 20, 0, 0)
var _tasks: Array[int] = []
var _shutting_down := false


func _ready() -> void:
	_material = _make_rock_material()
	for m in Crystals.CHANCE:
		_crystal_meshes[m] = Crystals.make_mesh(m)
		_crystal_meshes[m].surface_set_material(0, Crystals.make_material(m))


func _exit_tree() -> void:
	# Tasks reference this node; let queued ones bail out and wait for the rest.
	_shutting_down = true
	for id in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()


func _process(_delta: float) -> void:
	_tasks = _tasks.filter(func(id: int) -> bool: return not WorkerThreadPool.is_task_completed(id))
	if focus:
		var center := world_to_chunk(focus.global_position)
		if center != _last_center:
			_last_center = center
			_request_chunks_around(center)
	_apply_results()


# --- Public API -------------------------------------------------------------

static func world_to_chunk(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / S), floori(p.y / S), floori(p.z / S))


## True once every chunk within one chunk of `p` has been generated and meshed.
func is_ready_around(p: Vector3) -> bool:
	var c := world_to_chunk(p)
	for dz in range(-1, 2):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var ch: Chunk = _chunks.get(c + Vector3i(dx, dy, dz))
				if ch == null or not ch.meshed:
					return false
	return true


## Share of the 3×3×3 chunks around `p` that are meshed (for the loading bar).
func ready_fraction_around(p: Vector3) -> float:
	var c := world_to_chunk(p)
	var n := 0
	for dz in range(-1, 2):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var ch: Chunk = _chunks.get(c + Vector3i(dx, dy, dz))
				if ch != null and ch.meshed:
					n += 1
	return n / 27.0


func chunk_count() -> int:
	return _chunks.size()


## Debug: nearest solid sample of `mat` with open air on its +x/-x/+z/-z side.
## Returns [sample_position, direction_to_air] or [] if none within `radius`.
func find_exposed(mat: int, near: Vector3, radius: int) -> Array:
	var best: Array = []
	var best_d := INF
	var c := Vector3i(near.round())
	var sides: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for z in range(c.z - radius, c.z + radius + 1):
		for y in range(c.y - 2, c.y + 4):
			for x in range(c.x - radius, c.x + radius + 1):
				var p := Vector3i(x, y, z)
				var dist := Vector3(p).distance_squared_to(near)
				if dist >= best_d or density_at(p) <= 0.0:
					continue
				var ch: Chunk = _chunks.get(world_to_chunk(Vector3(p)))
				if ch == null or ch.mats[posmod(x, S) + posmod(y, S) * S + posmod(z, S) * S * S] != mat:
					continue
				for s in sides:
					# Needs a few metres of air in front so the camera can stand there.
					if density_at(p + s) <= 0.0 and density_at(p + s * 3) <= 0.0:
						best = [Vector3(p), Vector3(s)]
						best_d = dist
						break
	return best


## Debug: solid sample counts per material over all generated chunks.
func material_histogram() -> Dictionary:
	var h := {}
	for ch: Chunk in _chunks.values():
		if not ch.generated:
			continue
		for i in S3:
			if ch.density[i] > 0.0:
				var m := ch.mats[i]
				h[m] = h.get(m, 0) + 1
	return h


## Applies one terrain edit and returns {material_id: samples_mined}.
## op = {"type": "carve_sphere", "center": Vector3, "radius": float, "strength": float,
##       "diamond": bool (optional, lets the edit cut hard rock)}
func apply_edit(op: Dictionary) -> Dictionary:
	var mined := {}
	if op.get("type", "") == "clear_cells":
		return _clear_cells(op)
	if op.get("type", "") != "carve_sphere":
		push_warning("Unknown terrain op: %s" % op)
		return mined
	var center: Vector3 = op["center"]
	var radius: float = op["radius"]
	var strength: float = op["strength"]
	var diamond_tipped: bool = op.get("diamond", false)
	var removed := 0

	var lo := Vector3i(floori(center.x - radius), floori(center.y - radius), floori(center.z - radius))
	var hi := Vector3i(ceili(center.x + radius), ceili(center.y + radius), ceili(center.z + radius))
	var changed := false
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var dist := center.distance_to(Vector3(x, y, z))
				if dist > radius:
					continue
				var cpos := Vector3i(floori(float(x) / S), floori(float(y) / S), floori(float(z) / S))
				var ch: Chunk = _chunks.get(cpos)
				if ch == null or not ch.generated:
					continue
				var idx := posmod(x, S) + posmod(y, S) * S + posmod(z, S) * S * S
				var mat := ch.mats[idx]
				var hardness: float = Materials.HARDNESS[mat]
				if hardness <= 0.0:
					continue  # bedrock
				if Materials.NEEDS_DIAMOND[mat] and not diamond_tipped:
					continue  # hard rock
				var old := ch.density[idx]
				if old <= -1.0:
					continue
				var new_d := maxf(old - strength / hardness * (1.0 - dist / radius), -1.0)
				ch.density[idx] = new_d
				ch.modified = true
				changed = true
				if old > 0.0 and new_d <= 0.0:
					removed += 1
					if Materials.COLLECTIBLE[mat]:
						mined[mat] = mined.get(mat, 0) + 1

	if removed > 0:
		carved.emit(center, removed)
	if changed:
		# A sample is padding for the chunks holding its -1/+1 neighbours too.
		var cl := world_to_chunk(Vector3(lo) - Vector3.ONE)
		var ch_hi := world_to_chunk(Vector3(hi) + Vector3.ONE)
		for cz in range(cl.z, ch_hi.z + 1):
			for cy in range(cl.y, ch_hi.y + 1):
				for cx in range(cl.x, ch_hi.x + 1):
					var dirty: Chunk = _chunks.get(Vector3i(cx, cy, cz))
					if dirty and dirty.generated:
						_schedule_mesh(dirty, true)
	return mined


## Shredder op: {type: "clear_cells", cells: [Vector3i], mat: int}. Empties exactly those
## samples (only where they're still solid `mat`), leaving vein-shaped hollows.
func _clear_cells(op: Dictionary) -> Dictionary:
	var mined := {}
	var want: int = op.get("mat", -1)
	var removed := 0
	var dirty := {}
	var sum := Vector3.ZERO
	for c in op["cells"]:
		var cell: Vector3i = c
		var ch: Chunk = _chunks.get(Vector3i(floori(float(cell.x) / S), floori(float(cell.y) / S), floori(float(cell.z) / S)))
		if ch == null or not ch.generated:
			continue
		var idx := posmod(cell.x, S) + posmod(cell.y, S) * S + posmod(cell.z, S) * S * S
		var mat := ch.mats[idx]
		if (want >= 0 and mat != want) or ch.density[idx] <= 0.0 or Materials.HARDNESS[mat] <= 0.0:
			continue
		ch.density[idx] = -1.0
		ch.modified = true
		removed += 1
		sum += Vector3(cell)
		if Materials.COLLECTIBLE[mat]:
			mined[mat] = mined.get(mat, 0) + 1
		# A sample is padding for the chunks holding its -1/+1 neighbours too.
		for dz in range(-1, 2):
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					dirty[world_to_chunk(Vector3(cell + Vector3i(dx, dy, dz)))] = true
	if removed > 0:
		carved.emit(sum / removed, removed)
		for k in dirty:
			var dch: Chunk = _chunks.get(k)
			if dch and dch.generated:
				_schedule_mesh(dch, true)
	return mined


## Edited chunk densities for saving: {Vector3i: PackedFloat32Array}. Includes loaded-from-save
## chunks that haven't streamed in this session.
func export_modified() -> Dictionary:
	var out := _saved_density.duplicate()
	for ch: Chunk in _chunks.values():
		if ch.generated and ch.modified:
			out[ch.cpos] = ch.density
	return out


## Call before the world starts streaming.
func import_modified(data: Dictionary) -> void:
	_saved_density = data.duplicate()


## Ore scanner: groups exposed-or-buried ore within `radius` into ~4 m clusters.
## Returns [{"mat": int, "pos": Vector3, "count": int}], strongest clusters first.
func scan_ores(center: Vector3, radius: float) -> Array:
	var clusters := {}  # Vector3i cell -> {mat -> [sum_pos, count]}
	var r2 := radius * radius
	var c0 := world_to_chunk(center - Vector3.ONE * radius)
	var c1 := world_to_chunk(center + Vector3.ONE * radius)
	for cz in range(c0.z, c1.z + 1):
		for cy in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				var ch: Chunk = _chunks.get(Vector3i(cx, cy, cz))
				if ch == null or not ch.generated:
					continue
				var origin := ch.cpos * S
				# Every other sample is plenty for a scanner and 8x cheaper.
				for z in range(0, S, 2):
					for y in range(0, S, 2):
						for x in range(0, S, 2):
							var i := x + y * S + z * S * S
							var m := ch.mats[i]
							if not Materials.COLLECTIBLE[m] or ch.density[i] <= 0.0:
								continue
							var p := Vector3(origin.x + x, origin.y + y, origin.z + z)
							if p.distance_squared_to(center) > r2:
								continue
							var cell := Vector3i((p / 4.0).floor())
							var per: Dictionary = clusters.get_or_add(cell, {})
							var acc: Array = per.get_or_add(m, [Vector3.ZERO, 0])
							acc[0] += p
							acc[1] += 1
	var out: Array = []
	for cell in clusters:
		for m in clusters[cell]:
			var acc: Array = clusters[cell][m]
			out.append({"mat": m, "pos": acc[0] / acc[1], "count": acc[1] * 8})
	out.sort_custom(func(a, b) -> bool: return a["count"] > b["count"])
	return out


## Biome name at a position, for the HUD.
func zone_name(p: Vector3) -> String:
	if _main_gen == null:
		_main_gen = Generator.new(world_seed)
	return ["Normal rock", "Hard rock", "Fire caves"][biome_at(p)]


func biome_at(p: Vector3) -> int:
	if _main_gen == null:
		_main_gen = Generator.new(world_seed)
	if _main_gen.in_arena(p):
		return Generator.BIOME_FIRE
	return _main_gen.biome(p.x, p.y, p.z)


func material_at(p: Vector3i) -> int:
	var ch: Chunk = _chunks.get(Vector3i(floori(float(p.x) / S), floori(float(p.y) / S), floori(float(p.z) / S)))
	if ch == null or not ch.generated:
		return Materials.ROCK
	return ch.mats[posmod(p.x, S) + posmod(p.y, S) * S + posmod(p.z, S) * S * S]


## Trilinearly interpolated density at any world point (> 0 means inside rock).
func density_interp(p: Vector3) -> float:
	var b := Vector3i(p.floor())
	var f := p - Vector3(b)
	var c00 := lerpf(density_at(b), density_at(b + Vector3i(1, 0, 0)), f.x)
	var c10 := lerpf(density_at(b + Vector3i(0, 1, 0)), density_at(b + Vector3i(1, 1, 0)), f.x)
	var c01 := lerpf(density_at(b + Vector3i(0, 0, 1)), density_at(b + Vector3i(1, 0, 1)), f.x)
	var c11 := lerpf(density_at(b + Vector3i(0, 1, 1)), density_at(b + Vector3i(1, 1, 1)), f.x)
	return lerpf(lerpf(c00, c10, f.y), lerpf(c01, c11, f.y), f.z)


## Density at a world sample (for tools and tests). Ungenerated space reads as solid.
## Density of a cell if its chunk is loaded (dug tunnels included), else NAN.
func known_density(p: Vector3i) -> float:
	var ch: Chunk = _chunks.get(Vector3i(floori(float(p.x) / S), floori(float(p.y) / S), floori(float(p.z) / S)))
	if ch == null or not ch.generated:
		return NAN
	return ch.density[posmod(p.x, S) + posmod(p.y, S) * S + posmod(p.z, S) * S * S]


func density_at(p: Vector3i) -> float:
	var ch: Chunk = _chunks.get(Vector3i(floori(float(p.x) / S), floori(float(p.y) / S), floori(float(p.z) / S)))
	if ch == null or not ch.generated:
		return 1.0
	return ch.density[posmod(p.x, S) + posmod(p.y, S) * S + posmod(p.z, S) * S * S]


# --- Streaming --------------------------------------------------------------

func _request_chunks_around(center: Vector3i) -> void:
	var wanted: Array[Vector3i] = []
	for dz in range(-VIEW_RADIUS_H, VIEW_RADIUS_H + 1):
		for dy in range(-VIEW_RADIUS_V, VIEW_RADIUS_V + 1):
			for dx in range(-VIEW_RADIUS_H, VIEW_RADIUS_H + 1):
				var c := center + Vector3i(dx, dy, dz)
				# Everything this far above the ceiling is solid bedrock with no surface.
				if c.y * S > Generator.CEILING_Y + S:
					continue
				if not _chunks.has(c):
					wanted.append(c)
	wanted.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return (a - center).length_squared() < (b - center).length_squared())
	for c in wanted:
		var ch := Chunk.new()
		ch.cpos = c
		_chunks[c] = ch
		_tasks.append(WorkerThreadPool.add_task(_task_generate.bind(c)))


func _schedule_mesh(ch: Chunk, high_priority: bool) -> void:
	ch.mesh_version += 1
	# Packed arrays are copy-on-write, so the worker gets a stable snapshot of each neighbour.
	var dens_list := []
	var mats_list := []
	for dz in range(-1, 2):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: Chunk = _chunks.get(ch.cpos + Vector3i(dx, dy, dz))
				if n and n.generated:
					dens_list.append(n.density)
					mats_list.append(n.mats)
				else:
					dens_list.append(null)
					mats_list.append(null)
	_tasks.append(WorkerThreadPool.add_task(
		_task_mesh.bind(ch.cpos, ch.mesh_version, dens_list, mats_list, high_priority), high_priority))


func _push_result(r: Dictionary) -> void:
	_results_mutex.lock()
	_results.append(r)
	_results_mutex.unlock()


func _apply_results() -> void:
	_results_mutex.lock()
	var batch := _results
	_results = []
	_results_mutex.unlock()

	var applied_meshes := 0
	var leftover: Array = []
	for r in batch:
		var ch: Chunk = _chunks.get(r["cpos"])
		if ch == null:
			continue
		if r["kind"] == "gen":
			ch.density = r["density"]
			if _saved_density.has(ch.cpos):
				ch.density = _saved_density[ch.cpos]
				_saved_density.erase(ch.cpos)
				ch.modified = true
				# Neighbours that meshed before this chunk loaded used freshly generated rock for
				# its edge samples; with saved digging that's wrong (stale walls, floating crystals).
				for dz in range(-1, 2):
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							var n: Chunk = _chunks.get(ch.cpos + Vector3i(dx, dy, dz))
							if n and n != ch and n.generated and n.mesh_version > 0:
								_schedule_mesh(n, false)
			ch.mats = r["mats"]
			ch.generated = true
			_schedule_mesh(ch, false)
		else:
			if applied_meshes >= MAX_MESH_APPLY_PER_FRAME and not r["priority"]:
				leftover.append(r)
				continue
			if r["version"] <= ch.applied_version:
				continue
			ch.applied_version = r["version"]
			_apply_mesh(ch, r["mesh"])
			applied_meshes += 1

	if not leftover.is_empty():
		_results_mutex.lock()
		_results = leftover + _results
		_results_mutex.unlock()


func _apply_mesh(ch: Chunk, data: Dictionary) -> void:
	ch.meshed = true
	if data.is_empty():
		if ch.mesh_instance:
			ch.mesh_instance.mesh = null
			ch.shape.disabled = true
			_apply_crystals(ch, {})
		return
	if ch.mesh_instance == null:
		ch.mesh_instance = MeshInstance3D.new()
		ch.mesh_instance.position = Vector3(ch.cpos * S)
		add_child(ch.mesh_instance)
		var body := StaticBody3D.new()
		body.set_meta("terrain", true)
		ch.mesh_instance.add_child(body)
		ch.shape = CollisionShape3D.new()
		body.add_child(ch.shape)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data["arrays"])
	mesh.surface_set_material(0, _material)
	ch.mesh_instance.mesh = mesh
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(data["faces"])
	ch.shape.shape = shape
	ch.shape.disabled = false
	_apply_crystals(ch, data.get("crystals", {}))


func _apply_crystals(ch: Chunk, crystals: Dictionary) -> void:
	for m in _crystal_meshes:
		var xforms: Array = crystals.get(m, [])
		var node: MultiMeshInstance3D = ch.crystal_nodes.get(m)
		if xforms.is_empty():
			if node:
				node.visible = false
			continue
		if node == null:
			node = MultiMeshInstance3D.new()
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ch.mesh_instance.add_child(node)
			ch.crystal_nodes[m] = node
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _crystal_meshes[m]
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		node.multimesh = mm
		node.visible = true


# --- Worker tasks (no scene tree access) -----------------------------------

func _task_generate(cpos: Vector3i) -> void:
	if _shutting_down:
		return
	var gen = Generator.new(world_seed)
	var origin := cpos * S
	var dens := PackedFloat32Array()
	dens.resize(S3)
	var mats := PackedByteArray()
	mats.resize(S3)
	var i := 0
	for z in S:
		for y in S:
			for x in S:
				var wx := float(origin.x + x)
				var wy := float(origin.y + y)
				var wz := float(origin.z + z)
				var dv: float = gen.density(wx, wy, wz)
				dens[i] = dv
				mats[i] = gen.material(wx, wy, wz) if dv > 0.0 else Generator.MAT_ROCK
				i += 1
	_push_result({"kind": "gen", "cpos": cpos, "density": dens, "mats": mats})


func _task_mesh(cpos: Vector3i, version: int, dens_list: Array, mats_list: Array,
		priority: bool) -> void:
	if _shutting_down:
		return
	var mesh: Dictionary = _mesh_from(cpos, dens_list, mats_list)
	_push_result({"kind": "mesh", "cpos": cpos, "version": version, "mesh": mesh,
		"priority": priority})


## Debug: re-meshes every settled chunk from current data and counts the ones whose
## on-screen mesh differs (vertex count) — i.e. stale geometry. Slow; tests only.
func stale_mesh_count() -> int:
	var stale := 0
	for ch: Chunk in _chunks.values():
		if not ch.meshed or ch.applied_version != ch.mesh_version:
			continue
		var dens_list := []
		var mats_list := []
		for dz in range(-1, 2):
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var n: Chunk = _chunks.get(ch.cpos + Vector3i(dx, dy, dz))
					dens_list.append(n.density if n and n.generated else null)
					mats_list.append(n.mats if n and n.generated else null)
		var fresh: Dictionary = _mesh_from(ch.cpos, dens_list, mats_list)
		var fresh_n: int = 0 if fresh.is_empty() else fresh["arrays"][Mesh.ARRAY_VERTEX].size()
		var shown_n := 0
		if ch.mesh_instance and ch.mesh_instance.mesh:
			shown_n = ch.mesh_instance.mesh.surface_get_array_len(0)
		if fresh_n != shown_n:
			stale += 1
	return stale


func _mesh_from(cpos: Vector3i, dens_list: Array, mats_list: Array) -> Dictionary:
	var gen = null
	var origin := cpos * S
	var pd := PackedFloat32Array()
	pd.resize(P * P * P)
	var pm := PackedByteArray()
	pm.resize(P * P * P)
	var n := 0
	for pz in P:
		var lz := pz - 1
		var oz := -1 if lz < 0 else (1 if lz >= S else 0)
		for py in P:
			var ly := py - 1
			var oy := -1 if ly < 0 else (1 if ly >= S else 0)
			for px in P:
				var lx := px - 1
				var ox := -1 if lx < 0 else (1 if lx >= S else 0)
				var ni := (ox + 1) + (oy + 1) * 3 + (oz + 1) * 9
				var nd = dens_list[ni]
				if nd != null:
					var li := (lx - ox * S) + (ly - oy * S) * S + (lz - oz * S) * S * S
					pd[n] = nd[li]
					pm[n] = mats_list[ni][li]
				else:
					# Neighbour not generated yet: it is unedited, so the generator is exact.
					if gen == null:
						gen = Generator.new(world_seed)
					var wx := float(origin.x + lx)
					var wy := float(origin.y + ly)
					var wz := float(origin.z + lz)
					var dv: float = gen.density(wx, wy, wz)
					pd[n] = dv
					pm[n] = gen.material(wx, wy, wz) if dv > 0.0 else Generator.MAT_ROCK
				n += 1
	return Mesher.build(pd, pm, origin)


# --- Look -------------------------------------------------------------------

func _make_rock_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = RockShader

	var albedo_noise := FastNoiseLite.new()
	albedo_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	albedo_noise.frequency = 0.012
	albedo_noise.fractal_octaves = 6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.55, 0.55, 0.55))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	var albedo := NoiseTexture2D.new()
	albedo.width = 512
	albedo.height = 512
	albedo.seamless = true
	albedo.noise = albedo_noise
	albedo.color_ramp = ramp
	mat.set_shader_parameter("albedo_noise", albedo)

	var bump_noise := FastNoiseLite.new()
	bump_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	bump_noise.frequency = 0.02
	bump_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	bump_noise.fractal_octaves = 4
	var bump := NoiseTexture2D.new()
	bump.width = 512
	bump.height = 512
	bump.seamless = true
	bump.as_normal_map = true
	bump.bump_strength = 10.0
	bump.noise = bump_noise
	mat.set_shader_parameter("bump_noise", bump)

	# Fine speckle; only the brightest specks become glints.
	var glint_noise := FastNoiseLite.new()
	glint_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	glint_noise.frequency = 0.15
	glint_noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	var glint := NoiseTexture2D.new()
	glint.width = 256
	glint.height = 256
	glint.seamless = true
	glint.normalize = true
	glint.noise = glint_noise
	mat.set_shader_parameter("glint_noise", glint)
	mat.set_shader_parameter("glint_scale", 0.6)
	return mat
