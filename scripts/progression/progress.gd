extends RefCounted
## Persistent progression: the hand drill, its upgrade tracks, and one-time unlocks.
## Resources live in real inventories (backpack, pod, containers); purchases pay from a
## list of them (backpack + containers near you) via Inventory.pay().

const Items = preload("res://scripts/items/items.gd")
const Inventory = preload("res://scripts/items/inventory.gd")
const Market = preload("res://scripts/progression/market.gd")

const MAX_TIER := 5
const TRACKS := ["speed", "size", "fuel"]
const TRACK_NAMES := {"speed": "Drill speed", "size": "Bore size", "fuel": "Fuel tank"}
const TRACK_UNITS := {"speed": "dig/s", "size": "m", "fuel": "L"}

## Stat per tier (index 0 = tier 1).
const STATS := {
	# Tier I is only a bit faster than the pickaxe (~2.4/s); the drill earns its keep via upgrades.
	"speed": [3.0, 4.0, 5.25, 6.75, 8.5],  # dig strength per second
	"size": [1.3, 1.5, 1.75, 2.0, 2.3],  # bore radius
	"fuel": [100.0, 140.0, 190.0, 250.0, 320.0],  # tank size
}

## You start with only a pickaxe; the hand drill is the first thing you build.
const DRILL_COST := {Items.IRON: 15, Items.ELECTRUM: 10}

## Cost to go from tier t to t+1, index t-1. Tiers 3+ need diamond. No electrum: that's for power.
const TIER_COSTS := [
	{Items.IRON: 20},
	{Items.IRON: 35, Items.DIAMOND: 2},
	{Items.IRON: 55, Items.DIAMOND: 5},
	{Items.IRON: 80, Items.DIAMOND: 10},
]

## SHREDDER-MK1 upgrade tracks (bench): how far a vein it follows, and how fast it eats it.
const SHREDDER_MAX_TIER := 4
const SHREDDER_TRACKS := ["reach", "rate"]
const SHREDDER_TRACK_NAMES := {"reach": "Shredder reach", "rate": "Shredder rate"}
const SHREDDER_STATS := {
	"reach": [3.0, 4.5, 6.0, 8.0],  # metres from where it lands
	"rate": [1.0, 1.6, 2.5, 4.0],  # ore cells per second
}
const SHREDDER_TIER_COSTS := [
	{Items.IRON: 25},
	{Items.IRON: 45, Items.DIAMOND: 2},
	{Items.IRON: 70, Items.DIAMOND: 5},
]

var drill_owned := false
## Bench upgrade that lets the hand drill cut hard rock.
var diamond_tip := false
## Shredders can eat diamond veins.
var shredder_diamond := false
## Blueprint unlocked by finding obsidian in the fire caves.
var refinery_unlocked := false
## Crooked dagger crafted (weapon slot 5).
var dagger_owned := false
## Shredders hop to the next vein of the same ore when they finish one.
var shredder_hop := false
## Item ids you've ever carried: recipes show up once you've found all their materials.
var discovered := {}
## Been to the fire caves (boss lairs show on the scan) / the silicon caves (harvester blueprint).
var fire_visited := false
var silicon_found := false

## Elevator economy (M4).
var credits := 0
var market = Market.new()
var blueprints := {}  # shop id -> true (one-time purchases)
var cosmetics := {}  # slot ("cable", "lamp") -> chosen style id
var owned_cosmetics := {}  # style id -> true
var tiers := {"speed": 1, "size": 1, "fuel": 1}
var shredder_tiers := {"reach": 1, "rate": 1}
var combat_tiers := {}  # COMBAT_TRACKS key -> tier (missing = 1)


## Combat upgrades (bench). Each track's stat per tier and the cost to reach the next one;
## costs climb through the materials you find: iron/electrum, steel/cobalt, obsidianite,
## then microchips and the Arbiter's plating.
const COMBAT_TRACKS := {
	"armor": {"name": "Suit armor", "unit": "HP", "stats": [100.0, 125.0, 150.0, 185.0, 225.0], "costs": [
		{Items.IRON: 30, Items.ELECTRUM: 10},
		{Items.STEEL: 10, Items.COBALT: 8},
		{Items.STEEL: 20, Items.OBSIDIANITE: 1},
		{Items.ADVANCED_PLATING: 1, Items.MICROCHIP: 4, Items.STEEL: 20}]},
	"regen": {"name": "Med-gel", "unit": "HP/s", "stats": [4.0, 6.0, 9.0, 13.0], "costs": [
		{Items.ELECTRUM: 25, Items.DIAMOND: 2},
		{Items.COBALT: 10, Items.STEEL: 6},
		{Items.MICROCHIP: 2, Items.DIAMOND: 8}]},
	"pistol": {"name": "Pistol power", "unit": "dmg", "stats": [14.0, 18.0, 23.0, 30.0, 38.0], "costs": [
		{Items.IRON: 25, Items.ELECTRUM: 15},
		{Items.STEEL: 6, Items.DIAMOND: 3},
		{Items.COBALT: 12, Items.OBSIDIANITE: 1},
		{Items.MICROCHIP: 3, Items.OBSIDIANITE: 2}]},
	"cooling": {"name": "Pistol cooling", "unit": "%/s", "stats": [45.0, 65.0, 90.0], "costs": [
		{Items.IRON: 20, Items.ELECTRUM: 20},
		{Items.COBALT: 10, Items.STEEL: 5}]},
	"shotgun": {"name": "Shotgun power", "unit": "dmg/pellet", "stats": [7.0, 9.0, 11.5, 15.0, 19.0], "costs": [
		{Items.IRON: 30, Items.ELECTRUM: 15},
		{Items.STEEL: 8, Items.DIAMOND: 4},
		{Items.COBALT: 14, Items.OBSIDIANITE: 1},
		{Items.MICROCHIP: 3, Items.OBSIDIANITE: 2}]},
	"cells": {"name": "Shotgun cells", "unit": "charges", "stats": [12.0, 16.0, 20.0, 26.0], "costs": [
		{Items.IRON: 30, Items.ELECTRUM: 20},
		{Items.STEEL: 8, Items.COBALT: 6},
		{Items.OBSIDIANITE: 1, Items.DIAMOND: 8}]},
}


func combat_stat(track: String) -> float:
	return COMBAT_TRACKS[track]["stats"][combat_tiers.get(track, 1) - 1]


## Empty when the track is maxed.
func combat_next_cost(track: String) -> Dictionary:
	var costs: Array = COMBAT_TRACKS[track]["costs"]
	var t: int = combat_tiers.get(track, 1)
	return costs[t - 1] if t - 1 < costs.size() else {}


func stat(track: String) -> float:
	return STATS[track][tiers[track] - 1]


func next_stat(track: String) -> float:
	return STATS[track][mini(tiers[track], MAX_TIER - 1)]


## Empty when the track is maxed.
func next_cost(track: String) -> Dictionary:
	if tiers[track] >= MAX_TIER:
		return {}
	return TIER_COSTS[tiers[track] - 1]


func shredder_stat(track: String) -> float:
	return SHREDDER_STATS[track][shredder_tiers[track] - 1]


## Empty when the track is maxed.
func shredder_next_cost(track: String) -> Dictionary:
	if shredder_tiers[track] >= SHREDDER_MAX_TIER:
		return {}
	return SHREDDER_TIER_COSTS[shredder_tiers[track] - 1]


func buy_drill(sources: Array) -> bool:
	if drill_owned or not Inventory.pay(sources, DRILL_COST):
		return false
	drill_owned = true
	return true


func upgrade(track: String, sources: Array) -> bool:
	var cost := next_cost(track)
	if not drill_owned or cost.is_empty() or not Inventory.pay(sources, cost):
		return false
	tiers[track] += 1
	return true


## True once every item in `cost` has been found.
func knows_all(cost: Dictionary) -> bool:
	for id in cost:
		if not discovered.has(id):
			return false
	return true


static func describe(cost: Dictionary) -> String:
	return Items.describe(cost)


func to_dict() -> Dictionary:
	return {"drill_owned": drill_owned, "diamond_tip": diamond_tip, "shredder_diamond": shredder_diamond,
		"refinery_unlocked": refinery_unlocked,
		"dagger_owned": dagger_owned,
		"shredder_hop": shredder_hop,
		"discovered": discovered.duplicate(),
		"fire_visited": fire_visited,
		"silicon_found": silicon_found,
		"credits": credits,
		"market": market.to_dict(),
		"blueprints": blueprints.duplicate(),
		"cosmetics": cosmetics.duplicate(),
		"owned_cosmetics": owned_cosmetics.duplicate(),
		"tiers": tiers.duplicate(), "shredder_tiers": shredder_tiers.duplicate(),
		"combat_tiers": combat_tiers.duplicate()}


func from_dict(d: Dictionary) -> void:
	drill_owned = d.get("drill_owned", false)
	diamond_tip = d.get("diamond_tip", false)
	# Diamond bore heads (wall drill, now gone) carry over as diamond teeth.
	shredder_diamond = d.get("shredder_diamond", d.get("rig_diamond_head", false))
	refinery_unlocked = d.get("refinery_unlocked", false)
	dagger_owned = d.get("dagger_owned", false)
	shredder_hop = d.get("shredder_hop", false)
	# Saves from before discovery: the starting ores count as found.
	discovered = d.get("discovered", {Items.IRON: true, Items.ELECTRUM: true}).duplicate()
	# Saves from before the flag: having fire-cave ore means you've been there.
	fire_visited = d.get("fire_visited", discovered.has(Items.OBSIDIAN) or discovered.has(Items.COAL))
	silicon_found = d.get("silicon_found", false)
	credits = d.get("credits", 0)
	market.from_dict(d.get("market", {}))
	blueprints = d.get("blueprints", {}).duplicate()
	cosmetics = d.get("cosmetics", {}).duplicate()
	owned_cosmetics = d.get("owned_cosmetics", {}).duplicate()
	combat_tiers = {}
	var ct: Dictionary = d.get("combat_tiers", {})
	for track in COMBAT_TRACKS:
		if ct.has(track):
			combat_tiers[track] = clampi(int(ct[track]), 1, COMBAT_TRACKS[track]["stats"].size())
	var st: Dictionary = d.get("shredder_tiers", {})
	for track in SHREDDER_TRACKS:
		shredder_tiers[track] = clampi(st.get(track, 1), 1, SHREDDER_MAX_TIER)
	var t: Dictionary = d.get("tiers", {})
	for track in TRACKS:
		tiers[track] = clampi(t.get(track, 1), 1, MAX_TIER)
