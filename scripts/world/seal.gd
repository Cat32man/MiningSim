extends Node3D
## The sealed door in the back wall of the seal chamber: a great round plug of dark metal
## with glyph rings that turn against each other and a green core that breathes. Placed by
## the threat director while you're near (see threat_director.gd), facing into the room.

const GREEN := Color(0.35, 1.0, 0.5)

var _rings: Array = []
var _core_mat: StandardMaterial3D
var _glyph_mat: StandardMaterial3D
var _light: OmniLight3D
var _motes: CPUParticles3D
var _t := 0.0


func _ready() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.13, 0.14, 0.15)
	metal.metallic = 0.85
	metal.roughness = 0.35
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.32, 0.3, 0.26)
	trim.metallic = 0.7
	trim.roughness = 0.45
	_glyph_mat = StandardMaterial3D.new()
	_glyph_mat.albedo_color = GREEN
	_glyph_mat.emission_enabled = true
	_glyph_mat.emission = GREEN
	_glyph_mat.emission_energy_multiplier = 2.0
	_core_mat = _glyph_mat.duplicate()

	# Everything faces -Z (into the room); the disc is built lying in the XY plane.
	_disc(4.6, 0.5, Vector3(0, 0, 0.1), trim)  # frame
	_disc(4.1, 0.6, Vector3.ZERO, metal)  # the plug
	for i in 3:
		var ring := Node3D.new()
		ring.position.z = -0.32 - i * 0.04
		add_child(ring)
		var r := 3.6 - i * 1.05
		var marks := 10 + i * 4
		for k in marks:
			# Glyph ticks around each ring, a few missing so the turning is visible.
			if (k * 7 + i * 3) % 5 == 0:
				continue
			var a := TAU * k / marks
			var g := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(0.12, 0.42 - i * 0.08, 0.05)
			g.mesh = b
			g.material_override = _glyph_mat
			g.position = Vector3(cos(a), sin(a), 0) * r
			g.rotation.z = a - PI / 2
			ring.add_child(g)
		var groove := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r + 0.28
		tm.outer_radius = r + 0.38
		tm.rings = 48
		tm.ring_segments = 6
		groove.mesh = tm
		groove.material_override = trim
		groove.rotation.x = PI / 2
		ring.add_child(groove)
		_rings.append(ring)
	# Locking bolts around the frame.
	for k in 8:
		var a := TAU * k / 8.0 + PI / 8.0
		var bolt := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.9, 0.5, 0.5)
		bolt.mesh = bm
		bolt.material_override = trim
		bolt.position = Vector3(cos(a), sin(a), 0) * 4.5 + Vector3(0, 0, -0.2)
		bolt.rotation.z = a
		add_child(bolt)
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 1.1
	core.mesh = sm
	core.material_override = _core_mat
	core.position.z = -0.35
	add_child(core)

	_light = OmniLight3D.new()
	_light.light_color = GREEN
	_light.omni_range = 14.0
	_light.light_energy = 1.2
	_light.position = Vector3(0, 0, -2.0)
	add_child(_light)
	var fill := OmniLight3D.new()  # dim green over the whole chamber
	fill.light_color = GREEN
	fill.omni_range = 26.0
	fill.omni_attenuation = 1.4
	fill.light_energy = 0.7
	fill.shadow_enabled = true
	fill.position = Vector3(0, 2.0, -12.0)
	add_child(fill)
	# Slow green motes drifting off the door.
	_motes = CPUParticles3D.new()
	_motes.amount = 30
	_motes.lifetime = 4.0
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_motes.emission_sphere_radius = 3.5
	_motes.direction = Vector3(0, 0.3, -1)
	_motes.spread = 40.0
	_motes.initial_velocity_min = 0.2
	_motes.initial_velocity_max = 0.6
	_motes.gravity = Vector3(0, 0.15, 0)
	_motes.scale_amount_min = 0.03
	_motes.scale_amount_max = 0.07
	var dot := SphereMesh.new()
	dot.radius = 0.5
	dot.height = 1.0
	dot.radial_segments = 6
	dot.rings = 3
	dot.material = _glyph_mat
	_motes.mesh = dot
	_motes.position.z = -0.6
	add_child(_motes)


func _process(dt: float) -> void:
	_t += dt
	for i in _rings.size():
		_rings[i].rotation.z += dt * (0.12 if i % 2 == 0 else -0.2) * (1.0 + i * 0.3)
	var breathe := 0.5 + 0.5 * sin(_t * 1.3)
	_core_mat.emission_energy_multiplier = 2.5 + 3.0 * breathe
	_glyph_mat.emission_energy_multiplier = 1.6 + 0.6 * sin(_t * 2.1)
	_light.light_energy = 0.9 + 0.6 * breathe


func _disc(r: float, depth: float, pos: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = depth
	c.radial_segments = 48
	mi.mesh = c
	mi.material_override = m
	mi.rotation.x = PI / 2
	mi.position = pos
	add_child(mi)
