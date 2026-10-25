extends "res://scripts/build/building.gd"
## Materials refinery (blueprint unlocked by finding obsidian). Pick a recipe and it runs on
## its own while its input slots hold enough and the output has room: load it, come back,
## collect. Grid power or its battery slot.

const Sfx = preload("res://scripts/audio/sfx.gd")
const RecipeGrid = preload("res://scripts/ui/recipe_grid.gd")

const DEMAND_KW := 30.0
const RECIPES := {
	"steel": {"name": "Steel", "model": "steel", "in": {Items.IRON: 2, Items.COAL: 1}, "out": {Items.STEEL: 1}, "time": 6.0},
	# A little obsidian, a lot of diamond.
	"obsidianite": {"name": "Obsidianite", "model": "obsidianite", "in": {Items.OBSIDIAN: 1, Items.DIAMOND: 20},
		"out": {Items.OBSIDIANITE: 1}, "time": 30.0},
}

var recipe := "steel"
var input_inv = Inventory.new(4, "Input", [Items.IRON, Items.COAL, Items.OBSIDIAN, Items.DIAMOND])
var output_inv = Inventory.new(2, "Output")
var progress_t := 0.0
var status := "Idle"

var _running := false
var _window: MeshInstance3D
var _window_mat: StandardMaterial3D
var _light: OmniLight3D
var _smoke: CPUParticles3D
var _hum: AudioStreamPlayer3D
var _t := 0.0


func _init() -> void:
	cable_anchor = Vector3(0.85, 2.3, -0.5)
	battery_inv = Inventory.new(1, "Battery", [Items.BATTERY])


func _build_visuals() -> void:
	var steel := mat(Color(0.26, 0.27, 0.29), 0.8, 0.4)
	var dark := mat(Color(0.12, 0.12, 0.13), 0.8, 0.45)
	var paint := mat(Color(0.8, 0.52, 0.12), 0.35, 0.55)
	box(Vector3(2.0, 0.2, 1.4), Vector3(0, 0.1, 0), dark)  # plinth
	box(Vector3(1.6, 1.8, 1.2), Vector3(0, 1.1, 0), steel)  # furnace
	box(Vector3(1.64, 0.14, 1.24), Vector3(0, 1.75, 0), paint)
	box(Vector3(0.5, 0.6, 0.5), Vector3(-0.55, 2.3, 0.1), steel)  # feed hopper
	cyl(0.16, 1.4, Vector3(0.45, 2.7, -0.3), dark)  # chimney
	cyl(0.2, 0.08, Vector3(0.45, 3.4, -0.3), paint)
	cyl(0.05, 0.5, Vector3(0.85, 2.15, -0.5), dark)  # cable post
	box(Vector3(0.5, 0.3, 0.6), Vector3(0, 0.45, 0.85), dark)  # output chute
	# Crucible window: glows while refining.
	_window_mat = glow(Color(1.0, 0.45, 0.1), 0.0)
	_window = box(Vector3(0.7, 0.45, 0.05), Vector3(0, 1.05, 0.61), _window_mat)
	box(Vector3(0.82, 0.08, 0.08), Vector3(0, 1.31, 0.62), dark)
	box(Vector3(0.82, 0.08, 0.08), Vector3(0, 0.79, 0.62), dark)
	if ghost or preview:
		_window_mat.emission_energy_multiplier = 2.0
		return
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 1.0, 1.2)
	_light.light_color = Color(1.0, 0.5, 0.2)
	_light.omni_range = 7.0
	_light.light_energy = 0.0
	add_child(_light)
	_smoke = CPUParticles3D.new()
	_smoke.position = Vector3(0.45, 3.45, -0.3)
	_smoke.emitting = false
	_smoke.amount = 20
	_smoke.lifetime = 3.0
	_smoke.direction = Vector3.UP
	_smoke.spread = 12.0
	_smoke.initial_velocity_min = 0.6
	_smoke.initial_velocity_max = 1.1
	_smoke.gravity = Vector3(0.1, 0.2, 0)
	_smoke.scale_amount_min = 0.2
	_smoke.scale_amount_max = 0.5
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 2.0))
	_smoke.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.2, 0.19, 0.18, 0.6))
	fade.set_color(1, Color(0.3, 0.3, 0.3, 0.0))
	_smoke.color_ramp = fade
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1.0
	puff.radial_segments = 8
	puff.rings = 4
	var pm := StandardMaterial3D.new()
	pm.vertex_color_use_as_albedo = true
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = pm
	_smoke.mesh = puff
	add_child(_smoke)


func _collision_shape() -> Shape3D:
	var b := BoxShape3D.new()
	b.size = Vector3(2.0, 2.0, 1.4)
	return b


func _collision_offset() -> Vector3:
	return Vector3(0, 1.0, 0)


func _can_run() -> bool:
	var r: Dictionary = RECIPES[recipe]
	for id in r["in"]:
		if input_inv.count_of(id) < r["in"][id]:
			status = "Needs %s" % Items.describe(_missing(r))
			return false
	for id in r["out"]:
		if not _room_for(id, r["out"][id]):
			status = "Output full"
			return false
	return true


func _missing(r: Dictionary) -> Dictionary:
	var out := {}
	for id in r["in"]:
		var short: int = r["in"][id] - input_inv.count_of(id)
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
		var r: Dictionary = RECIPES[recipe]
		progress_t += dt * satisfaction / r["time"]
		status = "Refining %s — %d%%" % [r["name"].to_lower(), roundi(progress_t * 100.0)]
		if progress_t >= 1.0:
			progress_t = 0.0
			for id in r["in"]:
				input_inv.remove(id, r["in"][id])
			for id in r["out"]:
				output_inv.add(id, r["out"][id])
			Sfx.play_3d("deposit", global_position + Vector3(0, 0.5, 0.9), get_parent(), -6.0, 0.8)
	elif _can_run():
		status = "No power"
	if _hum == null and not ghost:
		_hum = Sfx.loop_3d("hum", self, -12.0, 4.0)
		_hum.pitch_scale = 0.7
	if _hum and _running != _hum.playing:
		_hum.playing = _running
	var flicker := 0.85 + 0.15 * sin(_t * 9.0) * sin(_t * 3.7)
	_window_mat.emission_energy_multiplier = 3.0 * flicker if _running else 0.2
	if _light:
		_light.light_energy = 1.4 * flicker if _running else 0.0
	if _smoke:
		_smoke.emitting = _running


func get_inventories() -> Array:
	return [input_inv, output_inv, battery_inv]


func ui_build(box_: VBoxContainer, player) -> void:
	box_.add_child(UI.label("MATERIALS REFINERY", 26, Color(1.0, 0.75, 0.4)))
	_can_run()
	box_.add_child(UI.label(status, 17))
	box_.add_child(UI.label(power_line() + "   ·   " + battery_line(), 14, Color(0.7, 0.7, 0.68)))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.add_child(UI.button("Load ingredients", func(): _load_from(player.backpack)))
	buttons.add_child(UI.button("Take output", func(): output_inv.move_all_to(player.backpack)))
	box_.add_child(buttons)


func ui_static(box_: VBoxContainer, player) -> void:
	var grid := RecipeGrid.new()
	grid.rows = 1
	grid.entries_fn = _entries.bind(player.progress)
	grid.on_pick = _select
	box_.add_child(grid)


## Recipe cards: click one to switch the refinery to it.
func _entries(progress) -> Array:
	var out: Array = []
	for id in RECIPES:
		var r: Dictionary = RECIPES[id]
		var on: bool = id == recipe
		if not on and progress and not progress.knows_all(r["in"]):
			continue  # haven't found its materials yet
		out.append({"id": id, "name": r["name"], "model": r["model"],
			"desc": "%s → %s" % [Items.describe(r["in"]), Items.describe(r["out"])],
			"cost": "%s · %ds" % [RecipeGrid.short_cost(r["in"]), roundi(r["time"])],
			"state": "selected" if on else "can", "progress": progress_t if on else 0.0})
	return out


## Recipes you've found all the materials for (for "new recipe" notices).
static func available_names(progress) -> Dictionary:
	var out := {}
	if progress == null or not progress.refinery_unlocked:
		return out
	for id in RECIPES:
		if progress.knows_all(RECIPES[id]["in"]):
			out["ref_" + id] = RECIPES[id]["name"]
	return out


func _select(id: String) -> void:
	recipe = id
	progress_t = 0.0


## Moves the current recipe's ingredients from `src` into the input slots.
func _load_from(src) -> void:
	for id in RECIPES[recipe]["in"]:
		var have: int = src.count_of(id)
		if have <= 0:
			continue
		var left: int = input_inv.add(id, have)
		src.remove(id, have - left)


func hover_text() -> String:
	_can_run()
	return "Materials refinery — %s\n[E] open · %s" % [status, power_line()]


func get_state() -> Dictionary:
	var s := super()
	s["recipe"] = recipe
	s["progress"] = progress_t
	return s


func apply_state(s: Dictionary) -> void:
	super(s)
	recipe = s.get("recipe", "steel")
	if not RECIPES.has(recipe):
		recipe = "steel"
	progress_t = s.get("progress", 0.0)
