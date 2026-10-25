extends "res://scripts/build/storage.gd"
## Large container (elevator shop blueprint): two containers stacked, 48 slots.

const LARGE_SLOTS := 48


func _init() -> void:
	super()
	inv = Inventory.new(LARGE_SLOTS, "Large container")


func _build_visuals() -> void:
	super()
	var paint := mat(Color(0.3, 0.32, 0.4), 0.35, 0.6)
	var steel := mat(Color(0.35, 0.36, 0.38), 0.85, 0.4)
	box(Vector3(2.4, 1.4, 1.4), Vector3(0, 2.3, 0), paint)
	for i in 7:
		box(Vector3(0.05, 1.3, 1.46), Vector3(-1.05 + i * 0.35, 2.3, 0), paint)
	box(Vector3(2.5, 0.08, 1.5), Vector3(0, 3.0, 0), steel)


func _collision_shape() -> Shape3D:
	var b := BoxShape3D.new()
	b.size = Vector3(2.5, 3.05, 1.5)
	return b


func _collision_offset() -> Vector3:
	return Vector3(0, 1.52, 0)
