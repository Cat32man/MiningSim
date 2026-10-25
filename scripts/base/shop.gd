extends RefCounted
## What credits buy at the elevator terminal. Everything here is optional: nice to have,
## never required to progress.

const Items = preload("res://scripts/items/items.gd")

## One-time purchases. Blueprints unlock a buildable ("bp:<id>" in buildables.gd).
const BLUEPRINTS := {
	"backpack_plus": {"name": "Backpack extension", "desc": "+8 backpack slots", "price": 400},
	"flare_pouch": {"name": "Flare pouch", "desc": "+2 flares", "price": 250},
	"storage_large": {"name": "Large container", "desc": "Blueprint: 48 slots", "price": 600},
	"beacon": {"name": "Respawn beacon", "desc": "Blueprint: respawn near your body", "price": 800},
}

## Looks. Buy once, then switch freely within the same slot.
const COSMETICS := {
	"cable_black": {"name": "Black cables", "slot": "cable", "price": 0, "color": Color(0.08, 0.08, 0.08)},
	"cable_orange": {"name": "Orange cables", "slot": "cable", "price": 150, "color": Color(0.85, 0.42, 0.06)},
	"cable_blue": {"name": "Blue cables", "slot": "cable", "price": 150, "color": Color(0.12, 0.3, 0.8)},
	"lamp_warm": {"name": "Warm lamps", "slot": "lamp", "price": 0, "color": Color(1.0, 0.86, 0.66)},
	"lamp_cool": {"name": "Cool white lamps", "slot": "lamp", "price": 100, "color": Color(0.82, 0.9, 1.0)},
	"lamp_green": {"name": "Green lamps", "slot": "lamp", "price": 100, "color": Color(0.5, 1.0, 0.55)},
}
const DEFAULT_COSMETIC := {"cable": "cable_black", "lamp": "lamp_warm"}

## Delivered by the next cage down, at about three times the market's base price.
const SUPPLIES := {
	"iron": {"name": "20 Iron", "price": 120, "id": Items.IRON, "count": 20},
	"electrum": {"name": "10 Electrum", "price": 90, "id": Items.ELECTRUM, "count": 10},
	"coal": {"name": "10 Coal", "price": 60, "id": Items.COAL, "count": 10},
	"battery": {"name": "Charged battery", "price": 150, "id": Items.BATTERY, "count": 1},
}


static func supply_stack(key: String) -> Dictionary:
	var s: Dictionary = SUPPLIES[key]
	if s["id"] == Items.BATTERY:
		return Items.new_battery(Items.BATTERY_CAPACITY)
	return {"id": s["id"], "count": s["count"]}


## Chosen style id for a cosmetic slot.
static func style(progress, slot: String) -> String:
	if progress == null:
		return DEFAULT_COSMETIC[slot]
	return progress.cosmetics.get(slot, DEFAULT_COSMETIC[slot])


static func color(progress, slot: String) -> Color:
	return COSMETICS[style(progress, slot)]["color"]
