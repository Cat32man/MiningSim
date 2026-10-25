extends RefCounted
## Plays an artist glb's per-part Blender actions by sampling their tracks directly, so
## several clips (one per part, as Blender exports them) act as one timeline. Only tracks
## with real motion (2+ keys) are kept: the single-key "rest" copies every clip carries
## would otherwise fight each other.

## [{node, anim, track, type, path}] for every animated part under `root`.
static func collect(root: Node) -> Array:
	var out: Array = []
	var ap: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	if ap == null:
		return out
	ap.active = false  # we drive the parts ourselves
	var base: Node = ap.get_node(ap.root_node)
	for name in ap.get_animation_list():
		var a: Animation = ap.get_animation(name)
		for t in a.get_track_count():
			if a.track_get_key_count(t) < 2:
				continue
			var path := a.track_get_path(t)
			var node := base.get_node_or_null(NodePath(path.get_concatenated_names()))
			if node is Node3D:
				out.append({"node": node, "anim": a, "track": t, "type": a.track_get_type(t), "path": str(path)})
	return out


## Poses every track at time `t` (clamped to its clip).
static func apply(tracks: Array, t: float) -> void:
	for tr in tracks:
		var a: Animation = tr["anim"]
		var i: int = tr["track"]
		var at := clampf(t, 0.0, a.length)
		var n: Node3D = tr["node"]
		match tr["type"]:
			Animation.TYPE_POSITION_3D:
				n.position = a.position_track_interpolate(i, at)
			Animation.TYPE_ROTATION_3D:
				n.quaternion = a.rotation_track_interpolate(i, at)
			Animation.TYPE_SCALE_3D:
				n.scale = a.scale_track_interpolate(i, at)
