extends SceneTree
## Top-down biome maps for checking biome sizes:
##   godot --headless --path . --script res://scripts/tools/biome_map.gd -- <out prefix> [seed]
## Writes <prefix>_y<depth>.png (1200 m square around spawn, 4 m per pixel) for a few depths.
## Grey normal, dark grey hard rock, orange fire, yellow silicon, white dot spawn.

const Gen = preload("res://scripts/world/terrain_generator.gd")
const SIZE := 300
const STEP := 4.0
const COLORS := {0: Color(0.45, 0.43, 0.4), 1: Color(0.22, 0.22, 0.24), 2: Color(0.95, 0.4, 0.1), 3: Color(0.95, 0.85, 0.35)}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://biomes"
	var gen = Gen.new(int(args[1]) if args.size() > 1 else 1337)
	for y in [-40, -100, -150]:
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		var counts := {0: 0, 1: 0, 2: 0, 3: 0}
		for j in SIZE:
			for i in SIZE:
				var x := (i - SIZE / 2) * STEP
				var z := (j - SIZE / 2) * STEP
				var b: int = gen.biome(x, y, z)
				counts[b] += 1
				img.set_pixel(i, j, COLORS[b])
		img.fill_rect(Rect2i(SIZE / 2 - 2, SIZE / 2 - 2, 4, 4), Color.WHITE)
		img.save_png("%s_y%d.png" % [prefix, -y])
		var n := float(SIZE * SIZE)
		print("y=%d  normal %d%%  hard %d%%  fire %d%%  silicon %d%%" % [y, roundi(counts[0] / n * 100),
			roundi(counts[1] / n * 100), roundi(counts[2] / n * 100), roundi(counts[3] / n * 100)])
	quit()
