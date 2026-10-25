extends CanvasLayer
## "You died" overlay: fades in over the slumped view, explains what happened to your
## loot, and offers a respawn after a short beat (button or Space).

signal respawn_pressed

const UI = preload("res://scripts/ui/ui_kit.gd")
const UNLOCK_DELAY := 2.0
const FADE_IN := 1.2

var _fade: ColorRect
var _box: VBoxContainer
var _details: Label
var _button: Button
var _t := 0.0


func _ready() -> void:
	layer = 8
	visible = false
	_fade = ColorRect.new()
	_fade.color = Color(0.12, 0.0, 0.0, 0.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_box = VBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", 18)
	center.add_child(_box)
	var title := UI.label("YOU DIED", 72, Color(0.95, 0.3, 0.22))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(title)
	_details = UI.label("", 20, Color(0.9, 0.85, 0.8))
	_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_details.custom_minimum_size.x = 760
	_box.add_child(_details)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(row)
	_button = UI.button("Respawn at drop pod  [Space]", _respawn)
	_button.custom_minimum_size = Vector2(340, 48)
	row.add_child(_button)


func show_death(details: String) -> void:
	_details.text = details
	_t = 0.0
	_fade.color.a = 0.0
	_box.modulate.a = 0.0
	_button.disabled = true
	visible = true


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	var k := clampf(_t / FADE_IN, 0.0, 1.0)
	_fade.color.a = k * 0.82
	_box.modulate.a = clampf((_t - 0.4) / FADE_IN, 0.0, 1.0)
	if _button.disabled and _t >= UNLOCK_DELAY:
		_button.disabled = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and not _button.disabled and event.is_action_pressed("jump"):
		get_viewport().set_input_as_handled()
		_respawn()


func _respawn() -> void:
	if not visible or _button.disabled:
		return
	visible = false
	respawn_pressed.emit()
