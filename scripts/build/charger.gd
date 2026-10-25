extends "res://scripts/build/building.gd"
## Battery charger: two slots for batteries or Shredders, charged from the grid at up to 20 kW each
## (empty to full in 5 minutes at full power). Drag batteries in and out.

const Sfx = preload("res://scripts/audio/sfx.gd")

const KW_PER_BATTERY := 20.0
## Shredders fill 5x faster than batteries for the same draw (a minute from empty).
const SHREDDER_CHARGE_MULT := 5.0

var slots_inv = Inventory.new(2, "Charging slots", [Items.BATTERY, Items.SHREDDER])
var _buzz: AudioStreamPlayer3D
var _slot_lamps: Array = []
var _full_mat := glow(Color(0.4, 1.0, 0.5), 2.5)
var _charging_mat := glow(Color(1.0, 0.75, 0.3), 2.5)
var _empty_mat := mat(Color(0.12, 0.12, 0.13), 0.5, 0.6)


func _init() -> void:
	cable_anchor = Vector3(0, 1.45, -0.25)


func _build_visuals() -> void:
	var body := mat(Color(0.3, 0.31, 0.33), 0.75, 0.45)
	var paint := mat(Color(0.75, 0.5, 0.12), 0.4, 0.55)
	box(Vector3(1.2, 1.1, 0.7), Vector3(0, 0.55, 0), body)
	box(Vector3(1.24, 0.12, 0.74), Vector3(0, 1.1, 0), paint)
	cyl(0.05, 0.3, Vector3(0, 1.3, -0.25), body)
	for i in 2:
		_slot_lamps.append(box(Vector3(0.35, 0.5, 0.05), Vector3(-0.28 + i * 0.56, 0.6, 0.36), _empty_mat))


func _collision_shape() -> Shape3D:
	var b := BoxShape3D.new()
	b.size = Vector3(1.2, 1.2, 0.7)
	return b


func _collision_offset() -> Vector3:
	return Vector3(0, 0.6, 0)


func _charging() -> Array:
	var out: Array = []
	for s in slots_inv.slots:
		if s and s["energy"] < BATTERY_CAPACITY:
			out.append(s)
	return out


func demand_kw() -> float:
	return KW_PER_BATTERY * _charging().size()


func power_tick(dt: float, satisfaction: float, _load: float) -> void:
	if _buzz == null and not ghost:
		_buzz = Sfx.loop_3d("hum", self, -16.0, 3.0)
		_buzz.pitch_scale = 3.0
	var charging := _charging()
	var active := not charging.is_empty() and satisfaction > 0.0
	if _buzz and active != _buzz.playing:
		_buzz.playing = active
	for s in charging:
		var mult := SHREDDER_CHARGE_MULT if s["id"] == Items.SHREDDER else 1.0
		s["energy"] = minf(s["energy"] + KW_PER_BATTERY * mult * satisfaction * dt, BATTERY_CAPACITY)
	for i in _slot_lamps.size():
		var s = slots_inv.slots[i]
		var m: Material = _empty_mat
		if s:
			m = _full_mat if s["energy"] >= BATTERY_CAPACITY else _charging_mat
		_slot_lamps[i].material_override = m


func get_inventories() -> Array:
	return [slots_inv]


func ui_build(box_: VBoxContainer, _player) -> void:
	box_.add_child(UI.label("BATTERY CHARGER", 26, Color(1.0, 0.75, 0.4)))
	box_.add_child(UI.label(power_line(), 14, Color(0.7, 0.7, 0.68)))
	box_.add_child(UI.label(_contents_line(), 16))


func _contents_line() -> String:
	var parts: Array[String] = []
	for s in slots_inv.slots:
		if s:
			parts.append("%d%%" % roundi(s["energy"] / BATTERY_CAPACITY * 100.0))
	return "Charging: " + ("empty — drag batteries in" if parts.is_empty() else ", ".join(parts))


func hover_text() -> String:
	return "Battery charger — %s\n[E] open · %s" % [_contents_line(), power_line()]


func apply_state(s: Dictionary) -> void:
	super(s)
	# Saves from before machine slots stored charges as 0..1 floats.
	for c in s.get("slots", []):
		slots_inv.add_stack(Items.new_battery(float(c) * BATTERY_CAPACITY))
