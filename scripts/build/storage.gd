extends "res://scripts/build/building.gd"
## Storage container: a 24-slot grid. Building and crafting can draw from containers near
## you. Removing one drops its contents as a cache on the spot.

const SLOTS := 24

var inv = Inventory.new(SLOTS, "Storage container")


func _init() -> void:
	is_power_node = false


func _build_visuals() -> void:
	var paint := mat(Color(0.28, 0.36, 0.3), 0.35, 0.6)
	var steel := mat(Color(0.35, 0.36, 0.38), 0.85, 0.4)
	box(Vector3(2.4, 1.5, 1.4), Vector3(0, 0.78, 0), paint)
	for i in 7:
		box(Vector3(0.05, 1.4, 1.46), Vector3(-1.05 + i * 0.35, 0.78, 0), paint)
	box(Vector3(2.5, 0.08, 1.5), Vector3(0, 0.04, 0), steel)
	box(Vector3(2.5, 0.08, 1.5), Vector3(0, 1.55, 0), steel)
	box(Vector3(0.3, 0.1, 0.05), Vector3(0, 1.1, 0.73), glow(Color(1.0, 0.72, 0.3), 1.5))


func _collision_shape() -> Shape3D:
	var b := BoxShape3D.new()
	b.size = Vector3(2.5, 1.6, 1.5)
	return b


func _collision_offset() -> Vector3:
	return Vector3(0, 0.8, 0)


func get_inventories() -> Array:
	return [inv]


func ui_build(box_: VBoxContainer, player) -> void:
	box_.add_child(UI.label("STORAGE CONTAINER", 26, Color(1.0, 0.75, 0.4)))
	box_.add_child(UI.button("Deposit all ore", func(): player.deposit_ore_into(inv)))


func hover_text() -> String:
	return "%s — %d / %d slots used\n[E] open" % [display_name(), inv.used_slots(), inv.slots.size()]
