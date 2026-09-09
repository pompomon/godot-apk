class_name UIDiagnostics
extends RefCounted
## Debug-only presentation probe. Never reads or writes Company state.

enum Mode { BASELINE, NO_ARTWORK, FIXED_ROWS }
const MODE_NAMES := ["A · Baseline", "B · No artwork drawing", "C · Fixed row sizing"]
const SCREENS := {
	"res://scenes/ui/roster/roster_screen.tscn": "Company Roster",
	"res://scenes/ui/party_formation/party_formation_screen.tscn": "Party Formation",
}
const MAX_BYTES := 65536
const MAX_MARKERS := 128
const PROBE_VERSION := 1

var enabled: bool = false
var mode: int = Mode.BASELINE
var last_error: String = ""
var last_record: Dictionary = {}
var generation: int = 0
var _path: String = ""
var _screen: String = ""
var _run_mode: int = Mode.BASELINE
var _viewport: String = ""
var _seen: Dictionary = {}


func initialize(directory: String, requested: bool) -> void:
	stop()
	enabled = OS.is_debug_build() and requested
	mode = Mode.BASELINE
	last_record = {}
	last_error = ""
	_path = ""
	if not enabled:
		return
	_path = directory.path_join("ui-diagnostics.jsonl")
	if not FileAccess.file_exists(_path):
		return
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		last_error = "Cannot read the diagnostic trace."
		return
	if file.get_length() > MAX_BYTES:
		last_error = "Diagnostic trace exceeds its size limit."
		file.close()
		return
	while file.get_position() < file.get_length():
		var json := JSON.new()
		if json.parse(file.get_line()) == OK and _valid_record(json.data):
			last_record = json.data
			last_record.mode = int(last_record.mode)
			last_record.probe = PROBE_VERSION
	file.close()
	if not last_record.is_empty():
		mode = int(last_record.mode)
	else:
		last_error = "No complete diagnostic record was readable."


func _valid_record(data: Variant) -> bool:
	if not data is Dictionary or data.get("probe") != PROBE_VERSION:
		return false
	var value: Variant = data.get("mode")
	if not (value is int or value is float) or not is_finite(float(value)):
		return false
	if value < Mode.BASELINE or value > Mode.FIXED_ROWS or value != int(value):
		return false
	if data.get("screen") not in SCREENS.values():
		return false
	if not data.get("first_draw_finished") is bool:
		return false
	for key in ["stage", "viewport", "renderer"]:
		if not data.get(key) is String or data[key].length() > 160:
			return false
	return true


func select_mode(value: int) -> void:
	if enabled and _screen.is_empty() and value in Mode.values():
		mode = value


func stop() -> void:
	generation += 1
	_screen = ""
	_seen.clear()


func begin_navigation(scene_path: String, viewport: Viewport) -> void:
	stop()
	if not enabled or not SCREENS.has(scene_path):
		return
	_screen = SCREENS[scene_path]
	_run_mode = mode
	var extent := viewport.get_visible_rect().size
	_viewport = "%d x %d" % [extent.x, extent.y]
	mark("navigation.begin", true)


func hide_artwork() -> bool:
	return enabled and not _screen.is_empty() and _run_mode == Mode.NO_ARTWORK


func fixed_rows() -> bool:
	return enabled and not _screen.is_empty() and _run_mode == Mode.FIXED_ROWS


func is_recording(token: int) -> bool:
	return enabled and not _screen.is_empty() and token == generation


func mark_for(token: int, stage: String) -> void:
	if is_recording(token):
		mark(stage)


func mark(stage: String, new_attempt: bool = false) -> void:
	if not enabled or _screen.is_empty() or _seen.has(stage) or _seen.size() >= MAX_MARKERS:
		return
	# Record each milestone once, not on every resize or foreground refresh.
	_seen[stage] = true
	var record := {
		"probe": PROBE_VERSION, "mode": _run_mode, "screen": _screen,
		"stage": stage.left(160), "viewport": _viewport,
		"renderer": RenderingServer.get_current_rendering_method(),
		"first_draw_finished": _seen.has("render.first_draw.end"),
	}
	var file := FileAccess.open(_path, FileAccess.WRITE if new_attempt else FileAccess.READ_WRITE)
	if file == null:
		last_error = "Cannot write diagnostic trace; no Company save was changed."
		return
	file.seek_end()
	var line := JSON.stringify(record) + "\n"
	if file.get_length() + line.to_utf8_buffer().size() > MAX_BYTES:
		file.close()
		last_error = "Diagnostic trace is full; later milestones were not recorded."
		return
	file.store_string(line)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		last_error = "Diagnostic write failed; the last durable milestone is uncertain."
		return
	last_record = record


func summary() -> String:
	var text := "UI probe %d · Last recorded attempt (not a crash verdict):\n" % PROBE_VERSION
	if last_record.is_empty():
		text += "None yet. Choose a mode, then open Company Roster or Form Party."
	else:
		text += "%s\n%s\n%s\nViewport: %s · Renderer: %s" % [
			MODE_NAMES[int(last_record.mode)], last_record.screen, last_record.stage,
			last_record.viewport, last_record.renderer]
		text += "\nFirst render cycle finished: %s" % (
			"yes" if last_record.first_draw_finished else "not observed")
	if not last_error.is_empty():
		text += "\n" + last_error
	return text
