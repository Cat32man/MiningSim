extends "res://scripts/build/building.gd"
## Microchip printer: a flat CNC bed, 1×2 wall pieces and half a piece tall. A gantry sweeps
## the bed and its laser head etches chips out of silicon, electrum and steel. Runs on its
## own while the inputs hold a batch and the output has room. Grid power or its battery slot.

const DEMAND_KW := 40.0
const RECIPE := {"in": {Items.SILICON: 4, Items.ELECTRUM: 2, Items.STEEL: 1}, "out": {Items.MICROCHIP: 1}, "time": 20.0}
const BED := Vector3(3.0, 1.5, 6.0)  # footprint and height (metres)

var input_inv = Inventory.new(3, "Input", [Items.SILICON, Items.ELECTRUM, Items.STEEL])
var output_inv = Inventory.new(2, "Output")
var progress_t := 0.0
var status := "Idle"

var _running := false
var _gantry: Node3D
var _head: Node3D
var _laser_mat: StandardMaterial3D
var _sparks: CPUParticles3D
var _light: OmniLight3D
var _hum: AudioStreamPlayer3D
var _t := 0.0


func _init() -> void:
	cable_anchor = Vector3(1.4, 1.6, 2.8)
	battery_inv = Inventory.new(1, "Battery", [Items.BATTERY])


func _build_visuals() -> void:
	var steel := mat(Color(0.28, 0.29, 0.31), 0.8, 0.4)
	var dark := mat(Color(0.12, 0.12, 0.13), 0.8, 0.45)
	var paint := mat(Color(0.8, 0.52, 0.12), 0.35, 0.55)
	var board := mat(Color(0.12, 0.35, 0.2), 0.2, 0.6)
	box(Vector3(BED.x, 0.8, BED.z), Vector3(0, 0.4, 0), dark)  # base cabinet
	box(Vector3(BED.x - 0.2, 0.06, BED.z - 0.2), Vector3(0, 0.83, 0), board)  # the sheet being etched
	for x in [-BED.x * 0.5 + 0.08, BED.x * 0.5 - 0.08]:
		box(Vector3(0.16, 0.12, BED.z), Vector3(x, 0.9, 0), paint)  # rails
	box(Vector3(0.5, 0.4, 0.08), Vector3(1.1, 0.5, BED.z * 0.5 + 0.02), glow(Color(0.4, 0.9, 1.0), 1.2))  # panel
	cyl(0.05, 0.6, Vector3(1.4, 1.3, 2.8), dark)  # cable post
	# Gantry bridge (moves along z) with the laser head (moves along x).
	_gantry = Node3D.new()
	_gantry.position = Vector3(0, 0.9, 0)
	add_child(_gantry)
	for x in [-BED.x * 0.5 + 0.08, BED.x * 0.5 - 0.08]:
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.14, 0.6, 0.3)
		post.mesh = pm
		post.material_override = steel
		post.position = Vector3(x, 0.3, 0)
		_gantry.add_child(post)
	var beam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(BED.x, 0.14, 0.25)
	beam.mesh = bm
	beam.material_override = paint
	beam.position = Vector3(0, 0.6, 0)
	_gantry.add_child(beam)
	_head = Node3D.new()
	_head.position = Vector3(0, 0.45, 0)
	_gantry.add_child(_head)
	var carriage := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.3, 0.35, 0.32)
	carriage.mesh = cm
	carriage.material_override = steel
	_head.add_child(carriage)
	_laser_mat = glow(Color(1.0, 0.25, 0.15), 0.0)
	var laser := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.012
	lm.bottom_radius = 0.012
	lm.height = 0.42
	laser.mesh = lm
	laser.material_override = _laser_mat
	laser.position = Vector3(0, -0.36, 0)
	_head.add_child(laser)
	if ghost or preview:
		return
	_sparks = CPUParticles3D.new()
	_sparks.emitting = false
	_sparks.amount = 24
	_sparks.lifetime = 0.4
	_sparks.spread = 70.0
	_sparks.direction = Vector3.UP
	_sparks.initial_velocity_min = 0.6
	_sparks.initial_velocity_max = 1.6
	_sparks.gravity = Vector3(0, -6, 0)
	_sparks.scale_amount_min = 0.015
	_sparks.scale_amount_max = 0.03
	var dot := SphereMesh.new()
	dot.radius = 0.5
	dot.height = 1.0
	dot.material = glow(Color(1.0, 0.6, 0.3), 4.0)
	_sparks.mesh = dot
	_sparks.position = Vector3(0, -0.58, 0)
	_head.add_child(_sparks)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.35, 0.2)
	_light.omni_range = 3.5
	_light.light_energy = 0.0
	_light.position = Vector3(0, -0.4, 0)
	_head.add_child(_light)


func _collision_shape() -> Shape3D:
	var b := BoxShape3D.new()
	b.size = BED
	return b


func _collision_offset() -> Vector3:
	return Vector3(0, BED.y * 0.5, 0)


func _can_run() -> bool:
	for id in RECIPE["in"]:
		if input_inv.count_of(id) < RECIPE["in"][id]:
			status = "Needs %s" % Items.describe(_missing())
			return false
	for id in RECIPE["out"]:
		if not _room_for(id, RECIPE["out"][id]):
			status = "Output full"
			return false
	return true


func _missing() -> Dictionary:
	var out := {}
	for id in RECIPE["in"]:
		var short: int = RECIPE["in"][id] - input_inv.count_of(id)
		if short > 0:
			out[id] = short
	return out


func _room_for(id: String, n: int) -> bool:
	var room := 0
	for s in output_inv.slots:
		if s == null:
			room += output_inv.max_stack(id)
		elif s["id"] == id:
			room += output_inv.max_stack(id) - s["count"]
	return room >= n


func demand_kw() -> float:
	return DEMAND_KW if _can_run() else 0.0


func power_tick(dt: float, satisfaction: float, _load: float) -> void:
	_t += dt
	_running = satisfaction > 0.0 and _can_run()
	if _running:
		progress_t += dt * satisfaction / RECIPE["time"]
		status = "Printing — %d%%" % roundi(progress_t * 100.0)
		if progress_t >= 1.0:
			progress_t = 0.0
			for id in RECIPE["in"]:
				input_inv.remove(id, RECIPE["in"][id])
			for id in RECIPE["out"]:
				output_inv.add(id, RECIPE["out"][id])
			SfxLib.play_3d("deposit", global_position + Vector3(0, 1.0, 0), get_parent(), -6.0, 1.4)
	elif _can_run():
		status = "No power"
	if _hum == null and not ghost:
		_hum = SfxLib.loop_3d("hum", self, -14.0, 4.0)
		_hum.pitch_scale = 1.6
	if _hum and _running != _hum.playing:
		_hum.playing = _running


func _process(dt: float) -> void:
	if ghost or _gantry == null:
		return
	# The gantry sweeps the bed and the head zig-zags across it while printing.
	if _running:
		_gantry.position.z = sin(_t * 0.35) * (BED.z * 0.5 - 0.4)
		_head.position.x = sin(_t * 2.3) * (BED.x * 0.5 - 0.35)
	var on := _running and sin(_t * 17.0) > -0.6
	_laser_mat.emission_energy_multiplier = 6.0 if on else 0.0
	if _sparks:
		_sparks.emitting = on
		_light.light_energy = 1.2 if on else 0.0


func get_inventories() -> Array:
	return [input_inv, output_inv, battery_inv]


func ui_build(box_: VBoxContainer, player) -> void:
	box_.add_child(UI.label("MICROCHIP PRINTER", 26, Color(1.0, 0.75, 0.4)))
	_can_run()
	box_.add_child(UI.label(status, 17))
	box_.add_child(UI.label(power_line() + "   ·   " + battery_line(), 14, Color(0.7, 0.7, 0.68)))
	box_.add_child(UI.label("%s → %s · %d s" % [Items.describe(RECIPE["in"]), Items.describe(RECIPE["out"]),
		roundi(RECIPE["time"])], 15, Color(1.0, 0.85, 0.6)))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.add_child(UI.button("Load ingredients", func(): _load_from(player.cost_sources())))
	buttons.add_child(UI.button("Take output", func(): player.take_up_to_limit(output_inv)))
	box_.add_child(buttons)


## Fills the inputs in recipe proportion, as many whole batches as fit and `sources` cover.
func _load_from(sources: Array) -> void:
	var need: Dictionary = RECIPE["in"]
	var have := {}
	for id in need:
		have[id] = input_inv.count_of(id)
		for src in sources:
			have[id] += src.count_of(id)
	var batches := 0
	while true:
		var n := batches + 1
		var ok := true
		for id in need:
			# One slot per ingredient.
			ok = ok and have[id] >= n * need[id] and n * need[id] <= input_inv.max_stack(id)
		if not ok:
			break
		batches = n
	for id in need:
		var short: int = batches * need[id] - input_inv.count_of(id)
		for src in sources:
			if short <= 0:
				break
			var n: int = mini(short, src.count_of(id))
			if n > 0:
				var left: int = input_inv.add(id, n)
				src.remove(id, n - left)
				short -= n - left


func hover_text() -> String:
	_can_run()
	return "Microchip printer — %s\n[E] open · %s" % [status, power_line()]


func get_state() -> Dictionary:
	var s := super()
	s["progress"] = progress_t
	return s


func apply_state(s: Dictionary) -> void:
	super(s)
	progress_t = s.get("progress", 0.0)
