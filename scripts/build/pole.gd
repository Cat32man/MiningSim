extends "res://scripts/build/building.gd"
## Power pole: a tall, cheap power node with long reach.


func _init() -> void:
	connect_range = 20.0
	cable_anchor = Vector3(0, 3.85, 0)


func _build_visuals() -> void:
	var steel := mat(Color(0.42, 0.43, 0.45), 0.8, 0.45)
	box(Vector3(0.5, 0.08, 0.5), Vector3(0, 0.04, 0), steel)
	cyl(0.09, 4.0, Vector3(0, 2.0, 0), steel)
	box(Vector3(0.9, 0.08, 0.08), Vector3(0, 3.75, 0), steel)
	cyl(0.05, 0.16, Vector3(0, 3.87, 0), glow(Color(0.5, 0.85, 1.0), 2.0))


func _collision_shape() -> Shape3D:
	var c := CylinderShape3D.new()
	c.radius = 0.15
	c.height = 4.0
	return c


func _collision_offset() -> Vector3:
	return Vector3(0, 2.0, 0)


func hover_text() -> String:
	return "Power pole\n" + power_line()
