extends RefCounted
## Renders a 3D model into its own little lit world for menu cards. Returns
## {viewport, pivot}: show viewport.get_texture(), turn the pivot to spin it, and switch the
## viewport's update mode to UPDATE_ALWAYS while it moves (it renders once by default).


static func make(owner: Node, model: Node3D, size: Vector2i) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	owner.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 2.2
	key.light_color = Color(1.0, 0.92, 0.8)
	key.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 1.0
	rim.light_color = Color(0.6, 0.75, 1.0)
	rim.rotation = Vector3(deg_to_rad(-20), deg_to_rad(200), 0)
	vp.add_child(rim)

	var pivot := Node3D.new()
	vp.add_child(pivot)
	pivot.add_child(model)

	# Frame the model: centre it on the pivot and back the camera off to fit it.
	var box := bounds(model)
	model.position = -box.get_center()
	var radius := maxf(box.size.length() * 0.5, 0.05)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.near = 0.01
	var dir := Vector3(0.75, 0.55, 1.0).normalized()
	# Flat, spread-out models fill less of their bounding sphere: they can ask to sit closer.
	var dist := radius / sin(deg_to_rad(cam.fov) * 0.5) * 0.92 / float(model.get_meta("thumb_zoom", 1.0))
	vp.add_child(cam)
	cam.look_at_from_position(dir * dist, Vector3.ZERO)
	pivot.rotation.y = -0.35
	return {"viewport": vp, "pivot": pivot}


static func bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for n in _all_children(root):
		if n is MeshInstance3D and n.visible:
			var b: AABB = (root.global_transform.affine_inverse() * n.global_transform) * n.get_aabb()
			box = b if first else box.merge(b)
			first = false
	return box


static func _all_children(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_all_children(c))
	return out
