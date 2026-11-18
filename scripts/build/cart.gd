extends "res://scripts/build/building.gd"
## Rail cart: [E] climbs in, W speeds up, S brakes and then backs up, Tab opens its cargo,
## E gets off. It follows the rails it sits on, carrying on across joints (taking the
## straightest way at a fork) and stopping at the end of the line. Uphill slows it a little,
## downhill speeds it up; let go and it coasts to a stop.

const Rail = preload("res://scripts/build/rail.gd")
const SfxLib2 = preload("res://scripts/audio/sfx.gd")

const MAX_SPEED := 16.0  # m/s: 500 m in about half a minute
const REVERSE_SPEED := 6.0
const ACCEL := 5.0
const BRAKE := 10.0
const COAST := 0.8  # slow-down when you let go
const SLOPE_PULL := 4.0
const SEAT := Vector3(0, 1.05, 0.35)  # where the rider's feet go

var cargo = Inventory.new(12, "Cart cargo")
var driver = null
var status := "Parked"
var speed := 0.0

var _rail = null  # the piece we're on
var _u := 0.0  # metres along it from its start
var _f := 1.0  # +1: the cart faces the way the rail runs, -1: against it
var _at_end := false  # stopped at the end of the line (until it moves off again)
var _wheels: Array = []
var _lamp: SpotLight3D
var _rumble: AudioStreamPlayer3D


func _init() -> void:
	is_power_node = false
	raidable = false


func _ready() -> void:
	super()
	if not ghost and not preview:
		add_to_group("carts")


func _build_visuals() -> void:
	var body := mat(Color(0.42, 0.3, 0.18), 0.3, 0.7)
	var metal := mat(Color(0.3, 0.31, 0.33), 0.8, 0.4)
	var trim := mat(Color(0.75, 0.5, 0.12), 0.4, 0.55)
	box(Vector3(1.3, 0.12, 2.0), Vector3(0, 0.42, 0), metal)  # chassis
	box(Vector3(1.3, 0.55, 0.08), Vector3(0, 0.75, -0.96), body)  # front
	box(Vector3(1.3, 0.55, 0.08), Vector3(0, 0.75, 0.96), body)  # back
	for side in [-1.0, 1.0]:
		box(Vector3(0.08, 0.55, 2.0), Vector3(side * 0.61, 0.75, 0), body)
		box(Vector3(0.1, 0.06, 2.04), Vector3(side * 0.62, 1.04, 0), trim)
		for z in [-0.65, 0.65]:
			var w := cyl(0.2, 0.08, Vector3(side * Rail.GAUGE * 0.5, 0.3, z), metal)
			w.rotation.z = PI / 2
			_wheels.append(w)
	box(Vector3(0.9, 0.12, 0.45), Vector3(0, 0.62, 0.45), trim)  # seat
	box(Vector3(0.18, 0.18, 0.12), Vector3(0, 0.95, -1.02), glow(Color(1.0, 0.85, 0.6), 2.0))  # headlamp
	_lamp = SpotLight3D.new()
	_lamp.position = Vector3(0, 0.95, -1.1)
	_lamp.light_color = Color(1.0, 0.88, 0.7)
	_lamp.light_energy = 0.0
	_lamp.spot_range = 26.0
	_lamp.spot_angle = 30.0
	add_child(_lamp)


func _collision_shape() -> Shape3D:
	var b := BoxShape3D.new()
	b.size = Vector3(1.4, 0.9, 2.1)
	return b


func _collision_offset() -> Vector3:
	return Vector3(0, 0.6, 0)


func interact(player) -> bool:
	if broken:
		player._flash("Broken — repair it first")
		return false
	if not _attach():
		player._flash("Put it on a rail first")
		return false
	player.enter_vehicle(self)
	return false


func seat_position() -> Vector3:
	return global_transform * SEAT


func set_broken(v: bool) -> void:
	super(v)
	if v and driver:
		driver.exit_vehicle()


## Finds the rail under the cart (after loading, or after being moved by co-op sync).
func _attach() -> bool:
	var best = null
	var best_d := 1.5
	var best_u := 0.0
	for r in get_tree().get_nodes_in_group("rails"):
		var a: Vector3 = r.start_point()
		var d: Vector3 = r.dir()
		var u := clampf((global_position - a).dot(d), 0.0, Rail.LENGTH)
		var dist := (a + d * u).distance_to(global_position)
		if dist < best_d:
			best_d = dist
			best = r
			best_u = u
	if best == null:
		return false
	_rail = best
	_u = best_u
	_f = 1.0 if (-global_basis.z).dot(best.dir()) >= 0.0 else -1.0
	return true


## Called by the rider every physics frame: input.y < 0 is W (forward).
func drive(input: Vector2, dt: float, _down := false) -> void:
	if (_rail == null or not is_instance_valid(_rail)) and not _attach():
		status = "Off the rails"
		speed = 0.0
		return
	var throttle := -input.y
	if throttle > 0.1:
		speed = move_toward(speed, MAX_SPEED * throttle, (BRAKE if speed < 0.0 else ACCEL) * dt)
	elif throttle < -0.1:
		speed = move_toward(speed, -REVERSE_SPEED, (BRAKE if speed > 0.0 else ACCEL) * dt)
	else:
		speed = move_toward(speed, 0.0, COAST * dt)
	_move(dt)


func _physics_process(dt: float) -> void:
	if ghost or preview:
		return
	if driver == null and absf(speed) > 0.01:
		speed = move_toward(speed, 0.0, BRAKE * dt)  # got off: the brake goes on
		_move(dt)
	for w in _wheels:
		w.rotation.x -= speed * dt / 0.2
	_lamp.light_energy = 2.2 if driver else 0.0
	if driver and _rumble == null:
		_rumble = SfxLib2.loop_3d("hum", self, -14.0, 3.0)
	if _rumble:
		_rumble.playing = absf(speed) > 0.5
		_rumble.pitch_scale = 0.35 + absf(speed) / MAX_SPEED * 0.5


func _move(dt: float) -> void:
	if _rail == null or not is_instance_valid(_rail):
		return
	# Uphill slows, downhill speeds up (a little).
	speed -= (_rail.dir() * _f).y * SLOPE_PULL * dt
	_u += speed * _f * dt
	if absf(speed) > 0.3:
		_at_end = false
	for i in 8:  # very fast over short pieces can cross more than one joint a frame
		if _u > Rail.LENGTH:
			if not _cross(_rail.end_point(), _rail.dir(), _u - Rail.LENGTH):
				break
		elif _u < 0.0:
			if not _cross(_rail.start_point(), -_rail.dir(), -_u):
				break
		else:
			break
	if absf(speed) > 0.3:
		status = "%d m/s" % roundi(absf(speed))
	elif _at_end:
		status = "End of the line"
	elif driver:
		status = "Stopped"
	else:
		status = "Parked"
	var fwd: Vector3 = _rail.dir() * _f
	global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP),
		_rail.start_point() + _rail.dir() * _u + Vector3.UP * 0.02)


## Leaving the current piece at `at`, moving along `going`: onto the joined piece that runs
## straightest on, or stop at the end of the line. Returns whether we carried on.
func _cross(at: Vector3, going: Vector3, over: float) -> bool:
	var forward: Vector3 = _rail.dir() * _f
	var best = null
	var best_dot := 0.5  # no hairpin turns
	var enter_start := true
	for r in get_tree().get_nodes_in_group("rails"):
		if r == _rail:
			continue
		if r.start_point().distance_to(at) < Rail.LINK and r.dir().dot(going) > best_dot:
			best = r
			best_dot = r.dir().dot(going)
			enter_start = true
		elif r.end_point().distance_to(at) < Rail.LINK and (-r.dir()).dot(going) > best_dot:
			best = r
			best_dot = (-r.dir()).dot(going)
			enter_start = false
	if best == null:
		_u = clampf(_u, 0.0, Rail.LENGTH)
		speed = 0.0
		_at_end = true
		return false
	_rail = best
	_u = over if enter_start else Rail.LENGTH - over
	_f = 1.0 if forward.dot(best.dir()) >= 0.0 else -1.0
	return true


func get_inventories() -> Array:
	return [cargo]


func ui_build(box_: VBoxContainer, player) -> void:
	box_.add_child(UI.label("RAIL CART", 26, Color(1.0, 0.75, 0.4)))
	box_.add_child(UI.label(status, 17))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(UI.button("Load ore", func(): cargo.pull_ore_from(player.backpack)))
	row.add_child(UI.button("Take all", func(): player.take_up_to_limit(cargo)))
	box_.add_child(row)


func hover_text() -> String:
	return "Rail cart — %s\n[E] ride · W/S speed · Tab cargo" % status
