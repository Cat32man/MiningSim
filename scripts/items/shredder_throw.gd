extends Node3D
## A thrown SHREDDER-MK1 in flight. Flies ballistically until it hits rock, then clamps on
## there (surface-aligned) as a deployed Shredder and starts on the vein it touched.

const Buildables = preload("res://scripts/build/buildables.gd")
const Items = preload("res://scripts/items/items.gd")
const Sfx = preload("res://scripts/audio/sfx.gd")

const GRAVITY := 9.8
const MAX_FLIGHT := 6.0

var velocity := Vector3.ZERO
var energy := 0.0
var grid
var player

var _age := 0.0
var _mesh: Node3D


func _ready() -> void:
	# The model at its first frame: legs folded, body up.
	_mesh = Node3D.new()
	add_child(_mesh)
	var model: Node3D = preload("res://assets/shredder/v1.glb").instantiate()
	model.scale = Vector3.ONE * 0.28
	model.position.y = -0.25  # spin around its middle, not its tip
	_mesh.add_child(model)
	var ap: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	if ap:
		ap.active = false


func _physics_process(dt: float) -> void:
	_age += dt
	velocity.y -= GRAVITY * dt
	var from := global_position
	var to := from + velocity * dt
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)  # terrain only
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_deploy(hit["position"], hit["normal"])
		return
	global_position = to
	_mesh.rotate_x(dt * 9.0)
	if _age > MAX_FLIGHT:
		# Fell into a void: leave it where it ended up rather than losing it.
		if grid and grid.drop_cache.is_valid():
			grid.drop_cache.call(global_position, [Items.new_shredder(energy)])
		queue_free()


func _deploy(at: Vector3, normal: Vector3) -> void:
	var b := Buildables.make("shredder")
	b.energy = energy
	var y := normal.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	b.transform = Transform3D(Basis(x, y, x.cross(y)), at)
	grid.add(b)
	b.scan_vein()
	Sfx.play_3d("place", at, grid, 0.0, 1.4)
	if player:
		player._flash(b.status)
	queue_free()
