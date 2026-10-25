extends CanvasLayer
## Scanning table map: a hologram of the caves around the table on an old CRT. Drag to turn
## it, right-drag or WASD to move, wheel to zoom. The terrain is meshed from the world
## generator (plus whatever you've dug nearby) in 32 m chunks on worker threads. Near the
## table and scanning towers it's steady; further out it wobbles, tears and drops out.

signal opened
signal closed

const Generator = preload("res://scripts/world/terrain_generator.gd")
const SurfaceNets = preload("res://scripts/world/surface_nets.gd")
const Materials = preload("res://scripts/world/materials.gd")

const STEP := 2.0  # metres between samples
const CH := STEP * SurfaceNets.S  # map chunk size (32 m)
const VIEW_XZ := 2  # chunks around the view centre, sideways
const VIEW_Y := 1  # and up/down
const MAX_PENDING := 6
const MAX_CACHED := 260
const FADE := 260.0  # metres past the steady zone until it's all noise
const MAX_RANGE := 640.0  # how far from the table the view can travel
const MAX_SOURCES := 16
const VEIN_CELL := 8.0  # ore is counted per 8 m block (64 samples)...
const VEIN_BLOCK := 10  # ...a block with this many ore samples is part of a vein...
const VEIN_BIG := 90  # ...and touching blocks adding up to this many get a tag

const AMBER := Color(1.0, 0.62, 0.22)

const TERRAIN_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, skip_vertex_transform;
uniform vec3 sources[16];
uniform float radii[16];
uniform int source_count = 1;
uniform float fade = 260.0;
uniform vec3 view_center;
uniform float view_radius = 80.0;
uniform vec4 tint : source_color = vec4(1.0, 0.62, 0.22, 1.0);
varying vec3 v_world;
varying float v_inst;

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }

float instability(vec3 w) {
	float d = 1e9;
	for (int i = 0; i < source_count; i++) {
		d = min(d, distance(w, sources[i]) - radii[i]);
	}
	return clamp(d / fade, 0.0, 1.0);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float inst = instability(w);
	float k = inst * inst;
	// Slow swim plus jitter that snaps to new spots several times a second.
	vec3 swim = vec3(sin(w.y * 0.3 + TIME * 2.1 + w.x * 0.11), sin(w.x * 0.27 + TIME * 1.7),
		cos(w.z * 0.31 + TIME * 2.3)) * k * 7.0;
	vec3 jit = (vec3(hash(floor(w * 0.25) + floor(TIME * 8.0)), hash(floor(w * 0.25) + 3.1 + floor(TIME * 8.0)),
		hash(floor(w * 0.25) + 7.7 + floor(TIME * 8.0))) - 0.5) * k * 5.0;
	// Horizontal tearing bands.
	float band = step(0.93, hash(vec3(floor(w.y * 0.5), floor(TIME * 6.0), 1.0)));
	w += swim + jit + vec3(band * k * 9.0, 0.0, 0.0);
	v_world = w;
	v_inst = inst;
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float c = abs(fract(v_world.y / 4.0) - 0.5) * 2.0;
	float contour = smoothstep(0.86, 1.0, c);
	float a = 0.012 + fres * 0.13 + contour * 0.2;
	// Drop-outs: whole patches blink out as the signal gets worse.
	float keep = step(v_inst * 0.9, hash(floor(v_world * 0.35) + floor(TIME * 10.0)));
	a *= mix(1.0, keep, v_inst);
	float edge = distance(v_world.xz, view_center.xz);
	a *= smoothstep(view_radius, view_radius * 0.75, edge);
	ALBEDO = mix(tint.rgb, vec3(1.0, 0.22, 0.12), v_inst * 0.8);
	ALPHA = a;
}
"""

const CRT_SHADER := """
shader_type canvas_item;
uniform float noise_amt = 0.0;
float rnd(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	c *= 1.0 + 0.05 * dot(c.yx, c.yx);  // bulging glass
	vec2 uv = c * 0.5 + 0.5;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		float line = floor(uv.y / SCREEN_PIXEL_SIZE.y / 3.0);
		uv.x += sin(uv.y * 30.0 + TIME * 2.0) * 0.0012 * (1.0 + noise_amt * 5.0);
		float tear = step(0.996 - noise_amt * 0.02, rnd(vec2(floor(uv.y * 70.0), floor(TIME * 14.0))));
		uv.x += tear * 0.025;
		float ab = 0.0016 + noise_amt * 0.003;
		vec3 col = vec3(texture(TEXTURE, uv + vec2(ab, 0.0)).r, texture(TEXTURE, uv).g,
			texture(TEXTURE, uv - vec2(ab, 0.0)).b);
		col *= 0.78 + 0.22 * step(0.5, fract(uv.y / SCREEN_PIXEL_SIZE.y / 3.0));  // scanlines
		col += (rnd(uv * 512.0 + TIME) - 0.5) * (0.05 + noise_amt * 0.12);  // static
		float roll = smoothstep(0.0, 0.03, abs(fract(uv.y - TIME * 0.12) - 0.5));
		col *= 0.93 + 0.07 * roll;  // slow rolling bar
		col *= 0.96 + 0.04 * sin(TIME * 57.0);  // flicker
		col += vec3(0.03, 0.02, 0.005);  // phosphor glow
		col *= smoothstep(1.45, 0.45, length(c));  // vignette
		COLOR = vec4(col, 1.0);
	}
}
"""

var table: Node3D
var player
var world

var _root: Control
var _vp: SubViewport
var _screen: TextureRect
var _crt: ShaderMaterial
var _terrain_mat: ShaderMaterial
var _map: Node3D  # chunk meshes
var _marks: Node3D  # labels and rings, rebuilt on open
var _pivot: Node3D
var _cam: Camera3D
var _readout: Label
var _center := Vector3.ZERO
var _yaw := 0.6
var _pitch := -0.85
var _dist := 190.0
var _drag := -1  # mouse button held
var _chunks := {}  # Vector3i -> MeshInstance3D or null (empty)
var _veins := {}  # Vector3i block -> Label3D
var _pending := {}  # Vector3i -> task id
var _done: Array = []  # finished results, filled by workers
var _mutex := Mutex.new()
var _sources: Array = []  # [position, radius]
var _seed := 0


func _ready() -> void:
	layer = 6
	visible = false
	add_to_group("scan_view")
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.015, 0.01)
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	_map = Node3D.new()
	_vp.add_child(_map)
	_marks = Node3D.new()
	_vp.add_child(_marks)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 2000.0
	_pivot.add_child(_cam)

	_terrain_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = TERRAIN_SHADER
	_terrain_mat.shader = sh
	_terrain_mat.set_shader_parameter("fade", FADE)
	_terrain_mat.set_shader_parameter("view_radius", CH * (VIEW_XZ + 0.5))

	_screen = TextureRect.new()
	_screen.texture = _vp.get_texture()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.stretch_mode = TextureRect.STRETCH_SCALE
	_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_crt = ShaderMaterial.new()
	var crt := Shader.new()
	crt.code = CRT_SHADER
	_crt.shader = crt
	_screen.material = _crt
	_screen.gui_input.connect(_on_screen_input)
	_root.add_child(_screen)

	var title := _label("SCANNER", 26, AMBER)
	title.position = Vector2(40, 30)
	_root.add_child(title)
	_readout = _label("", 18, AMBER)
	_readout.position = Vector2(40, 66)
	_root.add_child(_readout)
	var help := _label("Drag rotate · Right-drag / WASD move · R/F up/down · Wheel zoom · E close", 15,
		Color(AMBER, 0.6))
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.position = Vector2(40, -50)
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(help)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func open(t: Node3D, p) -> void:
	table = t
	player = p
	world = p.world
	if world.world_seed != _seed:
		_seed = world.world_seed
		_clear_chunks()
	_center = table.global_position
	_yaw = p.rotation.y + PI
	_vp.size = Vector2i(get_viewport().get_visible_rect().size)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_refresh_sources()
	_build_marks()
	visible = true
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	_drag = -1
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact") \
			or event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		close()


func _on_screen_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_dist = maxf(_dist * 0.88, 30.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_dist = minf(_dist * 1.14, 420.0)
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_drag = event.button_index if event.pressed else -1
	elif event is InputEventMouseMotion and _drag != -1:
		if _drag == MOUSE_BUTTON_LEFT:
			_yaw -= event.relative.x * 0.006
			_pitch = clampf(_pitch - event.relative.y * 0.005, -1.45, 0.3)
		else:
			var right := Vector3(cos(_yaw), 0, -sin(_yaw))
			var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
			_move((-right * event.relative.x + fwd * event.relative.y) * _dist * 0.0022)


func _move(by: Vector3) -> void:
	var to := _center + by
	var from_table: Vector3 = to - table.global_position
	if from_table.length() > MAX_RANGE:
		to = table.global_position + from_table.normalized() * MAX_RANGE
	_center = to


func _process(dt: float) -> void:
	if not visible:
		_collect(false)
		return
	if not is_instance_valid(table):
		close()
		return
	var keys := Vector3(
		Input.get_axis("move_left", "move_right"), 0.0, Input.get_axis("move_forward", "move_back"))
	if Input.is_physical_key_pressed(KEY_R):
		keys.y += 1.0
	if Input.is_physical_key_pressed(KEY_F):
		keys.y -= 1.0
	if keys != Vector3.ZERO:
		_move(Basis(Vector3.UP, _yaw) * keys * _dist * 0.8 * dt)
	_pivot.position = _center
	_pivot.rotation = Vector3(_pitch, _yaw, 0)
	_cam.position = Vector3(0, 0, _dist)
	_terrain_mat.set_shader_parameter("view_center", _center)
	var inst := instability(_center)
	_crt.set_shader_parameter("noise_amt", inst)
	var away := roundi(_center.distance_to(table.global_position))
	_readout.text = "SIGNAL %d%%   ·   %d m from table" % [roundi((1.0 - inst) * 100.0), away]
	_request_chunks()
	_collect(true)
	# Labels far out flicker with the signal.
	for l in _marks.get_children() + _map.get_children():
		if l is Label3D:
			var li := instability(l.global_position)
			l.visible = randf() > li * 0.6


# --- Signal ---------------------------------------------------------------------------

func _refresh_sources() -> void:
	_sources = [[table.global_position, table.STABLE_RADIUS]]
	for t in get_tree().get_nodes_in_group("scan_towers"):
		if _sources.size() >= MAX_SOURCES or t.ghost or t.broken:
			continue
		_sources.append([t.global_position, t.STABLE_RADIUS])
	var pos := PackedVector3Array()
	var radii := PackedFloat32Array()
	for s in _sources:
		pos.append(s[0])
		radii.append(s[1])
	pos.resize(MAX_SOURCES)
	radii.resize(MAX_SOURCES)
	_terrain_mat.set_shader_parameter("sources", pos)
	_terrain_mat.set_shader_parameter("radii", radii)
	_terrain_mat.set_shader_parameter("source_count", _sources.size())


## 0 = steady (near the table or a tower), 1 = all noise. Same formula as the shader.
func instability(p: Vector3) -> float:
	var d := INF
	for s in _sources:
		d = minf(d, p.distance_to(s[0]) - s[1])
	return clampf(d / FADE, 0.0, 1.0)


# --- Markers --------------------------------------------------------------------------

func _build_marks() -> void:
	for c in _marks.get_children():
		c.queue_free()
	for s in _sources:
		_ring(s[0], s[1])
	_tag(table.global_position + Vector3(0, 4, 0), "▼ TABLE", Color(1.0, 0.85, 0.5), 30)
	_tag(player.global_position + Vector3(0, 3, 0), "● YOU", Color(0.6, 1.0, 0.7), 26)
	for t in get_tree().get_nodes_in_group("scan_towers"):
		if not t.ghost:
			_tag(t.global_position + Vector3(0, 6, 0), "▲ TOWER", Color(1.0, 0.75, 0.4), 22)
	if player.pod:
		_tag(player.pod.global_position + Vector3(0, 6, 0), "DROP POD", Color(1.0, 0.72, 0.3), 24)
	var si: Vector3 = Generator.silicon_center(_seed)
	_tag(si, "◇ SILICON CAVES\n%d m" % roundi(si.distance_to(table.global_position)), Color(0.55, 0.85, 1.0), 30)
	_beam(si, Color(0.55, 0.85, 1.0))


func _tag(at: Vector3, text: String, color: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font_size = size
	l.outline_size = 6
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.modulate = color
	_marks.add_child(l)
	l.position = at
	return l


## Flat glowing ring: the steady zone around the table or a tower.
func _ring(at: Vector3, r: float) -> void:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = r - 0.5
	t.outer_radius = r + 0.5
	t.rings = 64
	t.ring_segments = 4
	mi.mesh = t
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(AMBER, 0.35)
	m.no_depth_test = true
	mi.material_override = m
	mi.position = at
	_marks.add_child(mi)


## Tall pillar of light over a far-off point of interest.
func _beam(at: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 1.5
	c.bottom_radius = 1.5
	c.height = 160.0
	mi.mesh = c
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(color, 0.25)
	mi.material_override = m
	mi.position = at + Vector3(0, 80, 0)
	_marks.add_child(mi)


# --- Terrain chunks -------------------------------------------------------------------

func _wanted() -> Array:
	var c := Vector3i((_center / CH).floor())
	var out: Array = []
	for dy in range(-VIEW_Y, VIEW_Y + 1):
		for dz in range(-VIEW_XZ, VIEW_XZ + 1):
			for dx in range(-VIEW_XZ, VIEW_XZ + 1):
				out.append(c + Vector3i(dx, dy, dz))
	# Nearest first.
	out.sort_custom(func(a, b): return (Vector3(a) * CH).distance_squared_to(_center) < (Vector3(b) * CH).distance_squared_to(_center))
	return out


func _request_chunks() -> void:
	var wanted := _wanted()
	var keep := {}
	for k in wanted:
		keep[k] = true
		if not _chunks.has(k) and not _pending.has(k) and _pending.size() < MAX_PENDING:
			_pending[k] = WorkerThreadPool.add_task(_build_task.bind(k, _seed))
	for k in _chunks:
		if _chunks[k] != null:
			_chunks[k].visible = keep.has(k)
	if _chunks.size() > MAX_CACHED:
		for k in _chunks.keys():
			if not keep.has(k):
				if _chunks[k] != null:
					_chunks[k].queue_free()
				_chunks.erase(k)
				if _chunks.size() <= MAX_CACHED * 0.8:
					break


## Worker thread: samples the generator for one map chunk and counts ore per 8 m block.
func _build_task(key: Vector3i, seed_value: int) -> void:
	var gen = Generator.new(seed_value)
	var P: int = SurfaceNets.P
	var origin := Vector3(key) * CH
	var dens := PackedFloat32Array()
	dens.resize(P * P * P)
	var ore := {}  # Vector4i(block, mat) -> samples
	for k in P:
		for j in P:
			for i in P:
				var w := origin + Vector3(i - 1, j - 1, k - 1) * STEP
				var d: float = gen.density(w.x, w.y, w.z)
				dens[i + j * P + k * P * P] = d
				if d > 0.0 and i > 0 and j > 0 and k > 0 and i <= SurfaceNets.S and j <= SurfaceNets.S \
						and k <= SurfaceNets.S:
					var m: int = gen.material(w.x, w.y, w.z)
					if Materials.COLLECTIBLE[m]:
						var b := Vector3i((w / VEIN_CELL).floor())
						var key2 := Vector4i(b.x, b.y, b.z, m)
						ore[key2] = ore.get(key2, 0) + 1
	_mutex.lock()
	_done.append({"key": key, "seed": seed_value, "dens": dens, "ore": ore})
	_mutex.unlock()


## Main thread: turns finished samples into meshes (one or two a frame).
func _collect(build: bool) -> void:
	_mutex.lock()
	var batch: Array = []
	var n := 2 if build else 0
	while not _done.is_empty() and batch.size() < n:
		batch.append(_done.pop_front())
	_mutex.unlock()
	for key in _pending.keys():
		if WorkerThreadPool.is_task_completed(_pending[key]):
			WorkerThreadPool.wait_for_task_completion(_pending[key])
			_pending.erase(key)
	for r in batch:
		if r["seed"] != _seed:
			continue
		_add_chunk(r)


func _add_chunk(r: Dictionary) -> void:
	var key: Vector3i = r["key"]
	var dens: PackedFloat32Array = r["dens"]
	var P: int = SurfaceNets.P
	var origin := Vector3(key) * CH
	# Where the real world is loaded, show it as it is now (your tunnels, your digging).
	if world and origin.distance_to(player.global_position) < 200.0:
		for k in P:
			for j in P:
				for i in P:
					var w := origin + Vector3(i - 1, j - 1, k - 1) * STEP
					var known: float = world.known_density(Vector3i(w.round()))
					if not is_nan(known):
						dens[i + j * P + k * P * P] = known
	var mats := PackedByteArray()
	mats.resize(P * P * P)  # all plain rock: colour comes from the shader
	var out: Dictionary = SurfaceNets.build(dens, mats, Vector3i(origin))
	var mi: MeshInstance3D = null
	if not out.is_empty():
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out["arrays"])
		mi = MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _terrain_mat
		mi.position = origin
		mi.scale = Vector3.ONE * STEP
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 16.0  # the wobble moves vertices outside the mesh bounds
		_map.add_child(mi)
	_chunks[key] = mi
	# Big ore veins: blocks that are mostly one ore.
	var ore: Dictionary = r["ore"]
	for vein in _clusters(ore):
		var m: int = vein[0]
		var at: Vector3 = vein[1]
		var b := Vector3i((at / VEIN_CELL).floor())
		if _veins.has(b) or _vein_near(at, m):
			continue  # one tag per vein, not one per chunk it spans
		var l := _tag(at, "◆ " + Materials.NAMES[m].to_upper(), Materials.COLOR[m].lightened(0.35), 20)
		l.reparent(_map)
		l.set_meta("mat", m)
		_veins[b] = l


## Joins touching ore-rich blocks of the same ore; returns [mat, centre] for the big ones.
static func _clusters(ore: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	for k in ore:
		if seen.has(k) or ore[k] < VEIN_BLOCK:
			continue
		var total := 0
		var sum := Vector3.ZERO
		var stack: Array = [k]
		seen[k] = true
		while not stack.is_empty():
			var c: Vector4i = stack.pop_back()
			total += ore[c]
			sum += (Vector3(c.x, c.y, c.z) + Vector3(0.5, 0.5, 0.5)) * VEIN_CELL * ore[c]
			for d in [Vector4i(1, 0, 0, 0), Vector4i(-1, 0, 0, 0), Vector4i(0, 1, 0, 0), Vector4i(0, -1, 0, 0),
					Vector4i(0, 0, 1, 0), Vector4i(0, 0, -1, 0)]:
				var n: Vector4i = c + d
				if not seen.has(n) and ore.get(n, 0) >= VEIN_BLOCK:
					seen[n] = true
					stack.append(n)
		if total >= VEIN_BIG:
			out.append([k.w, sum / total])
	return out


func _vein_near(at: Vector3, m: int) -> bool:
	for b in _veins:
		var l: Label3D = _veins[b]
		if l.get_meta("mat") == m and l.position.distance_to(at) < 40.0:
			return true
	return false


func _clear_chunks() -> void:
	for k in _chunks:
		if _chunks[k] != null:
			_chunks[k].queue_free()
	_chunks.clear()
	for b in _veins:
		_veins[b].queue_free()
	_veins.clear()


func _exit_tree() -> void:
	for key in _pending:
		WorkerThreadPool.wait_for_task_completion(_pending[key])
	_pending.clear()
