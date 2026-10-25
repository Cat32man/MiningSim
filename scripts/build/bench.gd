extends "res://scripts/build/building.gd"
## Crafting bench: pays from your backpack + nearby storage, works while powered (grid or
## its battery slot), and puts finished items in its output slots.

const Sfx = preload("res://scripts/audio/sfx.gd")
const RecipeGrid = preload("res://scripts/ui/recipe_grid.gd")

const DEMAND_KW := 15.0

const RECIPES := {
	"battery": {
		"model": "battery",
		"name": "Battery",
		"desc": "Stores 6000 kJ.",
		"cost": {Items.IRON: 10, Items.ELECTRUM: 6},
		"time": 5.0,
		"item": Items.BATTERY,
	},
	# One-time upgrades: applied to progress on completion instead of producing an item.
	"diamond_tip": {
		"model": "drill",
		"name": "Diamond-tipped drill",
		"desc": "Hand drill cuts hard rock.",
		"cost": {Items.IRON: 40, Items.ELECTRUM: 15, Items.DIAMOND: 3},
		"time": 12.0,
		"upgrade": "diamond_tip",
		"requires": "drill_owned",
	},
	"shredder": {
		"model": "shredder",
		"name": "SHREDDER-MK1",
		"desc": "Throw (G) onto ore to strip the vein.",
		"cost": {Items.IRON: 30, Items.ELECTRUM: 12},
		"time": 10.0,
		"item": Items.SHREDDER,
	},
	"thermal_suit": {
		"model": "thermal_suit",
		"name": "Thermal suit",
		"desc": "Shrugs off extreme heat.",
		"cost": {Items.IRON: 20, Items.COBALT: 18, Items.ELECTRUM: 6},
		"time": 20.0,
		"item": Items.THERMAL_SUIT,
	},
	"crooked_dagger": {
		"model": "dagger",
		"name": "Crooked dagger",
		"desc": "Huge damage, tiny reach. Weapon 5.",
		"cost": {Items.CROOKED_CLAW: 1, Items.STEEL: 4, Items.OBSIDIAN: 2},
		"time": 15.0,
		"upgrade": "dagger_owned",
	},
	"shredder_hop": {
		"model": "shredder_hop",
		"name": "Shredder hop legs",
		"desc": "Shredders jump to the next vein.",
		"cost": {Items.STEEL: 6, Items.IRON: 20},
		"time": 15.0,
		"upgrade": "shredder_hop",
	},
	"shredder_diamond": {
		"model": "shredder_teeth",
		"name": "Shredder diamond teeth",
		"desc": "Shredders eat diamond veins.",
		"cost": {Items.IRON: 40, Items.DIAMOND: 4},
		"time": 15.0,
		"upgrade": "shredder_diamond",
	},
	# Tiered: cost and name come from progress (see _recipe()).
	"shredder_reach": {"model": "shredder_up", "name": "Shredder reach", "track": "reach", "time": 10.0, "unit": "m"},
	"shredder_rate": {"model": "shredder_up", "name": "Shredder rate", "track": "rate", "time": 10.0, "unit": "ore/s"},
}

const ROMAN := ["I", "II", "III", "IV", "V"]

var output_inv = Inventory.new(4, "Output")
var crafting := ""
var craft_t := 0.0
var _whir: AudioStreamPlayer3D


func _init() -> void:
	cable_anchor = Vector3(-0.9, 1.6, -0.35)
	battery_inv = Inventory.new(1, "Battery", [Items.BATTERY])


func _build_visuals() -> void:
	var top := mat(Color(0.3, 0.31, 0.33), 0.7, 0.5)
	var leg := mat(Color(0.22, 0.22, 0.24), 0.8, 0.45)
	var paint := mat(Color(0.75, 0.5, 0.12), 0.4, 0.55)
	box(Vector3(2.0, 0.08, 0.9), Vector3(0, 0.95, 0), top)
	for x in [-0.92, 0.92]:
		for z in [-0.38, 0.38]:
			box(Vector3(0.08, 0.95, 0.08), Vector3(x, 0.475, z), leg)
	box(Vector3(2.0, 0.6, 0.12), Vector3(0, 1.3, -0.4), paint)  # back panel
	box(Vector3(0.5, 0.35, 0.05), Vector3(0.5, 1.3, -0.33), glow(Color(0.35, 0.75, 1.0), 1.2))  # screen
	box(Vector3(0.35, 0.2, 0.3), Vector3(-0.5, 1.09, 0.1), leg)  # vise
	cyl(0.05, 0.6, Vector3(-0.9, 1.3, -0.35), leg)  # cable post


func _collision_shape() -> Shape3D:
	var b := BoxShape3D.new()
	b.size = Vector3(2.0, 1.6, 0.9)
	return b


func _collision_offset() -> Vector3:
	return Vector3(0, 0.8, 0)


func demand_kw() -> float:
	return DEMAND_KW if crafting != "" else 0.0


func power_tick(dt: float, satisfaction: float, _load: float) -> void:
	if _whir == null and not ghost:
		_whir = Sfx.loop_3d("hum", self, -14.0, 3.0)
		_whir.pitch_scale = 2.2
	var working := crafting != "" and satisfaction > 0.0
	if _whir and working != _whir.playing:
		_whir.playing = working
	if crafting == "":
		return
	var r := _recipe(crafting, grid.progress if grid else null)
	if r.has("item") and output_inv.used_slots() >= output_inv.slots.size():
		return  # output full: wait
	craft_t += dt * satisfaction / r["time"]
	if craft_t >= 1.0:
		if r.has("upgrade"):
			if grid and grid.progress:
				grid.progress.set(r["upgrade"], true)
		elif r.has("track"):
			if grid and grid.progress:
				var t: Dictionary = grid.progress.shredder_tiers
				t[r["track"]] = mini(t[r["track"]] + 1, grid.progress.SHREDDER_MAX_TIER)
		elif r["item"] == Items.BATTERY:
			output_inv.add_stack(Items.new_battery(0.0))
		elif r["item"] == Items.SHREDDER:
			output_inv.add_stack(Items.new_shredder(0.0))
		else:
			output_inv.add(r["item"], 1)
		crafting = ""
		craft_t = 0.0


func get_inventories() -> Array:
	return [output_inv, battery_inv]


func ui_build(box_: VBoxContainer, player) -> void:
	box_.add_child(UI.label("CRAFTING BENCH", 26, Color(1.0, 0.75, 0.4)))
	box_.add_child(UI.label(power_line() + "   ·   " + battery_line(), 14, Color(0.7, 0.7, 0.68)))
	var status := "Idle"
	if crafting != "":
		status = "Crafting %s — %d%%" % [_recipe(crafting, player.progress)["name"], roundi(craft_t * 100.0)]
		if power_ratio <= 0.0:
			status += "   ⚠ No power"
		elif power_ratio < 1.0:
			status += "   (low power: %d%%)" % roundi(power_ratio * 100.0)
	box_.add_child(UI.label(status, 17))


func ui_static(box_: VBoxContainer, player) -> void:
	var grid := RecipeGrid.new()
	grid.entries_fn = _entries.bind(player)
	grid.on_pick = func(id: String): _craft(id, player)
	box_.add_child(grid)


## Recipe cards: click one to craft it.
func _entries(player) -> Array:
	var out: Array = []
	var sources: Array = player.cost_sources()
	for id in RECIPES:
		var r := _recipe(id, player.progress)
		var busy: bool = crafting == id
		if not busy and not available(id, player.progress):
			continue
		var state := "busy" if busy else ("can" if crafting == "" and Inventory.can_afford(sources, r["cost"]) else "cant")
		out.append({"id": id, "name": r["name"], "desc": "%s  (%s)" % [r["desc"], Items.describe(r["cost"])],
			"cost": "%s · %ds" % [RecipeGrid.short_cost(r["cost"]), roundi(r["time"])], "model": r["model"],
			"state": state, "progress": craft_t if busy else 0.0,
			"tag": "UPGRADE" if r.has("upgrade") or r.has("track") else ""})
	return out


func _craft(id: String, player) -> void:
	var cost: Dictionary = _recipe(id, player.progress)["cost"]
	if crafting == "" and not cost.is_empty() and Inventory.pay(player.cost_sources(), cost):
		crafting = id
		craft_t = 0.0


## Shown on the bench: not owned or maxed, its prerequisite met, and you've found every
## material it takes.
static func available(id: String, progress) -> bool:
	if progress == null:
		return false
	var r := _recipe(id, progress)
	if r.has("upgrade") and progress.get(r["upgrade"]):
		return false
	if r.has("track") and r["cost"].is_empty():
		return false  # maxed
	if r.has("requires") and not progress.get(r["requires"]):
		return false
	return progress.knows_all(r["cost"])


## Names of every recipe the bench would show right now (for "new recipe" notices).
static func available_names(progress) -> Dictionary:
	var out := {}
	for id in RECIPES:
		if available(id, progress):
			out[id] = _recipe(id, progress)["name"]
	return out


## A recipe with tiered upgrades resolved: "Shredder reach II", its next cost and stat.
static func _recipe(id: String, progress) -> Dictionary:
	var r: Dictionary = RECIPES[id].duplicate()
	if not r.has("track"):
		return r
	r["cost"] = {}
	r["desc"] = "Maxed"
	if progress == null:
		return r
	var track: String = r["track"]
	var tier: int = progress.shredder_tiers[track]
	r["cost"] = progress.shredder_next_cost(track)
	if not r["cost"].is_empty():
		var stats: Array = progress.SHREDDER_STATS[track]
		r["name"] = "%s %s" % [r["name"], ROMAN[tier]]
		r["desc"] = "%s → %s %s" % [str(stats[tier - 1]), str(stats[tier]), r["unit"]]
	return r


func hover_text() -> String:
	var s := "Crafting bench"
	if crafting != "":
		s += " — crafting %s %d%%" % [_recipe(crafting, grid.progress if grid else null)["name"], roundi(craft_t * 100.0)]
	return s + "\n[E] open · " + power_line()


func get_state() -> Dictionary:
	var s := super()
	s["crafting"] = crafting
	s["craft_t"] = craft_t
	return s


func apply_state(s: Dictionary) -> void:
	super(s)
	crafting = s.get("crafting", "")
	if not RECIPES.has(crafting):
		crafting = ""  # e.g. diamond bore heads, from before wall drills were replaced
	craft_t = s.get("craft_t", 0.0)
	# Saves from before machine slots: finished batteries waiting in "output".
	for i in s.get("output", {}).get("battery", 0):
		output_inv.add_stack(Items.new_battery(0.0))
