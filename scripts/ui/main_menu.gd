extends CanvasLayer
## Title screen: big title over a dark cave-toned backdrop, one card per save slot.

signal new_game(slot: int)
signal continue_game(slot: int)
signal text_editor

const UI = preload("res://scripts/ui/ui_kit.gd")
const SaveSystem = preload("res://scripts/save/save_system.gd")
const Items = preload("res://scripts/items/items.gd")

const SLOTS := 3
const ACCENT := Color(1.0, 0.72, 0.3)
const TEXT := Color(0.92, 0.91, 0.88)
const DIM := Color(0.6, 0.6, 0.58)
const CARD_WIDTH := 760.0
const BUTTON_WIDTH := 190.0

var _cards: VBoxContainer
var _glow: TextureRect
var _glow_tex: GradientTexture2D
var _dust: CPUParticles2D
var _t := 0.0
## Slot waiting for a second click to confirm overwrite / delete.
var _confirm := {}  # slot -> "new" | "delete"


func _ready() -> void:
	layer = 10
	_build_backdrop()

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)

	var title := UI.label("MININGSIM", 64, ACCENT)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	column.add_child(title)
	var subtitle := UI.label("Dig deep. Build out. Don't wake the swarm.   ·   prototype build", 18, DIM)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_OFF
	column.add_child(subtitle)
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	column.add_child(gap)

	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 12)
	column.add_child(_cards)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.custom_minimum_size.y = 56
	footer.add_theme_constant_override("separation", 10)
	var texts := _button("Text editor", func(): text_editor.emit(), false)
	texts.size_flags_vertical = Control.SIZE_SHRINK_END
	footer.add_child(texts)
	var quit := _button("Quit", func(): get_tree().quit(), false)
	quit.size_flags_vertical = Control.SIZE_SHRINK_END
	footer.add_child(quit)
	column.add_child(footer)
	_rebuild()


func _build_backdrop() -> void:
	var base := ColorRect.new()
	base.color = Color(0.035, 0.032, 0.03)
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(base)
	# Warm lamp-like glow from the upper left fading into the dark.
	var grad := Gradient.new()
	grad.set_color(0, Color(0.42, 0.26, 0.12, 0.55))
	grad.set_color(1, Color(0, 0, 0, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.25, 0.2)
	tex.fill_to = Vector2(0.95, 0.95)
	tex.width = 512
	tex.height = 512
	var glow := TextureRect.new()
	glow.texture = tex
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(glow)
	_glow = glow
	_glow_tex = tex

	# Dust motes drifting through the lamp light (something is always moving).
	var dust := CPUParticles2D.new()
	dust.amount = 90
	dust.lifetime = 16.0
	dust.preprocess = 16.0  # start already filled
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(1800, 1000)
	dust.position = Vector2(960, 540)
	dust.direction = Vector2(1, -0.2)
	dust.spread = 180.0
	dust.initial_velocity_min = 4.0
	dust.initial_velocity_max = 14.0
	dust.gravity = Vector2.ZERO
	dust.scale_amount_min = 1.0
	dust.scale_amount_max = 3.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.8, 0.55, 0.0))
	fade.add_point(0.2, Color(1.0, 0.8, 0.55, 0.35))
	fade.add_point(0.8, Color(1.0, 0.8, 0.55, 0.3))
	fade.set_color(fade.get_point_count() - 1, Color(1.0, 0.8, 0.55, 0.0))
	dust.color_ramp = fade
	add_child(dust)
	_dust = dust


func _process(dt: float) -> void:
	_t += dt
	# The lamp glow wanders and breathes, with a faint flicker like a lantern.
	_glow_tex.fill_from = Vector2(0.25 + sin(_t * 0.13) * 0.05, 0.2 + cos(_t * 0.11) * 0.04)
	var flicker := sin(_t * 7.3) * 0.015 + sin(_t * 13.1) * 0.01
	_glow.modulate.a = 0.85 + sin(_t * 0.6) * 0.1 + flicker
	# Slowly turning air current pushes the motes around.
	_dust.gravity = Vector2(cos(_t * 0.07), sin(_t * 0.05) * 0.5) * 3.0


func _rebuild() -> void:
	UI.clear(_cards)
	for slot in range(1, SLOTS + 1):
		_cards.add_child(_card(slot))


func _card(slot: int) -> Control:
	var data := SaveSystem.read(slot)
	var card := PanelContainer.new()
	card.custom_minimum_size.x = CARD_WIDTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.078, 0.082, 0.92)
	sb.border_color = Color(ACCENT, 0.55) if not data.is_empty() else Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.border_width_left = 4 if not data.is_empty() else 1
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(18)
	card.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	card.add_child(row)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size.x = CARD_WIDTH - BUTTON_WIDTH - 90
	row.add_child(info)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.custom_minimum_size.x = BUTTON_WIDTH
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(buttons)

	var pending: String = _confirm.get(slot, "")
	if data.is_empty():
		info.add_child(_line("SLOT %d" % slot, 22, DIM))
		info.add_child(_line("Empty — start a new expedition", 16, DIM))
		buttons.add_child(_button("New game", func(): new_game.emit(slot), true))
		return card

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	# Short labels side by side must not word-wrap: a wrapping label in a row gets no width.
	var name_l := _line("SLOT %d" % slot, 22, ACCENT)
	name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	header.add_child(name_l)
	var time_l := _line("%d min played" % int(data.get("play_time", 0.0) / 60.0), 16, DIM)
	time_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	time_l.size_flags_vertical = Control.SIZE_SHRINK_END
	header.add_child(time_l)
	info.add_child(header)
	info.add_child(_line("Last played " + _local_time(int(data.get("saved_at", 0))), 16, TEXT))
	info.add_child(_line("Pod: " + _pod_summary(data), 15, DIM))

	buttons.add_child(_button("Continue", func(): continue_game.emit(slot), true))
	var small := HBoxContainer.new()
	small.add_theme_constant_override("separation", 8)
	var new_b := _button("Overwrite?" if pending == "new" else "New", _confirmed.bind(slot, "new"), false)
	var del_b := _button("Really?" if pending == "delete" else "Delete", _confirmed.bind(slot, "delete"), false)
	for b in [new_b, del_b]:
		b.custom_minimum_size = Vector2((BUTTON_WIDTH - 8) / 2.0, 34)
		b.add_theme_font_size_override("font_size", 15)
		small.add_child(b)
	if pending == "delete":
		del_b.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	buttons.add_child(small)
	return card


func _line(text: String, size: int, color: Color) -> Label:
	var l := UI.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, action: Callable, primary: bool) -> Button:
	var b := UI.button(text, action)
	b.custom_minimum_size = Vector2(BUTTON_WIDTH, 44 if primary else 38)
	if primary:
		for state in ["normal", "hover", "pressed"]:
			var s := StyleBoxFlat.new()
			s.bg_color = ACCENT.darkened(0.15 if state == "normal" else (0.0 if state == "hover" else 0.3))
			s.set_corner_radius_all(4)
			b.add_theme_stylebox_override(state, s)
		b.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04))
		b.add_theme_color_override("font_hover_color", Color(0.05, 0.04, 0.03))
		b.add_theme_color_override("font_pressed_color", Color(0.05, 0.04, 0.03))
	return b


## Saves store UTC; show the player's local clock.
func _local_time(unix: int) -> String:
	var local := unix + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(local)
	const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%s %d, %d at %02d:%02d" % [MONTHS[d["month"] - 1], d["day"], d["year"], d["hour"], d["minute"]]


func _pod_summary(data: Dictionary) -> String:
	var totals := {}
	for s in data.get("pod_storage", []):
		if s:
			totals[s["id"]] = totals.get(s["id"], 0) + s["count"]
	if totals.is_empty():
		return "empty"
	var parts: Array[String] = []
	for id in totals:
		parts.append("%d %s" % [totals[id], Items.name_of(id)])
	return "  ·  ".join(parts)


## Destructive actions need a second click on the same button.
func _confirmed(slot: int, action: String) -> void:
	if _confirm.get(slot, "") != action:
		_confirm = {slot: action}
		_rebuild()
		return
	_confirm = {}
	if action == "new":
		new_game.emit(slot)
	else:
		SaveSystem.delete(slot)
		_rebuild()
