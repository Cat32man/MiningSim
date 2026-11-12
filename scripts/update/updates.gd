extends Node
## Game updates (autoload "Updates"). A release only changes the game-data pack, not the
## engine, so an update is a whole new pack (a few MB): the title screen fetches
## manifest.json from the update server, downloads the newer pack, checks it and saves it as
## user://update/game.pck. On every start of an exported build, this autoload loads that
## pack over the built-in one before the main scene loads, if it's newer than the build.
##
## The pack holds the co-op key, so update files are encrypted with the build's secret
## (AES-256-CBC, then HMAC-SHA256 over everything; see scripts/tools/make_update.gd).
## Only our builds can open them and anything altered is refused.
##
## Keep this script self-contained: it runs before the patch loads, so it can't be patched
## itself (a fix here needs a new full build).

signal status(text: String, ready: bool)  # for the title screen; ready = restart to apply

const DIR := "user://update/"
const PACK := DIR + "game.pck"
const INFO := DIR + "installed.json"
const KEY_PATH := "res://scripts/net/coop_key.gd"
const MAGIC := "MSUP1"

var version := 1  # what's running now
var base_version := 1  # what this build shipped with
var _http: HTTPRequest
var _urls: Array = []
var _url_i := 0
var _want := {}  # the manifest we're downloading for
var _busy := false


func _init() -> void:
	base_version = int(str(ProjectSettings.get_setting("application/config/version", "1")))
	version = base_version
	if OS.has_feature("template"):  # exported builds only: never patch the editor/source
		_load_patch()


func _load_patch() -> void:
	# A download that couldn't replace the pack in use last time goes in now.
	if FileAccess.file_exists(PACK + ".new"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PACK))
		DirAccess.rename_absolute(ProjectSettings.globalize_path(PACK + ".new"), ProjectSettings.globalize_path(PACK))
	if not FileAccess.file_exists(PACK) or not FileAccess.file_exists(INFO):
		return
	var info = JSON.parse_string(FileAccess.get_file_as_string(INFO))
	if not info is Dictionary:
		return
	var v := int(info.get("version", 0))
	if v <= base_version or info.get("engine", "") != _engine():
		return  # a newer full build (or another engine) already has everything
	if ProjectSettings.load_resource_pack(PACK, true):
		version = v
		print("Update: running v%d over v%d" % [v, base_version])
	else:
		push_warning("Update: couldn't load the downloaded pack; removing it")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PACK))


static func _engine() -> String:
	var e := Engine.get_version_info()
	return "%d.%d.%d" % [e["major"], e["minor"], e["patch"]]


static func _keys():
	return load(KEY_PATH) if ResourceLoader.exists(KEY_PATH) else null


# --- Checking for a new version (title screen) ---------------------------------------

## Starts a check; results come through `status`.
func check() -> void:
	if _busy or OS.has_feature("web"):
		return
	var k = _keys()
	_urls = k.get_script_constant_map().get("UPDATE_URLS", []) if k else []
	var test := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--update-url="):
			_urls = [arg.trim_prefix("--update-url=")]  # test server
			test = true
	if _urls.is_empty() or not (OS.has_feature("template") or test):
		return  # running from source: nothing to update
	_busy = true
	_url_i = 0
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = 20.0
		add_child(_http)
	_get_manifest()


func _base() -> String:
	var u: String = _urls[_url_i]
	return u if u.ends_with("/") else u + "/"


func _get_manifest() -> void:
	_http.request_completed.connect(_on_manifest, CONNECT_ONE_SHOT)
	if _http.request(_base() + "manifest.json") != OK:
		_http.request_completed.disconnect(_on_manifest)
		_next_url()


func _next_url() -> void:
	_url_i += 1
	if _url_i < _urls.size():
		_get_manifest()
	else:
		_busy = false  # offline or no server: just play


func _on_manifest(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_next_url()
		return
	var m = JSON.parse_string(body.get_string_from_utf8())
	if not m is Dictionary:
		_next_url()
		return
	var v := int(m.get("version", 0))
	if v <= version:
		_busy = false
		return  # up to date
	if FileAccess.file_exists(INFO):
		var info = JSON.parse_string(FileAccess.get_file_as_string(INFO))
		if info is Dictionary and int(info.get("version", 0)) >= v:
			_busy = false
			status.emit("Update v%d ready" % v, true)  # downloaded, not running yet
			return
	if m.get("engine", "") != _engine():
		_busy = false
		status.emit("v%d is out: get the new full download" % v, false)
		return
	_want = m
	status.emit("Downloading v%d…" % v, false)
	_http.request_completed.connect(_on_pack, CONNECT_ONE_SHOT)
	if _http.request(_base() + str(m.get("file", ""))) != OK:
		_http.request_completed.disconnect(_on_pack)
		_busy = false
		status.emit("Update download failed", false)


func _on_pack(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status.emit("Update download failed", false)
		return
	var pck := open_update(body, int(_want["version"]), _keys())
	if pck.is_empty():
		status.emit("Update file was damaged; skipped", false)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var tmp := PACK + ".new"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		status.emit("Couldn't save the update", false)
		return
	f.store_buffer(pck)
	f.close()
	# The running game may have the old pack open: then the swap waits for the next start.
	var abs_pack := ProjectSettings.globalize_path(PACK)
	if not FileAccess.file_exists(PACK) or DirAccess.remove_absolute(abs_pack) == OK:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), abs_pack)
	var info := FileAccess.open(INFO, FileAccess.WRITE)
	info.store_string(JSON.stringify({"version": int(_want["version"]), "engine": _engine()}))
	info.close()
	print("Update: v%d downloaded" % int(_want["version"]))
	status.emit("Update v%d ready" % int(_want["version"]), true)


## Starts this game again (picks up the new pack) and quits.
func restart() -> void:
	OS.create_process(OS.get_executable_path(), OS.get_cmdline_args())
	get_tree().quit()


# --- Update file format --------------------------------------------------------------

static func _subkey(secret: PackedByteArray, label: String) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(secret)
	h.update(label.to_utf8_buffer())
	return h.finish()


## Update file: "MSUP1" + version (u32) + IV (16) + AES-256-CBC(pck, PKCS#7) + HMAC (32).
static func seal_update(pck: PackedByteArray, ver: int, k) -> PackedByteArray:
	var secret: PackedByteArray = k.SECRET.hex_decode()
	var pad := 16 - pck.size() % 16
	var plain := pck.duplicate()
	for i in pad:
		plain.append(pad)
	var iv := Crypto.new().generate_random_bytes(16)
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_ENCRYPT, _subkey(secret, "update-enc"), iv)
	var ct := aes.update(plain)
	aes.finish()
	var head := MAGIC.to_ascii_buffer()
	var vb := PackedByteArray([0, 0, 0, 0])
	vb.encode_u32(0, ver)
	var body := head + vb + iv + ct
	return body + Crypto.new().hmac_digest(HashingContext.HASH_SHA256, _subkey(secret, "update-mac"), body)


## The pack inside an update file, or empty if it's not ours, damaged, or not `ver`.
static func open_update(data: PackedByteArray, ver: int, k) -> PackedByteArray:
	if k == null or data.size() < 5 + 4 + 16 + 16 + 32:
		return PackedByteArray()
	var secret: PackedByteArray = k.SECRET.hex_decode()
	var body := data.slice(0, data.size() - 32)
	var mac := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, _subkey(secret, "update-mac"), body)
	if not Crypto.new().constant_time_compare(mac, data.slice(data.size() - 32)):
		return PackedByteArray()
	if body.slice(0, 5).get_string_from_ascii() != MAGIC or body.decode_u32(5) != ver:
		return PackedByteArray()
	var ct := body.slice(25)
	if ct.size() % 16 != 0:
		return PackedByteArray()
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_DECRYPT, _subkey(secret, "update-enc"), body.slice(9, 25))
	var plain := aes.update(ct)
	aes.finish()
	var pad := plain[plain.size() - 1]
	if pad < 1 or pad > 16:
		return PackedByteArray()
	return plain.slice(0, plain.size() - pad)
