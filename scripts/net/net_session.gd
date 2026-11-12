extends Node
## Co-op over ENet, step 1: local only (127.0.0.1), so nothing is reachable from outside this
## computer. Players see each other and share the digging. The host's world is the real one:
## a joiner gets its seed and dug-out chunks, then every dig anyone makes is replayed for
## everyone else. Buildings, bugs, items and progress aren't shared yet.

signal joined(data: Dictionary)  # client: the host's world arrived
signal failed(text: String)  # client: couldn't connect
signal host_left  # client: the host closed the game
signal players_changed(count: int)

const RemotePlayer = preload("res://scripts/net/remote_player.gd")
const ADDRESS := "127.0.0.1"
const PORT := 24680
const MAX_PLAYERS := 4
const SEND_RATE := 20.0
const JOIN_TIMEOUT := 6.0
const COLORS := [Color(0.95, 0.55, 0.2), Color(0.3, 0.6, 0.95), Color(0.4, 0.85, 0.45), Color(0.85, 0.4, 0.85)]

var world  # VoxelWorld, once the game is running
var player
var avatar_parent: Node3D
var snapshot: Callable  # host: returns the world data a joiner needs
var is_host := false
var _avatars := {}  # peer id -> RemotePlayer
var _send_t := 0.0
var _join_t := -1.0


func _ready() -> void:
	name = "Net"  # same node path on every machine, so the calls find each other
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_disconnected.connect(_on_peer_left)


func active() -> bool:
	return multiplayer.multiplayer_peer != null \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func host() -> Error:
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(ADDRESS)
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_joined)
	is_host = true
	return OK


func join() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ADDRESS, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.connection_failed.connect(func(): _fail("No game open to join"))
	multiplayer.server_disconnected.connect(func(): host_left.emit())
	_join_t = JOIN_TIMEOUT
	return OK


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
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = 1.0 / SEND_RATE
		var pitch: float = player.camera.rotation.x if player.camera else 0.0
		_state.rpc(player.global_position, player.rotation.y, pitch)


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
func _state(pos: Vector3, yaw: float, pitch: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	var av = _avatars.get(id)
	if av == null or not is_instance_valid(av):
		if avatar_parent == null or not is_instance_valid(avatar_parent):
			return
		av = RemotePlayer.new()
		av.label_text = "Host" if id == 1 else "Miner"
		av.color = COLORS[0] if id == 1 else COLORS[1 + absi(id) % (COLORS.size() - 1)]
		avatar_parent.add_child(av)
		_avatars[id] = av
		print("Co-op: now showing player %d" % id)
		players_changed.emit(player_count())
	av.target(pos, yaw, pitch)


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
