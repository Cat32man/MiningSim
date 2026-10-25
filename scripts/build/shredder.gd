extends "res://scripts/build/building.gd"
## SHREDDER-MK1, deployed. It clamps onto the rock where it landed, finds the ore vein it
## touched, and strips every connected cell of that ore within reach, nearest first, into
## its hopper. It leaves vein-shaped hollows and doesn't touch the rock around them.
##
## Runs on its own charge (refill it in a battery charger). [E] takes the ore; once it's
## done or idle, [E] picks it back up too. [X] picks it up at any time. A running Shredder
## is noisy, so bugs raid it.

const Sfx = preload("res://scripts/audio/sfx.gd")

const KW := 10.0  # a full charge (6000 kJ) runs 10 minutes
const MAX_CELLS := 400
const HOPPER_SLOTS := 6
const BEAM_COLOR := Color(1.0, 0.55, 0.15)
const ShredderScene = preload("res://assets/shredder/v1.glb")
const GlbRig = preload("res://scripts/util/glb_rig.gd")
const MODEL_SCALE := 0.28
const DEPLOY_TIME := 36.0 / 24.0  # frames 0-36: legs fold out, body drops and bites in
const EMITTER := Vector3(0, 0.5, 0)  # top of the model, where the beam comes from
const STATUS_COLORS := {"run": Color(0.4, 1.0, 0.45), "idle": Color(1.0, 0.75, 0.25), "stop": Color(1.0, 0.25, 0.15)}
## Hop legs (bench upgrade): when a vein is done, jump to the nearest exposed cell of the
## same ore within HOP_RANGE and start on that one.
const HOP_RANGE := 10
const HOP_TIME := 0.8
const HOP_ENERGY := 60.0  # kJ per jump

var energy := 0.0
var hopper = Inventory.new(HOPPER_SLOTS, "Hopper")
var vein_mat := -1
var queue: Array = []  # Vector3i cells still to shred, nearest first
var total := 0
var status := "Idle"

var _t := 0.0
var _working := false
var _hop := {}  # in flight: {from, to, normal, t}
var _deploy_tracks: Array = []
var _anim_end := DEPLOY_TIME
var _glow_mats: Array = []
var _deploy_t := 0.0  # legs out, body settled at DEPLOY_TIME
var _grind_t := 0.0
var _hop_retry := 0.0
var _age := 0.0
var _alerted := ""  # last state we told the player about
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _dust: CPUParticles3D
var _sound: AudioStreamPlayer3D


func _init() -> void:
	is_power_node = false  # self-powered
	cable_anchor = Vector3(0, 0.55, 0)


func _build_visuals() -> void:
	# The artist's model (assets/shredder/v1.glb): origin at the point that hits the rock.
	var model: Node3D = ShredderScene.instantiate()
	model.scale = Vector3.ONE * MODEL_SCALE
	add_child(model)
	# One timeline: frames 0-36 deploy, 36 to the end loops while it shreds.
	_deploy_tracks = GlbRig.collect(model)
	for tr in _deploy_tracks:
		_anim_end = maxf(_anim_end, tr["anim"].length)
	# Its glowing strip doubles as a status light (own copies so Shredders don't share it).
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var m = mi.get_active_material(si)
			# Full chrome has nothing to reflect in a dark cave and renders black: keep some
			# diffuse colour so the flashlight shows it.
			if m is BaseMaterial3D:
				m.metallic = minf(m.metallic, 0.55)
				m.roughness = maxf(m.roughness, 0.3)
			if m is StandardMaterial3D and m.emission_enabled:
				var dup: StandardMaterial3D = m.duplicate()
				mi.set_surface_override_material(si, dup)
				_glow_mats.append(dup)
	if ghost or preview:
		_deploy_t = DEPLOY_TIME
	GlbRig.apply(_deploy_tracks, _deploy_t)

	# Cutting beam from the shredder to the cell it's eating.
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.albedo_color = Color(BEAM_COLOR, 0.7)
	_beam = MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.015
	bm.bottom_radius = 0.015
	bm.height = 1.0
	bm.radial_segments = 6
	bm.rings = 1
	_beam.mesh = bm
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	_beam.visible = false
	add_child(_beam)

	_dust = CPUParticles3D.new()
	_dust.top_level = true
	_dust.emitting = false
	_dust.one_shot = true
	_dust.amount = 14
	_dust.lifetime = 0.9
	_dust.explosiveness = 0.9
	_dust.spread = 180.0
	_dust.initial_velocity_min = 0.5
	_dust.initial_velocity_max = 1.6
	_dust.gravity = Vector3(0, -2.0, 0)
	_dust.scale_amount_min = 0.04
	_dust.scale_amount_max = 0.1
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1.0
	puff.radial_segments = 6
	puff.rings = 3
	puff.material = mat(Color(0.45, 0.42, 0.38), 0.0, 1.0)
	_dust.mesh = puff
	add_child(_dust)


func _collision_shape() -> Shape3D:
	var b := BoxShape3D.new()
	b.size = Vector3(0.7, 0.5, 0.7)
	return b


func _collision_offset() -> Vector3:
	return Vector3(0, 0.25, 0)


## Finds the vein under the landing spot and queues its cells (farthest first).
func scan_vein() -> void:
	queue.clear()
	total = 0
	vein_mat = -1
	var world = grid.world if grid else null
	if world == null:
		return
	var into: Vector3 = global_position - global_basis.y * 0.4
	var c0 := Vector3i(into.round())
	var seed_cell := Vector3i.ZERO
	var best := INF
	for z in range(-2, 3):
		for y in range(-2, 3):
			for x in range(-2, 3):
				var c := c0 + Vector3i(x, y, z)
				var m: int = world.material_at(c)
				if Materials.COLLECTIBLE[m] and world.density_at(c) > 0.0:
					var d := Vector3(c).distance_to(into)
					if d < best:
						best = d
						seed_cell = c
						vein_mat = m
	if vein_mat < 0:
		status = "No ore here"
		return
	if vein_mat == Materials.DIAMOND and not (grid.progress and grid.progress.shredder_diamond):
		status = "Needs diamond teeth"
		return
	var reach: float = grid.progress.shredder_stat("reach") if grid.progress else 3.0
	# Flood fill through touching cells (faces, edges and corners) of the same ore.
	var seen := {seed_cell: true}
	var frontier: Array = [seed_cell]
	while not frontier.is_empty() and queue.size() < MAX_CELLS:
		var c: Vector3i = frontier.pop_front()
		queue.append(c)
		for dz in range(-1, 2):
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var n := c + Vector3i(dx, dy, dz)
					if seen.has(n) or Vector3(n).distance_to(Vector3(seed_cell)) > reach:
						continue
					seen[n] = true
					if world.material_at(n) == vein_mat and world.density_at(n) > 0.0:
						frontier.append(n)
	var here := global_position
	# Farthest first: the rock it's clamped onto goes last, so it never hangs in the air.
	queue.sort_custom(func(a, b): return Vector3(a).distance_squared_to(here) > Vector3(b).distance_squared_to(here))
	total = queue.size()
	status = "Found %d %s" % [total, Materials.NAMES[vein_mat].to_lower()]


func _physics_process(dt: float) -> void:
	if ghost:
		return
	_age += dt
	_working = false
	if not _hop.is_empty():
		_fly(dt)
		_animate(dt)
		return
	if broken:
		status = "Broken"
	elif vein_mat < 0 or (queue.is_empty() and total == 0):
		pass  # "No ore here" / "Needs diamond teeth" from scan_vein()
	elif queue.is_empty():
		status = "Vein done"
		var can_hop: bool = grid != null and grid.progress != null and grid.progress.shredder_hop
		_hop_retry -= dt
		if can_hop and energy >= HOP_ENERGY and not _hopper_full():
			# Hop legs: look for the next vein every few seconds (the search is costly).
			if _hop_retry <= 0.0 and not _start_hop():
				_hop_retry = 3.0
			if _hop.is_empty():
				status = "Vein done · none nearby"
				_alert("done", "No ore left")
		else:
			_alert("done", "Vein done")
	elif energy <= 0.0:
		status = "Out of charge"
		_alert("charge", "Out of charge")
	elif _hopper_full():
		status = "Hopper full"
		_alert("full", "Hopper full")
	elif _deploy_t < DEPLOY_TIME:
		status = "Deploying"
	else:
		_working = true
		energy = maxf(energy - KW * dt, 0.0)
		_t += dt * (grid.progress.shredder_stat("rate") if grid and grid.progress else 1.0)
		while _t >= 1.0 and not queue.is_empty():
			_t -= 1.0
			_shred(queue.pop_front())
		_alerted = ""
		status = "Shredding %s — %d / %d" % [Materials.NAMES[vein_mat].to_lower(), total - queue.size(), total]
	_animate(dt)


## Tells the player (corner notice) when it stops for a new reason.
func _alert(key: String, text: String) -> void:
	if _alerted == key or preview:
		return
	_alerted = key
	if _age < 2.0:
		return  # a just-loaded base doesn't announce itself
	var p = get_tree().get_first_node_in_group("player")
	if p and p.hud:
		var col: Color = STATUS_COLORS["idle"] if key == "done" else STATUS_COLORS["stop"]
		p.hud.notify("SHREDDER", ["%s · %d m" % [text, roundi(p.global_position.distance_to(global_position))]], col)


## Looks for the nearest exposed cell of the same ore and jumps onto its face.
func _start_hop() -> bool:
	var w = grid.world
	var here := global_position
	var c0 := Vector3i(here.round())
	var candidates: Array = []  # [distance, cell, air cell next to it]
	var faces: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for z in range(-HOP_RANGE, HOP_RANGE + 1):
		for y in range(-HOP_RANGE, HOP_RANGE + 1):
			for x in range(-HOP_RANGE, HOP_RANGE + 1):
				var c := c0 + Vector3i(x, y, z)
				var d := Vector3(c).distance_to(here)
				if d > HOP_RANGE or d < 1.5:
					continue
				if w.material_at(c) != vein_mat or w.density_at(c) <= 0.0:
					continue
				for f in faces:
					if w.density_at(c + f) <= 0.0:
						candidates.append([d, c, c + f])
						break
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	# Nearest face it can actually reach: the whole arc has to be clear of rock.
	var pick: Array = []
	for cand in candidates.slice(0, 24):
		var normal := Vector3(cand[2] - cand[1])
		if _arc_clear(here, Vector3(cand[1]) + normal * 0.5):
			pick = cand
			break
	if pick.is_empty():
		return false
	var normal := Vector3(pick[2] - pick[1])
	energy -= HOP_ENERGY
	_hop = {"from": here, "to": Vector3(pick[1]) + normal * 0.5, "normal": normal, "t": 0.0}
	_deploy_t = 0.0  # legs fold for the jump; it deploys again where it lands
	GlbRig.apply(_deploy_tracks, 0.0)
	status = "Hopping"
	SfxLib.play_3d("place", here, get_parent(), -4.0, 1.6)
	return true


## Rock-free along the exact path _fly() takes? Reads the voxels, not collision: terrain
## far from the player has no collision, so rays there pass through everything.
func _arc_clear(from: Vector3, to: Vector3) -> bool:
	var h := 1.0 + from.distance_to(to) * 0.15
	var steps := maxi(ceili((from.distance_to(to) + h * 2.0) / 0.25), 8)
	for i in range(1, steps):
		var k := float(i) / steps
		var p := from.lerp(to, k) + Vector3.UP * sin(k * PI) * h
		# Both ends sit against rock on purpose.
		if p.distance_to(from) < 0.6 or p.distance_to(to) < 0.6:
			continue
		if grid.world.density_interp(p) > 0.0:
			return false
	return true


func _fly(dt: float) -> void:
	_hop["t"] += dt / HOP_TIME
	var k: float = minf(_hop["t"], 1.0)
	var from: Vector3 = _hop["from"]
	var to: Vector3 = _hop["to"]
	var arc := Vector3.UP * sin(k * PI) * (1.0 + from.distance_to(to) * 0.15)
	global_position = from.lerp(to, k) + arc
	rotate_object_local(Vector3.UP, dt * 9.0)  # spins in the air
	if k >= 1.0:
		var y: Vector3 = _hop["normal"]
		var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
		global_transform = Transform3D(Basis(x, y, x.cross(y)), to)
		_hop = {}
		SfxLib.play_3d("place", to, get_parent(), 0.0, 1.3)
		scan_vein()


func _shred(cell: Vector3i) -> void:
	var got: Dictionary = grid.world.apply_edit({"type": "clear_cells", "cells": [cell], "mat": vein_mat})
	for m in got:
		if Items.FROM_MATERIAL.has(m):
			hopper.add(Items.FROM_MATERIAL[m], got[m])
	if got.is_empty():
		return  # already dug out by hand
	var at := Vector3(cell)
	_dust.global_position = at
	_dust.restart()
	_dust.emitting = true
	# A chip of ore flies back into the hopper.
	var chip := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(0.09, 0.09, 0.09)
	chip.mesh = cb
	chip.material_override = mat(Materials.COLOR[vein_mat], Materials.METALLIC[vein_mat], 0.4)
	chip.top_level = true
	add_child(chip)
	chip.global_position = at
	var t := chip.create_tween()
	t.tween_property(chip, "global_position", to_global(EMITTER), 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(chip.queue_free)


func _hopper_full() -> bool:
	if hopper.used_slots() < HOPPER_SLOTS:
		return false
	for s in hopper.slots:
		if s["count"] < hopper.max_stack(s["id"]):
			return false
	return true


func _animate(dt: float) -> void:
	if _deploy_t < DEPLOY_TIME and _hop.is_empty():
		_deploy_t = minf(_deploy_t + dt, DEPLOY_TIME)
		GlbRig.apply(_deploy_tracks, _deploy_t)
	if _working and _anim_end > DEPLOY_TIME:
		_grind_t = fmod(_grind_t + dt, _anim_end - DEPLOY_TIME)
		GlbRig.apply(_deploy_tracks, DEPLOY_TIME + _grind_t)
	var key := "run" if _working else ("idle" if energy > 0.0 and not queue.is_empty() else "stop")
	for m in _glow_mats:
		m.emission = STATUS_COLORS[key]
	if _sound == null and not ghost:
		_sound = Sfx.loop_3d("drill", self, -12.0, 3.0)
		_sound.pitch_scale = 1.35
	if _sound and _working != _sound.playing:
		_sound.playing = _working
	_beam.visible = _working and not queue.is_empty()
	if _beam.visible:
		var a := to_global(EMITTER)
		var b := Vector3(queue[0])
		var d := b - a
		var y := d.normalized()
		var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
		_beam.global_transform = Transform3D(Basis(x, y * d.length(), x.cross(y)), (a + b) * 0.5)
		_beam_mat.albedo_color.a = randf_range(0.45, 0.85)


func is_running() -> bool:
	return _working


## [E]: take the ore. Once it's finished (or can't run), pick it back up as well.
func interact(player) -> bool:
	var had_ore: bool = not hopper.is_empty()
	if not player.take_up_to_limit(hopper):
		player._flash("Backpack full — %d left in the hopper" % _hopper_count())
		return false
	if _working or (energy > 0.0 and not queue.is_empty() and not _hopper_full()):
		player._flash("Took the ore" if had_ore else status)
		return false
	pick_up(player)
	return false


## Back into the backpack with its remaining charge (ore first).
func pick_up(player) -> void:
	player.take_up_to_limit(hopper)
	if not player.backpack.add_stack(Items.new_shredder(energy)):
		player._flash("Backpack full")
		return
	Sfx.play("deposit", player, -6.0, 1.3)
	player._flash("Picked up the Shredder")
	grid.remove(self)  # anything left in the hopper drops as a cache


func get_inventories() -> Array:
	return [hopper]


func hover_text() -> String:
	return "SHREDDER-MK1 — %s\nCharge %d%% · hopper %d · [E] collect · [X] pick up" % [status,
		roundi(energy / BATTERY_CAPACITY * 100.0), _hopper_count()]


func _hopper_count() -> int:
	var n := 0
	for s in hopper.slots:
		if s:
			n += s["count"]
	return n


func get_state() -> Dictionary:
	var s := super()
	s["energy"] = energy
	s["vein_mat"] = vein_mat
	s["queue"] = queue.duplicate()
	s["total"] = total
	s["status"] = status
	return s


func apply_state(s: Dictionary) -> void:
	super(s)
	energy = s.get("energy", 0.0)
	vein_mat = s.get("vein_mat", -1)
	queue = s.get("queue", []).duplicate()
	total = s.get("total", 0)
	status = s.get("status", "Idle")
	_deploy_t = DEPLOY_TIME  # loaded Shredders are already dug in
	GlbRig.apply(_deploy_tracks, _deploy_t)
