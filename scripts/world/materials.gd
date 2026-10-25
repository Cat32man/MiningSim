extends RefCounted
## Single source of truth for terrain materials: look, hardness, and what you get from mining.

const ROCK := 0
const IRON := 1
const ELECTRUM := 2
const BEDROCK := 3
const HARD_ROCK := 4
const DIAMOND := 5
const COBALT := 6  # hard-rock ore: thermal suit
const BASALT := 7  # fire-cave rock, with glowing cracks
const OBSIDIAN := 8  # fire-cave ore: unlocks the refinery
const COAL := 9  # fire-cave ore: steel

const NAMES := ["Rock", "Iron", "Electrum", "Bedrock", "Hard rock", "Diamond", "Cobalt", "Basalt", "Obsidian", "Coal"]

## Vertex tint.
const COLOR := [
	Color(0.40, 0.37, 0.34),  # rock
	Color(0.52, 0.27, 0.15),  # iron
	Color(0.80, 0.68, 0.36),  # electrum
	Color(0.09, 0.09, 0.10),  # bedrock
	Color(0.24, 0.26, 0.30),  # hard rock: cold blue-grey
	Color(0.82, 0.90, 0.96),  # diamond
	Color(0.16, 0.30, 0.82),  # cobalt: deep blue
	Color(0.15, 0.12, 0.11),  # basalt: near-black, warm
	Color(0.10, 0.07, 0.14),  # obsidian: glassy violet-black
	Color(0.06, 0.06, 0.06),  # coal: matte black
]

## Shader inputs (sent as UV2): metallic sheen, and crystal glints.
const METALLIC := [0.0, 0.45, 0.8, 0.0, 0.0, 0.0, 0.7, 0.0, 0.0, 0.0]
const GLINT := [0.0, 0.6, 1.0, 0.0, 0.15, 1.0, 0.8, 0.05, 1.0, 0.25]

## Lava glow in cracks (rock shader emission, sent as 1 - vertex colour alpha).
const GLOW := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0]

## Dig strength is divided by this. 0 = cannot be mined.
const HARDNESS := [1.0, 1.0, 0.9, 0.0, 2.6, 1.8, 1.6, 1.4, 2.2, 0.8]

## Only diamond-tipped tools (edit op "diamond": true) can cut these at all.
const NEEDS_DIAMOND := [false, false, false, false, true, false, false, false, false, false]

## Mined samples of these go into the backpack.
const COLLECTIBLE := [false, true, true, false, false, true, true, false, true, true]

## Backpack kilograms per mined sample.
const WEIGHT := [0.0, 1.5, 1.0, 0.0, 0.0, 0.5, 1.2, 0.0, 0.8, 0.4]
