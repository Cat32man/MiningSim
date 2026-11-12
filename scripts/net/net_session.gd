extends Node
## Co-op over ENet. Traffic is encrypted (DTLS) with the build's private key file
## (scripts/net/coop_key.gd, never in git): a joiner only connects to a host whose certificate
## matches theirs, and the host only lets in players who prove they have the same secret
## (an HMAC of a random challenge) and the same PROTOCOL. The host's world is the real one: a joiner gets its seed, dug-out chunks and
## buildings, then every dig anyone makes is replayed for everyone else. The host runs all
## machines and sends their contents out; whatever a joiner changes in one (items moved,
## a craft started, a harvester driven) goes back to the host. The host also runs every bug
## and boss (they go for whoever's closest); joiners see copies that follow them, and their
## hits go to the host's. Each player's copy of a projectile only hurts that player.
## Progress isn't shared yet.

signal joined(data: Dictionary)  # client: the host's world arrived
signal failed(text: String)  # client: couldn't connect
signal host_left  # client: the host closed the game
signal players_changed(count: int)

const RemotePlayer = preload("res://scripts/net/remote_player.gd")
const Bug = preload("res://scripts/enemies/bug.gd")
const Hydra = preload("res://scripts/enemies/hydra.gd")
const Arbiter = preload("res://scripts/enemies/arbiter.gd")
const Shot = preload("res://scripts/enemies/arbiter_shot.gd")
const Spine = preload("res://scripts/enemies/spine.gd")
const KEY_PATH := "res://scripts/net/coop_key.gd"
const CERT_NAME := "miningsim"
const PROTOCOL := 1  # bump when co-op messages change: older builds then can't join
const LOCAL := "127.0.0.1"
const PORT := 24680
const MAX_PLAYERS := 4
const SEND_RATE := 20.0
const JOIN_TIMEOUT := 10.0
const MACHINE_RATE := 10.0  # machine syncs a second
const HOLD := 0.6  # a joiner ignores the host's copy this long after changing a machine
const POD := 0  # sync key for the drop pod's storage (buildings count up from 1)
const ENEMY_RATE := 15.0
const COLORS := [Color(0.95, 0.55, 0.2), Color(0.3, 0.6, 0.95), Color(0.4, 0.85, 0.45), Color(0.85, 0.4, 0.85)]

var world  # VoxelWorld, once the game is running
var player
var avatar_parent: Node3D
var grid  # PowerGrid
var pod
var director
var snapshot: Callable  # host: returns the world data a joiner needs
var is_host := false
var _avatars := {}  # peer id -> RemotePlayer
var _send_t := 0.0
var _join_t := -1.0
var _machine_t := 0.0
var _sent := {}  # host: key -> bytes last sent out
var _known := {}  # joiner: key -> bytes of our copy as the host last left it
var _hold := {}  # joiner: key -> seconds left ignoring the host (we just changed it)
var _enemy_t := 0.0
var _next_enemy := 1
var _enemies_by_id := {}  # host: id -> bug/boss
var _puppets := {}  # joiner: id -> copy of the host's bug/boss
var _secret := PackedByteArray()
var _challenges := {}  # host: peer id -> random bytes it must sign
var _joined := false  # joiner: the host's world has arrived


func _ready() -> void:
	name = "Net"  # same node path on every machine, so the calls find each other
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_disconnected.connect(_on_peer_left)


func active() -> bool:
	return multiplayer.multiplayer_peer != null \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## The build's private co-op key, or null if this build doesn't have one.
static func keys():
	return load(KEY_PATH) if ResourceLoader.exists(KEY_PATH) else null


## Opens the game to other players. `bind`: "*" for every network (online), LOCAL for
## this computer only.
func host(bind := "*") -> Error:
	var k = keys()
	if k == null:
		return ERR_UNCONFIGURED
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(bind)
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		return err
	var key := CryptoKey.new()
	key.load_from_string(k.PRIVATE)
	var cert := X509Certificate.new()
	cert.load_from_string(k.CERT)
	err = peer.host.dtls_server_setup(TLSOptions.server(key, cert))
	if err != OK:
		peer.close()
		return err
	is_host = true
	_setup_auth(k)
	multiplayer.peer_connected.connect(_on_peer_joined)
	multiplayer.multiplayer_peer = peer
	return OK


func join(address: String) -> Error:
	var k = keys()
	if k == null:
		return ERR_UNCONFIGURED
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		return err
	var cert := X509Certificate.new()
	cert.load_from_string(k.CERT)
	err = peer.host.dtls_client_setup(CERT_NAME, TLSOptions.client(cert, CERT_NAME))
	if err != OK:
		peer.close()
		return err
	_setup_auth(k)
	multiplayer.connection_failed.connect(func(): _fail("No game found there"))
	multiplayer.server_disconnected.connect(func():
		if _joined:
			host_left.emit()
		else:
			_fail("The host turned us away (different build?)"))
	multiplayer.multiplayer_peer = peer
	_join_t = JOIN_TIMEOUT
	return OK


# --- Letting players in -------------------------------------------------------------

func _setup_auth(k) -> void:
	_secret = k.SECRET.hex_decode()
	if OS.get_cmdline_user_args().has("--badkey"):
		_secret[0] ^= 1  # test: a build with a different key must be turned away
	var mp := multiplayer as SceneMultiplayer
	mp.auth_timeout = 8.0
	mp.auth_callback = _on_auth
	if is_host:
		mp.peer_authenticating.connect(_on_authenticating)


## Host: a new connection must sign this before it's let in.
func _on_authenticating(id: int) -> void:
	var challenge := Crypto.new().generate_random_bytes(32)
	_challenges[id] = challenge
	(multiplayer as SceneMultiplayer).send_auth(id, challenge)


func _on_auth(id: int, data: PackedByteArray) -> void:
	var mp := multiplayer as SceneMultiplayer
	if is_host:
		var want := _sign(_challenges.get(id, PackedByteArray()))
		_challenges.erase(id)
		if data.size() == want.size() and data == want:
			mp.complete_auth(id)
		else:
			print("Co-op: turned away a player with the wrong key or version")
			mp.disconnect_peer(id)
	else:
		mp.send_auth(1, _sign(data))
		mp.complete_auth(1)


func _sign(challenge: PackedByteArray) -> PackedByteArray:
	var msg := challenge + ("miningsim-coop-v%d" % PROTOCOL).to_utf8_buffer()
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, _secret, msg)


func close() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	for av in _avatars.values():
		if is_instance_valid(av):
			av.queue_free()
	_avatars.clear()


func player_count() -> int:
	return _avatars.size() + 1


func _fail(text: String) -> void:
	_join_t = -1.0
	close()
	failed.emit(text)


func _process(delta: float) -> void:
	if _join_t > 0.0:
		_join_t -= delta
		if _join_t <= 0.0:
			_fail("No game open to join")
	if not active() or player == null or not is_instance_valid(player) or not player.active:
		return
	_sync_machines(delta)
	if is_host:
		_enemy_t -= delta
		if _enemy_t <= 0.0:
			_enemy_t = 1.0 / ENEMY_RATE
			_sync_enemies()
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = 1.0 / SEND_RATE
		var pitch: float = player.camera.rotation.x if player.camera else 0.0
		_state.rpc(player.global_position, player.rotation.y, pitch, player.health)


# --- Joining ------------------------------------------------------------------------

func _on_peer_joined(id: int) -> void:
	var data: Dictionary = snapshot.call()
	var raw := var_to_bytes(data)
	print("Co-op: player %d joined, sending %d KB of world" % [id, raw.size() / 1024])
	_welcome.rpc_id(id, raw.compress(FileAccess.COMPRESSION_ZSTD), raw.size())
	players_changed.emit(player_count() + 1)


@rpc("authority", "reliable")
func _welcome(blob: PackedByteArray, size: int) -> void:
	_join_t = -1.0
	_joined = true
	print("Co-op: joined, got %d KB of world" % (size / 1024))
	joined.emit(bytes_to_var(blob.decompress(size, FileAccess.COMPRESSION_ZSTD)))


func _on_peer_left(id: int) -> void:
	var av = _avatars.get(id)
	if av and is_instance_valid(av):
		av.queue_free()
	_avatars.erase(id)
	players_changed.emit(player_count())


# --- Players ------------------------------------------------------------------------

@rpc("any_peer", "unreliable_ordered")
func _state(pos: Vector3, yaw: float, pitch: float, health: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	var av = _avatars.get(id)
	if av == null or not is_instance_valid(av):
		if avatar_parent == null or not is_instance_valid(avatar_parent):
			return
		av = RemotePlayer.new()
		av.label_text = "Host" if id == 1 else "Miner"
		av.color = COLORS[0] if id == 1 else COLORS[1 + absi(id) % (COLORS.size() - 1)]
		av.peer_id = id
		av.net = self
		av.world = world
		avatar_parent.add_child(av)
		_avatars[id] = av
		print("Co-op: now showing player %d" % id)
		players_changed.emit(player_count())
	av.target(pos, yaw, pitch)
	av.health = health


## Host: a bug or boss hit a joiner's stand-in; the hit lands on their own computer.
func hurt_peer(id: int, amount: float, from: Vector3) -> void:
	if active():
		_hurt.rpc_id(id, amount, from)


@rpc("authority", "reliable")
func _hurt(amount: float, from: Vector3) -> void:
	if player and is_instance_valid(player):
		player.take_damage(amount, from)


# --- Bugs and bosses --------------------------------------------------------------

func _tag(e: Node) -> String:
	if e.get_script() == Bug:
		return "bug:" + e.kind
	if e.get_script() == Hydra:
		return "hydra"
	if e.get_script() == Arbiter:
		return "arbiter"
	return ""


## The closest living player to `p` (this computer's player if nobody else is).
func _nearest(p: Vector3):
	var best = player
	var best_d := INF
	for c in [player] + _avatars.values():
		if is_instance_valid(c) and c.health > 0.0 and c.active:
			var d: float = c.global_position.distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = c
	return best


## Host: every bug goes for whoever's closest, and the joiners get where they all are.
func _sync_enemies() -> void:
	var out := {}
	_enemies_by_id.clear()
	for e in get_tree().get_nodes_in_group("bugs"):
		var tag := _tag(e)
		if tag == "":
			continue
		if not e.has_meta("nid"):
			e.set_meta("nid", _next_enemy)
			_next_enemy += 1
		var id: int = e.get_meta("nid")
		_enemies_by_id[id] = e
		if not e._dead:
			e.player = _nearest(e.global_position)
		out[id] = [tag, e.global_position, e.rotation.y, e.health, e._dead,
			e.net_extra() if e.has_method("net_extra") else null]
	_enemies.rpc(out)


@rpc("authority", "unreliable_ordered")
func _enemies(out: Dictionary) -> void:
	if avatar_parent == null or not is_instance_valid(avatar_parent) or player == null:
		return
	for id in out:
		var d: Array = out[id]
		var p = _puppets.get(id)
		if p == null or not is_instance_valid(p):
			if d[4]:
				continue  # already dead before we saw it
			p = _make_puppet(id, d[0], d[1], d[2])
			if p == null:
				continue
		p.net_pos = d[1]
		p.net_yaw = d[2]
		if not p._dead:
			p.health = maxf(d[3], 1.0)
		if d[5] != null:
			p.net_apply(d[5])
		if d[4] and not p._dead:
			p.net_die()
			_boss_over(p, true)
	for id in _puppets.keys():
		if out.has(id):
			continue
		var p = _puppets[id]
		if is_instance_valid(p) and not p._dead:
			_boss_over(p, false)  # e.g. a boss going back to sleep
			p.queue_free()
		_puppets.erase(id)


func _make_puppet(id: int, tag: String, pos: Vector3, yaw: float) -> Node3D:
	var e
	if tag.begins_with("bug:"):
		e = Bug.new()
		e.kind = tag.trim_prefix("bug:")
	elif tag == "hydra":
		e = Hydra.new()
	elif tag == "arbiter":
		e = Arbiter.new()
	else:
		return null
	e.player = player
	e.director = director
	e.puppet = true
	e.net_hit = _send_hit
	e.net_pos = pos
	e.net_yaw = yaw
	e.set_meta("nid", id)
	avatar_parent.add_child(e)
	e.global_position = pos
	e.rotation.y = yaw
	_puppets[id] = e
	if e.is_in_group("boss") and director:
		director.boss = e
		director.boss_appeared.emit(e)
	return e


func _boss_over(p: Node3D, killed: bool) -> void:
	if director and director.boss == p:
		director.boss = null
		director.boss_gone.emit(p, killed)


## Joiner: we hit a copy, so the host's bug takes it.
func _send_hit(e: Node3D, amount: float, from: Vector3, at: Vector3) -> void:
	if active():
		_enemy_hit.rpc_id(1, e.get_meta("nid", -1), amount, from, at)


@rpc("any_peer", "reliable")
func _enemy_hit(id: int, amount: float, from: Vector3, at: Vector3) -> void:
	var e = _enemies_by_id.get(id)
	if is_host and e and is_instance_valid(e):
		e.take_damage(amount, from, at)


## Host: a bug or boss fired; every joiner gets a copy that can hit them.
func enemy_shot(shooter: Node3D, s: Node3D) -> void:
	if not active() or not is_host:
		return
	var big: bool = s.get("big") == true
	_shot.rpc(shooter.get_meta("nid", -1), "spine" if s.get_script() == Spine else "shot",
		s.global_position, s.velocity, big, s.damage)


@rpc("authority", "reliable")
func _shot(id: int, kind: String, pos: Vector3, vel: Vector3, big: bool, damage: float) -> void:
	if avatar_parent == null or not is_instance_valid(avatar_parent):
		return
	var s = Spine.new() if kind == "spine" else Shot.new()
	var from = _puppets.get(id)
	if from and is_instance_valid(from):
		s.shooter = from
	if kind != "spine":
		s.big = big
		s.target = player
	s.damage = damage
	s.velocity = vel
	avatar_parent.add_child(s)
	s.global_position = pos


# --- Buildings ----------------------------------------------------------------------

func request_place(d: Dictionary) -> void:
	_place_req.rpc_id(1, d)


func request_remove(nid: int) -> void:
	_remove_req.rpc_id(1, nid)


## Host: tell the joiners about a new building.
func building_placed(d: Dictionary) -> void:
	if active() and is_host:
		_placed.rpc(d)


func building_removed(nid: int) -> void:
	if active() and is_host:
		_removed.rpc(nid)


@rpc("any_peer", "reliable")
func _place_req(d: Dictionary) -> void:
	if is_host and grid:
		var b = grid.net_spawn(d, true)
		if b:
			building_placed(grid.describe(b))


@rpc("any_peer", "reliable")
func _remove_req(nid: int) -> void:
	if is_host and grid:
		var b = grid.by_nid(nid)
		if b:
			grid.remove(b)


@rpc("authority", "reliable")
func _placed(d: Dictionary) -> void:
	if grid:
		grid.net_spawn(d, false)


@rpc("authority", "reliable")
func _removed(nid: int) -> void:
	if grid:
		grid.net_despawn(nid)


## What a joiner can change in a machine (contents, health, where it stands).
func _blob(key: int):
	if key == POD:
		return [pod.storage.to_data()] if pod else null
	var b = grid.by_nid(key)
	return [b.get_state(), b.hp, b.transform] if b else null


## Joiner: remember the world as the host sent it, so any later change counts as ours.
func prime() -> void:
	if grid:
		for k in _keys():
			_known[k] = var_to_bytes(_blob(k))


func _keys() -> Array:
	var out: Array = [POD]
	for b in grid.buildings:
		out.append(b.net_id)
	return out


func _sync_machines(delta: float) -> void:
	for k in _hold.keys():
		_hold[k] -= delta
		if _hold[k] <= 0.0:
			_hold.erase(k)
	_machine_t -= delta
	if _machine_t > 0.0 or grid == null:
		return
	_machine_t = 1.0 / MACHINE_RATE
	if is_host:
		var changes := {}
		for k in _keys():
			var s = _blob(k)
			var bytes := var_to_bytes(s)
			if _sent.get(k) != bytes:
				_sent[k] = bytes
				if k != POD:
					s.append(grid.by_nid(k).power_ratio)
				changes[k] = s
		if not changes.is_empty():
			_machines.rpc(changes)
	else:
		# Anything different from what the host last sent is our doing: send it back.
		for k in _keys():
			var s = _blob(k)
			var bytes := var_to_bytes(s)
			if not _known.has(k):
				_known[k] = bytes
			elif _known[k] != bytes:
				_known[k] = bytes
				_hold[k] = HOLD
				_machine_edit.rpc_id(1, k, s)


func _apply_blob(k: int, s: Array) -> void:
	if k == POD:
		if pod:
			pod.storage.from_data(s[0])
		return
	var b = grid.by_nid(k)
	if b == null:
		return
	b.apply_state(s[0])
	if b.transform != s[2]:
		b.transform = s[2]
	b.hp = s[1]
	if (b.hp <= 0.0) != b.broken:
		b.set_broken(b.hp <= 0.0)
	if s.size() > 3:
		b.power_ratio = s[3]


@rpc("authority", "reliable")
func _machines(changes: Dictionary) -> void:
	if grid == null:
		return
	for k in changes:
		if _hold.has(k):
			continue
		_apply_blob(k, changes[k])
		_known[k] = var_to_bytes(_blob(k))


@rpc("any_peer", "reliable")
func _machine_edit(k: int, s: Array) -> void:
	if is_host and grid:
		_apply_blob(k, s)  # goes out to the other joiners with the next sync


# --- Digging ------------------------------------------------------------------------

## Connected to the world's `edited` signal: our digs go to everyone else.
func send_edit(op: Dictionary) -> void:
	if active():
		_edit.rpc(op)


@rpc("any_peer", "reliable")
func _edit(op: Dictionary) -> void:
	if world and is_instance_valid(world):
		world.apply_remote_edit(op)
		if OS.get_cmdline_user_args().has("--netlog"):
			print("Co-op: edit from %d at %s" % [multiplayer.get_remote_sender_id(), op.get("center", "")])
