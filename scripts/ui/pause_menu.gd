extends CanvasLayer
## Esc menu. Runs while the tree is paused.

signal resume_pressed
signal unstuck_pressed
signal save_pressed
signal save_quit_pressed
signal quit_desktop_pressed

const UI = preload("res://scripts/ui/ui_kit.gd")

var _status: Label


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var box := UI.panel(self, 360)
	box.add_child(UI.label("PAUSED", 26, Color(1.0, 0.75, 0.4)))
	box.add_child(UI.button("Resume", func(): resume_pressed.emit()))
	box.add_child(UI.button("Unstuck", func(): unstuck_pressed.emit()))
	box.add_child(UI.button("Save", func(): save_pressed.emit()))
	box.add_child(UI.button("Save & quit to menu", func(): save_quit_pressed.emit()))
	box.add_child(UI.button("Save & quit to desktop", func(): quit_desktop_pressed.emit()))
	_status = UI.label("", 15, Color(0.7, 0.8, 0.7))
	box.add_child(_status)


func set_status(text: String) -> void:
	_status.text = text
