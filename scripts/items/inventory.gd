extends RefCounted
## A grid of item slots (Valheim / Satisfactory style). Each slot is null or a stack
## {"id": String, "count": int, ...extra} — batteries carry "energy" and never stack.
## Optional `accept` restricts what may go in (machine slots: fuel, batteries).

const Items = preload("res://scripts/items/items.gd")

signal changed

var slots: Array = []
var title := ""
## Empty = anything. Otherwise a list of allowed item ids.
var accept: Array = []
## Per-slot stack cap override (0 = use the item's own).
var stack_limit := 0


func _init(size := 0, title_ := "", accept_: Array = []) -> void:
	slots.resize(size)
	title = title_
	accept = accept_


func accepts(id: String) -> bool:
	return accept.is_empty() or id in accept


func max_stack(id: String) -> int:
	var s: int = Items.DEFS[id]["stack"]
	return mini(s, stack_limit) if stack_limit > 0 else s


func weight() -> float:
	var w := 0.0
	for s in slots:
		if s:
			w += Items.DEFS[s["id"]]["weight"] * s["count"]
	return w


func count_of(id: String) -> int:
	var n := 0
	for s in slots:
		if s and s["id"] == id:
			n += s["count"]
	return n


func used_slots() -> int:
	var n := 0
	for s in slots:
		if s:
			n += 1
	return n


func is_empty() -> bool:
	return used_slots() == 0


## Adds up to `count`; returns how many did NOT fit.
func add(id: String, count: int) -> int:
	if not accepts(id) or count <= 0:
		return count
	var cap := max_stack(id)
	for s in slots:  # top up existing stacks first
		if count <= 0:
			break
		if s and s["id"] == id and s["count"] < cap:
			var n := mini(cap - s["count"], count)
			s["count"] += n
			count -= n
	for i in slots.size():
		if count <= 0:
			break
		if slots[i] == null:
			var n := mini(cap, count)
			slots[i] = {"id": id, "count": n}
			count -= n
	changed.emit()
	return count


## Puts a whole stack (keeps extras like battery energy) in the first free slot.
func add_stack(stack: Dictionary) -> bool:
	if not accepts(stack["id"]):
		return false
	if max_stack(stack["id"]) > 1:
		var left := add(stack["id"], stack["count"])
		stack["count"] = left
		return left == 0
	for i in slots.size():
		if slots[i] == null:
			slots[i] = stack.duplicate()
			changed.emit()
			return true
	return false


## Removes up to `count`; returns how many were removed.
func remove(id: String, count: int) -> int:
	var removed := 0
	for i in range(slots.size() - 1, -1, -1):
		if removed >= count:
			break
		var s = slots[i]
		if s and s["id"] == id:
			var n := mini(s["count"], count - removed)
			s["count"] -= n
			removed += n
			if s["count"] <= 0:
				slots[i] = null
	if removed > 0:
		changed.emit()
	return removed


## Moves everything possible into `other`; returns true if this inventory is now empty.
func move_all_to(other) -> bool:
	for i in slots.size():
		var s = slots[i]
		if s and other.add_stack(s):
			slots[i] = null
		elif s and s["count"] <= 0:
			slots[i] = null
	changed.emit()
	other.changed.emit()
	return is_empty()


## Moves every stackable resource (ore, not batteries) from `src` into this inventory.
## Returns how many units moved.
func pull_ore_from(src) -> int:
	var moved := 0
	for i in src.slots.size():
		var s = src.slots[i]
		if s == null or Items.DEFS[s["id"]]["stack"] <= 1:
			continue
		var left := add(s["id"], s["count"])
		moved += s["count"] - left
		s["count"] = left
		if left <= 0:
			src.slots[i] = null
	src.changed.emit()
	return moved


## Drag and drop: move / merge / swap a stack between two slots (possibly across inventories).
static func transfer(src, si: int, dst, di: int) -> void:
	if src == dst and si == di:
		return
	var a = src.slots[si]
	if a == null or not dst.accepts(a["id"]):
		return
	var b = dst.slots[di]
	if b == null:
		var cap: int = dst.max_stack(a["id"])
		if a["count"] <= cap:
			dst.slots[di] = a
			src.slots[si] = null
		else:
			dst.slots[di] = a.duplicate()
			dst.slots[di]["count"] = cap
			a["count"] -= cap
	elif b["id"] == a["id"] and dst.max_stack(a["id"]) > 1:
		var n := mini(dst.max_stack(a["id"]) - b["count"], a["count"])
		b["count"] += n
		a["count"] -= n
		if a["count"] <= 0:
			src.slots[si] = null
	elif src.accepts(b["id"]):
		src.slots[si] = b
		dst.slots[di] = a
	src.changed.emit()
	if dst != src:
		dst.changed.emit()


## Shift-click: send a stack to the first inventory in `targets` that takes it.
static func quick_move(src, si: int, targets: Array) -> void:
	var s = src.slots[si]
	if s == null:
		return
	for t in targets:
		if t == src:
			continue
		if t.add_stack(s):
			src.slots[si] = null
			break
	src.changed.emit()


# --- Paying from several inventories (backpack + nearby containers) ----------------

static func total(sources: Array, id: String) -> int:
	var n := 0
	for inv in sources:
		n += inv.count_of(id)
	return n


static func can_afford(sources: Array, cost: Dictionary) -> bool:
	for id in cost:
		if total(sources, id) < cost[id]:
			return false
	return true


static func pay(sources: Array, cost: Dictionary) -> bool:
	if not can_afford(sources, cost):
		return false
	for id in cost:
		var need: int = cost[id]
		for inv in sources:
			need -= inv.remove(id, need)
			if need <= 0:
				break
	return true


# --- Save -------------------------------------------------------------------------

func to_data() -> Array:
	var out: Array = []
	for s in slots:
		out.append(s.duplicate() if s else null)
	return out


func from_data(data: Array) -> void:
	for i in mini(data.size(), slots.size()):
		slots[i] = data[i].duplicate() if data[i] else null
	changed.emit()
