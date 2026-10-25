extends CanvasLayer
## Full-screen cover while the caves around the player stream in (game start and respawn).
## Hides the frozen view underneath; fades out once the terrain is solid.

const UI = preload("res://scripts/ui/ui_kit.gd")
const FADE_OUT := 0.5

const TIPS := [
	"Hold Q to scan for ore, caches and your bodies.",
	"Hold Space against rock to climb — stamina refills on the ground.",
	"Tap F to throw a flare. Hold F to toggle your flashlight.",
	"Bugs get bolder the more you dig and the deeper you go.",
	"Hard rock needs a diamond tip — craft one at the bench.",
	"Machines draw from storage within 15 m when you build.",
	"Stuck? Esc → Unstuck puts you back where you last stood.",
]

var _title: Label
var _sub: Label
var _bar: ColorRect
var _bar_back: ColorRect
var _tip: Label
var _root: Control
var _t := 0.0
var _fading := -1.0
var _progress := 0.0


func _ready() -> void:
	layer = 9  # over the HUD and death screen, under the pause menu
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var base := ColorRect.new()
	base.color = Color(0.035, 0.032, 0.03)
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(base)

	var grad := Gradient.new()
	grad.set_color(0, Color(0.42, 0.26, 0.12, 0.4))
	grad.set_color(1, Color(0, 0, 0, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.45)
	tex.fill_to = Vector2(1.0, 1.0)
	var glow := TextureRect.new()
	glow.texture = tex
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(glow)

	# Dust falling slowly through the lamp light.
	var dust := CPUParticles2D.new()
	dust.amount = 70
	dust.lifetime = 14.0
	dust.preprocess = 14.0
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(1800, 1000)
	dust.position = Vector2(960, 540)
	dust.direction = Vector2(0.2, 1)
	dust.spread = 60.0
	dust.initial_velocity_min = 6.0
	dust.initial_velocity_max = 18.0
	dust.gravity = Vector2.ZERO
	dust.scale_amount_min = 1.0
	dust.scale_amount_max = 3.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.8, 0.55, 0.0))
	fade.add_point(0.2, Color(1.0, 0.8, 0.55, 0.3))
	fade.add_point(0.8, Color(1.0, 0.8, 0.55, 0.25))
	fade.set_color(fade.get_point_count() - 1, Color(1.0, 0.8, 0.55, 0.0))
	dust.color_ramp = fade
	_root.add_child(dust)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	_title = UI.label("", 40, Color(1.0, 0.75, 0.4))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_sub = UI.label("", 18, Color(0.75, 0.72, 0.68))
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_sub)

	_bar_back = ColorRect.new()
	_bar_back.color = Color(1, 1, 1, 0.08)
	_bar_back.custom_minimum_size = Vector2(420, 4)
	var bar_row := CenterContainer.new()
	bar_row.add_child(_bar_back)
	box.add_child(bar_row)
	_bar = ColorRect.new()
	_bar.color = Color(1.0, 0.72, 0.35)
	_bar.size = Vector2(0, 4)
	_bar_back.add_child(_bar)

	_tip = UI.label("", 16, Color(0.6, 0.58, 0.55))
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.anchor_left = 0.0
	_tip.anchor_right = 1.0
	_tip.anchor_top = 1.0
	_tip.anchor_bottom = 1.0
	_tip.offset_top = -80
	_tip.offset_bottom = -50
	_root.add_child(_tip)
	visible = false


func show_loading(title: String, sub: String) -> void:
	_title.text = title
	_sub.text = sub
	_tip.text = TIPS[randi() % TIPS.size()]
	_t = 0.0
	_fading = -1.0
	_progress = 0.0
	_bar.size.x = 0.0
	_root.modulate.a = 1.0
	visible = true


func set_progress(f: float) -> void:
	_progress = maxf(_progress, f)


## Terrain is ready: fade away.
func finish() -> void:
	if visible and _fading < 0.0:
		_fading = 0.0
		_progress = 1.0


func is_showing() -> bool:
	return visible and _fading < 0.0


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	_bar.size.x = lerpf(_bar.size.x, _bar_back.size.x * _progress, minf(dt * 8.0, 1.0))
	_title.modulate.a = 0.75 + 0.25 * sin(_t * 2.5)
	if _fading >= 0.0:
		_fading += dt
		_root.modulate.a = 1.0 - clampf(_fading / FADE_OUT, 0.0, 1.0)
		if _fading >= FADE_OUT:
			visible = false
