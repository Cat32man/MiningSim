extends "res://scripts/build/building.gd"
## Silicon harvester: a drivable bore, about 1.5 wall pieces tall. [E] climbs on top and
## drives it (WASD, Tab for its cargo, E to get off). The cutting head chews through the
## silicon caves' sand, sifting silicon into its hopper and leaving dull plain sand behind.
## It can't cut rock, and it burns coal.

const SPEED := 3.5  # m/s over open ground
const BORE_SPEED := 1.3  # m/s while cutting sand
const TURN := 0.9  # rad/s
const BORE_CENTER := Vector3(0, 2.45, -3.1)  # local; -z is forward; cuts level, just above the tracks
const DIG_DROP := 1.1  # Space lowers the cut this much so it trenches down into the sand bed
const BORE_RADIUS := 2.3
const BORE_EVERY := 0.15  # seconds between cuts
const ROCK_LIMIT := 18  # solid rock samples in the cut before it refuses to go on
const COAL_SECONDS := 12.0  # one coal lasts this long while the engine works
const SILICON_PER_SAND := 0.25
const SEAT := Vector3(0, 4.35, 1.3)  # where the driver's feet go

var fuel_inv = Inventory.new(2, "Coal", [Items.COAL])
var hopper = Inventory.new(8, "Silicon", [Items.SILICON])
var status := "Parked"
var driver = null

var _burn := 0.0
var _si := 0.0
var _bore_t := 0.0
var _working := false
var _head: Node3D
var _dust: CPUParticles3D
var _smoke: CPUParticles3D
var _lamp: SpotLight3D
var _hum: AudioStreamPlayer3D
var _fall := 0.0
var _down := false
var _yaw := NAN  # heading, kept apart from the slope lean


func _init() -> void:
	is_power_node = false


func _build_visuals() -> void:
	var paint := mat(Color(0.82, 0.55, 0.12), 0.35, 0.55)
	var steel := mat(Color(0.28, 0.29, 0.31), 0.8, 0.4)
	var dark := mat(Color(0.1, 0.1, 0.11), 0.7, 0.5)
	var teeth := mat(Color(0.7, 0.72, 0.75), 0.9, 0.25)
	# Tracks and body.
	for x in [-1.45, 1.45]:
		box(Vector3(0.8, 1.0, 5.2), Vector3(x, 0.5, 0.2), dark)
		for i in 6:
			box(Vector3(0.84, 0.12, 0.3), Vector3(x, 1.02, -2.0 + i * 0.85), steel)
	box(Vector3(3.2, 2.6, 4.2), Vector3(0, 2.1, 0.5), paint)
	box(Vector3(3.3, 0.15, 4.3), Vector3(0, 3.45, 0.5), steel)
	box(Vector3(2.2, 0.9, 1.2), Vector3(0, 3.95, 1.6), steel)  # driver's rail housing
	box(Vector3(2.0, 0.5, 0.06), Vector3(0, 4.05, 0.99), glow(Color(1.0, 0.75, 0.35), 0.8))  # cab glass
	cyl(0.18, 1.6, Vector3(1.2, 4.2, 2.2), dark)  # exhaust
	# Cutting head: a big drum facing forward, with teeth, turning while it works.
	_head = Node3D.new()
	_head.position = BORE_CENTER + Vector3(0, 0, 0.35)
	add_child(_head)
	var drum := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 2.15
	dm.bottom_radius = 2.15
	dm.height = 0.8
	drum.mesh = dm
	drum.material_override = steel
	drum.rotation.x = PI / 2
	_head.add_child(drum)
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.1
	hm.bottom_radius = 0.6
	hm.height = 0.9
	hub.mesh = hm
	hub.material_override = paint
	hub.rotation.x = -PI / 2
	hub.position.z = -0.8
	_head.add_child(hub)
	for i in 10:
		var a := TAU * i / 10.0
		for r in [0.9, 1.7]:
			var t := MeshInstance3D.new()
			var tm := BoxMesh.new()
			tm.size = Vector3(0.2, 0.2, 0.35)
			t.mesh = tm
			t.material_override = teeth
			t.position = Vector3(cos(a + r) * r, sin(a + r) * r, -0.55)
			t.rotation.z = a
			_head.add_child(t)
	if ghost or preview:
		return
	_lamp = SpotLight3D.new()
	_lamp.position = Vector3(0, 3.9, -0.5)
	_lamp.rotation.x = -0.25
	_lamp.spot_range = 22.0
	_lamp.spot_angle = 40.0
	_lamp.light_energy = 0.0
	_lamp.light_color = Color(1.0, 0.9, 0.75)
	add_child(_lamp)
	_dust = _particles(Color(0.78, 0.66, 0.42, 0.7), 40, 1.2)
	_dust.position = BORE_CENTER + Vector3(0, -1.2, -0.6)
	_dust.direction = Vector3(0, 1, 0.5)
	_smoke = _particles(Color(0.18, 0.17, 0.16, 0.6), 18, 2.5)
	_smoke.position = Vector3(1.2, 5.0, 2.2)
	_smoke.direction = Vector3.UP


func _particles(color: Color, amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.spread = 35.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, -0.5, 0)
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.45
	var fade := Gradient.new()
	fade.set_color(0, color)
	fade.set_color(1, Color(color, 0.0))
	p.color_ramp = fade
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1.0
	puff.radial_segments = 6
	puff.rings = 3
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = m
	p.mesh = puff
	add_child(p)
	return p


func _collision_shapes() -> Array:
	var body := BoxShape3D.new()
	body.size = Vector3(3.8, 3.6, 5.2)
	var head := BoxShape3D.new()
	head.size = Vector3(4.3, 4.3, 1.0)
	return [[body, Transform3D(Basis.IDENTITY, Vector3(0, 1.8, 0.3))],
		[head, Transform3D(Basis.IDENTITY, BORE_CENTER + Vector3(0, -0.1, 0.4))]]


func _physics_process(dt: float) -> void:
	if ghost or preview:
		return
	if driver == null:
		_working = false
		status = "Broken" if broken else "Parked"
		_settle(dt)
	var spin := 6.0 if _working else (1.0 if driver else 0.0)
	_head.rotation.z += spin * dt
	if _dust:
		_dust.emitting = _working and (status.begins_with("Cutting") or status.begins_with("Digging"))
		_smoke.emitting = driver != null and _has_fuel()
		_lamp.light_energy = 1.6 if driver else 0.0
	if _hum == null:
		_hum = SfxLib.loop_3d("hum", self, -8.0, 3.0)
		_hum.pitch_scale = 0.45
	var on: bool = driver != null and _has_fuel()
	if on != _hum.playing:
		_hum.playing = on
	if _hum.playing:
		_hum.pitch_scale = 0.6 if _working else 0.45


## Called by the driver every physics frame with WASD as (x = turn, y = -forward); `down`
## (Space) angles the cut into the floor.
func drive(input: Vector2, dt: float, down := false) -> void:
	_working = false
	_down = down
	if broken:
		status = "Broken"
		return
	if not _has_fuel():
		status = "Out of coal"
		_settle(dt)
		return
	var fwd := -input.y
	var turning := absf(input.x) > 0.1
	if turning:
		_yaw = _heading() - input.x * TURN * dt
	var speed := 0.0
	status = "Idling"
	if fwd > 0.1:
		var cut := _probe()
		if cut["rock"] > ROCK_LIMIT:
			status = "Rock ahead — it only cuts sand"
		elif cut["sand"] > 0:
			if hopper.count_of(Items.SILICON) >= hopper.slots.size() * hopper.max_stack(Items.SILICON):
				status = "Hopper full"
			else:
				speed = BORE_SPEED
				status = "%s — %d silicon" % ["Digging down" if down else "Cutting sand", hopper.count_of(Items.SILICON)]
				_bore_t -= dt
				if _bore_t <= 0.0:
					_bore_t = BORE_EVERY
					_cut()
		else:
			speed = SPEED
			status = "Driving"
	elif fwd < -0.1:
		speed = -SPEED * 0.5
		status = "Reversing"
	if speed != 0.0 or turning:
		_working = true
		_burn += dt / COAL_SECONDS
		if _burn >= 1.0:
			_burn -= 1.0
			fuel_inv.remove(Items.COAL, 1)
	global_position += -global_basis.z * speed * dt
	_settle(dt)


## Sticks to the ground under it, leaning with the slope; falls if there's none.
func _settle(dt: float) -> void:
	var from := global_position + Vector3.UP * 3.0
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 9.0, 1)  # terrain only
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_fall += 9.8 * dt
		global_position.y -= _fall * dt
		return
	_fall = 0.0
	global_position.y = move_toward(global_position.y, hit["position"].y, 6.0 * dt)
	var n: Vector3 = hit["normal"]
	if n.dot(Vector3.UP) > 0.6:
		var yaw := _heading()
		var up := global_basis.y.slerp(n, minf(dt * 3.0, 1.0)).normalized()
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var x := up.cross(-fwd).normalized()
		global_basis = Basis(x, up, x.cross(up)).orthonormalized()


## Counts what's in the cutting head's reach: sand it can take, rock that stops it.
func _probe() -> Dictionary:
	var w = grid.world
	var c: Vector3 = global_transform * _cut_center()
	var out := {"rock": 0, "sand": 0}
	var r := ceili(BORE_RADIUS)
	for z in range(-r, r + 1):
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				var p := Vector3i(c.round()) + Vector3i(x, y, z)
				if Vector3(p).distance_to(c) > BORE_RADIUS or w.density_at(p) <= 0.0:
					continue
				var m: int = w.material_at(p)
				if m == Materials.SILICON_SAND or m == Materials.SAND:
					out["sand"] += 1
				else:
					out["rock"] += 1
	return out


func _cut() -> void:
	var got: Dictionary = grid.world.apply_edit({"type": "harvest", "center": global_transform * _cut_center(),
		"radius": BORE_RADIUS, "forward": -global_basis.z})
	_si += got.get(Materials.SILICON_SAND, 0) * SILICON_PER_SAND
	var whole := floori(_si)
	if whole > 0:
		_si -= whole
		hopper.add(Items.SILICON, whole)


func _heading() -> float:
	if is_nan(_yaw):
		_yaw = global_rotation.y
	return _yaw


func _cut_center() -> Vector3:
	return BORE_CENTER - Vector3(0, DIG_DROP if _down else 0.0, 0)


func _has_fuel() -> bool:
	return fuel_inv.count_of(Items.COAL) > 0


func seat_position() -> Vector3:
	return global_transform * SEAT


func is_running() -> bool:
	return _working


func set_broken(v: bool) -> void:
	super(v)
	if v and driver:
		driver.exit_vehicle()


func interact(player) -> bool:
	if broken:
		player._flash("Broken — repair it first")
		return false
	player.enter_vehicle(self)
	return false


func get_inventories() -> Array:
	return [fuel_inv, hopper]


func ui_build(box_: VBoxContainer, player) -> void:
	box_.add_child(UI.label("SILICON HARVESTER", 26, Color(1.0, 0.75, 0.4)))
	box_.add_child(UI.label(status, 17))
	var coal: int = fuel_inv.count_of(Items.COAL)
	box_.add_child(UI.label("Coal %d (~%d s)   ·   Silicon %d" % [coal, roundi((coal - _burn) * COAL_SECONDS),
		hopper.count_of(Items.SILICON)], 14, Color(0.7, 0.7, 0.68)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(UI.button("Load coal", func():
		for src in player.cost_sources():
			fuel_inv.pull_ore_from(src)))
	row.add_child(UI.button("Take silicon", func(): player.take_up_to_limit(hopper)))
	box_.add_child(row)


func hover_text() -> String:
	return "Silicon harvester — %s\nCoal %d · silicon %d · [E] drive" % [status, fuel_inv.count_of(Items.COAL),
		hopper.count_of(Items.SILICON)]
