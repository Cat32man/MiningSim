extends RefCounted
## Naive surface nets mesher for one chunk.
##
## Input is a padded sample grid of P^3 = (S+2)^3 values covering chunk-local samples
## -1..S on each axis (padded index = local sample + 1). Each cell between samples gets one
## vertex at the average of its edge crossings; each sign-changing edge owned by this chunk
## (edges leaving local samples 0..S-1 in +x/+y/+z) emits one quad. Neighbouring chunks
## see identical padding, so seams line up without stitching.

const S := 16
const P := S + 2
const PP := P * P
const C := S + 1
const CC := C * C

const Materials = preload("res://scripts/world/materials.gd")
const Crystals = preload("res://scripts/world/crystals.gd")

# Corner c of a cell sits at offset (c & 1, (c >> 1) & 1, (c >> 2) & 1).
const CORNER_OFFSET := [0, 1, P, P + 1, PP, PP + 1, PP + P, PP + P + 1]
const EDGE_A := [0, 2, 4, 6, 0, 1, 4, 5, 0, 1, 2, 3]
const EDGE_B := [1, 3, 5, 7, 2, 3, 6, 7, 4, 5, 6, 7]
const CORNER_POS := [
	Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0),
	Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1),
]


## Returns {"arrays": Array for ArrayMesh, "faces": PackedVector3Array,
## "crystals": {material: Array[Transform3D]}} or {} when empty.
## `origin` is the chunk's first world sample, used to seed crystal placement.
static func build(dens: PackedFloat32Array, mats: PackedByteArray, origin: Vector3i) -> Dictionary:
	var any_solid := false
	var any_air := false
	for v in dens:
		if v > 0.0:
			any_solid = true
		else:
			any_air = true
		if any_solid and any_air:
			break
	if not (any_solid and any_air):
		return {}

	var cell_vertex := PackedInt32Array()
	cell_vertex.resize(C * C * C)
	cell_vertex.fill(-1)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var shine := PackedVector2Array()  # UV2: (metallic, glint) for rock.gdshader
	var crystals := {}  # material -> Array of chunk-local Transform3D
	var d := PackedFloat32Array()
	d.resize(8)

	for k in C:
		for j in C:
			for i in C:
				var base := i + j * P + k * PP
				var mask := 0
				for c in 8:
					var v := dens[base + CORNER_OFFSET[c]]
					d[c] = v
					if v > 0.0:
						mask |= 1 << c
				if mask == 0 or mask == 255:
					continue

				var sum := Vector3.ZERO
				var count := 0
				for e in 12:
					var ca: int = EDGE_A[e]
					var cb: int = EDGE_B[e]
					var da := d[ca]
					var db := d[cb]
					if (da > 0.0) != (db > 0.0):
						var t := da / (da - db)
						sum += CORNER_POS[ca].lerp(CORNER_POS[cb], t)
						count += 1

				# Cell i has its min corner at padded sample i, i.e. chunk-local sample i - 1.
				verts.append(Vector3(i - 1, j - 1, k - 1) + sum / count)
				var grad := Vector3(
					(d[1] - d[0]) + (d[3] - d[2]) + (d[5] - d[4]) + (d[7] - d[6]),
					(d[2] - d[0]) + (d[3] - d[1]) + (d[6] - d[4]) + (d[7] - d[5]),
					(d[4] - d[0]) + (d[5] - d[1]) + (d[6] - d[2]) + (d[7] - d[3]))
				normals.append(-grad.normalized() if grad.length_squared() > 0.000001 else Vector3.UP)

				# Colour from the most solid corner.
				var best := 0
				for c in 8:
					if d[c] > d[best]:
						best = c
				var m: int = mats[base + CORNER_OFFSET[best]]
				# Alpha carries the lava glow (inverted, so ordinary rock stays at alpha 1).
				colors.append(Color(Materials.COLOR[m], 1.0 - Materials.GLOW[m]))
				shine.append(Vector2(Materials.METALLIC[m], Materials.GLINT[m]))
				# Crystals only for cells this chunk owns (padding cells belong to neighbours).
				if i > 0 and j > 0 and k > 0 and Crystals.CHANCE.has(m):
					Crystals.cluster(m, origin + Vector3i(i - 1, j - 1, k - 1), verts[verts.size() - 1],
						normals[normals.size() - 1], crystals.get_or_add(m, []))
				cell_vertex[i + j * C + k * CC] = verts.size() - 1

	var indices := PackedInt32Array()
	for k in range(1, S + 1):
		for j in range(1, S + 1):
			for i in range(1, S + 1):
				var s := i + j * P + k * PP
				var solid := dens[s] > 0.0
				var c := i + j * C + k * CC
				# +x edge: u = y, v = z
				if (dens[s + 1] > 0.0) != solid:
					_quad(indices, cell_vertex, c - C - CC, c - CC, c, c - C, solid)
				# +y edge: u = z, v = x
				if (dens[s + P] > 0.0) != solid:
					_quad(indices, cell_vertex, c - 1 - CC, c - 1, c, c - CC, solid)
				# +z edge: u = x, v = y
				if (dens[s + PP] > 0.0) != solid:
					_quad(indices, cell_vertex, c - 1 - C, c - C, c, c - 1, solid)

	if indices.is_empty():
		return {}

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV2] = shine
	arrays[Mesh.ARRAY_INDEX] = indices

	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for n in indices.size():
		faces[n] = verts[indices[n]]
	return {"arrays": arrays, "faces": faces, "crystals": crystals}


## c0..c3 go around the edge so (c0, c1, c2) has a right-handed normal along +axis.
## Godot treats clockwise triangles as front faces, so the order is flipped to face the air side.
static func _quad(indices: PackedInt32Array, cell_vertex: PackedInt32Array,
		c0: int, c1: int, c2: int, c3: int, solid_first: bool) -> void:
	var v0 := cell_vertex[c0]
	var v1 := cell_vertex[c1]
	var v2 := cell_vertex[c2]
	var v3 := cell_vertex[c3]
	if v0 < 0 or v1 < 0 or v2 < 0 or v3 < 0:
		return
	if solid_first:
		# Surface faces +axis.
		indices.append_array([v0, v3, v2, v0, v2, v1])
	else:
		indices.append_array([v0, v1, v2, v0, v2, v3])
