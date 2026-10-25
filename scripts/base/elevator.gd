extends Node3D
## Freight elevator in the spawn cavern: a shaft up through the bedrock to the surface.
## It starts broken; repair it with iron and electrum. Then load its cargo cage and send it
## up: what sells goes to the market at the current (drifting) prices, credits come back,
## and anything you ordered rides down with the cage. Nothing teleports: goods only move
## by riding the cage. Unsellable things stay in the cage and come back down.
##
## The terminal (E) has three tabs: Cargo (send up + prices), Shop (blueprints, looks,
## supplies) and the status line.

signal sold(credits: int)

const Inventory = preload("res://scripts/items/inventory.gd")
const Items = preload("res://scripts/items/items.gd")
const Shop = preload("res://scripts/base/shop.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const Sfx = preload("res://scripts/audio/sfx.gd")

const REPAIR_COST := {Items.IRON: 60, Items.ELECTRUM: 25}
const CARGO_SLOTS := 12
const TRIP_TIME := 12.0  # each way
const SHAFT_HEIGHT := 14.0
const CAGE_TRAVEL := 40.0  # how far up the cage visibly goes (into the rock)
const ACCENT := Color(1.0, 0.75, 0.4)
const DIM := Color(0.7, 0.7, 0.68)

enum State { BROKEN, READY, UP, DOWN }

## Set by main.
var progress
var state := State.BROKEN
var cargo = Inventory.new(CARGO_SLOTS, "Cargo cage")
var orders: Array = []  # supply keys, delivered on the next trip down
var _t := 0.0
var _tab := 0  # 0 cargo, 1 shop
var _last_sale := ""

var _cage: Node3D
var _cable: MeshInstance3D
var _screen_mat: StandardMaterial3D
var _lamp: OmniLight3D
var _sparks: CPUParticles3D
var _hum: AudioStreamPlayer3D
var _broken_parts: Array = []
var _fixed_parts: Array = []


func _ready() -> void:
	add_to_group("stations")
	var steel := _mat(Color(0.3, 0.31, 0.33), 0.85, 0.4)
	var dark := _mat(Color(0.12, 0.12, 0.13), 0.8, 0.45)
	var paint := _mat(Color(0.85, 0.6, 0.1), 0.35, 0.5)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	add_child(body)
	# Base platform with hazard edging.
	_box(Vector3(4.2, 0.3, 4.2), Vector3(0, 0.15, 0), dark, body)
	for i in 8:
		var stripe := _box(Vector3(0.3, 0.02, 4.2), Vector3(-1.85 + i * 0.53, 0.31, 0), paint if i % 2 == 0 else dark)
		stripe.rotation.y = 0.0
	# Four girder legs up into the rock, with braces.
	for x in [-1.9, 1.9]:
		for z in [-1.9, 1.9]:
			_box(Vector3(0.25, SHAFT_HEIGHT, 0.25), Vector3(x, SHAFT_HEIGHT * 0.5, z), steel, body)
	for h in [3.0, 6.5, 10.0]:
		for z in [-1.9, 1.9]:
			_box(Vector3(3.8, 0.15, 0.12), Vector3(0, h, z), steel)
		_fixed_parts.append(_box(Vector3(0.12, 0.15, 3.8), Vector3(-1.9, h, 0), steel))
	# Broken: two braces hang loose and a leg brace lies on the floor.
	var hanging := _box(Vector3(3.8, 0.15, 0.12), Vector3(0.3, 5.0, -1.9), steel)
	hanging.rotation.z = 0.9
	_broken_parts.append(hanging)
	var fallen := _box(Vector3(3.6, 0.15, 0.15), Vector3(2.8, 0.4, 0.8), steel)
	fallen.rotation = Vector3(0.1, 0.6, 0.05)
	_broken_parts.append(fallen)

	# The cage: floor, rails on three sides, a gate bar at the front (+Z, toward spawn).
	_cage = Node3D.new()
	_cage.position.y = 0.35
	add_child(_cage)
	_box(Vector3(3.4, 0.12, 3.4), Vector3(0, 0, 0), dark, null, _cage)
	for side in [[Vector3(3.4, 0.06, 0.06), Vector3(0, 1.1, -1.67)], [Vector3(0.06, 0.06, 3.4), Vector3(-1.67, 1.1, 0)],
			[Vector3(0.06, 0.06, 3.4), Vector3(1.67, 1.1, 0)], [Vector3(3.4, 0.06, 0.06), Vector3(0, 1.1, 1.67)]]:
		_box(side[0], side[1], paint, null, _cage)
	for x in [-1.67, 1.67]:
		for z in [-1.67, 1.67]:
			_box(Vector3(0.06, 1.1, 0.06), Vector3(x, 0.55, z), steel, null, _cage)
	# Crates sit in the cage while it carries something.
	_box(Vector3(0.9, 0.7, 0.9), Vector3(-0.7, 0.4, -0.6), _mat(Color(0.35, 0.28, 0.18), 0.1, 0.8), null, _cage).name = "Crate"
	_cable = _box(Vector3(0.05, 1.0, 0.05), Vector3.ZERO, dark)

	# Terminal post beside the shaft.
	_box(Vector3(0.5, 1.3, 0.35), Vector3(2.6, 0.65, 2.0), steel, body)
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.emission_enabled = true
	_box(Vector3(0.4, 0.3, 0.05), Vector3(2.6, 1.1, 2.19), _screen_mat)

	_lamp = OmniLight3D.new()
	_lamp.position = Vector3(0, 3.2, 2.4)
	_lamp.omni_range = 14.0
	_lamp.shadow_enabled = true
	add_child(_lamp)
	_sparks = CPUParticles3D.new()
	_sparks.position = Vector3(0.3, 5.0, -1.9)
	_sparks.amount = 12
	_sparks.lifetime = 0.8
	_sparks.explosiveness = 0.8
	_sparks.spread = 70.0
	_sparks.direction = Vector3.DOWN
	_sparks.initial_velocity_min = 1.0
	_sparks.initial_velocity_max = 3.0
	_sparks.gravity = Vector3(0, -9.8, 0)
	_sparks.scale_amount_min = 0.02
	_sparks.scale_amount_max = 0.04
	var spark := SphereMesh.new()
	spark.radius = 0.5
	spark.height = 1.0
	spark.radial_segments = 4
	spark.rings = 2
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(1.0, 0.65, 0.25)
	spark.material = sm
	_sparks.mesh = spark
	add_child(_sparks)
	_hum = Sfx.loop_3d("rig", self, -10.0, 6.0)
	_apply_look()


func is_in_reach(p: Vector3, reach: float) -> bool:
	var flat := Vector2(p.x - global_position.x, p.z - global_position.z)
	return flat.length() < reach + 2.6 and absf(p.y - global_position.y) < 4.0


func prompt_text() -> String:
	return "[E] Freight elevator%s" % (" — broken" if state == State.BROKEN else "")


func get_inventories() -> Array:
	return [] if state == State.BROKEN else [cargo]


func _process(dt: float) -> void:
	if progress:
		progress.market.tick(dt)
	match state:
		State.UP:
			_t += dt
			if _t >= TRIP_TIME:
				_arrive_top()
		State.DOWN:
			_t += dt
			if _t >= TRIP_TIME:
				_t = 0.0
				state = State.READY
				var waiting: Array = []
				for key in orders:
					if not cargo.add_stack(Shop.supply_stack(key)):
						waiting.append(key)  # full cage: it comes on the next trip
				orders = waiting
				Sfx.play_3d("place", global_position + Vector3.UP, get_parent(), 2.0, 0.6)
				_apply_look()
	# The cage rides the shaft; the cable stretches above it.
	var h := 0.0
	if state == State.UP:
		h = _ease(_t / TRIP_TIME) * CAGE_TRAVEL
	elif state == State.DOWN:
		h = (1.0 - _ease(_t / TRIP_TIME)) * CAGE_TRAVEL
	_cage.position.y = 0.35 + h
	var top := SHAFT_HEIGHT
	var cable_len := maxf(top - (_cage.position.y + 1.1), 0.05)
	_cable.scale.y = cable_len
	_cable.position = Vector3(0, _cage.position.y + 1.1 + cable_len * 0.5, 0)
	_cable.visible = _cage.position.y + 1.1 < top
	if _hum:
		var moving := state == State.UP or state == State.DOWN
		if moving != _hum.playing:
			_hum.playing = moving


static func _ease(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


func _arrive_top() -> void:
	var total := 0
	var parts: Array[String] = []
	for i in cargo.slots.size():
		var s = cargo.slots[i]
		if s and progress.market.sells(s["id"]):
			var got: int = progress.market.sell(s["id"], s["count"])
			total += got
			parts.append("%d %s" % [s["count"], Items.name_of(s["id"])])
			cargo.slots[i] = null
	cargo.changed.emit()
	progress.credits += total
	_last_sale = ("Sold %s for %d credits" % [", ".join(parts), total]) if total > 0 else "Nothing sold"
	sold.emit(total)
	state = State.DOWN
	_t = 0.0


func send_up() -> void:
	if state != State.READY:
		return
	state = State.UP
	_t = 0.0
	Sfx.play_3d("place", global_position + Vector3.UP, get_parent(), 2.0, 0.5)
	_apply_look()


func repair(player) -> void:
	if state == State.BROKEN and Inventory.pay(player.cost_sources(), REPAIR_COST):
		state = State.READY
		Sfx.play_3d("place", global_position + Vector3.UP * 2.0, get_parent(), 4.0, 0.8)
		player._flash("Elevator repaired")
		_apply_look()


func _apply_look() -> void:
	var broken := state == State.BROKEN
	for p in _broken_parts:
		p.visible = broken
	for p in _fixed_parts:
		p.visible = not broken
	_sparks.emitting = broken
	var c := Color(1.0, 0.2, 0.1) if broken else Color(0.35, 1.0, 0.5)
	_screen_mat.albedo_color = c
	_screen_mat.emission = c
	_screen_mat.emission_energy_multiplier = 2.0
	_lamp.light_color = Color(1.0, 0.4, 0.25) if broken else Color(1.0, 0.85, 0.6)
	_lamp.light_energy = 0.8 if broken else 1.8
	var crate := _cage.get_node_or_null("Crate")
	if crate:
		crate.visible = state == State.UP or state == State.DOWN


# --- Terminal ------------------------------------------------------------------------

func ui_build(box: VBoxContainer, player) -> void:
	box.add_child(UI.label("FREIGHT ELEVATOR", 26, ACCENT))
	if state == State.BROKEN:
		box.add_child(UI.label("Broken. Repair it to sell to the surface.", 16))
		var can := Inventory.can_afford(player.cost_sources(), REPAIR_COST)
		box.add_child(UI.button("Repair — %s" % Items.describe(REPAIR_COST), repair.bind(player), can))
		return
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var credits := UI.label("Credits  %d" % progress.credits, 20, Color(1.0, 0.85, 0.45))
	credits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(credits)
	for t in 2:
		var b := UI.button(["Cargo", "Shop"][t], func(): _tab = t)
		b.custom_minimum_size = Vector2(100, 32)
		b.add_theme_color_override("font_color", ACCENT if _tab == t else DIM)
		if _tab == t:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.16, 0.14, 0.11)
			sb.border_color = ACCENT
			sb.border_width_bottom = 2
			b.add_theme_stylebox_override("normal", sb)
			b.add_theme_stylebox_override("hover", sb)
		head.add_child(b)
	box.add_child(head)
	box.add_child(UI.label(_status_line(), 15, DIM))
	if _tab == 0:
		_ui_cargo(box, player)
	else:
		_ui_shop(box, player)


func _status_line() -> String:
	match state:
		State.UP:
			return "Going up — %ds" % ceili(TRIP_TIME - _t)
		State.DOWN:
			return "%s · coming down — %ds" % [_last_sale, ceili(TRIP_TIME - _t)]
	return _last_sale if _last_sale != "" else "Load the cage, then send it up."


func _ui_cargo(box: VBoxContainer, player) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(UI.button("Send up", send_up, state == State.READY))
	row.add_child(UI.button("Load all ore", func():
		for src in player.cost_sources():  # backpack first, then containers nearby
			cargo.pull_ore_from(src), state == State.READY))
	box.add_child(row)
	# Prices, two columns, with which way each last moved.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	for id in progress.market.BASE:
		var tr: int = progress.market.trend[id]
		var arrow := "▲" if tr > 0 else ("▼" if tr < 0 else "·")
		var col := Color(0.5, 0.95, 0.55) if tr > 0 else (Color(1.0, 0.5, 0.4) if tr < 0 else DIM)
		var l: Label = UI.label("%s  %d  %s" % [Items.name_of(id), progress.market.price(id), arrow], 14, col)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF  # wrapping in a grid squashes it to one letter wide
		l.custom_minimum_size.x = 160
		grid.add_child(l)
	box.add_child(grid)


## Three short sections, each a two-column grid so the whole shop fits on screen.
func _ui_shop(box: VBoxContainer, player) -> void:
	var g := _section(box, "UPGRADES")
	for id in Shop.BLUEPRINTS:
		var d: Dictionary = Shop.BLUEPRINTS[id]
		var owned: bool = progress.blueprints.has(id)
		_shop_cell(g, d["name"], d["desc"], "Owned" if owned else "%d" % d["price"],
			not owned and progress.credits >= d["price"], _buy_blueprint.bind(id, player))
	g = _section(box, "LOOKS")
	for id in Shop.COSMETICS:
		var d: Dictionary = Shop.COSMETICS[id]
		var owned: bool = d["price"] == 0 or progress.owned_cosmetics.has(id)
		var using: bool = Shop.style(progress, d["slot"]) == id
		var label := "Using" if using else ("Use" if owned else "%d" % d["price"])
		_shop_cell(g, d["name"], "", label, not using and (owned or progress.credits >= d["price"]), _buy_cosmetic.bind(id))
	g = _section(box, "SUPPLIES — next cage down")
	for key in Shop.SUPPLIES:
		var d: Dictionary = Shop.SUPPLIES[key]
		var pending := orders.count(key)
		_shop_cell(g, d["name"] + (" ×%d" % pending if pending > 0 else ""), "", "%d" % d["price"],
			progress.credits >= d["price"], _order.bind(key))


func _section(box: VBoxContainer, title: String) -> GridContainer:
	box.add_child(UI.label(title, 14, ACCENT))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 4)
	box.add_child(g)
	return g


func _shop_cell(g: GridContainer, text: String, tip: String, button: String, enabled: bool, action: Callable) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.x = 262
	row.add_theme_constant_override("separation", 6)
	var l := UI.label(text, 14)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.clip_text = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(l)
	var b := UI.button(button, action, enabled)
	b.custom_minimum_size = Vector2(70, 28)
	b.add_theme_font_size_override("font_size", 14)
	b.tooltip_text = tip
	row.add_child(b)
	g.add_child(row)


func _buy_blueprint(id: String, player) -> void:
	var price: int = Shop.BLUEPRINTS[id]["price"]
	if progress.blueprints.has(id) or progress.credits < price:
		return
	progress.credits -= price
	progress.blueprints[id] = true
	player.apply_blueprints()
	Sfx.play("scan", player, -6.0, 1.4)


func _buy_cosmetic(id: String) -> void:
	var d: Dictionary = Shop.COSMETICS[id]
	if not (d["price"] == 0 or progress.owned_cosmetics.has(id)):
		if progress.credits < d["price"]:
			return
		progress.credits -= d["price"]
		progress.owned_cosmetics[id] = true
	progress.cosmetics[d["slot"]] = id
	get_tree().call_group("cosmetic_listeners", "apply_cosmetics")


func _order(key: String) -> void:
	var price: int = Shop.SUPPLIES[key]["price"]
	if progress.credits < price:
		return
	progress.credits -= price
	orders.append(key)


func get_state() -> Dictionary:
	return {"state": state, "t": _t, "cargo": cargo.to_data(), "orders": orders.duplicate(), "sale": _last_sale}


func apply_state(s: Dictionary) -> void:
	state = s.get("state", State.BROKEN)
	_t = s.get("t", 0.0)
	cargo.from_data(s.get("cargo", []))
	orders = s.get("orders", []).duplicate()
	_last_sale = s.get("sale", "")
	if is_inside_tree():
		_apply_look()


# --- Helpers -------------------------------------------------------------------------

static func _mat(c: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = roughness
	return m


func _box(size: Vector3, pos: Vector3, m: Material, collide_in: StaticBody3D = null, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	(parent if parent else self).add_child(mi)
	if collide_in:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.position = pos
		collide_in.add_child(cs)
	return mi
