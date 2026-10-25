extends RefCounted
## Little 3D models of crafted things, for recipe cards. make(key) builds a fresh one:
## "battery", "shredder", "thermal_suit", "dagger", "drill", "steel", "obsidianite",
## "shredder_hop", "shredder_teeth", "shredder_up". Unknown keys get a plain crate.

const Buildables = preload("res://scripts/build/buildables.gd")


static func make(key: String) -> Node3D:
	match key:
		"battery":
			return _battery()
		"shredder":
			return _shredder()
		"shredder_hop":
			var s := _shredder()
			_spring(s, Vector3(0.34, 0.0, 0.0))
			_spring(s, Vector3(-0.34, 0.0, 0.0))
			return s
		"shredder_teeth":
			var s := _shredder()
			var d := _crystal(Color(0.75, 0.92, 1.0), 0.09, 4)
			d.position = Vector3(0.32, 0.12, 0.15)
			s.add_child(d)
			return s
		"shredder_up":
			return _shredder()
		"thermal_suit":
			return _suit()
		"dagger":
			return _dagger()
		"drill":
			return _drill()
		"steel":
			return _steel()
		"obsidianite":
			return _crystal(Color(0.6, 0.3, 0.9), 0.18, 6, 1.6)
	var root := Node3D.new()
	_box(root, Vector3(0.4, 0.3, 0.3), Vector3.ZERO, _mat(Color(0.5, 0.42, 0.3)))
	return root


static func _mat(c: Color, metal := 0.2, rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


static func _glow(c: Color, energy := 2.0) -> StandardMaterial3D:
	var m := _mat(c)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, m: Material, sides := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = sides
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _sphere(parent: Node3D, r: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _capsule(parent: Node3D, r: float, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _battery() -> Node3D:
	var root := Node3D.new()
	var shell := _mat(Color(0.2, 0.21, 0.23), 0.6, 0.4)
	_cyl(root, 0.16, 0.16, 0.5, Vector3.ZERO, shell)
	_cyl(root, 0.165, 0.165, 0.12, Vector3(0, 0.06, 0), _glow(Color(0.35, 0.95, 0.5), 2.5))
	_cyl(root, 0.17, 0.17, 0.04, Vector3(0, 0.25, 0), _mat(Color(0.75, 0.5, 0.12), 0.4, 0.5))
	_cyl(root, 0.05, 0.05, 0.06, Vector3(0, 0.29, 0), _mat(Color(0.7, 0.7, 0.72), 0.9, 0.3))
	return root


## The real Shredder, legs out.
static func _shredder() -> Node3D:
	var s: Node3D = Buildables.make("shredder")
	s.preview = true
	s.set_meta("thumb_zoom", 1.45)
	return s


static func _spring(parent: Node3D, pos: Vector3) -> void:
	var m := _mat(Color(0.66, 0.71, 0.78), 0.7, 0.3)
	for i in 4:
		var mi := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.045
		t.outer_radius = 0.07
		mi.mesh = t
		mi.material_override = m
		mi.position = pos + Vector3(0, 0.04 + i * 0.05, 0)
		mi.rotation.z = 0.15 * (1 if i % 2 == 0 else -1)
		parent.add_child(mi)


## Faceted gem: a prism with pointed ends.
static func _crystal(c: Color, r: float, sides: int, stretch := 1.0) -> Node3D:
	var root := Node3D.new()
	var m := _glow(c, 0.6)
	m.metallic = 0.3
	m.roughness = 0.15
	_cyl(root, r, r, r * 1.2 * stretch, Vector3.ZERO, m, sides)
	_cyl(root, 0.0, r, r * 1.1 * stretch, Vector3(0, r * 1.15 * stretch, 0), m, sides)
	_cyl(root, r, 0.0, r * 0.8 * stretch, Vector3(0, -r * 1.0 * stretch, 0), m, sides)
	return root


static func _steel() -> Node3D:
	var root := Node3D.new()
	var m := _mat(Color(0.66, 0.71, 0.78), 0.75, 0.3)
	for i in 3:
		var bar := _cyl(root, 0.07, 0.1, 0.42, Vector3(-0.11 + i * 0.11, 0.0, 0), m, 4)
		bar.rotation = Vector3(PI / 2, PI / 4, 0)
	var top := _cyl(root, 0.07, 0.1, 0.42, Vector3(0, 0.1, 0), m, 4)
	top.rotation = Vector3(PI / 2, PI / 4, 0)
	return root


static func _suit() -> Node3D:
	var root := Node3D.new()
	var cloth := _mat(Color(0.85, 0.5, 0.25), 0.1, 0.7)
	var foil := _mat(Color(0.78, 0.78, 0.8), 0.6, 0.35)
	_capsule(root, 0.2, 0.62, Vector3(0, 0.0, 0), cloth)  # torso
	_box(root, Vector3(0.34, 0.36, 0.14), Vector3(0, 0.02, -0.2), foil)  # tank pack
	_sphere(root, 0.16, Vector3(0, 0.42, 0.01), foil)  # helmet
	_box(root, Vector3(0.2, 0.09, 0.05), Vector3(0, 0.43, 0.14), _glow(Color(1.0, 0.6, 0.2), 1.5))  # visor
	for x in [-0.27, 0.27]:
		var arm := _capsule(root, 0.07, 0.46, Vector3(x, -0.02, 0), cloth)
		arm.rotation.z = 0.25 * signf(x)
		_cyl(root, 0.075, 0.075, 0.06, Vector3(x * 1.12, -0.2, 0), foil)  # cuffs
	_box(root, Vector3(0.4, 0.05, 0.42), Vector3(0, -0.12, 0), foil)  # belt
	return root


## The crooked dagger: wrapped grip, steel guard, curved bone blade.
static func _dagger() -> Node3D:
	var root := Node3D.new()
	var bone := _mat(Color(0.86, 0.77, 0.58), 0.0, 0.35)
	bone.clearcoat_enabled = true
	var wrap := _mat(Color(0.2, 0.12, 0.08), 0.0, 0.9)
	var steel := _mat(Color(0.62, 0.64, 0.68), 0.85, 0.3)
	_cyl(root, 0.016, 0.018, 0.11, Vector3(0, -0.06, 0), wrap)
	_box(root, Vector3(0.07, 0.016, 0.02), Vector3(0, 0.0, 0), steel)
	var p := Vector3(0, 0.005, 0)
	var dir := Vector3.UP
	for i in 6:
		var seg_len := 0.045
		var r0 := 0.018 * (1.0 - i / 6.0) + 0.003
		var r1 := 0.018 * (1.0 - (i + 1) / 6.0) + 0.001
		var seg := _cyl(root, r1, r0, seg_len, Vector3.ZERO, bone, 6)
		var mid := p + dir * seg_len * 0.5
		seg.basis = Basis(Quaternion(Vector3.UP, dir))
		seg.position = mid
		p += dir * seg_len
		dir = dir.rotated(Vector3(0, 0, 1), -0.22)
	root.rotation.z = 0.5
	return root


static func _drill() -> Node3D:
	var root := Node3D.new()
	var body := _mat(Color(0.8, 0.52, 0.12), 0.35, 0.55)
	var dark := _mat(Color(0.18, 0.18, 0.2), 0.7, 0.4)
	var bit := _glow(Color(0.75, 0.92, 1.0), 0.8)
	bit.roughness = 0.15
	var barrel := _cyl(root, 0.09, 0.11, 0.36, Vector3(0, 0, 0), body)
	barrel.rotation.z = PI / 2
	var collar := _cyl(root, 0.06, 0.06, 0.08, Vector3(0.22, 0, 0), dark)
	collar.rotation.z = PI / 2
	var tip := _cyl(root, 0.0, 0.055, 0.22, Vector3(0.36, 0, 0), bit, 6)
	tip.rotation.z = -PI / 2
	var handle := _box(root, Vector3(0.07, 0.24, 0.07), Vector3(-0.08, -0.16, 0), dark)
	handle.rotation.z = -0.25
	return root
