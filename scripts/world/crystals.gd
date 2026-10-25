extends RefCounted
## DRG-style ore crystals that stick out of exposed ore so veins read at a glance:
## square-cut for iron, triangular spires for electrum, faceted octahedrons for diamond,
## hexagonal prisms for cobalt.
## Placement is a pure function of the world cell, so crystals stay put across remeshes.

const Materials = preload("res://scripts/world/materials.gd")

## Materials that grow crystals, and the chance a surface cell of that ore gets a cluster.
const CHANCE := {Materials.IRON: 0.4, Materials.ELECTRUM: 0.4, Materials.DIAMOND: 0.65, Materials.COBALT: 0.45,
	Materials.OBSIDIAN: 0.55}
const MAX_PER_CLUSTER := 3


## Appends 0..MAX_PER_CLUSTER transforms (chunk-local) for one surface cell to `out`.
static func cluster(mat: int, cell: Vector3i, pos: Vector3, normal: Vector3, out: Array) -> void:
	var h := _hash(cell)
	if float(h & 0xFFFF) / 65535.0 > CHANCE[mat]:
		return
	var count := 1 + (h >> 16) % MAX_PER_CLUSTER
	var up := normal.normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	for i in count:
		var r := _rand3(h, i)  # three values in 0..1
		# Lean each crystal away from the surface normal and spread the cluster a little.
		var tilt := Basis(side.rotated(up, r.x * TAU), (r.y - 0.5) * 1.1)
		var dir := tilt * up
		var basis := _basis_from_up(dir).rotated(dir, r.z * TAU)
		var s := lerpf(0.7, 1.3, r.y) * (0.75 if i > 0 else 1.0)
		var offset := side.rotated(up, r.x * TAU) * (0.0 if i == 0 else 0.18 + r.z * 0.12)
		out.append(Transform3D(basis.scaled(Vector3(s, s, s)), pos + offset - up * 0.06))


static func _basis_from_up(up: Vector3) -> Basis:
	var x := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(up).normalized()
	return Basis(x, up, z)


static func _hash(c: Vector3i) -> int:
	var h := (c.x * 73856093) ^ (c.y * 19349663) ^ (c.z * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))


static func _rand3(h: int, i: int) -> Vector3:
	var a := _hash(Vector3i(h & 0x3FF, i, h >> 10))
	return Vector3(float(a & 0x3FF) / 1023.0, float((a >> 10) & 0x3FF) / 1023.0, float((a >> 20) & 0x3FF) / 1023.0)


# --- Look -------------------------------------------------------------------------

static func make_mesh(mat: int) -> Mesh:
	match mat:
		Materials.IRON:
			# Square-cut column with a flat top.
			var b := BoxMesh.new()
			b.size = Vector3(0.12, 0.26, 0.12)
			return _lifted(b, 0.13)
		Materials.ELECTRUM:
			# Triangular spire.
			var c := CylinderMesh.new()
			c.radial_segments = 3
			c.rings = 1
			c.top_radius = 0.015
			c.bottom_radius = 0.11
			c.height = 0.42
			return _lifted(c, 0.21)
		Materials.OBSIDIAN:
			# Long glassy shard.
			var sh := CylinderMesh.new()
			sh.radial_segments = 4
			sh.rings = 1
			sh.top_radius = 0.0
			sh.bottom_radius = 0.07
			sh.height = 0.55
			return _lifted(sh, 0.27)
		Materials.COBALT:
			# Stubby hexagonal prism.
			var hx := CylinderMesh.new()
			hx.radial_segments = 6
			hx.rings = 1
			hx.top_radius = 0.075
			hx.bottom_radius = 0.085
			hx.height = 0.3
			return _lifted(hx, 0.15)
		_:
			return _octahedron(0.12, 0.26)


static func make_material(mat: int) -> StandardMaterial3D:
	# No glow: crystals are lit by your flashlight and flares like the rock around them.
	# Moderate metallic keeps some diffuse colour; full metal goes black in a dark cave.
	var m := StandardMaterial3D.new()
	match mat:
		Materials.IRON:
			m.albedo_color = Color(0.6, 0.34, 0.2)
			m.metallic = 0.45
			m.roughness = 0.35
		Materials.ELECTRUM:
			m.albedo_color = Color(0.92, 0.76, 0.38)
			m.metallic = 0.6
			m.roughness = 0.22
		Materials.OBSIDIAN:
			m.albedo_color = Color(0.12, 0.08, 0.18)
			m.metallic = 0.0
			m.roughness = 0.02
			m.metallic_specular = 1.0
			m.clearcoat_enabled = true
			m.rim_enabled = true
			m.rim = 0.5
			m.rim_tint = 0.8
		Materials.COBALT:
			m.albedo_color = Color(0.22, 0.4, 0.95)
			m.metallic = 0.55
			m.roughness = 0.25
		_:
			m.albedo_color = Color(0.82, 0.95, 1.0)
			m.metallic = 0.0
			m.roughness = 0.03
			m.metallic_specular = 1.0
			m.clearcoat_enabled = true
			m.rim_enabled = true
			m.rim = 0.6
	return m


## Primitive meshes are centred; crystals should grow out from their base. Also re-derives
## flat normals so every facet catches light on its own (crystals shouldn't look smooth).
static func _lifted(prim: PrimitiveMesh, lift: float) -> Mesh:
	var st := SurfaceTool.new()
	st.create_from(prim, 0)
	st.deindex()
	st.generate_normals()
	var arr := st.commit_to_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y += lift
	arr[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Elongated octahedron (a classic cut-gem bipyramid), flat-shaded, base at y=0.
static func _octahedron(r: float, h: float) -> Mesh:
	var top := Vector3(0, h * 2.0, 0)
	var bottom := Vector3(0, 0, 0)
	var mid := h * 0.8
	var ring := [Vector3(r, mid, 0), Vector3(0, mid, r), Vector3(-r, mid, 0), Vector3(0, mid, -r)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 4]
		_tri(st, top, b, a)
		_tri(st, bottom, a, b)
	return st.commit()


## (a, b, c) is given counter-clockwise from outside; Godot front faces are clockwise,
## so the vertices go in as a, c, b with the outward normal.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	for v in [a, c, b]:
		st.set_normal(n)
		st.add_vertex(v)
