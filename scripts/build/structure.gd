extends "res://scripts/build/building.gd"
## Building pieces (M3.5): foundations, floors, walls, windows, doors, ramps, ladders and
## catwalks. One script, shaped by build_id.
##
## Pieces snap together on a 3 m grid. Every piece of a structure shares one snap frame
## (origin + yaw, saved with it); slot_key says which cell / edge of that grid it fills.
## Local space: y = 0 is the floor level, walls run along x with their thickness on z.
## Bugs chew through pieces in their way; at 0 HP a piece is destroyed (no refund).

const CELL := 3.0
## Pieces are laid out below at a 2 m size and scaled up by this (walls were too short).
const K := CELL / 2.0
## Saved with each piece; pieces from before the resize are refunded on load.
const SIZE_VERSION := 2
## Which kind of grid slot each piece fills.
const SLOTS := {
	"foundation": "cell", "floor": "cell", "catwalk": "cell", "ramp": "cell",
	"wall": "edge", "half_wall": "edge", "window": "edge", "door": "edge", "ladder": "ladder",
}
const DOOR_OPEN_RANGE := 3.4
const DOOR_SPEED := 4.0

var frame := Transform3D.IDENTITY
var slot_key := ""

var _boxes: Array = []  # [size, Transform3D, material, collides]
var _door_panels: Array = []
var _door_cols: Array = []
var _door_t := 0.0
var _door_open := false


func _init() -> void:
	is_power_node = false
	is_structure = true


func _ready() -> void:
	_boxes = _layout()
	if build_id == "ladder":
		add_to_group("ladders")
	super()
	if build_id == "door" and not ghost:
		_make_door()


func _build_visuals() -> void:
	for b in _boxes:
		if b[2] == null:
			continue  # collision only
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b[0]
		mi.mesh = bm
		mi.material_override = b[2]
		mi.transform = b[1]
		add_child(mi)


func _collision_shapes() -> Array:
	var out: Array = []
	for b in _boxes:
		if b[3]:
			var s := BoxShape3D.new()
			s.size = b[0]
			out.append([s, b[1]])
	return out


static func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


func _layout() -> Array:
	var plate := mat(Color(0.32, 0.33, 0.35), 0.7, 0.45)
	var dark := mat(Color(0.14, 0.14, 0.15), 0.8, 0.4)
	var paint := mat(Color(0.8, 0.52, 0.12), 0.35, 0.55)
	var deck := mat(Color(0.38, 0.38, 0.4), 0.85, 0.32)
	var concrete := mat(Color(0.43, 0.42, 0.4), 0.0, 0.9)
	var out: Array = []
	match build_id:
		"foundation":
			out.append([Vector3(2, 1, 2), _at(0, -0.5, 0), concrete, true])
			for z in [-0.97, 0.97]:
				out.append([Vector3(2.0, 0.1, 0.08), _at(0, -0.05, z), dark, false])
			for x in [-0.97, 0.97]:
				out.append([Vector3(0.08, 0.1, 2.0), _at(x, -0.05, 0), dark, false])
		"floor":
			out.append([Vector3(2, 0.2, 2), _at(0, -0.1, 0), deck, true])
			out.append([Vector3(2.0, 0.21, 0.03), _at(0, -0.1, 0), dark, false])  # seam
		"catwalk":
			out.append([Vector3(2, 0.06, 2), _at(0, -0.03, 0), dark, true])
			for i in 9:  # grating bars
				out.append([Vector3(2.0, 0.03, 0.06), _at(0, 0.005, -0.88 + i * 0.22), deck, false])
			for x in [-0.97, 0.97]:
				out.append([Vector3(0.07, 0.07, 2.0), _at(x, 1.0, 0), paint, false])
				out.append([Vector3(0.05, 0.05, 2.0), _at(x, 0.5, 0), dark, false])
				for z in [-0.95, 0.0, 0.95]:
					out.append([Vector3(0.06, 1.0, 0.06), _at(x, 0.5, z), dark, false])
		"ramp":
			var tilt := Basis(Vector3.RIGHT, -PI / 4.0)
			var n := tilt.y
			out.append([Vector3(2, 0.2, 2.83), Transform3D(tilt, Vector3(0, 1, 0) - n * 0.1), deck, true])
			for i in 7:  # treads
				var along := -1.2 + i * 0.4
				out.append([Vector3(1.9, 0.05, 0.06), Transform3D(tilt, Vector3(0, 1, 0) + tilt.z * along + n * 0.02),
					dark, false])
		"wall":
			out.append([Vector3(2, 2, 0.2), _at(0, 1, 0), plate, true])
			_trim(out, 2.0, dark, paint)
		"half_wall":
			out.append([Vector3(2, 1, 0.2), _at(0, 0.5, 0), plate, true])
			_trim(out, 1.0, dark, paint)
		"window":
			out.append([Vector3(2, 0.9, 0.2), _at(0, 0.45, 0), plate, true])
			out.append([Vector3(2, 0.4, 0.2), _at(0, 1.8, 0), plate, true])
			for x in [-0.75, 0.75]:
				out.append([Vector3(0.5, 0.7, 0.2), _at(x, 1.25, 0), plate, true])
			out.append([Vector3(1.04, 0.05, 0.24), _at(0, 0.92, 0), paint, false])  # sill
			_trim(out, 2.0, dark, paint)
		"door":
			for x in [-0.8, 0.8]:
				out.append([Vector3(0.4, 2, 0.2), _at(x, 1, 0), plate, true])
			out.append([Vector3(1.2, 0.3, 0.2), _at(0, 1.85, 0), plate, true])
			for x in [-0.62, 0.62]:
				out.append([Vector3(0.04, 1.7, 0.24), _at(x, 0.85, 0), paint, false])  # frame stripes
		"ladder":
			for x in [-0.25, 0.25]:
				out.append([Vector3(0.05, 2.0, 0.05), _at(x, 1.0, 0), paint, false])
			for i in 7:
				out.append([Vector3(0.5, 0.035, 0.035), _at(0, 0.15 + i * 0.29, 0), dark, false])
			out.append([Vector3(0.6, 2.0, 0.08), _at(0, 1.0, 0), null, true])  # climbable surface
	if build_id == "catwalk":
		# Rails block falls but are see-through: collision-only planes.
		for x in [-0.97, 0.97]:
			out.append([Vector3(0.05, 1.0, 2.0), _at(x, 0.5, 0), null, true])
	# Walls meeting at a corner overlap there, and their tops and trims would sit in the same
	# plane and flicker. Edges running along z sit 4 mm higher so one always wins.
	var lift := 0.004 if SLOTS.get(build_id, "") == "edge" and _runs_along_z() else 0.0
	for b in out:
		b[0] *= K
		b[1].origin *= K
		b[1].origin.y += lift
	return out


## Edge keys are "e<x>,<y>,<z>" in half cells: an odd x means the edge sits between two
## cells along x, so the wall runs along z.
func _runs_along_z() -> bool:
	var parts := slot_key.trim_prefix("e").split(",")
	return parts.size() == 3 and posmod(int(parts[0]), 2) == 1


## Dark base strip and an orange band along the top of wall pieces.
static func _trim(out: Array, h: float, dark: Material, paint: Material) -> void:
	out.append([Vector3(2.0, 0.1, 0.22), _at(0, 0.05, 0), dark, false])
	out.append([Vector3(2.0, 0.06, 0.22), _at(0, h - 0.03, 0), paint, false])
	out.append([Vector3(0.03, h, 0.21), _at(0, h * 0.5, 0), dark, false])  # panel seam


# --- Door -----------------------------------------------------------------------------

## Two pocket panels that slide apart into the wall when you come near. Closed, they stop bugs.
func _make_door() -> void:
	var panel_mat := mat(Color(0.5, 0.36, 0.14), 0.5, 0.5)
	for side in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.6 * K, 1.7 * K, 0.06 * K)
		mi.mesh = bm
		mi.material_override = panel_mat
		mi.position = Vector3(side * 0.3, 0.85, 0) * K
		mi.set_meta("side", side)
		add_child(mi)
		_door_panels.append(mi)
		var col := CollisionShape3D.new()
		var s := BoxShape3D.new()
		s.size = Vector3(0.6, 1.7, 0.1) * K
		col.shape = s
		col.position = mi.position
		add_child(col)
		_door_cols.append(col)


func _physics_process(dt: float) -> void:
	if _door_panels.is_empty():
		return
	var player = get_tree().get_first_node_in_group("player")
	var want: bool = player != null and player.health > 0.0 \
		and player.global_position.distance_to(global_position + Vector3.UP * K) < DOOR_OPEN_RANGE
	if want != _door_open:
		_door_open = want
		SfxLib.play_3d("overheat", global_position + Vector3.UP, get_parent(), -14.0, 1.8)
	_door_t = move_toward(_door_t, 1.0 if _door_open else 0.0, dt * DOOR_SPEED)
	for i in _door_panels.size():
		var side: float = _door_panels[i].get_meta("side")
		var x := side * (0.3 + 0.58 * _door_t) * K
		_door_panels[i].position.x = x
		_door_cols[i].position.x = x
		_door_cols[i].disabled = _door_t > 0.3


# --- Damage ---------------------------------------------------------------------------

## Structure pieces don't break down: at 0 HP they're destroyed.
func take_damage(amount: float, at: Vector3) -> void:
	if ghost or hp <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	HitFx.ichor(get_parent(), at, global_position + (at - global_position) * 2.0, Color(0.6, 0.6, 0.62))
	if hp <= 0.0:
		_destroy()


func _destroy() -> void:
	SfxLib.play_3d("break", global_position + Vector3.UP, get_parent(), 2.0, 0.8)
	var debris := CPUParticles3D.new()
	debris.one_shot = true
	debris.explosiveness = 1.0
	debris.amount = 18
	debris.lifetime = 1.4
	debris.spread = 180.0
	debris.initial_velocity_min = 1.5
	debris.initial_velocity_max = 4.0
	debris.scale_amount_min = 0.06
	debris.scale_amount_max = 0.16
	var chunk := BoxMesh.new()
	chunk.size = Vector3.ONE
	chunk.material = mat(Color(0.32, 0.33, 0.35), 0.7, 0.45)
	debris.mesh = chunk
	get_parent().add_child(debris)
	debris.global_position = global_position + global_basis.y
	debris.emitting = true
	debris.finished.connect(debris.queue_free)
	grid.remove(self)


func is_running() -> bool:
	return false


func get_state() -> Dictionary:
	var s := super()
	s["frame"] = frame
	s["slot"] = slot_key
	s["v"] = SIZE_VERSION
	return s


func apply_state(s: Dictionary) -> void:
	super(s)
	frame = s.get("frame", Transform3D.IDENTITY)
	slot_key = s.get("slot", "")
