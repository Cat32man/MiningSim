extends CanvasLayer
## Error panel: tells the player something went wrong and lets them copy the details for a
## bug report (version, computer, recent errors) or open the log folder.
##   - script errors and the game's own push_error()s pop it up during play;
##   - engine-internal errors are only recorded (they go into "Copy details");
##   - if the last run didn't close properly (froze, crashed, was killed), it shows on the
##     title screen with the end of that run's log;
##   - main shows it for co-op disconnects too.

const UI = preload("res://scripts/ui/ui_kit.gd")
const RUN_FLAG := "user://running.flag"
const KEEP_LINES := 40


## Catches errors from anywhere (any thread) for the panel.
class Collector extends Logger:
	var mutex := Mutex.new()
	var pending: Array[String] = []  # to show
	var recent: Array[String] = []  # for "Copy details"

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var msg := rationale if rationale != "" else code
		if msg.begins_with("BUG: Unreferenced static string"):
			return  # engine noise at exit
		var where := "%s:%d" % [file, line]
		if not script_backtraces.is_empty() and script_backtraces[0].get_frame_count() > 0:
			where = "%s:%d" % [script_backtraces[0].get_frame_file(0), script_backtraces[0].get_frame_line(0)]
		var text := "%s  (%s)" % [msg, where]
		mutex.lock()
		recent.append(text)
		if recent.size() > KEEP_LINES:
			recent.pop_front()
		if error_type == ERROR_TYPE_SCRIPT or file.ends_with("variant_utility.cpp"):  # push_error()
			pending.append(text)
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


static var collector: Collector

var on_close: Callable  # main: give the mouse back to the game
var _shown: Array[String] = []
var _body: VBoxContainer
var _title: Label
var _text: Label
var _extra := ""


## Start catching errors (first thing at start-up).
static func install() -> void:
	if collector == null:
		collector = Collector.new()
		OS.add_logger(collector)


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_body = UI.panel(self, 680)
	_title = UI.label("", 26, Color(1.0, 0.55, 0.4))
	_body.add_child(_title)
	_text = UI.label("", 15)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 640
	_body.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(UI.button("Copy details", func():
		DisplayServer.clipboard_set(details())
		_text.text += "\n\nCopied: paste it to whoever makes the game."))
	row.add_child(UI.button("Open log folder", func():
		OS.shell_open(ProjectSettings.globalize_path("user://logs"))))
	row.add_child(UI.button("Keep playing", close))
	_body.add_child(row)


func _process(_dt: float) -> void:
	if collector == null:
		return
	collector.mutex.lock()
	var new: Array[String] = collector.pending.duplicate()
	collector.pending.clear()
	collector.mutex.unlock()
	var fresh := new.filter(func(t): return not _shown.has(t))
	if fresh.is_empty():
		return
	_shown.append_array(fresh)
	var lines: Array[String] = []
	for t in fresh.slice(-5):
		lines.append("• " + t)
	show_report("Something went wrong", "The game hit an error. It may keep working; if it acts up, " +
		"copy the details for a bug report.\n\n" + "\n".join(lines))


## Shows the panel (replacing what it showed). `extra` goes into "Copy details" too.
func show_report(title: String, text: String, extra := "") -> void:
	_title.text = title
	_text.text = text
	_extra = extra
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	if on_close.is_valid():
		on_close.call()


## Version, computer and recent errors, for a bug report.
func details() -> String:
	var out := "MiningSim v%d (built v%d) on %s, %s\n" % [Updates.version, Updates.base_version, OS.get_name(),
		RenderingServer.get_video_adapter_name()]
	out += "Shown: %s\n%s\n" % [_title.text, _text.text.get_slice("\n\nCopied", 0)]
	if collector:
		collector.mutex.lock()
		out += "\nRecent errors:\n" + "\n".join(collector.recent) + "\n"
		collector.mutex.unlock()
	if _extra != "":
		out += "\n" + _extra
	return out


# --- Did the last run end properly? --------------------------------------------------

## Call at start-up (normal play only). True if the last run never got to mark_clean_exit():
## it froze, crashed or was killed.
static func last_run_crashed() -> bool:
	var crashed := FileAccess.file_exists(RUN_FLAG)
	var f := FileAccess.open(RUN_FLAG, FileAccess.WRITE)
	if f:
		f.store_string(Time.get_datetime_string_from_system())
		f.close()
	return crashed


static func mark_clean_exit() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_FLAG))


## The last lines of the previous run's log (Godot keeps the older ones beside godot.log).
static func previous_log_tail(lines := 60) -> String:
	var dir := DirAccess.open("user://logs")
	if dir == null:
		return ""
	var logs: Array = Array(dir.get_files()).filter(func(n: String): return n.begins_with("godot") and n != "godot.log")
	if logs.is_empty():
		return ""
	logs.sort()  # timestamped names: newest last
	var text := FileAccess.get_file_as_string("user://logs/" + logs[-1])
	var all := text.split("\n")
	return "Last run's log (end):\n" + "\n".join(all.slice(maxi(all.size() - lines, 0)))
