extends CanvasLayer
## In-game HUD. The player pushes a state dictionary every frame via update_state().
## Every control ignores the mouse: the captured cursor sits at screen centre, and any
## control there that stops mouse events would swallow mouse-look.

const ACCENT := Color(1.0, 0.72, 0.3)
const TEXT := Color(0.92, 0.91, 0.88)
const DIM := Color(0.62, 0.62, 0.6)
const HELP_VISIBLE_TIME := 30.0
const MAX_HEALTH_DISPLAY := 100.0

var _slot_pick: PanelContainer
var _slot_drill: PanelContainer
var _slot_shotgun: PanelContainer
var _slot_pistol: PanelContainer
var _slot_dagger: PanelContainer
var _weapon: Label
var _threat: Label
var _health_bar: ProgressBar
var _health_value: Label
var _vignette: ColorRect
var _dot: Panel
var _dot_style: StyleBoxFlat
var _hit_t := 0.0
var _hit_scale := 1.0
var _drill_label: Label
var _flares: Label
var _scan_label: Label
var _scan_bar: ProgressBar
var _zone: Label
var _stash: Label
var _fuel_bar: ProgressBar
var _fuel_value: Label
var _stamina_bar: ProgressBar
var _stamina_value: Label
var _pack_bar: ProgressBar
var _pack_value: Label
var _pack_items: Label
var _prompt: Label
var _message: Label
var _loading: Label
var _credits: Label
var _boss: VBoxContainer
var _boss_name: Label
var _boss_fill: ColorRect
var _boss_trail: ColorRect
var _help: Label
var _help_time := 0.0
var _toasts: VBoxContainer
var _toast_list: Array = []
const TOAST_TIME := 5.0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Top-left: tool slots, flares, scanner.
	var tl := VBoxContainer.new()
	tl.position = Vector2(24, 20)
	tl.add_theme_constant_override("separation", 8)
	root.add_child(tl)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 8)
	tl.add_child(slots)
	_slot_pick = _slot("1", "PICKAXE")
	slots.add_child(_slot_pick)
	_slot_drill = _slot("2", "HAND DRILL")
	slots.add_child(_slot_drill)
	_drill_label = _slot_drill.get_child(0).get_child(1)
	_slot_shotgun = _slot("3", "LASER SHOTGUN")
	slots.add_child(_slot_shotgun)
	_slot_pistol = _slot("4", "LASER PISTOL")
	slots.add_child(_slot_pistol)
	_slot_dagger = _slot("5", "CROOKED DAGGER")
	slots.add_child(_slot_dagger)
	var tools_panel := _panel()
	tl.add_child(tools_panel)
	var tools_box := VBoxContainer.new()
	tools_panel.add_child(tools_box)
	_flares = _label("", 16)
	tools_box.add_child(_flares)
	var scan_row := HBoxContainer.new()
	scan_row.add_theme_constant_override("separation", 10)
	tools_box.add_child(scan_row)
	_scan_label = _label("", 16)
	_scan_label.custom_minimum_size.x = 140
	scan_row.add_child(_scan_label)
	_scan_bar = _bar(Color(0.45, 0.8, 0.95))
	_scan_bar.custom_minimum_size = Vector2(110, 8)
	_scan_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scan_row.add_child(_scan_bar)
	_weapon = _label("", 16)
	tools_box.add_child(_weapon)

	# Top-right: zone and stash.
	var tr := _panel()
	tr.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.offset_left = -360
	tr.offset_right = -24
	tr.offset_top = 20
	root.add_child(tr)
	var tr_box := VBoxContainer.new()
	tr.add_child(tr_box)
	tr_box.add_child(_label("ZONE", 12, DIM))
	_zone = _label("", 20, ACCENT)
	tr_box.add_child(_zone)
	_threat = _label("", 15)
	tr_box.add_child(_threat)
	tr_box.add_child(_label("STORAGE NEARBY", 12, DIM))
	_stash = _label("", 15)
	_stash.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tr_box.add_child(_stash)
	_credits = _label("", 15, Color(1.0, 0.85, 0.45))
	tr_box.add_child(_credits)

	# Bottom-left: vitals.
	var bl := _panel()
	bl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bl.offset_left = 24
	bl.offset_right = 384
	bl.offset_bottom = -24
	root.add_child(bl)
	var vitals := VBoxContainer.new()
	vitals.add_theme_constant_override("separation", 6)
	bl.add_child(vitals)
	var hp := _vital(vitals, "HEALTH", Color(0.9, 0.3, 0.25))
	_health_bar = hp[0]
	_health_value = hp[1]
	var fuel := _vital(vitals, "FUEL", ACCENT)
	_fuel_bar = fuel[0]
	_fuel_value = fuel[1]
	var climb := _vital(vitals, "CLIMB", Color(0.55, 0.85, 1.0))
	_stamina_bar = climb[0]
	_stamina_value = climb[1]
	var pack := _vital(vitals, "PACK", Color(0.75, 0.72, 0.66))
	_pack_bar = pack[0]
	_pack_value = pack[1]
	_pack_items = _label("", 14, DIM)
	_pack_items.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vitals.add_child(_pack_items)

	# Damage flash: a red wash that fades out.
	_vignette = ColorRect.new()
	_vignette.color = Color(0.7, 0.05, 0.02, 0.0)
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_vignette)

	# Centre: crosshair, messages, prompts, loading.
	var dot := Panel.new()
	_dot = dot
	var dot_style := StyleBoxFlat.new()
	_dot_style = dot_style
	dot_style.bg_color = Color(1, 1, 1, 0.85)
	dot_style.set_corner_radius_all(3)
	dot_style.border_color = Color(0, 0, 0, 0.6)
	dot_style.set_border_width_all(1)
	dot.add_theme_stylebox_override("panel", dot_style)
	dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	dot.offset_left = -3
	dot.offset_top = -3
	dot.offset_right = 3
	dot.offset_bottom = 3
	dot.pivot_offset = Vector2(3, 3)
	root.add_child(dot)

	_message = _centered_label(root, Control.PRESET_CENTER_TOP, 70, 20, Color(1.0, 0.85, 0.6))
	_prompt = _centered_label(root, Control.PRESET_CENTER_BOTTOM, -130, 20, TEXT)
	_loading = _centered_label(root, Control.PRESET_CENTER, -20, 28, TEXT)

	# Boss health bar, top centre.
	_boss = VBoxContainer.new()
	_boss.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boss.offset_left = -300
	_boss.offset_right = 300
	_boss.offset_top = 14
	_boss.add_theme_constant_override("separation", 4)
	_boss.visible = false
	root.add_child(_boss)
	_boss_name = _label("", 18, Color(1.0, 0.55, 0.3))
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss.add_child(_boss_name)
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.6)
	back.custom_minimum_size = Vector2(600, 10)
	_boss.add_child(back)
	_boss_trail = ColorRect.new()
	_boss_trail.color = Color(1.0, 0.85, 0.6, 0.8)
	_boss_trail.size = Vector2(600, 10)
	back.add_child(_boss_trail)
	_boss_fill = ColorRect.new()
	_boss_fill.color = Color(0.9, 0.25, 0.1)
	_boss_fill.size = Vector2(600, 10)
	back.add_child(_boss_fill)
	_loading.text = "Generating caves..."

	_help = _label("WASD move · Shift sprint · Space jump (hold at a wall to climb) · LMB use · 1/2 tools · 3/4/5 weapons · Q build (hold: scan) · F flare (hold: flashlight) · G Shredder · E use · Tab inventory · X remove building · Esc menu", 14, Color(1, 1, 1, 0.5))
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help.offset_right = -24
	_help.offset_bottom = -24
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_help)

	# Corner notices ("New material", "New recipes"), stacked under the zone panel.
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toasts.offset_right = -24
	_toasts.offset_top = 190
	_toasts.add_theme_constant_override("separation", 8)
	root.add_child(_toasts)

	_ignore_mouse(root)


## A notice in the top-right corner: slides in, holds a few seconds, fades.
func notify(title: String, lines: Array, color := ACCENT) -> void:
	var p := _panel()
	p.custom_minimum_size.x = 260
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel").duplicate()
	sb.border_color = color
	sb.border_width_left = 3
	p.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	p.add_child(box)
	box.add_child(_label(title, 13, color))
	for l in lines:
		box.add_child(_label(str(l), 18, TEXT))
	# Wrapped in a plain Control so it can slide sideways without the stack fighting it.
	var holder := Control.new()
	holder.add_child(p)
	_toasts.add_child(holder)
	_ignore_mouse(holder)
	p.position.x = 320.0
	p.modulate.a = 0.0
	_toast_list.append({"holder": holder, "panel": p, "t": 0.0})


func _animate_toasts(delta: float) -> void:
	for i in range(_toast_list.size() - 1, -1, -1):
		var e: Dictionary = _toast_list[i]
		e["t"] += delta
		var t: float = e["t"]
		var p: Control = e["panel"]
		var holder: Control = e["holder"]
		holder.custom_minimum_size = p.get_combined_minimum_size()
		var w: float = holder.custom_minimum_size.x
		# Slide in (ease out), hold, then fade.
		var k := clampf(t / 0.35, 0.0, 1.0)
		p.position.x = (1.0 - k) * (1.0 - k) * 320.0 + (holder.size.x - w)
		p.modulate.a = k if t < TOAST_TIME else clampf(1.0 - (t - TOAST_TIME) / 0.6, 0.0, 1.0)
		if t > TOAST_TIME + 0.6:
			holder.queue_free()
			_toast_list.remove_at(i)


## Shows the boss bar (ratio 0..1); a pale trail catches up behind recent damage.
func set_boss(boss_name: String, ratio: float) -> void:
	_boss.visible = true
	_boss_name.text = boss_name
	_boss_fill.size.x = 600.0 * clampf(ratio, 0.0, 1.0)


func hide_boss() -> void:
	_boss.visible = false


func flash_damage() -> void:
	_vignette.color.a = 0.35


## Crosshair feedback: flashes red on a hit, bigger and longer on a kill.
func hit_marker(killed: bool) -> void:
	_hit_t = 0.35 if killed else 0.15
	_hit_scale = 3.5 if killed else 2.2


func _process(delta: float) -> void:
	if _boss.visible:
		_boss_trail.size.x = move_toward(_boss_trail.size.x, _boss_fill.size.x, delta * 120.0)
	_vignette.color.a = maxf(_vignette.color.a - delta * 0.9, 0.0)
	_animate_toasts(delta)
	_hit_t = maxf(_hit_t - delta, 0.0)
	var k := clampf(_hit_t / 0.15, 0.0, 1.0)
	_dot.scale = Vector2.ONE * lerpf(1.0, _hit_scale, k)
	_dot_style.bg_color = Color(1, 1, 1, 0.85).lerp(Color(1.0, 0.25, 0.15, 1.0), k)
	if _help.visible:
		_help_time += delta
		if _help_time > HELP_VISIBLE_TIME:
			_help.modulate.a = maxf(_help.modulate.a - delta, 0.0)
			_help.visible = _help.modulate.a > 0.0


func update_state(s: Dictionary) -> void:
	var owned: bool = s["drill_owned"]
	_set_slot_active(_slot_pick, s["tool"] == 0, true)
	_set_slot_active(_slot_drill, s["tool"] == 1, owned)
	_set_slot_active(_slot_shotgun, s["tool"] == 2, true)
	_set_slot_active(_slot_pistol, s["tool"] == 3, true)
	_set_slot_active(_slot_dagger, s["tool"] == 4, s.get("dagger_owned", false))
	_slot_dagger.visible = s.get("dagger_owned", false)  # appears once you've made it
	var heat_txt: String = "OVERHEATED" if s["overheated"] else "%d%%" % roundi(s["heat"] * 100.0)
	_weapon.text = "SHOTGUN  %d / %d charges   ·   PISTOL heat %s" % [s["charges"], s["charges_max"], heat_txt]
	_weapon.label_settings.font_color = Color(1.0, 0.45, 0.35) if s["overheated"] else TEXT
	_threat.text = "Threat: " + String(s["threat"])
	var hp: float = s["health"]
	_health_bar.value = hp / MAX_HEALTH_DISPLAY
	_health_value.text = "%d / %d%s" % [roundi(hp), roundi(s["max_health"]), "  shaken" if s["shaken"] > 0.0 else ""]
	_drill_label.text = "HAND DRILL" if owned else "HAND DRILL — build at pod"

	var pips := ""
	for i in s["flares_max"]:
		pips += "● " if i < s["flares"] else "○ "
	_flares.text = "FLARES [F]  %s" % pips
	if s["flares"] < s["flares_max"]:
		_flares.text += " +1 in %ds" % ceili(s["flare_eta"])

	var cd: float = s["scan_cd"]
	_scan_label.text = "SCANNER [hold Q]  " + ("ready" if cd <= 0.0 else "%ds" % ceili(cd))
	_scan_bar.value = 1.0 - cd / s["scan_max"]

	_zone.text = String(s["zone"]).to_upper()
	_stash.text = s["stash"]
	_credits.text = "Credits  %d" % s.get("credits", 0)
	_credits.visible = s.get("credits_known", false)

	if owned:
		_fuel_bar.value = s["fuel"] / s["fuel_max"]
		_fuel_value.text = "%d / %d" % [roundi(s["fuel"]), roundi(s["fuel_max"])]
		_fuel_bar.modulate = Color.WHITE if _fuel_bar.value > 0.2 else Color(1.0, 0.45, 0.4)
	else:
		_fuel_bar.value = 0.0
		_fuel_value.text = "no drill"
	_stamina_bar.value = s["stamina"]
	_stamina_value.text = "climbing" if s["climbing"] else "%d%%" % roundi(s["stamina"] * 100.0)
	_pack_bar.value = s["weight"] / s["capacity"]
	_pack_bar.modulate = Color.WHITE if _pack_bar.value < 0.9 else Color(1.0, 0.55, 0.4)
	_pack_value.text = "%.0f / %.0f kg" % [s["weight"], s["capacity"]]
	_pack_items.text = s["backpack"]


func set_prompt(text: String) -> void:
	_prompt.text = text


func set_message(text: String) -> void:
	_message.text = text


func set_loading(on: bool) -> void:
	_loading.visible = on


# --- Builders -------------------------------------------------------------------

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.055, 0.06, 0.62)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	return p


func _slot(key: String, title: String) -> PanelContainer:
	var p := _panel()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	p.add_child(row)
	row.add_child(_label(key, 16, ACCENT))
	row.add_child(_label(title, 16))
	return p


func _set_slot_active(p: PanelContainer, active: bool, available: bool) -> void:
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
	sb.border_color = ACCENT if active else Color(1, 1, 1, 0.08)
	sb.set_border_width_all(2 if active else 1)
	p.modulate = Color.WHITE if available else Color(1, 1, 1, 0.45)


func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.0
	b.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	return b


## Returns [bar, value_label].
func _vital(parent: Container, title: String, color: Color) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var t := _label(title, 13, DIM)
	t.custom_minimum_size.x = 48
	row.add_child(t)
	var bar := _bar(color)
	bar.custom_minimum_size.y = 10
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var v := _label("", 14)
	v.custom_minimum_size.x = 96
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	return [bar, v]


func _label(text: String, size: int, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = 3
	ls.outline_color = Color(0, 0, 0, 0.7)
	l.label_settings = ls
	return l


func _centered_label(root: Control, preset: Control.LayoutPreset, y: float, size: int, color: Color) -> Label:
	var l := _label("", size, color)
	l.set_anchors_and_offsets_preset(preset)
	l.offset_left = -500
	l.offset_right = 500
	l.offset_top = y
	l.offset_bottom = y + 40
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(l)
	return l


func _ignore_mouse(n: Node) -> void:
	if n is Control:
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)
