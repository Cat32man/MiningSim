extends Node3D
## Owns every placed building. Connects power nodes into networks, draws cables, and
## balances supply against demand per network each frame.

const Buildables = preload("res://scripts/build/buildables.gd")
const Items = preload("res://scripts/items/items.gd")
const Shop = preload("res://scripts/base/shop.gd")
const Structure = preload("res://scripts/build/structure.gd")

## A bug bit a building (main shows an alert).
signal building_attacked(b: Node3D)

const CABLE_SEGMENTS := 8
const CABLE_SAG := 0.05  # sag per metre of span

## Set by main.
var progress
## Shredders dig through this.
var world
## main's drop_cache(position, stacks: Array) — leaves items in the world.
var drop_cache: Callable

var buildings: Array = []
var _edges: Array = []  # [a, b]
var _stats := {}  # network id -> Vector2(supply, demand)
var _cables: Node3D
var _cable_mat: StandardMaterial3D


func _ready() -> void:
	_cables = Node3D.new()
	add_child(_cables)
	_cable_mat = StandardMaterial3D.new()
	add_to_group("cosmetic_listeners")
	apply_cosmetics()
	_cable_mat.roughness = 0.6


## Cable colour from the elevator shop.
func apply_cosmetics() -> void:
	_cable_mat.albedo_color = Shop.color(progress, "cable")


func add(b: Node3D) -> void:
	b.grid = self
	if b.get_parent() == null:
		add_child(b)
	buildings.append(b)
	_rebuild()


## Removing a building drops whatever is inside it as a cache on the spot.
func remove(b: Node3D) -> void:
	var stuff: Array = b.contents()
	if not stuff.is_empty() and drop_cache.is_valid():
		drop_cache.call(b.global_position, stuff)
	buildings.erase(b)
	b.queue_free()
	_rebuild()


func network_stats(id: int) -> Vector2:
	return _stats.get(id, Vector2.ZERO)


func _process(dt: float) -> void:
	var nets := {}  # id -> [supply, demand, members]
	for b in buildings:
		if not b.is_power_node:
			continue
		if b.broken:
			b.power_ratio = 0.0  # a broken machine neither supplies nor draws: it winds down
			b.power_tick(dt, 0.0, 0.0)
			continue
		var n: Array = nets.get_or_add(b.network_id, [0.0, 0.0, []])
		n[0] += b.supply_kw()
		n[1] += b.demand_kw()
		n[2].append(b)
	_stats.clear()
	for id in nets:
		var n: Array = nets[id]
		var supply: float = n[0]
		var demand: float = n[1]
		_stats[id] = Vector2(supply, demand)
		var satisfaction := minf(supply / demand, 1.0) if demand > 0.0 else 0.0
		var load := minf(demand / supply, 1.0) if supply > 0.0 else 0.0
		for b in n[2]:
			# A machine's own battery tops up whatever the grid can't cover.
			var s: float = b.battery_assist(satisfaction, dt)
			b.power_ratio = s
			b.power_tick(dt, s, load)


## Recomputes connections, network ids, cables and stash capacity.
func rebuild() -> void:
	_rebuild()


func _rebuild() -> void:
	var nodes: Array = buildings.filter(func(b): return b.is_power_node and not b.broken)
	_edges.clear()
	var adj := {}
	for b in nodes:
		adj[b] = []
	# Every pair in range could connect, but cabling them all makes a tangle: keep only a
	# minimum spanning tree (shortest cables that still join everything). Same networks,
	# far fewer wires. Kruskal with union-find.
	var candidates: Array = []
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			var a = nodes[i]
			var c = nodes[j]
			var d: float = a.global_position.distance_to(c.global_position)
			if d <= maxf(a.connect_range, c.connect_range):
				candidates.append([d, a, c])
	candidates.sort_custom(func(x, y): return x[0] < y[0])
	var parent := {}
	for b in nodes:
		parent[b] = b
	var find := func(x):
		while parent[x] != x:
			parent[x] = parent[parent[x]]
			x = parent[x]
		return x
	for e in candidates:
		var ra = find.call(e[1])
		var rc = find.call(e[2])
		if ra == rc:
			continue
		parent[ra] = rc
		_edges.append([e[1], e[2]])
		adj[e[1]].append(e[2])
		adj[e[2]].append(e[1])
	# Connected components -> network ids.
	var next_id := 0
	for b in nodes:
		b.network_id = -1
	for b in nodes:
		if b.network_id != -1:
			continue
		var stack: Array = [b]
		b.network_id = next_id
		while not stack.is_empty():
			var cur = stack.pop_back()
			for n in adj[cur]:
				if n.network_id == -1:
					n.network_id = next_id
					stack.append(n)
		next_id += 1
	_draw_cables()


func _draw_cables() -> void:
	for c in _cables.get_children():
		c.queue_free()
	for e in _edges:
		var p0: Vector3 = e[0].to_global(e[0].cable_anchor)
		var p1: Vector3 = e[1].to_global(e[1].cable_anchor)
		var sag := p0.distance_to(p1) * CABLE_SAG
		var prev := p0
		for s in range(1, CABLE_SEGMENTS + 1):
			var t := float(s) / CABLE_SEGMENTS
			var p := p0.lerp(p1, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
			_segment(prev, p)
			prev = p


func _segment(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	if length < 0.001:
		return
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.025
	m.bottom_radius = 0.025
	m.height = length
	m.radial_segments = 6
	m.rings = 1
	mi.mesh = m
	mi.material_override = _cable_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cables.add_child(mi)
	var dir := (b - a) / length
	mi.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), (a + b) * 0.5)


# --- Save -------------------------------------------------------------------------

func get_state() -> Array:
	var out: Array = []
	for b in buildings:
		out.append({"id": b.build_id, "xform": b.global_transform, "state": b.get_state(), "hp": b.hp})
	return out


func load_state(list: Array) -> void:
	var refunds := {}  # snap-frame origin -> {item id: count}, old-size pieces
	for d in list:
		var id: String = d.get("id", "")
		if Structure.SLOTS.has(id) and d.get("state", {}).get("v", 1) < Structure.SIZE_VERSION:
			_refund_old_piece(d, refunds)
			continue
		if id == "rig":
			_convert_old_rig(d)
			continue
		if id == "wall_drill":
			_convert_wall_drill(d)
			continue
		if not Buildables.DEFS.has(id):
			continue
		var b := Buildables.make(id)
		if d.has("xform"):
			b.transform = d["xform"]
		else:
			b.position = d["pos"]
			b.rotation.y = d.get("yaw", 0.0)
		b.apply_state(d.get("state", {}))
		b.hp = d.get("hp", b.max_hp)
		if b.hp <= 0.0:
			b.set_broken(true)
		b.grid = self
		add_child(b)
		buildings.append(b)
	for at in refunds:
		var stacks: Array = []
		for item in refunds[at]:
			stacks.append({"id": item, "count": refunds[at][item]})
		if drop_cache.is_valid():
			drop_cache.call(at, stacks)
	_rebuild()


## Structure pieces got bigger: old ones would clip into the new grid, so each is taken
## down and its build cost left in one cache per structure.
func _refund_old_piece(d: Dictionary, refunds: Dictionary) -> void:
	var frame: Transform3D = d.get("state", {}).get("frame", Transform3D.IDENTITY)
	var at: Vector3 = frame.origin if frame != Transform3D.IDENTITY else d["xform"].origin
	var key: Vector3 = at + Vector3(0, 0.3, 0)
	var pile: Dictionary = refunds.get(key, {})
	var cost: Dictionary = Buildables.DEFS[d["id"]]["cost"]
	for item in cost:
		pile[item] = pile.get(item, 0) + cost[item]
	refunds[key] = pile


## Wall drills were replaced by Shredders. Whatever was inside one, plus its build and arm
## extension cost, becomes a cache where it stood.
func _convert_wall_drill(d: Dictionary) -> void:
	var Inventory = preload("res://scripts/items/inventory.gd")
	var st: Dictionary = d.get("state", {})
	var stacks: Array = []
	for data in st.get("inventories", []):
		var inv = Inventory.new(data.size())
		inv.from_data(data)
		for s in inv.slots:
			if s:
				stacks.append(s)
	var iron := 40
	for n in st.get("extensions", 0):
		iron += 15 + 10 * n
	stacks.append({"id": Items.IRON, "count": iron})
	stacks.append({"id": Items.ELECTRUM, "count": 15})
	var at: Vector3 = d["xform"].origin if d.has("xform") else d.get("pos", Vector3.ZERO)
	if drop_cache.is_valid():
		drop_cache.call(at, stacks)


## The drivable rig was replaced by wall drills. Its hopper, battery and build cost become
## a cache where it last stood — nothing teleports.
func _convert_old_rig(d: Dictionary) -> void:
	var st: Dictionary = d.get("state", {})
	var stacks: Array = []
	var mat_to_item := {1: Items.IRON, 2: Items.ELECTRUM, 5: Items.DIAMOND}
	for m in st.get("hopper", {}):
		if mat_to_item.has(int(m)):
			stacks.append({"id": mat_to_item[int(m)], "count": st["hopper"][m]})
	stacks.append({"id": Items.IRON, "count": 60})
	stacks.append({"id": Items.ELECTRUM, "count": 20})
	if st.get("battery", -1.0) >= 0.0:
		stacks.append(Items.new_battery(st["battery"] * Items.BATTERY_CAPACITY))
	var at: Vector3 = st.get("last_floor", d.get("pos", Vector3.ZERO))
	if at == Vector3.INF:
		at = d.get("pos", Vector3.ZERO)
	if drop_cache.is_valid():
		drop_cache.call(at, stacks)
