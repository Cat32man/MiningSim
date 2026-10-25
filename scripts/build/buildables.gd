extends RefCounted
## Everything the player can place with the build menu (Q).

const Items = preload("res://scripts/items/items.gd")

const POLE := "pole"
const GENERATOR := "generator"
const BENCH := "bench"
const CHARGER := "charger"
const STORAGE := "storage"
const SHREDDER := "shredder"
const REFINERY := "refinery"
const STORAGE_LARGE := "storage_large"
const BEACON := "beacon"
const SCAN_TABLE := "scan_table"
const SCAN_TOWER := "scan_tower"

## Menu order, per build-menu tab.
const ORDER := [POLE, GENERATOR, BENCH, CHARGER, STORAGE, REFINERY, STORAGE_LARGE, BEACON, SCAN_TABLE, SCAN_TOWER]
const STRUCTURE_ORDER := ["foundation", "floor", "wall", "half_wall", "window", "door", "ramp", "ladder",
	"catwalk", "lamp"]

## radius = footprint used for overlap checks when placing.
## mount = "floor" (flat ground, R spins it), "wall" (steep rock, R tilts it), "snap" (structure
## pieces on the 2 m grid, R turns 90°) or "surface" (any rock or building face).
const DEFS := {
	POLE: {
		"name": "Power pole",
		"desc": "Carries power 20 m.",
		"cost": {Items.IRON: 4},
		"radius": 0.4,
		"mount": "floor",
		"hp": 60.0,
		"bite_radius": 0.5,
		"script": "res://scripts/build/pole.gd",
	},
	GENERATOR: {
		"name": "Electrum generator",
		"desc": "Burns electrum. 30 kW.",
		"cost": {Items.IRON: 30, Items.ELECTRUM: 10},
		"radius": 1.3,
		"mount": "floor",
		"hp": 160.0,
		"bite_radius": 1.3,
		"script": "res://scripts/build/generator.gd",
	},
	BENCH: {
		"name": "Crafting bench",
		"desc": "Crafts batteries and upgrades. 15 kW.",
		"cost": {Items.IRON: 25},
		"radius": 1.2,
		"mount": "floor",
		"hp": 120.0,
		"bite_radius": 1.2,
		"script": "res://scripts/build/bench.gd",
	},
	CHARGER: {
		"name": "Battery charger",
		"desc": "Charges 2 batteries. 20 kW each.",
		"cost": {Items.IRON: 20, Items.ELECTRUM: 8},
		"radius": 0.8,
		"mount": "floor",
		"hp": 100.0,
		"bite_radius": 0.8,
		"script": "res://scripts/build/charger.gd",
	},
	STORAGE: {
		"name": "Storage container",
		"desc": "24 slots.",
		"cost": {Items.IRON: 20},
		"radius": 1.3,
		"mount": "floor",
		"hp": 140.0,
		"bite_radius": 1.3,
		"script": "res://scripts/build/storage.gd",
	},
	"foundation": {
		"name": "Foundation",
		"desc": "Flat base, 2×2 m.",
		"cost": {Items.IRON: 6},
		"radius": 0.0,
		"mount": "snap",
		"hp": 300.0,
		"bite_radius": 1.0,
		"script": "res://scripts/build/structure.gd",
	},
	"floor": {
		"name": "Floor",
		"desc": "Floor or ceiling, 2×2 m.",
		"cost": {Items.IRON: 3},
		"radius": 0.0,
		"mount": "snap",
		"hp": 200.0,
		"bite_radius": 1.0,
		"script": "res://scripts/build/structure.gd",
	},
	"wall": {
		"name": "Wall",
		"desc": "2×2 m.",
		"cost": {Items.IRON: 4},
		"radius": 0.0,
		"mount": "snap",
		"hp": 220.0,
		"bite_radius": 0.6,
		"script": "res://scripts/build/structure.gd",
	},
	"half_wall": {
		"name": "Half wall",
		"desc": "2×1 m.",
		"cost": {Items.IRON: 2},
		"radius": 0.0,
		"mount": "snap",
		"hp": 140.0,
		"bite_radius": 0.6,
		"script": "res://scripts/build/structure.gd",
	},
	"window": {
		"name": "Window wall",
		"desc": "2×2 m with an opening.",
		"cost": {Items.IRON: 3},
		"radius": 0.0,
		"mount": "snap",
		"hp": 160.0,
		"bite_radius": 0.6,
		"script": "res://scripts/build/structure.gd",
	},
	"door": {
		"name": "Door",
		"desc": "Opens for you. Bugs chew it first.",
		"cost": {Items.IRON: 5},
		"radius": 0.0,
		"mount": "snap",
		"hp": 90.0,
		"bite_radius": 0.6,
		"script": "res://scripts/build/structure.gd",
	},
	"ramp": {
		"name": "Ramp",
		"desc": "Climbs one level.",
		"cost": {Items.IRON: 4},
		"radius": 0.0,
		"mount": "snap",
		"hp": 200.0,
		"bite_radius": 1.0,
		"script": "res://scripts/build/structure.gd",
	},
	"ladder": {
		"name": "Ladder",
		"desc": "Climb without stamina.",
		"cost": {Items.IRON: 2},
		"radius": 0.0,
		"mount": "snap",
		"hp": 60.0,
		"bite_radius": 0.4,
		"script": "res://scripts/build/structure.gd",
	},
	"catwalk": {
		"name": "Catwalk",
		"desc": "Railed walkway, 2×2 m.",
		"cost": {Items.IRON: 3},
		"radius": 0.0,
		"mount": "snap",
		"hp": 120.0,
		"bite_radius": 1.0,
		"script": "res://scripts/build/structure.gd",
	},
	"lamp": {
		"name": "Wall lamp",
		"desc": "Lights an outpost. 1 kW.",
		"cost": {Items.IRON: 3, Items.ELECTRUM: 1},
		"radius": 0.3,
		"mount": "surface",
		"hp": 40.0,
		"bite_radius": 0.4,
		"script": "res://scripts/build/lamp.gd",
	},
	REFINERY: {
		"name": "Materials refinery",
		"desc": "Refines steel and obsidianite. 30 kW.",
		"cost": {Items.IRON: 60, Items.ELECTRUM: 20, Items.OBSIDIAN: 4},
		"radius": 1.4,
		"mount": "floor",
		"hp": 180.0,
		"bite_radius": 1.3,
		"requires": "refinery_unlocked",
		"locked_hint": "Find obsidian",
		"script": "res://scripts/build/refinery.gd",
	},
	# Shop blueprints ("bp:" = bought at the elevator).
	STORAGE_LARGE: {
		"name": "Large container",
		"desc": "48 slots.",
		"cost": {Items.IRON: 45},
		"radius": 1.3,
		"mount": "floor",
		"hp": 200.0,
		"bite_radius": 1.3,
		"requires": "bp:storage_large",
		"locked_hint": "Elevator shop",
		"script": "res://scripts/build/storage_large.gd",
	},
	BEACON: {
		"name": "Respawn beacon",
		"desc": "Respawn at the beacon nearest your body.",
		"cost": {Items.IRON: 30, Items.ELECTRUM: 10},
		"radius": 0.6,
		"mount": "floor",
		"hp": 100.0,
		"bite_radius": 0.6,
		"requires": "bp:beacon",
		"locked_hint": "Elevator shop",
		"script": "res://scripts/build/beacon.gd",
	},
	SCAN_TABLE: {
		"name": "Scanning table",
		"desc": "3D map of the caves. Tags big veins.",
		"cost": {Items.IRON: 150, Items.STEEL: 20, Items.OBSIDIANITE: 5, Items.ELECTRUM: 300},
		"radius": 1.2,
		"mount": "floor",
		"hp": 160.0,
		"bite_radius": 1.1,
		"script": "res://scripts/build/scan_table.gd",
	},
	SCAN_TOWER: {
		"name": "Scanning tower",
		"desc": "Steadies the map near it.",
		"cost": {Items.IRON: 15, Items.ELECTRUM: 20, Items.DIAMOND: 5},
		"radius": 0.6,
		"mount": "floor",
		"hp": 90.0,
		"bite_radius": 0.6,
		"script": "res://scripts/build/scan_tower.gd",
	},
	# Not in the build menu: deployed by throwing the item (G).
	SHREDDER: {
		"name": "SHREDDER-MK1",
		"desc": "Strips an ore vein into its hopper.",
		"cost": {},
		"radius": 0.4,
		"mount": "thrown",
		"hp": 80.0,
		"bite_radius": 0.6,
		"script": "res://scripts/build/shredder.gd",
	},
}


static func make(id: String) -> Node3D:
	var b: Node3D = load(DEFS[id]["script"]).new()
	b.build_id = id
	b.max_hp = DEFS[id]["hp"]
	b.hp = b.max_hp
	b.bite_radius = DEFS[id]["bite_radius"]
	return b
