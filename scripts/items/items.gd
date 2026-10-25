extends RefCounted
## Item definitions. Ore items map 1:1 to terrain materials that drop when mined.

const Materials = preload("res://scripts/world/materials.gd")

const IRON := "iron"
const ELECTRUM := "electrum"
const DIAMOND := "diamond"
const BATTERY := "battery"
const SHREDDER := "shredder"
const COBALT := "cobalt"
const THERMAL_SUIT := "thermal_suit"
const OBSIDIAN := "obsidian"
const COAL := "coal"
const STEEL := "steel"
const OBSIDIANITE := "obsidianite"
const CROOKED_CLAW := "crooked_claw"
const SILICON := "silicon"
const MICROCHIP := "microchip"

## Battery energy: 20 kW for 5 minutes (10 kW lasts 10 minutes, and so on).
const BATTERY_CAPACITY := 20.0 * 300.0  # kJ

const DEFS := {
	# Weights: ~250 iron before you're overweight, so both slots and weight matter.
	IRON: {"name": "Iron", "short": "Fe", "weight": 0.6, "stack": 50, "color": Color(0.62, 0.36, 0.22)},
	ELECTRUM: {"name": "Electrum", "short": "El", "weight": 0.4, "stack": 50, "color": Color(0.9, 0.75, 0.38)},
	DIAMOND: {"name": "Diamond", "short": "Di", "weight": 0.2, "stack": 50, "color": Color(0.75, 0.92, 1.0)},
	COBALT: {"name": "Cobalt", "short": "Co", "weight": 0.5, "stack": 50, "color": Color(0.25, 0.42, 0.95)},
	OBSIDIAN: {"name": "Obsidian", "short": "Ob", "weight": 0.8, "stack": 50, "color": Color(0.32, 0.2, 0.45)},
	COAL: {"name": "Coal", "short": "C", "weight": 0.4, "stack": 50, "color": Color(0.3, 0.3, 0.32)},
	# Refined (materials refinery).
	STEEL: {"name": "Steel", "short": "St", "weight": 1.0, "stack": 50, "color": Color(0.66, 0.71, 0.78)},
	OBSIDIANITE: {"name": "Obsidianite", "short": "Obn", "weight": 0.5, "stack": 50, "color": Color(0.6, 0.3, 0.9)},
	# Silicon caves: silicon comes only from the harvester; microchips from the chip printer.
	SILICON: {"name": "Silicon", "short": "Si", "weight": 0.3, "stack": 50, "color": Color(0.92, 0.78, 0.45)},
	MICROCHIP: {"name": "Microchip", "short": "Chip", "weight": 0.1, "stack": 50, "color": Color(0.25, 0.65, 0.4)},
	# Boss trophy: the Magma Hydra's claw, made into the crooked dagger at the bench.
	CROOKED_CLAW: {"name": "Crooked claw", "short": "Claw", "weight": 2.0, "stack": 1, "color": Color(0.86, 0.76, 0.56)},
	# Worn in the suit slot (kept on death).
	THERMAL_SUIT: {"name": "Thermal suit", "short": "Suit", "weight": 6.0, "stack": 1, "color": Color(0.85, 0.5, 0.25)},
	BATTERY: {"name": "Battery", "short": "Bat", "weight": 8.0, "stack": 1, "color": Color(0.35, 0.8, 0.45)},
	# Throwable vein miner (G). Charges in a battery charger like a battery.
	SHREDDER: {"name": "SHREDDER-MK1", "short": "Shr", "weight": 10.0, "stack": 1, "color": Color(0.95, 0.6, 0.15)},
}

## Terrain material -> item id for ore that goes into your inventory.
const FROM_MATERIAL := {Materials.IRON: IRON, Materials.ELECTRUM: ELECTRUM, Materials.DIAMOND: DIAMOND,
	Materials.COBALT: COBALT, Materials.OBSIDIAN: OBSIDIAN, Materials.COAL: COAL}


static func name_of(id: String) -> String:
	return DEFS[id]["name"] if DEFS.has(id) else id


static func new_battery(energy := 0.0) -> Dictionary:
	return {"id": BATTERY, "count": 1, "energy": energy}


static func new_shredder(energy := 0.0) -> Dictionary:
	return {"id": SHREDDER, "count": 1, "energy": energy}


## {"iron": 10, ...} -> "10 Iron, ..."
static func describe(cost: Dictionary) -> String:
	if cost.is_empty():
		return "nothing"
	var parts: Array[String] = []
	for id in cost:
		parts.append("%d %s" % [cost[id], name_of(id)])
	return ", ".join(parts)
