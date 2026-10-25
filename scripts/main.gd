extends Node3D
## Game flow: title menu -> game session (terrain, drop pod, player, HUD, menus) -> menu.
##
## Command-line user args (after `--`):
##   --selftest            run terrain/dig/save checks, print results, quit
##   --screenshot=<path>   save a screenshot once the caves are ready, then quit
##   --ore=<id>            with --screenshot: frame the nearest exposed ore (1 iron, 2 electrum)

const VoxelWorld = preload("res://scripts/world/voxel_world.gd")
const DropPod = preload("res://scripts/base/drop_pod.gd")
const Elevator = preload("res://scripts/base/elevator.gd")
const ELEVATOR_POS := Vector3(9.5, -1.5, -1.0)
const Player = preload("res://scripts/player/player.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Progress = preload("res://scripts/progression/progress.gd")
const SaveSystem = preload("res://scripts/save/save_system.gd")
const MainMenu = preload("res://scripts/ui/main_menu.gd")
const TextEditor = preload("res://scripts/ui/text_editor.gd")
const Buildables = preload("res://scripts/build/buildables.gd")
const FightMusic = preload("res://assets/music/FIGHT.wav")
const MUSIC_DB := -6.0
const PauseMenu = preload("res://scripts/ui/pause_menu.gd")
const Items = preload("res://scripts/items/items.gd")
const PowerGrid = preload("res://scripts/build/power_grid.gd")
const BuildController = preload("res://scripts/build/build_controller.gd")
const BuildMenu = preload("res://scripts/ui/build_menu.gd")
const BuildingPanel = preload("res://scripts/ui/building_panel.gd")
const ScanView = preload("res://scripts/ui/scan_view.gd")
const ThreatDirector = preload("res://scripts/enemies/threat_director.gd")
const BodyMarker = preload("res://scripts/player/body_marker.gd")
const DeathScreen = preload("res://scripts/ui/death_screen.gd")
const CaveDust = preload("res://scripts/world/cave_dust.gd")
const LoadingScreen = preload("res://scripts/ui/loading_screen.gd")
const Sfx = preload("res://scripts/audio/sfx.gd")

const MAX_BODIES := 3

const SPAWN_POS := Vector3(0.0, 0.0, 5.0)
const POD_POS := Vector3(0.0, -1.5, -6.0)
const AUTOSAVE_INTERVAL := 300.0
const TEST_SLOT := 99

var world
var pod
var elevator
var _death_pos := Vector3.INF
var player
var hud
var progress
var pause_menu
var grid
var builder
var build_menu
var building_panel
var scan_view
var director
var bodies: Node3D
var death_screen
var _ambience: AudioStreamPlayer
var _drip_t := 6.0

var _menu
var _game: Node3D
## -1 = unsaved session (test modes).
var _slot := -1
var _play_time := 0.0
var _autosave_timer := 0.0

var _selftest := false
var _screenshot_path := ""
var loading_screen: CanvasLayer
var _cave_dust: Node3D
var _env: Environment
var _music: AudioStreamPlayer
var _music_tween: Tween
var _respawn_flash := false
var _shot_ore := 0
var _shot_drill := false
var _shot_inventory := false
var _shot_death := false
var _shot_hit := false
var _shot_bug
var _ready_time := -1.0
var _clock := 0.0
var _base_alert_t := -99.0
const BASE_ALERT_GAP := 20.0  # seconds between "base under attack" warnings
var _test_step := 0


func _ready() -> void:
	# 3D labels (scanner tags, bug numbers) use the same font as the UI.
	ThemeDB.fallback_font = preload("res://assets/fonts/ui_font.tres")
	# Menus and Esc handling must keep working while the game tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg == "--selftest":
			_selftest = true
		elif arg.begins_with("--screenshot="):
			_screenshot_path = arg.trim_prefix("--screenshot=")
		elif arg.begins_with("--ore="):
			_shot_ore = int(arg.trim_prefix("--ore="))
		elif arg == "--drill":
			_shot_drill = true
		elif arg == "--inventory":
			_shot_inventory = true
		elif arg == "--death":
			_shot_death = true
		elif arg == "--hit":
			_shot_hit = true

	_register_inputs()
	_make_environment()
	Sfx.preload_all()

	if OS.get_cmdline_user_args().has("--menu") and not _screenshot_path.is_empty():
		_show_menu()
		if OS.get_cmdline_user_args().has("--texteditor"):
			_open_text_editor()
		await get_tree().create_timer(1.5).timeout
		get_viewport().get_texture().get_image().save_png(_screenshot_path)
		print("Screenshot saved to ", _screenshot_path)
		get_tree().quit()
	elif OS.get_cmdline_user_args().has("--reloadtest"):
		# Load the save written by --selftest and check no chunk shows stale geometry.
		var data := SaveSystem.read(TEST_SLOT)
		if data.is_empty():
			push_error("RELOADTEST FAIL: run --selftest first")
			get_tree().quit(1)
			return
		_start_game(-1, data)
		while _ready_time < 0.0 or _clock - _ready_time < 4.0:
			await get_tree().process_frame
		var stale: int = world.stale_mesh_count()
		print("Reload: %d chunks, %d edited, stale meshes: %d" % [world.chunk_count(), data["chunks"].size(), stale])
		SaveSystem.delete(TEST_SLOT)
		print("RELOADTEST PASS" if stale == 0 else "RELOADTEST FAIL")
		get_tree().quit(0 if stale == 0 else 1)
	elif _selftest or not _screenshot_path.is_empty():
		_start_game(-1, {})
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_show_menu()


# --- Flow ---------------------------------------------------------------------

func _show_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu = MainMenu.new()
	add_child(_menu)
	_menu.new_game.connect(func(slot: int): _leave_menu(); _start_game(slot, {}))
	_menu.continue_game.connect(_on_continue)
	_menu.text_editor.connect(_open_text_editor)


## Full-screen string editor over the title screen.
func _open_text_editor() -> void:
	var ed := TextEditor.new()
	ed.closed.connect(ed.queue_free)
	add_child(ed)


func _on_continue(slot: int) -> void:
	var data := SaveSystem.read(slot)
	if data.is_empty():
		push_error("Could not read save slot %d" % slot)
		return
	_leave_menu()
	_start_game(slot, data)


func _leave_menu() -> void:
	if _menu:
		_menu.queue_free()
		_menu = null


func _start_game(slot: int, data: Dictionary) -> void:
	_slot = slot
	_play_time = data.get("play_time", 0.0)
	_autosave_timer = 0.0
	_ready_time = -1.0
	_test_step = 0

	_game = Node3D.new()
	_game.name = "Game"
	_game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_game)

	progress = Progress.new()
	if data.has("progress"):
		progress.from_dict(data["progress"])

	world = VoxelWorld.new()
	world.name = "World"
	# Test modes use a fixed seed so results are repeatable.
	world.world_seed = data.get("seed", 1337 if slot < 0 else randi())
	world.import_modified(data.get("chunks", {}))
	_game.add_child(world)

	pod = DropPod.new()
	pod.name = "DropPod"
	pod.position = POD_POS
	pod.progress = progress
	pod.storage.from_data(data.get("pod_storage", []))
	_game.add_child(pod)

	elevator = Elevator.new()
	elevator.name = "Elevator"
	elevator.progress = progress
	elevator.position = ELEVATOR_POS
	elevator.rotation.y = atan2(-ELEVATOR_POS.x, -ELEVATOR_POS.z)  # cage gate faces the cavern centre
	elevator.apply_state(data.get("elevator", {}))
	_game.add_child(elevator)
	elevator.sold.connect(func(c: int): if c > 0: player._flash("Sold for %d credits" % c))

	# Bodies and caches: items left in the world (never moved, never teleported).
	bodies = Node3D.new()
	bodies.name = "Caches"
	_game.add_child(bodies)
	_load_caches(data)

	grid = PowerGrid.new()
	grid.name = "Buildings"
	grid.progress = progress
	grid.world = world
	grid.drop_cache = drop_cache
	_game.add_child(grid)
	grid.load_state(data.get("buildings", []))
	_migrate_old_stash(data)

	hud = Hud.new()
	_game.add_child(hud)

	player = Player.new()
	player.name = "Player"
	player.position = SPAWN_POS
	player.world = world
	player.pod = pod
	player.hud = hud
	player.progress = progress
	if data.has("player"):
		player.apply_state(data["player"])
	_game.add_child(player)
	world.focus = player

	builder = BuildController.new()
	builder.player = player
	builder.grid = grid
	builder.pod = pod
	_game.add_child(builder)
	player.builder = builder

	build_menu = BuildMenu.new()
	build_menu.closed.connect(_close_ui)
	build_menu.selected.connect(func(id: String): builder.start(id); _close_ui())
	_game.add_child(build_menu)
	scan_view = ScanView.new()
	scan_view.opened.connect(_open_ui)
	scan_view.closed.connect(_close_ui)
	_game.add_child(scan_view)
	player.build_menu_requested.connect(func(): _open_ui(); build_menu.open(player))

	building_panel = BuildingPanel.new()
	building_panel.closed.connect(_close_ui)
	_game.add_child(building_panel)
	player.building_panel_requested.connect(func(b): _open_ui(); building_panel.open(b, player))
	player.pod_opened.connect(func(): _open_ui(); building_panel.open(pod, player))
	player.station_opened.connect(func(st): _open_ui(); building_panel.open(st, player))
	player.inventory_requested.connect(func(): _open_ui(); building_panel.open(null, player))

	director = ThreatDirector.new()
	director.name = "Bugs"
	director.world = world
	director.player = player
	director.progress = progress
	director.mined = data.get("threat", {}).duplicate()
	director.grid = grid
	director.load_swarms_state(data.get("death_swarms", []))
	director.wave_cd = data.get("wave_cd", 0.0)
	for k in data.get("bosses_defeated", []):
		director.bosses_defeated[k] = true
	director.boss_appeared.connect(_on_boss_appeared)
	player.director = director
	director.boss_gone.connect(_on_boss_gone)
	_game.add_child(director)
	world.carved.connect(director.on_carved)
	director.raid_started.connect(func(b): _machine_alert(b, "Bugs heading for the %s"))
	director.base_threatened.connect(_base_alert)
	grid.building_attacked.connect(func(b):
		_base_alert(b)
		if not b.is_structure:
			_machine_alert(b, "%s broke down" if b.broken else "%s under attack", b.broken))

	_mark_oldest_body()
	player.died.connect(_on_player_died)
	death_screen = DeathScreen.new()
	death_screen.respawn_pressed.connect(_on_respawn)
	_game.add_child(death_screen)

	var dust := CaveDust.new()
	dust.follow = player
	_game.add_child(dust)
	_cave_dust = dust

	loading_screen = LoadingScreen.new()
	_game.add_child(loading_screen)
	_begin_loading("ENTERING THE CAVES", "Loading the rock around you")

	_ambience = AudioStreamPlayer.new()
	_ambience.stream = Sfx.stream("ambience")
	_ambience.volume_db = -16.0
	_game.add_child(_ambience)
	_ambience.play()

	_music = AudioStreamPlayer.new()
	_music.stream = FightMusic
	_music.volume_db = -60.0
	_music.finished.connect(func(): if director.boss: _music.play())  # loop while the fight lasts
	_game.add_child(_music)

	pause_menu = PauseMenu.new()
	pause_menu.resume_pressed.connect(_resume)
	pause_menu.unstuck_pressed.connect(_on_unstuck)
	pause_menu.save_pressed.connect(func(): pause_menu.set_status("Saved." if _save_game() else "Save failed!"))
	pause_menu.save_quit_pressed.connect(func(): _save_game(); _end_game(); _show_menu())
	pause_menu.quit_desktop_pressed.connect(func(): _save_game(); get_tree().quit())
	_game.add_child(pause_menu)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _end_game() -> void:
	get_tree().paused = false
	if _game:
		_game.queue_free()
		_game = null
	world = null
	player = null


func _save_game() -> bool:
	if _slot < 0 or _game == null:
		return false
	var data := {
		"seed": world.world_seed,
		"saved_at": Time.get_unix_time_from_system(),
		"play_time": _play_time,
		"player": player.get_state(),
		"progress": progress.to_dict(),
		"chunks": world.export_modified(),
		"buildings": grid.get_state(),
		"threat": director.mined,
		"death_swarms": director.get_swarms_state(),
		"bosses_defeated": director.bosses_defeated.keys(),
		"wave_cd": director.wave_cd,
		"pod_storage": pod.storage.to_data(),
		"elevator": elevator.get_state(),
		"caches": _live_caches().map(func(b): return b.get_state()),
	}
	if death_screen.visible:
		data["player"]["pos"] = SPAWN_POS  # saved while dead: load in at the pod, alive
	return SaveSystem.write(_slot, data)


func _exit_tree() -> void:
	Sfx._cache.clear()  # static cache would otherwise be reported as leaked at exit


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and player and player.active:
		_save_game()


func _unhandled_input(event: InputEvent) -> void:
	if _game == null or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if builder.is_placing() and not get_tree().paused:
		builder.cancel()
	elif get_tree().paused:
		_resume()
	else:
		get_tree().paused = true
		pause_menu.set_status("")
		pause_menu.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume() -> void:
	pause_menu.visible = false
	get_tree().paused = false
	if not (build_menu.visible or building_panel.visible or death_screen.visible or scan_view.visible):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Drops the backpack where you fell (bodies never move), keeps at most MAX_BODIES, and
## shows the death screen; respawn happens when you press the button. The oldest body
## crumbles, with its loot, past the cap.
func _on_player_died() -> void:
	_death_pos = player.global_position
	var lines: Array[String] = []
	var dist := roundi(player.global_position.distance_to(POD_POS))
	if not player.backpack.is_empty():
		var body := BodyMarker.new()
		body.kind = "body"
		body.inv.from_data(player.backpack.to_data())
		for i in player.backpack.slots.size():
			player.backpack.slots[i] = null
		player.backpack.changed.emit()
		bodies.add_child(body)
		body.global_position = player.global_position - Vector3(0, 0.85, 0)
		lines.append("Your gear is on your body, %d m from the pod." % dist)
		var alive := _live_bodies()
		if alive.size() > MAX_BODIES:
			alive[0].queue_free()
			lines.append("Your oldest body crumbled.")
		elif alive.size() == MAX_BODIES:
			lines.append("Next death destroys your oldest body.")
	else:
		lines.append("Nothing was lost.")
	director.add_death_swarm(player.global_position)
	lines.append("Bugs are gathering at your body.")
	_mark_oldest_body()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	death_screen.show_death("\n".join(lines))


func _on_respawn() -> void:
	var beacon = _nearest_beacon(_death_pos)
	player.respawn(beacon.respawn_point() if beacon else SPAWN_POS)
	player.set_deferred("controls_enabled", true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# The pod may be far away and unloaded: freeze physics until the rock there exists.
	if beacon:
		_begin_loading("RETURNING TO THE BEACON", "Loading the rock around the beacon")
	else:
		_begin_loading("RETURNING TO THE DROP POD", "Loading the rock around the pod")
	_respawn_flash = true


## Freezes the player behind the loading screen until the caves around them are meshed;
## _process lifts it. The HUD, cave dust and held tool are hidden meanwhile.
func _begin_loading(title: String, sub: String) -> void:
	player.active = false
	hud.visible = false
	_cave_dust.visible = false
	loading_screen.show_loading(title, sub)


## The respawn beacon closest to where you died (null if none).
func _nearest_beacon(near: Vector3):
	var best = null
	var best_d := INF
	for b in grid.buildings:
		if b.build_id == "beacon" and not b.broken:
			var d: float = b.global_position.distance_to(near) if near != Vector3.INF else 0.0
			if d < best_d:
				best_d = d
				best = b
	return best


func _live_caches() -> Array:
	return bodies.get_children().filter(func(b): return not b.is_queued_for_deletion())


func _live_bodies() -> Array:
	return _live_caches().filter(func(b): return b.kind == "body")


## The oldest body is flagged once you're at the cap: the next death destroys it.
func _mark_oldest_body() -> void:
	var alive := _live_bodies()
	for i in alive.size():
		alive[i].is_oldest = i == 0 and alive.size() >= MAX_BODIES


## Leaves a pile of item stacks in the world (removed containers, refunds that didn't fit,
## converted rigs). Splits across several caches if it's a lot.
func drop_cache(pos: Vector3, stacks: Array) -> void:
	var cache = null
	for st in stacks:
		if st == null or st.get("count", 0) <= 0:
			continue
		if cache == null or not cache.inv.add_stack(st.duplicate()):
			cache = BodyMarker.new()
			cache.kind = "cache"
			bodies.add_child(cache)
			cache.global_position = pos + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
			cache.inv.add_stack(st.duplicate())


func _load_caches(data: Dictionary) -> void:
	for s in data.get("caches", []):
		var c := BodyMarker.new()
		c.kind = s.get("kind", "cache")
		c.inv.from_data(s.get("slots", []))
		c.position = s["pos"]
		bodies.add_child(c)
	# Saves from before slot inventories: bodies held {material: count} + battery charges.
	var mat_to_item := {1: Items.IRON, 2: Items.ELECTRUM, 5: Items.DIAMOND}
	for s in data.get("bodies", []):
		var b := BodyMarker.new()
		b.kind = "body"
		for m in s.get("items", {}):
			if mat_to_item.has(int(m)):
				b.inv.add(mat_to_item[int(m)], s["items"][m])
		for ch in s.get("batteries", []):
			b.inv.add_stack(Items.new_battery(float(ch) * Items.BATTERY_CAPACITY))
		b.position = s["pos"]
		bodies.add_child(b)


## Saves from before slot inventories kept one shared stash; it moves into the pod, and
## anything that doesn't fit becomes a cache beside it.
func _migrate_old_stash(data: Dictionary) -> void:
	var stash: Dictionary = data.get("progress", {}).get("stash", {})
	if stash.is_empty():
		return
	var mat_to_item := {1: Items.IRON, 2: Items.ELECTRUM, 5: Items.DIAMOND}
	var overflow: Array = []
	for m in stash:
		if not mat_to_item.has(int(m)):
			continue
		var left: int = pod.storage.add(mat_to_item[int(m)], stash[m])
		while left > 0:
			var n := mini(left, 50)
			overflow.append({"id": mat_to_item[int(m)], "count": n})
			left -= n
	if not overflow.is_empty():
		drop_cache(POD_POS + Vector3(4.0, 0.2, 3.0), overflow)


# --- Boss fight -----------------------------------------------------------------------

func _on_boss_appeared(boss: Node3D) -> void:
	player._flash(boss.BOSS_NAME)
	_fade_music(true)


func _on_boss_gone(boss: Node3D, killed: bool) -> void:
	_fade_music(false)
	hud.hide_boss()
	if killed:
		player._flash("%s slain" % boss.BOSS_NAME)
		drop_cache(boss.global_position + Vector3(0, 0.3, 0), [
			{"id": Items.CROOKED_CLAW, "count": 1},
			{"id": Items.OBSIDIAN, "count": 10}, {"id": Items.DIAMOND, "count": 15}, {"id": Items.COBALT, "count": 12}])


func _fade_music(on: bool) -> void:
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	if on:
		if not _music.playing:
			_music.volume_db = -40.0
			_music.play()
		_music_tween.tween_property(_music, "volume_db", MUSIC_DB, 1.5)
		_music_tween.parallel().tween_property(_ambience, "volume_db", -30.0, 1.5)
	else:
		_music_tween.tween_property(_music, "volume_db", -60.0, 3.0)
		_music_tween.parallel().tween_property(_ambience, "volume_db", -16.0, 3.0)
		_music_tween.tween_callback(_music.stop)


## HUD alert about a machine, at most once every few seconds per machine (bites come fast).
func _machine_alert(b: Node3D, text: String, force := false) -> void:
	var now := _clock
	if not force and now - float(b.get_meta("alert_t", -99.0)) < 8.0:
		return
	b.set_meta("alert_t", now)
	var dist := roundi(player.global_position.distance_to(b.global_position))
	player._flash("⚠ " + (text % b.display_name()) + "  (%d m)" % dist)
	Sfx.play("scan", player, -8.0, 0.7)


## Corner warning when bugs hit anything you built; at most once every BASE_ALERT_GAP.
func _base_alert(b: Node3D) -> void:
	if _clock - _base_alert_t < BASE_ALERT_GAP:
		return
	_base_alert_t = _clock
	var dist := roundi(player.global_position.distance_to(b.global_position))
	player.hud.notify("BASE UNDER ATTACK", ["%s · %d m" % [b.display_name(), dist]], Color(1.0, 0.3, 0.2))
	Sfx.play("swarm_warn", player, -6.0, 1.2)


func _on_unstuck() -> void:
	_resume()
	if player.health > 0.0:
		player._flash(player.unstuck())


func _open_ui() -> void:
	player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_ui() -> void:
	# Deferred so the key that closed the menu (E/Q) isn't seen by the player as a new press.
	player.set_deferred("controls_enabled", true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if _game == null or get_tree().paused:
		return
	_clock += delta
	if not player.active:
		loading_screen.set_progress(world.ready_fraction_around(player.global_position))
	if not player.active and world.is_ready_around(player.global_position):
		player.active = true
		hud.set_loading(false)
		hud.visible = true
		_cave_dust.visible = true
		loading_screen.finish()
		if _respawn_flash:
			_respawn_flash = false
			hud.flash_damage()  # brief red fade as you come back in
		_ready_time = _clock
		print("Caves ready after %.2fs with %d chunks" % [_clock, world.chunk_count()])
	if not player.active:
		return

	_play_time += delta
	var here: Vector3 = player.vehicle.global_position if player.vehicle else player.global_position
	player.threat_label = director.label(director.threat_at(here))
	if director.boss and is_instance_valid(director.boss):
		hud.set_boss(director.boss.BOSS_NAME, director.boss.health_ratio())
	# Fire caves: warm, ember-filled air.
	_cave_dust.heat = player.heat
	_env.volumetric_fog_albedo = Color(0.75, 0.72, 0.68).lerp(Color(0.95, 0.68, 0.5), player.heat)
	_env.ambient_light_color = Color(0.5, 0.55, 0.65).lerp(Color(0.85, 0.55, 0.4), player.heat)
	_env.ambient_light_energy = lerpf(0.05, 0.09, player.heat)
	_drip_t -= delta
	if _drip_t <= 0.0:
		_drip_t = randf_range(5.0, 15.0)
		var drip_at := here + Vector3(randf_range(-12, 12), randf_range(2, 8), randf_range(-12, 12))
		Sfx.play_3d("drip", drip_at, _game, -6.0, randf_range(0.8, 1.3))
	if _slot >= 0:
		_autosave_timer += delta
		if _autosave_timer >= AUTOSAVE_INTERVAL:
			_autosave_timer = 0.0
			if _save_game():
				player._flash("Autosaved")

	if _selftest:
		_run_selftest()
	elif not _screenshot_path.is_empty():
		_run_screenshot()


func _run_selftest() -> void:
	match _test_step:
		0:
			# Give physics a moment to register the new collision shapes.
			if _clock - _ready_time < 0.5:
				return
			# Find the cavern wall toward +x and walk up to it.
			var from: Vector3 = player.global_position + Vector3(0, 0.7, 0)
			var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(40, 0, 0), 1)
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			if hit.is_empty():
				_fail("no wall found toward +x")
				return
			var wall: Vector3 = hit["position"]
			print("Wall found at ", wall)
			player.global_position = wall - Vector3(2.0, 0.7, 0)
			player.rotation.y = -PI / 2  # face +x
			player.camera.rotation.x = 0.0
			_test_step = 1
		1:
			var probe := Vector3i((player.global_position + Vector3(2.4, 0.7, 0)).round())
			var before: float = world.density_at(probe)
			var hits := 0
			for i in 4:
				if player.dig(player.PICK_RANGE, player.PICK_RADIUS, player.PICK_STRENGTH):
					hits += 1
			var after: float = world.density_at(probe)
			print("Pickaxe hits: %d, density at wall %.2f -> %.2f" % [hits, before, after])
			if hits == 0:
				_fail("pickaxe never hit terrain")
				return
			# Directly carve an ore-rich patch to check collection.
			var mined: Dictionary = world.apply_edit({"type": "carve_sphere",
				"center": Vector3(0, 30, 0), "radius": 3.0, "strength": 3.0})
			print("Test carve mined: ", mined)
			_ready_time = _clock
			_test_step = 2
		2:
			if _clock - _ready_time > 1.0:
				# Mouse-look: push a motion event at screen centre (where the crosshair is).
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				var yaw_before: float = player.rotation.y
				var motion := InputEventMouseMotion.new()
				motion.position = get_viewport().get_visible_rect().size / 2.0
				motion.relative = Vector2(100, 0)
				get_viewport().push_input(motion)
				print("Mouse-look yaw: %.3f -> %.3f (mouse mode %d)" % [yaw_before, player.rotation.y, Input.mouse_mode])
				if is_equal_approx(yaw_before, player.rotation.y) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					_fail("mouse motion did not rotate the player")
					return
				player.throw_flare()
				# Place one of each building in the spawn cavern so every building script loads.
				for i in Buildables.ORDER.size():
					var b = Buildables.make(Buildables.ORDER[i])
					b.position = Vector3(-8.0 + i * 3.5, -1.5, 8.0)
					grid.add(b)
				var gen = grid.buildings[1]
				gen.fuel_inv.add(Items.ELECTRUM, 5)
				# Shredder on the nearest exposed iron, run for 10 s on a full charge.
				var vein: Array = world.find_exposed(1, SPAWN_POS, 24)
				if not vein.is_empty():
					var shred = Buildables.make("shredder")
					var n: Vector3 = vein[1]
					var sx := n.cross(Vector3.UP).normalized()
					shred.transform = Transform3D(Basis(sx, n, sx.cross(n)), vein[0] + n * 0.5)
					shred.energy = Items.BATTERY_CAPACITY
					grid.add(shred)
					shred.scan_vein()
					var found: int = shred.total
					for k in 40:
						shred._physics_process(0.25)
					print("Shredder: vein %d cells, shredded %d, hopper iron %d, charge %.0f kJ, '%s'" % [
						found, found - shred.queue.size(), shred.hopper.count_of(Items.IRON), shred.energy, shred.status])
					# Hop legs: finish this vein, then jump to the next iron nearby.
					progress.shredder_hop = true
					var start_pos: Vector3 = shred.global_position
					var hopped := false
					for k in 200:
						shred._physics_process(0.25)
						if not shred._hop.is_empty():
							hopped = true
					print("Shredder hop: hopped=%s, moved %.1f m, now '%s'" % [hopped,
						shred.global_position.distance_to(start_pos), shred.status])
					progress.shredder_hop = false
					player.backpack.add_stack(Items.new_shredder(1000.0))
					shred.pick_up(player)
					print("Shredder picked up: in grid=%s, backpack shredders=%d" % [shred in grid.buildings,
						player.backpack.count_of(Items.SHREDDER)])
				# Inventory: stacking, transfer, paying from backpack + nearby storage.
				var store = grid.buildings[4]
				store.inv.add(Items.IRON, 30)
				player.backpack.add(Items.IRON, 70)
				var Inv = preload("res://scripts/items/inventory.gd")
				Inv.transfer(player.backpack, 0, store.inv, 5)
				var paid: bool = Inv.pay(player.cost_sources(), {Items.IRON: 60})
				print("Inventory: backpack iron %d, store iron %d, paid=%s, sources=%d" % [
					player.backpack.count_of(Items.IRON), store.inv.count_of(Items.IRON), paid, player.cost_sources().size()])
				builder.grid.remove(store)  # contents must drop as a cache
				var bug = director.spawn_bug(player.global_position + Vector3(0, 0.2, -3))
				player._select_tool(3)
				player.weapons.fire_pistol()
				player.weapons._cd = 0.0
				player.weapons.fire_shotgun()
				# Unstuck: bury the player in the solid slab under the floor, then ask to get out.
				var before_bury: Vector3 = player.global_position
				player.global_position = Vector3(0, -4.5, 0)
				var buried: bool = not player._fits(player.global_position)
				var how: String = player.unstuck()
				print("Unstuck: buried=%s -> '%s', fits now=%s, moved %.1f m" % [buried, how,
					player._fits(player.global_position), player.global_position.distance_to(before_bury)])
				player._safe_spots.clear()  # no trail: must search for open space
				player.global_position = Vector3(0, -4.5, 0)
				how = player.unstuck()
				print("Unstuck (no trail): '%s', fits now=%s at %s" % [how, player._fits(player.global_position),
					player.global_position])
				bug.take_damage(100.0, player.global_position)
				# Breakdown: a gnawer chews a pole to 0 HP, then E-style repair restores it.
				var pole := Buildables.make("pole")
				builder.grid.add(pole)
				pole.global_position = player.global_position + Vector3(4, 0, 0)
				var gnawer = director.spawn_bug(pole.global_position + Vector3(1, 0.2, 0), "gnawer")
				gnawer.target_building = pole
				while not pole.broken:
					pole.take_damage(gnawer._s["machine_bite"], pole.global_position)
				player.backpack.add(Items.IRON, 10)
				var fixed: bool = pole.repair(player.cost_sources())
				print("Breakdown: broke=true, repaired=%s, hp=%.0f/%.0f, swarm groups ok=%s" % [fixed, pole.hp,
					pole.max_hp, director._gnawer_share(1.0, true) > 0.0])
				builder.grid.remove(pole)
				gnawer.take_damage(500.0, player.global_position)
				# Cobalt grows only in hard rock; a thermal suit goes on in the suit slot and survives saving.
				var gen_w = world._main_gen
				var hard := 0
				var cobalt := 0
				for k in 20000:
					var q := Vector3(randf_range(-900, 900), randf_range(-300, 0), randf_range(-900, 900))
					if gen_w.biome(q.x, q.y, q.z) == gen_w.BIOME_HARD:
						hard += 1
						if gen_w.material(q.x, q.y, q.z) == preload("res://scripts/world/materials.gd").COBALT:
							cobalt += 1
				player.backpack.add_stack({"id": Items.THERMAL_SUIT, "count": 1})
				var Inv2 = preload("res://scripts/items/inventory.gd")
				for si in player.backpack.slots.size():
					var st = player.backpack.slots[si]
					if st and st["id"] == Items.THERMAL_SUIT:
						Inv2.quick_move(player.backpack, si, [player.equipment])
				var worn: bool = player.heat_protected()
				var pstate: Dictionary = player.get_state()
				player.equipment.slots[0] = null
				player.apply_state(pstate)
				print("Cobalt: %d of %d hard-rock samples (%.1f%%); suit worn=%s, after reload=%s" % [cobalt, hard,
					100.0 * cobalt / maxf(hard, 1.0), worn, player.heat_protected()])
				# Fire caves exist; obsidian unlocks the refinery, which turns iron + coal into steel.
				var fire := 0
				for k in 20000:
					var q := Vector3(randf_range(-900, 900), randf_range(-300, 0), randf_range(-900, 900))
					if gen_w.biome(q.x, q.y, q.z) == 2:
						fire += 1
				player.backpack.add(Items.OBSIDIAN, 5)
				var unlocked: bool = progress.refinery_unlocked
				var ref = Buildables.make("refinery")
				ref.position = player.global_position + Vector3(-6, -0.95, 0)
				grid.add(ref)
				player.backpack.add(Items.IRON, 20)
				player.backpack.add(Items.COAL, 10)
				ref._load_from([player.backpack])
				ref.battery_inv.add_stack(Items.new_battery(Items.BATTERY_CAPACITY))
				for k in 30:
					var sat: float = ref.battery_assist(0.0, 0.5)
					ref.power_tick(0.5, sat, 0.0)
				print("Fire: %.1f%% of samples; refinery unlocked=%s, steel=%d, iron left in it=%d, '%s'" % [
					100.0 * fire / 20000.0, unlocked, ref.output_inv.count_of(Items.STEEL), ref.input_inv.count_of(Items.IRON),
					ref.status])
				grid.remove(ref)
				# Boss: enrages at half health (calls swarmers), dies, drops loot, lair marked beaten.
				var caches_before := _live_caches().size()
				var bugs_before := get_tree().get_nodes_in_group("bugs").size()
				var hydra = director.spawn_boss(player.global_position + Vector3(0, 0.3, -12), "test")
				hydra.take_damage(750.0, player.global_position)
				var summoned: int = get_tree().get_nodes_in_group("bugs").size() - bugs_before - 1
				hydra.take_damage(700.0, player.global_position)
				print("Boss: enraged=%s, summoned=%d, dead=%s, lair beaten=%s, loot caches +%d, boss slot clear=%s" % [
					hydra._enraged, summoned, hydra._dead, director.bosses_defeated.has("test"),
					_live_caches().size() - caches_before, director.boss == null])
				for b in get_tree().get_nodes_in_group("bugs"):
					if b != hydra and b.has_method("take_damage"):
						b.take_damage(999.0, player.global_position)
				# Elevator: repair, sell (prices drop as you flood), buy a blueprint, order supplies.
				player.backpack.add(Items.IRON, 60)
				player.backpack.add(Items.ELECTRUM, 25)
				elevator.repair(player)
				var repaired: bool = elevator.state == elevator.State.READY
				elevator.cargo.add(Items.IRON, 100)
				elevator.cargo.add(Items.DIAMOND, 10)
				var iron_price: int = progress.market.price(Items.IRON)
				var credits0: int = progress.credits
				elevator.send_up()
				elevator._process(elevator.TRIP_TIME + 0.1)
				var sold_for: int = progress.credits - credits0
				elevator._process(elevator.TRIP_TIME + 0.1)
				progress.credits += 1000
				var slots0: int = player.backpack.slots.size()
				elevator._buy_blueprint("backpack_plus", player)
				elevator._order("battery")
				elevator.send_up()
				elevator._process(elevator.TRIP_TIME + 0.1)
				elevator._process(elevator.TRIP_TIME + 0.1)
				print("Elevator: repaired=%s, sold for %d, iron price %d -> %d, backpack %d -> %d, battery delivered=%s, back=%s" % [
					repaired, sold_for, iron_price, progress.market.price(Items.IRON), slots0, player.backpack.slots.size(),
					elevator.cargo.count_of(Items.BATTERY) == 1, elevator.state == elevator.State.READY])
				# Crooked dagger: a bug at arm's length dies in one stab; one 3 m off isn't touched.
				progress.dagger_owned = true
				player._select_tool(4)
				var fwd: Vector3 = -player.camera.global_basis.z
				fwd = Vector3(fwd.x, 0, fwd.z).normalized()
				var near_bug = director.spawn_bug(player.global_position + fwd * 1.1 + Vector3(0, -0.6, 0))
				var far_bug = director.spawn_bug(player.global_position + fwd * 3.2 + Vector3(0, -0.6, 0))
				player._dagger_cd = 0.0
				player._stab_attack()
				var near_dead: bool = near_bug._dead
				near_bug.queue_free()
				player._dagger_cd = 0.0
				player._stab_attack()
				print("Dagger: near bug killed=%s, far bug hp=%.0f/30" % [near_dead, far_bug.health])
				far_bug.queue_free()
				player._select_tool(0)
				progress.dagger_owned = false
				# Structure: a hut; a wall is chewed down; a snapped wall goes to the right edge.
				var hut := _debug_hut(player.global_position + Vector3(8, -0.95, 0))
				var wall = hut[2]
				var hp0: float = wall.hp
				while is_instance_valid(wall) and wall in grid.buildings:
					wall.take_damage(25.0, wall.global_position)
				var structures: int = grid.buildings.filter(func(b): return b.is_structure).size()
				print("Structure: %d pieces, wall hp %.0f destroyed=%s, door panels=%d, ladder group=%d" % [
					structures, hp0, not (wall in grid.buildings), hut[7]._door_panels.size(),
					get_tree().get_nodes_in_group("ladders").size()])
				for b in hut:
					if is_instance_valid(b) and b in grid.buildings:
						grid.remove(b)
				player.backpack.add(Items.IRON, 5)
				player.take_damage(500.0, Vector3.ZERO)
				var died_screen: bool = death_screen.visible
				death_screen.visible = false
				_on_respawn()
				print("Death screen shown=%s" % died_screen)
				print("Combat: bug dead=%s, player hp=%.0f, caches=%d (bodies %d), threat here=%.2f (%s)" % [
					bug._dead, player.health, _live_caches().size(), _live_bodies().size(),
					director.threat_at(player.global_position), player.threat_label])
				print("Buildings: %d, generator: %s" % [grid.buildings.size(), gen.hover_text().replace("\n", " | ")])
				# Save round-trip: edited chunks must come back byte-identical.
				_slot = TEST_SLOT
				var saved_ok := _save_game()
				var back := SaveSystem.read(TEST_SLOT)
				# Kept on disk for `--reloadtest`, which loads it in a fresh process.
				_slot = -1
				var exported: Dictionary = world.export_modified()
				var chunks_back: Dictionary = back.get("chunks", {})
				var same := saved_ok and chunks_back.size() == exported.size() and not exported.is_empty()
				for k in exported:
					same = same and chunks_back.has(k) and chunks_back[k] == exported[k]
				print("Save round-trip: %d edited chunks, identical=%s" % [exported.size(), same])
				if not same:
					_fail("save round-trip mismatch")
					return
				print("Backpack: %.1f kg, %d slots used" % [player.backpack.weight(), player.backpack.used_slots()])
				print("Chunks: %d" % world.chunk_count())
				print("Solid samples by material: ", world.material_histogram())
				print("SELFTEST PASS")
				get_tree().quit(0)


## Builds a 2×1-cell hut on foundations: walls, a window, a door, a ramp up the side, a
## ladder, a catwalk roof and a lamp powered by a battery. Returns the pieces.
func _debug_hut(at: Vector3) -> Array:
	var frame := Transform3D(Basis.IDENTITY, at)
	var pieces: Array = []
	var put := func(id: String, local: Transform3D, key: String):
		var b = Buildables.make(id)
		b.frame = frame
		b.slot_key = key
		local.origin *= preload("res://scripts/build/structure.gd").K  # laid out at the old 2 m size
		b.transform = frame * local
		grid.add(b)
		pieces.append(b)
	for cx in [0, 1]:
		put.call("foundation", Transform3D(Basis.IDENTITY, Vector3(cx * 2, 0, 0)), "c%d,0,0" % cx)
		put.call("catwalk", Transform3D(Basis.IDENTITY, Vector3(cx * 2, 2, 0)), "c%d,1,0" % cx)
		put.call("wall", Transform3D(Basis.IDENTITY, Vector3(cx * 2, 0, -1)), "e%d,0,-2" % (cx * 4))
	put.call("window", Transform3D(Basis.IDENTITY, Vector3(2, 0, 1)), "e4,0,2")
	put.call("door", Transform3D(Basis.IDENTITY, Vector3(0, 0, 1)), "e0,0,2")
	put.call("wall", Transform3D(Basis(Vector3.UP, PI / 2), Vector3(-1, 0, 0)), "e-2,0,0")
	put.call("half_wall", Transform3D(Basis(Vector3.UP, PI / 2), Vector3(3, 0, 0)), "e6,0,0")
	put.call("ramp", Transform3D(Basis(Vector3.UP, PI), Vector3(4, 0, 2)), "c2,0,1")
	put.call("ladder", Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(-1.16, 0, 0)), "l-2,0,0s-1")
	var lamp = Buildables.make("lamp")
	lamp.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2), at + Vector3(1.5, 2.4, 1.65))
	grid.add(lamp)
	pieces.append(lamp)
	var pole = Buildables.make("pole")
	pole.position = at + Vector3(-3, 0, 3)
	grid.add(pole)
	pieces.append(pole)
	var gen = Buildables.make("generator")
	gen.position = at + Vector3(-5, 0, 5)
	gen.fuel_inv.add(Items.ELECTRUM, 5)
	grid.add(gen)
	pieces.append(gen)
	return pieces


func _run_screenshot() -> void:
	if _test_step == 0:
		if _shot_ore > 0:
			# Close-up of the nearest exposed vein, lit only by the flashlight.
			var found: Array = world.find_exposed(_shot_ore, SPAWN_POS, 24)
			if found.is_empty():
				_fail("no exposed ore %d near spawn" % _shot_ore)
				return
			var sample: Vector3 = found[0]
			var dir: Vector3 = found[1]
			print("Ore %d exposed at %s facing %s" % [_shot_ore, sample, dir])
			player.active = false
			player.global_position = sample + dir * 2.2 - Vector3(0, 0.55, 0)
			player.rotation.y = atan2(dir.x, dir.z)
			player.camera.rotation.x = -0.1
			if OS.get_cmdline_user_args().has("--shredder"):
				var shred = Buildables.make("shredder")
				var sx := dir.cross(Vector3.UP).normalized()
				shred.transform = Transform3D(Basis(sx, dir, sx.cross(dir)), sample + dir * 0.5 + Vector3(0, -0.3, 0))
				shred.energy = Items.BATTERY_CAPACITY
				grid.add(shred)
				shred.scan_vein()
				player.global_position += dir * 1.0 + Vector3(0, 0.3, 0)
				player.camera.rotation.x = -0.35
		else:
			player.throw_flare()
		if _shot_drill:
			progress.drill_owned = true
			player._select_tool(1)
		if OS.get_cmdline_user_args().has("--shotgun"):
			player._select_tool(2)
		if _shot_inventory:
			player.backpack.add(Items.IRON, 73)
			player.backpack.add(Items.ELECTRUM, 18)
			player.backpack.add(Items.DIAMOND, 2)
			player.backpack.add(Items.COBALT, 12)
			player.equipment.add_stack({"id": Items.THERMAL_SUIT, "count": 1})
			player.backpack.add_stack(Items.new_battery(Items.BATTERY_CAPACITY * 0.6))
			pod.storage.add(Items.IRON, 40)
			building_panel.open(pod, player)
		if _shot_death:
			player.backpack.add(Items.IRON, 34)
			player.backpack.add(Items.ELECTRUM, 9)
			player.take_damage(500.0, Vector3.ZERO)
		if OS.get_cmdline_user_args().has("--fire"):
			# Into the nearest fire cave: open floor with the fire biome around it.
			var g = world._main_gen
			var spot := Vector3.INF
			for rr in range(150, 900, 6):
				for k in 48:
					var a := TAU * k / 48.0
					for yy in range(-10, -260, -3):
						var q := Vector3(cos(a) * rr, yy, sin(a) * rr)
						if g.biome(q.x, q.y, q.z) == 2 and g.density(q.x, q.y, q.z) <= -0.3 								and g.density(q.x, q.y + 1.0, q.z) <= -0.3 and g.density(q.x, q.y - 1.5, q.z) > 0.0:
							spot = q
							break
					if spot != Vector3.INF:
						break
				if spot != Vector3.INF:
					break
			print("Fire cave at %s" % spot)
			player.global_position = spot + Vector3(0, 0.4, 0)
			player.active = false
			player.equipment.add_stack({"id": Items.THERMAL_SUIT, "count": 1})
		if OS.get_cmdline_user_args().has("--arena"):
			# Onto the floor of the nearest boss arena, looking across it.
			var g = world._main_gen
			var best := Vector3.INF
			for cz in range(-6, 7):
				for cy in range(-3, 1):
					for cx in range(-6, 7):
						var c: Vector3 = g.arena_center(Vector3i(cx, cy, cz))
						if c != Vector3.INF and (best == Vector3.INF or c.length() < best.length()):
							best = c
			print("Arena at %s" % best)
			var edge := Vector3(1, 0, 0.3).normalized() * 14.0
			player.global_position = best + edge + Vector3(0, g.ARENA_FLOOR + 0.6, 0)
			player.rotation.y = atan2(edge.x, edge.z)
			player.camera.rotation.x = 0.05
			player.active = false
			player.equipment.add_stack({"id": Items.THERMAL_SUIT, "count": 1})
		if OS.get_cmdline_user_args().has("--floorshredder"):
			# A Shredder deployed on the open spawn floor right ahead, for looking at the model.
			var fwd: Vector3 = -player.global_basis.z
			var at: Vector3 = player.global_position + fwd * 2.2
			var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN * 4.0, 1)
			var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				var shred = Buildables.make("shredder")
				shred.position = hit["position"]
				grid.add(shred)
				print("Floor shredder at %s" % shred.position)
			player.camera.rotation.x = -0.45
		if OS.get_cmdline_user_args().has("--elevator"):
			# Look at the elevator from the spawn; with --shop, repaired and its shop open.
			var d: Vector3 = ELEVATOR_POS - player.global_position
			player.rotation.y = atan2(-d.x, -d.z)
			player.camera.rotation.x = 0.25
			if OS.get_cmdline_user_args().has("--shop"):
				elevator.state = elevator.State.READY
				elevator._apply_look()
				progress.credits = 735
				elevator._tab = 1
				_open_ui()
				building_panel.open(elevator, player)
		if OS.get_cmdline_user_args().has("--buildmenu"):
			player.backpack.add(Items.IRON, 100)
			player.backpack.add(Items.ELECTRUM, 12)
			_open_ui()
			build_menu.open(player)
			if OS.get_cmdline_user_args().has("--tab2"):
				build_menu._tab = 1
				build_menu._rebuild()
		if OS.get_cmdline_user_args().has("--bench") or OS.get_cmdline_user_args().has("--refinery"):
			# A crafting panel open, mid-job; --refinery for the refinery instead.
			var is_ref: bool = OS.get_cmdline_user_args().has("--refinery")
			var m = Buildables.make("refinery" if is_ref else "bench")
			m.position = player.global_position + Vector3(0, -0.95, -4.0)
			grid.add(m)
			player.backpack.add(Items.IRON, 60)
			player.backpack.add(Items.ELECTRUM, 14)
			player.backpack.add(Items.COBALT, 20)
			if is_ref:
				m.progress_t = 0.4
			else:
				m.crafting = "battery"
				m.craft_t = 0.6
			_open_ui()
			building_panel.open(m, player)
		if OS.get_cmdline_user_args().has("--scantable"):
			# A scanning table by the spawn with a tower out in the caves, map open.
			var t = Buildables.make("scan_table")
			t.position = player.global_position + Vector3(0, -0.95, -3.0)
			grid.add(t)
			var tw = Buildables.make("scan_tower")
			tw.position = player.global_position + Vector3(60, -0.95, 20)
			grid.add(tw)
			t.interact(player)
		if OS.get_cmdline_user_args().has("--structure"):
			# A little hut ahead of the spawn, seen from outside with its lamp on.
			_debug_hut(player.global_position + Vector3(0, -0.95, -5.0))
			player.camera.rotation.x = -0.12
			player.global_position += Vector3(1.5, 0, 1.5)
			player.rotation.y = 0.35
		if _shot_hit:
			_shot_bug = director.spawn_bug(player.global_position + Vector3(0.3, -0.6, -3.0),
				"gnawer" if OS.get_cmdline_user_args().has("--gnawer") else "swarmer")
			_shot_bug.player = null  # frozen in view for the picture
			player._select_tool(3)
			if OS.get_cmdline_user_args().has("--dagger"):
				progress.dagger_owned = true
				player._select_tool(4)
		_test_step = 1
	elif _shot_hit and _test_step == 1 and _clock - _ready_time > 2.75:
		# Two pistol hits just before the capture so the numbers and flash are on screen.
		var from: Vector3 = player.camera.global_position
		_shot_bug.take_damage(14.0, from)
		hud.hit_marker(false)
		_shot_bug.take_damage(14.0, from)
		_test_step = 2
	elif OS.get_cmdline_user_args().has("--boss") and _test_step == 1 and _clock - _ready_time > 0.5:
		# Boss in plain view, a few metres ahead.
		var at := Vector3.INF
		for tries in 20:
			at = director._find_spawn(player.global_position, 5.0, 14.0, false)
			if at != Vector3.INF:
				break
		print("Boss shot spawn at %s" % at)
		if at != Vector3.INF:
			var h = director.spawn_boss(at, "shot")
			var d: Vector3 = at - player.global_position
			player.rotation.y = atan2(-d.x, -d.z)
			player.camera.rotation.x = 0.12
			h.player = null  # frozen for the picture
			h.rotation.y = atan2(d.x, d.z)
		_test_step = 2
	elif _clock - _ready_time > (4.0 if OS.get_cmdline_user_args().has("--boss") else (10.0 if OS.get_cmdline_user_args().has("--scantable") else 3.0)):
		var img := get_viewport().get_texture().get_image()
		img.save_png(_screenshot_path)
		print("Screenshot saved to ", _screenshot_path)
		get_tree().quit(0)


func _fail(reason: String) -> void:
	push_error("SELFTEST FAIL: " + reason)
	get_tree().quit(1)


func _make_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.65)
	env.ambient_light_energy = 0.05
	# AgX rolls off bright highlights instead of clipping them to white.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.2
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.75, 0.72, 0.68)
	env.volumetric_fog_length = 40.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env


func _register_inputs() -> void:
	_key("move_forward", KEY_W)
	_key("move_back", KEY_S)
	_key("move_left", KEY_A)
	_key("move_right", KEY_D)
	_key("jump", KEY_SPACE)
	_key("sprint", KEY_SHIFT)
	_key("interact", KEY_E)
	_key("flare", KEY_F)  # tap: throw flare · hold: flashlight on/off
	_key("build", KEY_Q)  # tap: build menu · hold: scanner
	_key("rotate_build", KEY_R)
	_key("deconstruct", KEY_X)
	_key("deploy", KEY_G)  # throw a Shredder
	_key("tool_1", KEY_1)
	_key("tool_2", KEY_2)
	_key("tool_3", KEY_3)
	_key("tool_4", KEY_4)
	_key("tool_5", KEY_5)
	_key("inventory", KEY_TAB)
	if not InputMap.has_action("use"):
		InputMap.add_action("use")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("use", mb)


func _key(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)
