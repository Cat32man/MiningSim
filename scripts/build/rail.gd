extends "res://scripts/build/building.gd"
## One 4 m piece of rail line. Pieces join end to start (the build controller snaps a new
## piece onto the free end you aim near, turned toward your aim and tilted to follow the
## ground); a rail cart rides along them. Local -Z is the way the piece runs: it starts at
## its origin and ends LENGTH ahead.

const LENGTH := 4.0
const GAUGE := 1.1
const LINK := 0.3  # ends closer than this are joined

static var _mesh: ArrayMesh


func _init() -> void:
	is_power_node = false
	raidable = false


func _ready() -> void:
	super()
	if not ghost and not preview:
		add_to_group("rails")


func _build_visuals() -> void:
	if _mesh == null:
		_mesh = _make_mesh()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	add_child(mi)


## Two steel rails on five sleepers, as one mesh shared by every piece (lines get long).
static func _make_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var steel := SurfaceTool.new()
	steel.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rail_box := BoxMesh.new()
	rail_box.size = Vector3(0.09, 0.12, LENGTH)
	for side in [-1.0, 1.0]:
		steel.append_from(rail_box, 0, Transform3D(Basis.IDENTITY, Vector3(side * GAUGE * 0.5, 0.18, -LENGTH * 0.5)))
	steel.commit(mesh)
	mesh.surface_set_material(0, mat(Color(0.55, 0.56, 0.6), 0.85, 0.35))
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sleeper := BoxMesh.new()
	sleeper.size = Vector3(1.6, 0.1, 0.25)
	for k in 5:
		wood.append_from(sleeper, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.07, -0.4 - k * 0.8)))
	wood.commit(mesh)
	mesh.surface_set_material(1, mat(Color(0.36, 0.25, 0.16), 0.0, 0.85))
	return mesh


func _collision_shape() -> Shape3D:
	var b := BoxShape3D.new()
	b.size = Vector3(1.6, 0.24, LENGTH)
	return b


func _collision_offset() -> Vector3:
	return Vector3(0, 0.12, -LENGTH * 0.5)


func start_point() -> Vector3:
	return global_position


func end_point() -> Vector3:
	return global_transform * Vector3(0, 0, -LENGTH)


## Which way the piece runs (start to end), in world space.
func dir() -> Vector3:
	return -global_basis.z.normalized()


func hover_text() -> String:
	return "Rail · [X] remove"
