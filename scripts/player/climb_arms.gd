extends Node3D
## First-person climbing arms. Shoulders ride the camera; hands plant on the rock and
## leapfrog upward as you climb, with an analytic two-bone IK putting the elbow in place.
## The geometry is placeholder capsules — the solver's shoulder/elbow/hand points are what
## a skinned arm rig would be driven from later.

const Sfx = preload("res://scripts/audio/sfx.gd")

const UPPER := 0.36  # shoulder -> elbow
const FORE := 0.34  # elbow -> wrist
const SHOULDER := Vector3(0.26, -0.36, 0.08)  # camera space; x is mirrored per side
const GRAB_SIDE := 0.2  # hands grab this far either side of centre
const GRAB_UP := 0.3  # a fresh grab reaches this far above the eye
const GRAB_PROBE := 1.15  # how far ahead of the body a grab looks for rock
const REGRAB_DROP := 0.2  # re-grab once the hold has slid this far below the eye
const REACH_TIME := 0.16
const REACH_LIFT := 0.12  # the hand arcs this far off the wall mid-reach
const ENGAGE_SPEED := 7.0

var player: CharacterBody3D

var _engage := 0.0
var _hands: Array = []  # per side: {target, normal, from, t, wall}
var _upper: Array[MeshInstance3D] = []
var _fore: Array[MeshInstance3D] = []
var _palm: Array[MeshInstance3D] = []


func _ready() -> void:
	top_level = true
	visible = false
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.84, 0.84, 0.82)
	mat.roughness = 0.55
	for i in 2:
		_upper.append(_capsule(0.042, UPPER + 0.07, mat))
		_fore.append(_capsule(0.034, FORE + 0.05, mat))
		var palm := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.045
		s.height = 0.09
		palm.mesh = s
		palm.material_override = mat
		palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(palm)
		_palm.append(palm)
		_hands.append({"target": Vector3.ZERO, "normal": Vector3.BACK, "from": Vector3.ZERO,
			"t": 1.0, "wall": false})


func _capsule(radius: float, height: float, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	c.radial_segments = 12
	c.rings = 4
	m.mesh = c
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


## True once the arms are up enough that the held tool should be put away.
func is_engaged() -> bool:
	return _engage > 0.3


func update(delta: float, climbing: bool) -> void:
	var was := _engage
	_engage = move_toward(_engage, 1.0 if climbing else 0.0, delta * ENGAGE_SPEED)
	visible = _engage > 0.0
	if not visible:
		return
	var cam: Camera3D = player.camera
	var cb := cam.global_basis
	var eye := cam.global_position

	if was == 0.0:
		# Arms come up from below the view; the left hand leads, the right follows.
		for i in 2:
			var h: Dictionary = _hands[i]
			h.from = _low_point(i, cam)
			h.t = 0.0 if i == 0 else -0.45
			_pick_hold(i, GRAB_UP if i == 0 else GRAB_UP * 0.4)

	for i in 2:
		var h: Dictionary = _hands[i]
		if h.t < 1.0:
			h.t = minf(h.t + delta / REACH_TIME, 1.0)
			if h.t >= 1.0 and h.wall:
				Sfx.play("step", player, -16.0, randf_range(1.4, 1.8))
		elif climbing:
			var other: Dictionary = _hands[1 - i]
			var slid: bool = eye.y - h.target.y > REGRAB_DROP
			var far: bool = h.target.distance_to(_shoulder(i, cam)) > UPPER + FORE + 0.2
			# Leapfrog: only let go when the other hand is holding on.
			if (slid or far or not h.wall) and other.t >= 1.0:
				h.from = _hand_point(h)
				h.t = 0.0
				_pick_hold(i, GRAB_UP)

	for i in 2:
		var h: Dictionary = _hands[i]
		var side := -1.0 if i == 0 else 1.0
		var shoulder := _shoulder(i, cam)
		var hand := _hand_point(h).lerp(_low_point(i, cam), 1.0 - _ease(_engage))
		var pole := cb.x * side * 0.7 + Vector3.DOWN - cb.z * 0.2
		var elbow_hand := _solve(shoulder, hand, pole)
		_place(_upper[i], shoulder, elbow_hand[0])
		_place(_fore[i], elbow_hand[0], elbow_hand[1])
		_place_palm(_palm[i], elbow_hand[1], h.normal, cb)


## Where hand `i` would be right now: planted, or partway through an arcing reach.
func _hand_point(h: Dictionary) -> Vector3:
	if h.t >= 1.0:
		return h.target
	var k := _ease(clampf(h.t, 0.0, 1.0))
	return h.from.lerp(h.target, k) + h.normal * sin(k * PI) * REACH_LIFT


func _pick_hold(i: int, up: float) -> void:
	var h: Dictionary = _hands[i]
	var side := -1.0 if i == 0 else 1.0
	var fwd := -player.global_basis.z
	var right := player.global_basis.x
	var eye_y: float = player.camera.global_position.y
	var space := player.get_world_3d().direct_space_state
	for lift in [up, up * 0.5, 0.0]:
		var from := player.global_position + right * side * GRAB_SIDE
		from.y = eye_y + lift
		var q := PhysicsRayQueryParameters3D.create(from, from + fwd * GRAB_PROBE, 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			h.target = hit.position + hit.normal * 0.035
			h.normal = hit.normal
			h.wall = true
			return
	# Nothing to hold: reach into the air ahead.
	h.target = player.camera.global_position + fwd * 0.55 + right * side * GRAB_SIDE + Vector3.UP * up
	h.normal = -fwd
	h.wall = false


func _shoulder(i: int, cam: Camera3D) -> Vector3:
	var s := SHOULDER
	s.x *= -1.0 if i == 0 else 1.0
	return cam.global_transform * s


func _low_point(i: int, cam: Camera3D) -> Vector3:
	var p := Vector3(0.28 * (-1.0 if i == 0 else 1.0), -0.85, -0.25)
	return cam.global_transform * p


## Two-bone IK: returns [elbow, wrist]. Out-of-reach targets get a straight arm pointing at them.
func _solve(s: Vector3, t: Vector3, pole: Vector3) -> Array:
	var d_vec := t - s
	var n := d_vec.normalized() if d_vec.length() > 0.001 else Vector3.FORWARD
	var d := clampf(d_vec.length(), 0.05, UPPER + FORE - 0.001)
	var x := (UPPER * UPPER - FORE * FORE + d * d) / (2.0 * d)
	var y := sqrt(maxf(UPPER * UPPER - x * x, 0.0))
	var p := pole - n * pole.dot(n)
	p = p.normalized() if p.length() > 0.001 else Vector3.DOWN
	return [s + n * x + p * y, s + n * d]


func _place(m: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var y := d.normalized() if d.length() > 0.001 else Vector3.UP
	var ref := Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	m.global_transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)


## Flattened ball for a hand, palm facing the rock, fingers pointing up.
func _place_palm(m: MeshInstance3D, wrist: Vector3, normal: Vector3, cb: Basis) -> void:
	var z := normal
	var up := Vector3.UP - z * Vector3.UP.dot(z)
	if up.length() < 0.1:
		up = -cb.z
	var y := up.normalized()
	var x := y.cross(z)
	var b := Basis(x * 0.85, y * 1.25, z * 0.5)
	m.global_transform = Transform3D(b, wrist + y * 0.05)


static func _ease(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)
