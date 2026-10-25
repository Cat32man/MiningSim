extends Node3D
## Placement mode: a ghost follows the crosshair; LMB places (and stays in build mode so
## you can chain pieces), RMB cancels, R rotates. Also handles deconstruction (X).
##
## Structure pieces snap to the 2 m grid of the nearest structure within SNAP_SEARCH; the
## first piece of a new structure goes freely where you aim and starts its grid.

const Buildables = preload("res://scripts/build/buildables.gd")
const Structure = preload("res://scripts/build/structure.gd")
const Materials = preload("res://scripts/world/materials.gd")
const Sfx = preload("res://scripts/audio/sfx.gd")

const REACH := 8.0
const DECONSTRUCT_REACH := 5.0
const MIN_FLATNESS := 0.7  # surface normal.y for floor buildings
const WALL_MAX_SLOPE := 0.55  # |normal.y| for wall mounts
const POD_CLEARANCE := 3.5
const SNAP_SEARCH := 5.0
const PLAYER_LAYER := 8
const Inventory = preload("res://scripts/items/inventory.gd")
const Items = preload("res://scripts/items/items.gd")

## Set by main.
var player
var grid
var pod

var selected := ""
var _ghost: Node3D
var _yaw := 0.0
var _tilt := 0  # wall mounts: 15° steps
var _turns := 0  # snap pieces: 90° steps
var _valid := false
var _snap := {}  # frame + slot key for the piece under the crosshair
var _why := ""


func is_placing() -> bool:
	return selected != ""


func start(id: String) -> void:
	cancel()
	selected = id
	_ghost = Buildables.make(id)
	_ghost.ghost = true
	add_child(_ghost)
	_ghost.visible = false


func cancel() -> void:
	selected = ""
	if _ghost:
		_ghost.queue_free()
		_ghost = null


## R: floor buildings spin 45°; wall-mounted ones tilt in 15° steps (-45..45); structure
## pieces turn 90° (which way a ramp climbs, which side a door or ladder faces).
func rotate_step() -> void:
	match _mount():
		"wall":
			_tilt = _tilt + 1 if _tilt < 3 else -3
		"snap":
			_turns = (_turns + 1) % 4
		_:
			_yaw = wrapf(_yaw + PI / 4.0, 0.0, TAU)


func _mount() -> String:
	return Buildables.DEFS[selected]["mount"] if selected != "" else ""


func _process(_dt: float) -> void:
	if _ghost == null:
		return
	var mount := _mount()
	var hit := _ray(REACH, 1 if mount == "wall" else 3)
	if hit.is_empty():
		_ghost.visible = false
		_valid = false
		return
	var pos: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	_ghost.visible = true
	_why = ""
	match mount:
		"snap":
			_valid = _place_snap(hit)
		"surface":
			_ghost.global_transform = Transform3D(_basis_up(normal), pos)
			_valid = _check_surface(pos, hit["collider"])
		"wall":
			# -Z points into the rock, tilted by R.
			var into := -normal
			var basis := Basis.looking_at(into, Vector3.UP if absf(into.y) < 0.95 else Vector3.FORWARD)
			basis = basis.rotated(basis.x, deg_to_rad(15.0 * _tilt))
			_ghost.global_transform = Transform3D(basis, pos)
			_valid = _check(pos, normal, hit["collider"])
		_:
			_ghost.global_position = pos
			_ghost.rotation = Vector3(0, _yaw, 0)
			_valid = _check(pos, normal, hit["collider"])
	_ghost.set_ghost_valid(_valid and _affordable())


static func _basis_up(normal: Vector3) -> Basis:
	var y := normal.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


# --- Structure snapping ------------------------------------------------------------

## Puts the ghost in the grid slot under the crosshair. Returns whether it can go there.
func _place_snap(hit: Dictionary) -> bool:
	var slot: String = Structure.SLOTS[selected]
	var view: Vector3 = -player.camera.global_basis.z
	# Nudge the aim point past the surface: aiming at a wall's face puts a floor beyond it.
	var p: Vector3 = hit["position"] + view * (0.3 if slot == "cell" else 0.05)
	var anchor = _nearest_structure(hit["position"])
	var frame: Transform3D
	if anchor:
		frame = anchor.frame
	else:
		var yaw := snappedf(player.rotation.y, deg_to_rad(15.0))
		frame = Transform3D(Basis(Vector3.UP, yaw), hit["position"])
	var l := frame.affine_inverse() * p
	var cx := roundi(l.x / Structure.CELL)
	var cz := roundi(l.z / Structure.CELL)
	var local: Transform3D
	var key := ""
	if slot == "cell":
		var lv := roundi(l.y / Structure.CELL) if anchor else 0
		local = Transform3D(Basis(Vector3.UP, _turns * PI / 2.0), Vector3(cx, lv, cz) * Structure.CELL)
		key = "c%d,%d,%d" % [cx, lv, cz]
	else:
		var lv := floori(l.y / Structure.CELL + 0.25) if anchor else 0
		var dx := l.x - cx * Structure.CELL
		var dz := l.z - cz * Structure.CELL
		var at := Vector3(cx * Structure.CELL, lv * Structure.CELL, cz * Structure.CELL)
		var yaw := 0.0
		if absf(dx) > absf(dz):
			at.x += signf(dx) * Structure.CELL * 0.5
			yaw = PI / 2.0
		else:
			at.z += signf(dz) * Structure.CELL * 0.5
		var side := 1.0
		if slot == "ladder":
			# Ladders sit just in front of the edge, on your side, facing you.
			var n := Basis(Vector3.UP, yaw).z
			side = signf(n.dot(frame.affine_inverse() * player.global_position - at))
			side = side if side != 0.0 else 1.0
			at += n * side * 0.16 * Structure.K
			yaw += 0.0 if side > 0.0 else PI
		elif _turns % 2 == 1:
			yaw += PI  # doors and windows: R flips which face is out
		local = Transform3D(Basis(Vector3.UP, yaw), at)
		var ep := (at * 2.0).round()
		key = "%s%d,%d,%d" % ["l" if slot == "ladder" else "e", ep.x, ep.y, ep.z]
		if slot == "ladder":
			key += "s%d" % roundi(side)
	_ghost.global_transform = frame * local
	_snap = {"frame": frame, "key": key}

	for b in grid.buildings:
		if b.is_structure and b.slot_key == key and b.frame.is_equal_approx(frame):
			_why = "Already built there"
			return false
	var origin: Vector3 = _ghost.global_position
	var w = grid.world
	if w and w.material_at(Vector3i(origin.round())) == Materials.BEDROCK and w.density_at(Vector3i(origin.round())) > 0.0:
		_why = "Can't build into bedrock"
		return false
	if _hits_player():
		_why = "You're in the way"
		return false
	return true


func _nearest_structure(near: Vector3):
	var best = null
	var best_d := SNAP_SEARCH
	for b in grid.buildings:
		if not b.is_structure:
			continue
		var d: float = b.global_position.distance_to(near)
		if d < best_d:
			best_d = d
			best = b
	return best


## Would the ghost's collision overlap you?
func _hits_player() -> bool:
	var space := get_world_3d().direct_space_state
	for cs in _ghost._collision_shapes():
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cs[0]
		q.transform = _ghost.global_transform * cs[1]
		q.collision_mask = PLAYER_LAYER
		if not space.intersect_shape(q, 1).is_empty():
			return true
	return false


# --- Other mounts --------------------------------------------------------------------

func _check(pos: Vector3, normal: Vector3, on) -> bool:
	if _mount() == "wall":
		if absf(normal.y) > WALL_MAX_SLOPE:
			return false
	elif normal.y < MIN_FLATNESS:
		return false
	if on is Node and on in grid.buildings and not on.is_structure:
		return false  # machines stand on rock or on floors, not on other machines
	var r: float = Buildables.DEFS[selected]["radius"]
	if pod and Vector2(pos.x - pod.global_position.x, pos.z - pod.global_position.z).length() < POD_CLEARANCE + r:
		return false
	for st in get_tree().get_nodes_in_group("stations"):
		if Vector2(pos.x - st.global_position.x, pos.z - st.global_position.z).length() < 3.2 + r:
			return false  # keep the elevator clear
	var flat_player := Vector2(pos.x - player.global_position.x, pos.z - player.global_position.z)
	if flat_player.length() < r + 0.45 and absf(pos.y - player.global_position.y) < 2.0:
		return false  # don't build on top of yourself
	for b in grid.buildings:
		if b.is_structure:
			continue
		var br: float = Buildables.DEFS[b.build_id]["radius"]
		if b.global_position.distance_to(pos) < r + br:
			return false
	return true


func _check_surface(pos: Vector3, on) -> bool:
	if on is Node and on in grid.buildings and not on.is_structure:
		return false
	for b in grid.buildings:
		if not b.is_structure and b.global_position.distance_to(pos) < 0.5:
			return false
	return true


func _affordable() -> bool:
	return Inventory.can_afford(player.cost_sources(), Buildables.DEFS[selected]["cost"])


func try_place() -> void:
	if _ghost == null or not _ghost.visible:
		return
	if not _valid:
		match _mount():
			"snap":
				player._flash(_why if _why != "" else "Can't build here")
			"wall":
				player._flash("Needs a rock wall")
			"surface":
				player._flash("Can't build here")
			_:
				player._flash("Needs flat ground")
		return
	var def: Dictionary = Buildables.DEFS[selected]
	if not Inventory.pay(player.cost_sources(), def["cost"]):
		player._flash("Need %s" % Items.describe(def["cost"]))
		return
	var b := Buildables.make(selected)
	b.transform = _ghost.global_transform
	if b.is_structure:
		b.frame = _snap["frame"]
		b.slot_key = _snap["key"]
	grid.add(b)
	Sfx.play_3d("place", b.global_position, grid)
	if not b.is_structure:
		player._flash("Built %s" % def["name"])


## Removes the building under the crosshair. Its full cost goes back into your backpack;
## whatever doesn't fit, plus anything stored inside it, drops as a cache on the spot.
func deconstruct() -> void:
	var hit := _ray(DECONSTRUCT_REACH, 2)
	if hit.is_empty():
		return
	var b = hit["collider"]
	if b == null or not b in grid.buildings:
		return
	if b.has_method("pick_up"):
		b.pick_up(player)  # Shredders go back in the backpack, charge and all
		return
	var def: Dictionary = Buildables.DEFS[b.build_id]
	var overflow: Array = []
	for id in def["cost"]:
		var left: int = player.backpack.add(id, def["cost"][id])
		if left > 0:
			overflow.append({"id": id, "count": left})
	if not overflow.is_empty() and grid.drop_cache.is_valid():
		grid.drop_cache.call(b.global_position, overflow)
	Sfx.play_3d("place", b.global_position, grid, 0.0, 0.75)
	grid.remove(b)
	player._flash("Removed %s%s" % [def["name"], " — some dropped as a cache" if not overflow.is_empty() else ""])


func target_building():
	var hit := _ray(DECONSTRUCT_REACH, 2)
	if hit.is_empty():
		return null
	var b = hit["collider"]
	return b if b in grid.buildings else null


func _ray(reach: float, mask: int) -> Dictionary:
	var cam: Camera3D = player.camera
	var from := cam.global_position
	var to := from - cam.global_basis.z * reach
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)
