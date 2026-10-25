extends RefCounted
## Small helpers so all menus share one look.


## Adds a centred dark panel to `layer` and returns its content VBox.
static func panel(layer: Node, min_width: float) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.085, 0.09, 0.95)
	sb.border_color = Color(0.85, 0.6, 0.25, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(24)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size.x = min_width
	center.add_child(p)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	p.add_child(box)
	return box


static func label(text: String, size: int = 18, color := Color(0.9, 0.9, 0.88)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, on_press: Callable, enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.add_theme_font_size_override("font_size", 18)
	b.custom_minimum_size = Vector2(150, 36)
	b.pressed.connect(on_press)
	return b


static func clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
