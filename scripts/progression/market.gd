extends RefCounted
## Surface market for what you send up the elevator. Every item has a base price; its
## current price drifts (a slow random walk pulled back toward base) and drops as you flood
## it, recovering over the next few minutes. So selling one ore in bulk pays less and less,
## and it's worth spreading out what you sell.

const Items = preload("res://scripts/items/items.gd")

## Credits per unit at base price.
const BASE := {
	Items.IRON: 2, Items.ELECTRUM: 3, Items.COAL: 2, Items.COBALT: 8, Items.DIAMOND: 12,
	Items.OBSIDIAN: 15, Items.STEEL: 9, Items.OBSIDIANITE: 380,
}
const STEP := 30.0  # seconds between price moves
const DRIFT := 0.06
const PULL := 0.08  # share of the gap to base closed each step
const FLOOD_PER_UNIT := 0.004
const MIN_MULT := 0.35
const MAX_MULT := 1.8

var mult := {}  # item -> current price multiplier
var trend := {}  # item -> -1 / 0 / 1, last move
var _t := 0.0


func _init() -> void:
	for id in BASE:
		mult[id] = 1.0
		trend[id] = 0


func sells(id: String) -> bool:
	return BASE.has(id)


func price(id: String) -> int:
	return maxi(1, roundi(BASE[id] * mult[id])) if BASE.has(id) else 0


func tick(dt: float) -> void:
	_t += dt
	while _t >= STEP:
		_t -= STEP
		for id in BASE:
			var old: float = mult[id]
			var m: float = old + randf_range(-DRIFT, DRIFT) + (1.0 - old) * PULL
			mult[id] = clampf(m, MIN_MULT, MAX_MULT)
			trend[id] = signi(roundi((mult[id] - old) * 100.0))


## Credits for `count` units, each one sold at the (falling) price at that moment.
func sell(id: String, count: int) -> int:
	if not BASE.has(id):
		return 0
	var total := 0
	for i in count:
		total += price(id)
		mult[id] = maxf(mult[id] - FLOOD_PER_UNIT, MIN_MULT)
	if count > 0:
		trend[id] = -1
	return total


func to_dict() -> Dictionary:
	return {"mult": mult.duplicate()}


func from_dict(d: Dictionary) -> void:
	var m: Dictionary = d.get("mult", {})
	for id in m:
		if BASE.has(id):
			mult[id] = clampf(float(m[id]), MIN_MULT, MAX_MULT)
