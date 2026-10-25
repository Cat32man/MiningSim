extends "res://scripts/build/building.gd"
## Electrum generator: 30 kW max while it has fuel. Burns electrum from its fuel slot in
## proportion to load, so an idle network costs nothing. Drag electrum into the slot.

const Sfx = preload("res://scripts/audio/sfx.gd")

const OUTPUT_KW := 30.0
## Seconds one electrum lasts at full load.
const SECONDS_PER_ELECTRUM := 25.0

var fuel_inv = Inventory.new(1, "Fuel (electrum)", [Items.ELECTRUM])
## Remaining fraction of the electrum currently burning.
var burn := 0.0

var _light: OmniLight3D
var _lamp: MeshInstance3D
var _hum: AudioStreamPlayer3D
var _on_mat := glow(Color(0.4, 1.0, 0.5), 3.0)
var _off_mat := glow(Color(1.0, 0.3, 0.2), 1.5)


func _init() -> void:
	cable_anchor = Vector3(0.0, 1.95, 0.0)


func _build_visuals() -> void:
	var body := mat(Color(0.75, 0.5, 0.12), 0.4, 0.55)
	var steel := mat(Color(0.35, 0.36, 0.38), 0.85, 0.4)
	box(Vector3(2.2, 0.15, 1.5), Vector3(0, 0.075, 0), steel)
	box(Vector3(2.0, 1.3, 1.3), Vector3(0, 0.8, 0), body)
	var coil := cyl(0.35, 1.1, Vector3(-0.5, 0.9, 0), steel)
	coil.rotation.z = PI / 2
	for i in 4:
		box(Vector3(0.04, 0.9, 1.32), Vector3(0.25 + i * 0.16, 0.8, 0), steel)  # cooling fins
	cyl(0.06, 0.4, Vector3(0, 1.75, 0), steel)  # cable post
	_lamp = cyl(0.08, 0.08, Vector3(0.6, 1.5, 0.66), _off_mat)
	_lamp.rotation.x = PI / 2
	_light = OmniLight3D.new()
	_light.light_color = Color(0.6, 0.85, 1.0)
	_light.omni_range = 6.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, 1.6, 1.0)
	add_child(_light)
	if not ghost and not preview:
		# Electric hum (it runs on electrum, not a combustion engine).
		_hum = Sfx.loop_3d("hum", self, -6.0, 4.0)
		_hum.position.y = 0.8


func _collision_shape() -> Shape3D:
	var b := BoxShape3D.new()
	b.size = Vector3(2.2, 1.5, 1.5)
	return b


func _collision_offset() -> Vector3:
	return Vector3(0, 0.75, 0)


func fuel() -> int:
	return fuel_inv.count_of(Items.ELECTRUM)


func supply_kw() -> float:
	return OUTPUT_KW if fuel() > 0 or burn > 0.0 else 0.0


func power_tick(dt: float, _satisfaction: float, load: float) -> void:
	var running := load > 0.0 and supply_kw() > 0.0
	if running:
		burn -= dt * load / SECONDS_PER_ELECTRUM
		if burn <= 0.0:
			if fuel_inv.remove(Items.ELECTRUM, 1) > 0:
				burn += 1.0
			else:
				burn = 0.0
	if _lamp:
		_lamp.material_override = _on_mat if running else _off_mat
		_light.light_energy = 1.2 * load if running else 0.0
	if _hum:
		if running != _hum.playing:
			_hum.playing = running
		# Pitch and loudness rise with load.
		_hum.pitch_scale = 0.9 + 0.2 * load
		_hum.volume_db = lerpf(-12.0, -3.0, load)


func get_inventories() -> Array:
	return [fuel_inv]


func ui_build(box_: VBoxContainer, player) -> void:
	box_.add_child(UI.label("ELECTRUM GENERATOR", 26, Color(1.0, 0.75, 0.4)))
	for line in _status().split("\n"):
		box_.add_child(UI.label(line, 15))
	var have: int = player.backpack.count_of(Items.ELECTRUM)
	box_.add_child(UI.button("Load all electrum (%d)" % have,
		func(): fuel_inv.pull_ore_from(player.backpack), have > 0))


func _status() -> String:
	var minutes := (fuel() + burn) * SECONDS_PER_ELECTRUM / 60.0
	var st: Vector2 = grid.network_stats(network_id) if grid else Vector2.ZERO
	# Max is the network's total: generators on one network share the load.
	var s := "Fuel: %d electrum (~%.1f min)\nDraw %d / %d kW" % [
		fuel(), minutes, roundi(minf(st.y, st.x)), roundi(st.x)]
	if st.x > 0.0 and st.y > st.x:
		# Demand over max output: every grid-only machine runs at supply/demand speed.
		s += "\n⚠ Overloaded: %d kW wanted, running at %d%%" % [roundi(st.y), roundi(st.x / st.y * 100.0)]
	return s


func hover_text() -> String:
	return "Electrum generator — %s\n[E] open" % _status().split("\n")[0]


func get_state() -> Dictionary:
	var s := super()
	s["burn"] = burn
	return s


func apply_state(s: Dictionary) -> void:
	super(s)
	burn = s.get("burn", 0.0)
	# Saves from before machine slots stored fuel as a plain number.
	if s.has("fuel") and fuel_inv.is_empty():
		fuel_inv.add(Items.ELECTRUM, s["fuel"])
