extends RefCounted
## Shared hit feedback for enemies: ichor spray, floating damage numbers, red flash, and
## an optional health bar for tougher bugs.

const NUMBER_RISE := 0.9
const NUMBER_TIME := 0.8
## Hits within this window add to the same number (drill ticks read as one rising total).
const NUMBER_MERGE := 0.35


## A short burst of bug ichor at `pos`, spraying out the far side (away from `from`) and up.
## Spraying toward the attacker sends the droplets straight into the camera.
static func ichor(parent: Node, pos: Vector3, from: Vector3, color := Color(0.75, 0.85, 0.2)) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 14
	p.lifetime = 0.6
	var away := pos - from
	away.y = 0.0
	p.direction = (away.normalized() + Vector3.UP * 0.8).normalized() if away.length() > 0.01 else Vector3.UP
	p.spread = 40.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.03
	p.scale_amount_max = 0.07
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.2
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.4
	m.material = mat
	p.mesh = m
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


## Floating damage number. Pass the label returned last time (and when it was made) to
## merge rapid hits into one; returns the label in use.
static func number(parent: Node, pos: Vector3, amount: float, last: Variant, last_time: float, now: float,
		killed: bool) -> Label3D:
	# `last` is untyped on purpose: the previous label may already have faded and been freed,
	# and a freed object can't be passed through a typed Label3D argument.
	var label: Label3D = last if is_instance_valid(last) and now - last_time <= NUMBER_MERGE else null
	if label == null:
		label = Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.0011
		label.font_size = 34
		label.outline_size = 10
		label.outline_modulate = Color(0, 0, 0, 0.85)
		label.set_meta("total", 0.0)
		parent.add_child(label)
		label.global_position = pos + Vector3(randf_range(-0.15, 0.15), 0.3, randf_range(-0.15, 0.15))
		var t := label.create_tween().set_parallel()
		t.tween_property(label, "position:y", label.position.y + NUMBER_RISE, NUMBER_TIME).set_ease(Tween.EASE_OUT)
		t.tween_property(label, "modulate:a", 0.0, NUMBER_TIME * 0.5).set_delay(NUMBER_TIME * 0.5)
		t.chain().tween_callback(label.queue_free)
	var total: float = label.get_meta("total") + amount
	label.set_meta("total", total)
	label.text = ("%d" % roundi(total)) + ("  ✖" if killed else "")
	label.modulate = Color(1.0, 0.35, 0.25) if killed else Color(1.0, 0.92, 0.6)
	label.modulate.a = 1.0
	return label


## Billboarded health bar: returns [root, fill]. Update with set_bar().
static func make_bar(parent: Node3D, height: float) -> Array:
	var root := Node3D.new()
	root.position.y = height
	root.visible = false
	parent.add_child(root)
	var bg := _quad(Vector2(0.62, 0.08), Color(0, 0, 0, 0.6))
	root.add_child(bg)
	var fill := _quad(Vector2(0.6, 0.06), Color(0.9, 0.25, 0.2))
	fill.position.z = 0.001
	root.add_child(fill)
	return [root, fill]


static func set_bar(bar: Array, ratio: float) -> void:
	bar[0].visible = ratio < 1.0 and ratio > 0.0
	bar[1].scale.x = maxf(ratio, 0.001)


static func _quad(size: Vector2, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.albedo_color = color
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
