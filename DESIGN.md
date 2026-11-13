# MiningSim — Design Document

Working title. Pitch: **Satisfactory + Deep Rock Galactic.** A first-person mining and
automation game in one enormous persistent underground world. You start with a pickaxe
and flares, work up through hand drills to piloted rigs and finally automated
extractors, while bug pressure grows with everything you take from the rock.

Status legend: **[D]** decided with the user · **[P]** placeholder pick, open to change ·
**[L]** deliberately left for later.

---

## 1. Pillars

1. **Digging feels good.** Smooth destructible terrain, readable ore, satisfying tools.
2. **Your factory is out in the world, not behind a wall.** Machines break and must be
   visited; you cannot AFK in a base.
3. **Greed has a price.** The more you mine and the further you push, the harder the
   world pushes back.
4. **Semi-realistic look.** [D] Grounded materials, real lighting and darkness, believable
   machinery — not cartoony, not photoreal.

## 2. Structure

- **Persistent world, Minecraft-style, multiple save slots.** [D]
- **Single-player first; co-op is a "maybe later".** [D] Engineering rule from day one:
  *every* terrain change goes through one `apply_edit(op)` function that takes a small,
  replayable operation (e.g. "carve sphere r=1.5 at x,y,z"). Co-op later ships these
  ops as deltas — late joiners get a save snapshot then the op stream.
- **Story:** [L]. Seed already in the design: the rare *ruined elevators* mean someone
  was down here before you.

## 3. World

- **Underground slab with a bedrock ceiling.** [D] Bedrock is unmineable, thick, and has
  a safety volume behind it that returns anyone who gets through.
- **Enormous central area** around the drop pod. [D]
- **Difficulty gradient:** bugs and hazards get harder the further *out* and the
  *deeper* you go. [D] This keeps players in the central area without hard walls.
- **World edge:** rock eventually becomes too hard to drill. [P]
- **Biomes** are placed randomly but trend later-game with distance and depth. [D]

| Biome | Notes |
|---|---|
| Normal rock | Start area. Iron, electrum. |
| Hard rock | Slower digging. Diamond. [P] |
| Sand | Silicon. Loose/collapsing sand as a small, contained hazard. [P] |
| Fire | Heat damage, lava pockets. Obsidian. |
| Water | Oxygen matters here. [D] Flooding hazard. [P] |
| Thick coral (sub-biome) | Dense, maze-like growth. |
| Tarland | Oil. Toxic gas pockets. [P] |
| More | [L] |

Cave-ins were **cut** as too complicated. [D] Digging risk comes from biome hazards instead.

## 4. Player

- **First-person, human miners** (explicitly *not* dwarves). [D]
- **Starting kit:** pickaxe, flares, flashlight. [D]
- **Slots:** miner, weapon, offhand. One extra miner slot and one extra weapon slot can be
  unlocked; offhand never doubles. [D] Weapon slots start locked or allow a second tool
  until combat ramps. [P]
- **Health** regenerates slowly out of combat. [D]
- **Oxygen** only in water areas (maybe tarland gas). [D]/[P]
- **Backpack:** high but finite capacity, weight-based (iron heavy, silicon light). [D]/[P]

### Tools

- **Pickaxe** — slow, free, precise; stays useful for gem-grade work and quiet mining. [P]
- **Hand drill** — first upgrade. Three upgrade tracks of 5 tiers each: **speed, size,
  fuel**. [D] Refuel at the spawn drop pod; fuel lines and refuel stations come later
  (beta). [D]
- **Flares** — limited count, slow recharge (DRG-like). [P]
- **Later:** scanner (also finds ruined elevators), more tools. [L]

## 5. Resources and economy

| Resource | Role | Phase |
|---|---|---|
| Electrum | Early power — cheap, common, weak | Early |
| Iron | Core building material | Early–mid (very valuable) |
| Silicon | Computers | Early–mid |
| Diamond | Tool upgrades and builds | Early–mid |
| Oil (refined) | Mid power | Mid |
| Obsidian | Fire biome; obsidian-diamond compound → ultra-hard tools/weapons | Mid–late |
| Gold | Late computers/automation; low value — the natural thing to sell | Late |
| Esoteric power | [L] | Late |

**Keep or sell:** [D] buy an **elevator** with credits, send resources up for credits.
Credits buy cosmetics and advanced or optional blueprints. Whether "advanced"
blueprints are ever *required* is still open (if so, selling is mandatory). [P: optional]

### Elevators [D]

- Fixed elevators at the start area.
- **Ruined elevators** — rare, found mid-game (scanner pings [P]), repaired with rare
  parts + iron [P].
- **Place-anywhere elevators** late game; these need power. [P]

## 6. Machines and automation

- **Early–mid:** big mining machines you **pilot**. [D]
- **Later:** automated extractors — you still **aim** them. [D] Still to decide: what
  stops them (distance, fuel, hard rock), where ore goes (internal storage vs a
  conveyor that follows), and whether their tunnels are buildable space. [P: they stop
  on fuel/hard rock and leave usable tunnels]
- **Power chain:** electrum → refined oil → esoteric. [D]
- **Machines break.** [D] Triggers: bug damage, biome hazards, visible wear — **not**
  random failures. [P] Repairs cost resources and require you to be there.
- **Building on voxel terrain:** foundations flatten a footprint; buildings can never
  clip into bedrock. [P]/[D]

### Building pieces [D]

Walls, floors, doors and other structural pieces, so outposts can be closed off and defended. [D]

- **Pieces** [P]:
  - Floors and foundations, 3×3 m. A foundation flattens rock under itself.
  - Walls, 3×3 m: half-height and window variants.
  - Doors: open for you, closed to bugs.
  - Ramps and stairs, ladders, catwalks with railings, pillars, ceiling panels.
  - Wall lamps: they draw a little power and keep an outpost lit.
- **Placement** [P]:
  - The first piece goes freely on rock. Further pieces snap to edges on a 3 m grid (Valheim/Satisfactory style).
  - Pieces may overlap rock but never bedrock.
  - R rotates; X removes with a full refund (overflow drops as a cache).
- **Cost:** iron. Reinforced (later) variants use better materials. [P]
- **Defence:** every piece has HP. Bugs that can't reach you or a machine chew through the nearest wall or door, and doors are weaker than walls. Repairs cost iron. Walls buy time but never make a base safe. [P]

### Scanning table [D]

The step between the fire caves and the next biome.

- **Scanning table** (150 iron, 20 steel, 5 microchips, 300 electrum): [E] opens a 3D hologram map of the caves on a CRT screen, like Deep Rock's terrain scanner. Drag to turn it, right-drag or WASD to move, R/F up and down, wheel to zoom.
- **Signal:** the map is steady within 64 m of the table. Further out it swims, tears and drops out, until it's all noise about 260 m past the steady zone.
- **Scanning tower** (15 iron, 20 electrum, 5 diamond): a cheap relay mast. The map is steady within 48 m of each tower, so a chain of towers maps further out.
- **Tags:** large hidden ore veins, and the signal of the **silicon caves**, the next biome. It's deep and 420–520 m out, at a fixed spot per world. The biome itself comes later.

### Silicon caves [D]

- **Where:** one huge dune cavern, deep (about y −130 to −170) and 420–520 m out, at the spot the scanning table tags. Two long tunnels lead back toward the spawn. Walking in unlocks the harvester and chip printer blueprints.
- **Silicon sand:** golden and shimmering, in a ~7 m bed under the dunes, over sandstone. Hand tools and Shredders can't take it.
- **Silicon harvester** (120 iron, 30 steel, 8 obsidianite, 40 electrum): a drivable bore about 1.5 wall pieces tall. [E] climbs on top: WASD drives, Space angles the cut down into the sand, Tab opens its cargo, E gets off. It cuts sand only (rock stops it), burns coal (one per 12 s of work), and sifts silicon into its hopper. The walls it leaves behind are dull plain sand.
- **The Seal / THE ARBITER:** a sandstone chamber off the far side of the silicon caves, one tunnel in, four pillars, a great round sealed door in the back wall. THE ARBITER wakes when you step in: a floating hooded machine with a green visor, energy blades along its forearms and green wisps. Moves: charged dash (green line on the floor; dodge so it hits a pillar and it's stunned, taking 1.5× damage), blade slash up close, volleys of small fast bursts, and a slow homing bomb with a 4.5 m blast. Below half health: three-dash chains (glowing pips over its head count the dashes; the triple has a long charge-up), faster fire. It keeps to where you are looking, and its dashes stop short of you. At zero it flees through the Seal and drops **Advanced plating** (needed for the microchip printer). Shows on the scan as THE SEAL once you've found the silicon caves.
- **Combat upgrades (bench):** Max health (100→225 HP), Med-gel (regen 4→13 HP/s), Pistol power (14→38), Pistol cooling (45→90 %/s), Shotgun power (7→19 per pellet), Shotgun cells (12→26), SMG power (7→14.5). Costs climb iron/electrum → steel/cobalt → obsidianite → microchips and plating.
- **Laser SMG (bench, weapon 6):** full auto, 7 damage, its own heat gauge (~33 shots before overheating).
- **Suits (bench, each built on a thermal suit so they all keep out the heat):** worn in the suit slot.
  - **Tank:** an armor pool (50→140) that halves every hit; when it's empty hits do 4/3 damage. Regenerates after 3 s without being hit (2→8/s).
  - **Scout:** Shift in midair dashes the way you're moving (1→3 dashes, recharge 4→1.5 s each).
  - **Engineer:** B swaps the number keys to a build hotbar (4→10 slots; right-click parts in the build menu to pin them) and longer build reach (8→14 m).
- **Microchip printer** (60 iron, 15 steel, 30 electrum, 1 advanced plating, 40 kW): a 1×2-piece CNC bed, half a piece tall. 4 silicon + 2 electrum + 1 steel → 1 microchip, 20 s. What microchips unlock comes next.
- **Boss lairs** only show on the scan after you've been to the fire caves.

## 7. Bugs and threat

- DRG-style bugs. Rare early, escalating **exponentially**, forcing upgrades toward the end. [D]
- **Threat is local and driven by progression,** not time: [D]
  - *tier* — best material ever refined (step jumps);
  - *area mined* — volume of rock removed in that area (steady climb);
  - *distance/depth baseline* — the world gradient from §3.
- Automated drills raise area threat while you are away — ties breakdowns to danger.
  Automation threat may need a cap. [P]
- Biome-specific bug types. [P] Warning signs (tremors, sounds) instead of a meter. [P]
- Threat can be held back by clearing hives but never really drops. [P]
- Possible set-piece swarm when reaching a new tier. [P]

## 8. Death and recovery [D]

- Death drops your inventory into your **body**, which stays where you fell and never
  despawns. Walk back to recover it.
- **Loot never moves.** Up to **3 bodies** exist; a 4th death crumbles the oldest and its
  loot is lost. The oldest body is clearly marked ("next death destroys this").
- **Recovery is take-all.** You can't open, browse, or deposit into a body. If your
  backpack is full, the overflow stays in the body.
- Bodies settle into **static, non-colliding markers** — no stacking, no climbing.
- **Death triggers a bug swarm.** It hunts near your body first, then spills to nearby
  machines if you're slow. [D]/[P]
- **Death is never free fast travel:** swarm + respawn cost + post-respawn debuff. [D]
- Respawn at the drop pod, plus buildable respawn beacons mid-game. [P]
- Philosophy: harmless weirdness may stay exploitable (it's free marketing); only
  save-breaking exploits get closed.

## 9. Tech

- **Engine: Godot 4.5.x.** Familiar, open, good enough lighting for semi-realistic.
- **Terrain:** density-field voxels (1 m samples, 16³ chunks) meshed with **surface
  nets** for smooth DRG-like rock. The prototype uses our own GDScript mesher behind
  `VoxelWorld.apply_edit()`; it can be swapped for the godot_voxel module (Zylann)
  later without touching gameplay code.
- Generation and meshing run on `WorkerThreadPool`. Chunk data arrays are copy-on-write,
  so workers mesh consistent snapshots while the main thread keeps editing.
- **Factory simulation** (later) runs in a data-oriented layer, not one node per belt
  item; move hot paths to C#/GDExtension when needed.
- **Saves:** seed + modified chunks per slot.

## 10. Milestones

- **M0 — Dig prototype (this build):** streaming voxel caves, bedrock ceiling, spawn
  cavern with drop pod, FPS controller, pickaxe, hand drill with fuel and pod refuel,
  flashlight, flares, iron + electrum ore, weight-based backpack, deposit at pod, HUD.
- **M1 (built):** 3 save slots with title menu, pause menu and 5-minute autosave; pickaxe-only
  start, hand drill built at the pod (15 iron, 10 electrum); drill speed/size/fuel tracks,
  tiers 3–5 cost diamond; hard-rock biome (2.6× harder) with diamond, further out and
  deeper; ore scanner (Q, 32 m, markers through rock); strata plates give caverns flat
  floors, tunnels cut through as ramps.
- **M2a (built):** build menu (tap Q; LMB place, R rotate, RMB cancel, X remove with full
  refund). Power poles (20 m reach) and machines (12 m) auto-connect with drawn cables into
  networks; per-network supply vs demand, overload = every machine slows to supply/demand.
  Electrum generator (30 kW max, burns 1 electrum per 25 s at full load, idle = free),
  crafting bench (15 kW, crafts batteries), battery charger (20 kW, 2 slots, 30 s charge),
  storage containers (+400). Pod stash capped at 150; storage is one shared pool. Building
  and crafting pay from backpack first, then stash. Drill upgrades no longer cost electrum.
  Keys: Q tap build / hold scan; F tap flare / hold flashlight.
- **Hard rock gate (built):** hard rock is impenetrable until you craft a one-time bench
  upgrade — *Diamond-tipped drill* (40 iron, 15 electrum, 3 diamond; needs the drill) for
  the hand drill, *Rig diamond bore head* (60 iron, 20 electrum, 5 diamond) for the rig. The
  pickaxe never cuts it. Diamonds also appear rarely in normal rock (~0.45%, a bit more with
  depth) so the first tip is reachable. The diamond drill skin shows once the tip is crafted.
- **M2b (built):** mining rig from the build menu (60 iron, 20 electrum). E to drive
  (third-person), W/S/A/D, mouse aims the bore ±43° down / 34° up for ramps, LMB bores a
  4.8 m tunnel. One battery: entering swaps in your best charged battery (old one to your
  backpack, 8 kg each); ~50 s of boring per battery. 300-unit hopper unloads into the stash
  when you exit near the pod or a storage container.
- **M3 (built, first pass):**
  - Slots: 1 pickaxe, 2 drill (melee 20 dps — poor), 3 laser shotgun (main: 8 pellets × 7,
    12 charges, +1 per 15 s, refilled at the pod), 4 laser pistol (offhand: 14 dmg, heat,
    overheats and vents). Both weapons available from the start for now.
  - Health 100, regen 4/s after 6 s unhurt. Death: backpack drops into a body where you
    fell (not solid, never moves, max 3, oldest crumbles with its loot), take-all recovery
    with E, scanner pings bodies. Respawn at the pod, drill tank emptied, "shaken" (half max
    health) for 60 s. No death swarm yet.
  - Swarmer bug (30 HP, bite 8): wanders, notices you within 16 m, chases and scrambles up
    walls; no pathfinding. Spawns alone (no swarms yet) out of sight 14–24 m away.
  - Local threat per 32 m region = distance/300 + depth/220 + dug samples/3000 + tool tier.
    Spawn roll every ~25 s with chance threat×1.5 (min 8%); live-bug cap 1 + (2·threat)².
    HUD shows Calm / Low / Elevated / High / Extreme.
  - All sounds synthesised in code (scripts/audio/sfx.gd): electric generator hum, drill,
    pickaxe, footsteps, lasers, bugs, flares, scanner, build clunks, rig, cave ambience.
  - Q while placing exits build mode entirely.
- **Inventory + machines refactor (built):**
  - Valheim-style backpack: 32 slots (ore stacks 50, batteries 1) + 150 kg soft cap
    (overweight = walk only: no sprint, jump or climb). Tab opens it.
  - Satisfactory-style machine slots: E on a machine shows its slots beside your backpack;
    drag, or shift-click to send across. Generator fuel slot (electrum); charger 2 battery
    slots (20 kW each); bench output + battery slots; wall drill battery + 6 output slots;
    storage container 24 slots; drop pod 12 slots + terminal (limited space).
  - No shared stash: building, crafting and upgrades pay from your backpack + storage
    within 15 m.
  - Batteries hold 6000 kJ (20 kW × 5 min; 10 kW lasts 10 min). Any machine with a battery
    slot runs off it for whatever the grid can't supply — no generator needed.
  - Goods never teleport: removing a building drops its contents (and refund overflow) as a
    cache; bodies and caches are take-all with E.
  - **Wall drill** replaced the drivable rig: mounts on a steep rock face (R tilts ±45° in
    15° steps), its arm extends 0.2 m/s boring a 3 m tunnel, 8 m long + 6 m per iron
    extension (15 iron, +10 each). 25 kW. Stops at hard rock without diamond bore heads.
    Old rigs in saves convert to a cache (hopper + battery + build cost).
- **SHREDDER-MK1 (built, replaces the wall drill):**
  - **Making and charging:** crafted at the bench (30 iron, 12 electrum). It's an item with its own 6000 kJ charge and charges in a battery charger.
  - **Shredding:** G throws it, and it clamps onto rock where it lands. It finds the ore cell it touched and strips every connected cell of that ore within reach (26-neighbour flood fill, nearest first) into a 6-slot hopper. It leaves vein-shaped hollows and doesn't touch the surrounding rock. It draws 10 kW while working (a full charge lasts 10 minutes). A cutting beam, dust and flying ore chips show the work.
  - **Collecting:** E takes the ore, and also picks the Shredder up once it's done or idle. X picks it up at any time.
  - **Risk:** it has 80 HP, raiders target it because it's running, and shredding adds local threat like any digging.
  - **Bench upgrades** (one model, applied to every Shredder):
    - Reach: 3 / 4.5 / 6 / 8 m.
    - Rate: 1 / 1.6 / 2.5 / 4 ore per second.
    - Upgrade costs: 25 iron, then 45 iron + 2 diamond, then 70 iron + 5 diamond.
    - Diamond teeth (40 iron, 4 diamond) let it eat diamond veins.
  - **Old saves:**
    - Wall drills become a cache holding their contents plus their build and extension cost.
    - Diamond bore heads carry over as diamond teeth.
- **Cobalt + thermal suit (built):**
  - **Cobalt** is a deep-blue ore with hexagonal crystals. It grows only in hard rock (~3% of it), so you reach it with the diamond tip or a Shredder.
  - **Thermal suit:** crafted at the bench (20 iron, 18 cobalt, 6 electrum) and worn in the new **suit slot** shown above the backpack (shift-click to equip).
  - **Death:** worn gear, like tools and weapons, stays with you; only the backpack drops.
  - **What it does:** `heat_protected()` is ready, but there's nothing hot yet. The magma biome comes next.
- **Fire caves + materials refinery (built):**
  - **Fire caves:** hot pockets past hard rock (biome score > 1.15 and heat noise; the nearest are ~150 m out and deep).
    - The rock is basalt, which isn't diamond-gated, with orange lava veins that glow and slowly pulse (rock shader emission; the glow travels in vertex colour alpha).
    - Embers drift up through the air, and fog and ambient light turn warm.
  - **Heat:** without a thermal suit you get 3 s of "Too hot", then 6 HP/s burns. With the suit you're fine.
  - **Ores:**
    - **Obsidian** (scarce, glassy violet-black shards).
    - **Coal** (plentiful, matte, no crystals).
  - **Materials refinery:**
    - **Unlock:** picking up your first obsidian unlocks the blueprint. Until then it shows as a locked silhouette ("??? · Find obsidian") in the build menu.
    - **Cost:** 60 iron, 20 electrum, 4 obsidian. Runs at 30 kW on grid power or its battery.
    - **Use:** pick a recipe. It runs on its own while its 4 input slots hold enough and its 2 output slots have room. "Load ingredients" and "Take output" buttons, glowing crucible window, chimney smoke.
    - **Recipes:**
      - **Steel:** 2 iron + 1 coal, 6 s.
      - **Obsidianite:** 1 obsidian + 20 diamond, 30 s.
  - **Next:** what steel and obsidianite upgrade.
- **Magma Hydra boss (built, placeholder model):**
  - **Where:** a **boss arena** in each 128 m cube whose hashed arena centre lands in the fire caves.
    - **Shape:** a 40 m dome with a flat, guarded floor, 4 basalt pillars for cover, and 3 tunnels out into the surrounding caves. Generated by the terrain generator, so it's part of the world.
    - **Fire everywhere:** the whole arena counts as fire cave (rock and heat).
    - **Light:** a flickering warm light hangs in it while you're within 60 m.
    - **Scanner:** pings LAIR / LAIR (cleared) within 200 m.
  - **Crooked claw → Crooked dagger:** the hydra drops a Crooked claw. The bench turns it into the Crooked dagger (claw + 4 steel + 2 obsidian, a one-time unlock), weapon slot 5.
    - **Damage:** 110 per stab (one-shots a swarmer) every 0.5 s.
    - **Reach:** ~1.5 m. Melee measures reach to big bugs' bodies (`melee_point`), so you can stab the hydra up close.
  - **Waking:** the hydra wakes when you step onto the arena floor, rising on the far side with a roar, and FIGHT.wav fades in (cave ambience ducks).
  - **Staying put:** it never leaves the arena; at its edge it holds and keeps spitting. Get 50 m from the arena and it goes back to sleep, ready again when you return. The boss bar is top centre, with a damage trail.
  - **Stats:** 1400 HP, 3 m tall, serpentine with a spined hood, scythe arms and a glowing belly.
  - **Attacks:**
    - Keeps ~9 m away, spitting volleys of 3 burning spines (9 dmg, slight lead) when it can see you.
    - Scythe slash for 24 up close.
    - Below 50% it enrages: roars, calls 4 swarmers, fires 5-spine volleys and moves faster.
  - **Ending the fight:**
    - **Kill it:** it drops a cache (10 obsidian, 15 diamond, 12 cobalt), and the lair stays beaten (saved).
- **Bugs, second pass (built):**
  - **Swarms.** Each spawn roll (~25 s) sends a group of 1 + threat×(2–5) bugs, capped by the live-bug cap. A group of 3+ is announced by a rumble ~4 s before it arrives, and groups come straight for you.
  - **Raids.** 35% of rolls go for a machine within 45 m instead, preferring ones that are running. Raiders bite the machine until it breaks, then move to the next one within 25 m, then come for you. They turn on you if you come within 7 m or shoot them.
  - **Breakdowns.** Machines have HP (pole 60 … generator 160). At 0 HP a machine breaks: it smokes and sparks, drops out of its network (cables go), and does nothing. E repairs it for 1 iron per 15 missing HP, from your backpack plus nearby storage. HUD alerts show "under attack" and "broke down" with distance.
  - **Death swarm.** Dying leaves 3 + threat×4 bugs (max 10) guarding your body. They appear when you come within 45 m and lurk within 5 m of it. After 3 min they drift off to wreck the nearest machine. Saved with the game.
  - **Gnawer** (second bug): 140 HP, slow, bites hard and chews machines (22 per bite). From Elevated threat it appears in groups, and it leads raids.
- **M3 next:** more bug types (spitter, burrower), hives, biome bugs.
- **M3.5 — building pieces (built, first pass):**
  - **Menu:** a Structure tab in the build menu (number keys, 0 for the 10th). All pieces cost iron:
    - foundation 6 (2×2, 1 m thick, overlaps rock);
    - floor/ceiling 3, wall 4, half wall 2, window wall 3;
    - door 5: two pocket panels that slide open when you're near;
    - ramp 4: climbs one level;
    - ladder 2: climbing it uses no stamina;
    - catwalk 3: grating with rails;
    - wall lamp: 3 iron + 1 electrum, 1 kW, sticks to any rock or piece face.
  - **Snapping:** pieces snap to the 2 m grid of the nearest structure within 5 m, and the first piece starts a new grid. Cells hold floors and ramps, edges hold walls and doors, and ladders sit in front of an edge on your side. Aiming at a wall top or face puts a floor or ceiling there, and aiming at a floor puts a wall on its nearest edge. R turns a piece 90° (ramp direction, door and window facing). A slot can only be filled once, never in bedrock or where you're standing.
  - Machines can stand on floors.
  - **HP:** foundation 300, wall 220, door 90, ladder 60, and so on. A bug blocked by a piece chews it instead of climbing over it, and at 0 HP the piece is destroyed (debris, no refund). E repairs a damaged piece with iron; X removes it with a full refund. Pieces are never raid targets.
  - **Not yet:** pillars, reinforced variants, structural support (floors don't need anything under them), and foundations don't flatten rock.
- **M4 (built, first pass):**
  - **Freight elevator** in the spawn cavern. It starts broken: repair it for 60 iron and 25 electrum.
    - **Selling:** load the 12-slot cargo cage ("Load all ore" helps) and Send up. The cage rides the shaft for 12 s each way. At the top, everything sellable goes to the market; credits come back, and the rest stays in the cage.
    - **Orders:** supply orders ride down with the next cage. Nothing teleports.
  - **Market:** each item has a base price (iron 2, electrum 3, coal 2, cobalt 8, diamond 12, obsidian 15, steel 9, obsidianite 380).
    - **Drift:** every 30 s prices take a random step (±6%), pulled back toward base.
    - **Flooding:** each unit sold drops its price 0.4% (floor 35%), so it pays to sell a mix.
    - The terminal shows prices with ▲/▼ trends.
  - **Shop (credits, all optional):**
    - **Upgrades:** backpack +8 slots (400), flare pouch +2 (250), and the large container (600, 48 slots) and respawn beacon (800) blueprints. With a beacon you respawn at the one nearest your body.
    - **Looks:** cable and lamp colours.
    - **Supplies:** iron, electrum, coal and charged batteries at ~3× base, delivered by the cage.
  - **HUD:** credits show in the top right once you have any.
  - **Shredder hop legs** (bench: 6 steel, 20 iron) instead of a separate extractor. When a vein is done, the Shredder jumps (60 kJ) to the nearest exposed cell of the same ore within 10 m and starts again.
- Later: more biomes, oil chain, ruined elevators, co-op via op deltas, story.

## 11. Open questions

1. ~~Advanced blueprints required?~~ Optional (decided in M4).
2. ~~Automated extractor?~~ Shredder hop legs; ore stays in its hopper.
3. Exact respawn cost and debuff.
4. Flares: recharge vs crafted.
5. Story, setting, and ending.

## Co-op (in progress)
- Step 1 (done): local co-op on one PC over ENet bound to 127.0.0.1. Host: Esc → "Open to co-op". Join: title screen → "Join co-op". Players see each other (helmet + headlamp avatars) and all digging is shared; edits for chunks a player hasn't loaded wait and replay when they load (saved as `net_edits`).
- Step 2 (done): buildings. Each has a `net_id`; joiners ask the host to place/remove and the host tells everyone. The host runs power and every machine and sends changed machine states (contents, health, position, power) 10×/s. A joiner's copy only mirrors them, so anything that differs from the host's last copy is the joiner's doing (items moved, craft started, harvester driven) and goes back to the host. The drop pod's storage syncs the same way.
- Step 3 (done): bugs and bosses. The host runs them all and each one goes for the closest living player (a joiner's avatar on the host stands in for them; bites/slashes on it are sent to that joiner). Joiners see copies that follow the host's 15×/s (bosses also send their attack state, so dash warnings and the bomb show); hits on a copy go to the host's. Projectiles are sent as events and every player's copy only hurts that player. Joiners get the boss bar, music and the boss's loot.
- Step 5 (done): shared progress, elevator, caches. Progress (unlocks, tiers, credits; not the Engineer hotbar or the market) is host-owned; a joiner's change is sent as before/after and merged (unlocks OR'd, tiers max, credit deltas added). The market syncs host→joiners every 3 s. The joiner's elevator is a puppet (no trips/market ticking of its own). Caches and bodies get ids; joiners ask the host to create them (death body, dropped piles) and the host shares contents and removals. The bug spawner rolls around a random living player each time (out of that player's sight); death-swarm guards wake for whichever player comes near; joiner deaths add their swarm on the host.
- Step 6 (done): bosses wake when any player steps into a lair and only sleep again when every player is past the leash; joiners' directors run in puppet mode (just the Seal door and lair glow around them). Each copy has a player id (user://coop.cfg, sent with the join handshake; PROTOCOL 2). Joiners send their state (backpack, equipment, position) to the host every 3 s; the host keeps it under that id in its save ("coop_players") and hands it back on rejoin.
- Step 4 (done): online (desktop builds). Host: Esc → "Open to co-op" listens on UDP 24680 on every network; joiners type the host's address on the title screen (remembered). Traffic is DTLS-encrypted; joiners pin the build's certificate, and the host lets in only players who sign a random challenge with the build's secret (HMAC-SHA256, plus PROTOCOL). The key lives in scripts/net/coop_key.gd, made by scripts/tools/make_coop_key.gd and git-ignored (the repo is public), so only builds made from the user's copy can play together. Over the internet the host needs UDP 24680 forwarded (or a relay on the user's server, not set up).
- Relay (server/relay.py, systemd unit server/miningsim-relay.service, UDP 24690 control + 24691-24694 one join port per hosted game): the host's game keeps a UDP tunnel to the relay (addresses in the private key file's RELAY list), registers with an HMAC of the shared secret, and shows "Join: <public ip>:<port>" in the Esc menu. Friends type that; their packets are passed through untouched (still DTLS end to end). Installed on the user's server (home.olympus) at /opt/miningsim-relay, secret in /etc/miningsim-relay/secret. For friends outside the house the Verizon router must forward UDP 24690-24694 to the server, like Valheim's 2456-2457.
- Web builds (GitHub Pages) can't use this: browsers have no UDP/ENet, and a key inside a public web build is readable by anyone.
- Next: shared progress.

## Updates
- Version: `application/config/version` in project.godot (an integer, bump it per release). Shown on the title screen.
- A release only changes the game-data pack, never the engine, so an update is the whole pack (~2.6 MB). `tools/release.sh` exports every build, packs the update (`--export-pack "macOS"`, which has all desktop texture formats) with scripts/tools/make_update.gd, and uploads `update-<v>.bin` + `manifest.json` to /var/www/miningsim on the server. The relay serves that folder over plain HTTP on TCP 24690 (same port number as its UDP control port; the Verizon rule forwards both).
- Releasing is automatic on push: tools/git-hooks/pre-push (enabled with `git config core.hooksPath tools/git-hooks`, per clone) runs tools/release.sh when a push to main carries a config/version newer than the server's manifest and the tree is clean. release.sh also force-pushes the public web build to gh-pages (after checking the key isn't in it). A failed release never blocks the push. `SKIP_RELEASE=1 git push` skips it.
- Update files are AES-256-CBC encrypted + HMAC-SHA256 with keys derived from the co-op secret (the pack contains the key). Wrong/altered files are refused.
- The Updates autoload (scripts/update/updates.gd) checks on the title screen (exported builds only), saves the pack as user://update/game.pck, and offers Restart; at start-up it loads that pack over the built-in one if it's newer than the build and for the same engine version. A Godot upgrade needs new full builds (the title screen says so).

## Graphics
- Path tracing: the user's GodotPathTrace GDExtension (C:\projects\GodotPathTrace, Rust) in addons/pathtrace, Light mode (screen-space path-traced GI, works with the changing caves) as a Compositor effect on the WorldEnvironment. Off by default; Esc menu toggle, remembered in user://settings.cfg. Windows only: the DLL is git-ignored and copied from GodotPathTrace/target/release by tools/release.sh; Mac/Linux/Web presets exclude addons/pathtrace and the option is hidden where the class doesn't exist. Since v6 the DLL is packed inside the game data (Windows preset, and the macOS preset that makes update packs, include addons/pathtrace/bin/*.dll; there's no .gdextension in the project). scripts/pathtrace_loader.gd, called first in main._ready (not an autoload: updates can't add autoloads), copies it to user://pathtrace/ beside a generated .gdextension and loads it with GDExtensionManager. So the Windows build is one file and updates deliver the DLL (update packs are ~6.5 MB).
- Path tracing has three settings (Esc menu, cycles): Off, Light (screen-space bounce light, ~53 fps at 3440x1440), Heavy (the ChronosEngine-derived BVH tracer over a 28 m snapshot around the player, re-captured after moving 3 m or digging; every omni/spot light sampled with shadows; bugs, other players and the viewmodel are in group pt_skip and drawn by the normal render; ~26 fps at 1 bounce/1 spp). Rock uses PT_ROCK as its snapshot colour and borrows the raster hue.
- F11 toggles fullscreen anywhere.
