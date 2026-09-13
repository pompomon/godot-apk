extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
const HOME := "res://scenes/ui/home/home_screen.tscn"
const SETTINGS := "res://scenes/ui/settings/settings_screen.tscn"
const ScreenMargin = preload("res://scenes/ui/screen_margin.gd")
var _isolation: RefCounted
var _main: Control
var _root: Control
var _auto_accept_quit: bool


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	_auto_accept_quit = get_tree().auto_accept_quit
	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	_root = _main.get_node("ScreenRoot")
	await get_tree().process_frame
	assert_true(SaveManager.last_success, SaveManager.last_error)


func after_each() -> void:
	if is_instance_valid(_main):
		_main.free()
	await get_tree().process_frame
	get_tree().auto_accept_quit = _auto_accept_quit
	_isolation.finish()


func _screen() -> Control:
	return _root.get_child(0)


func _node(name: String) -> Node:
	return _screen().find_child(name, true, false)


func _open_settings() -> void:
	_node("SettingsButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, SETTINGS)


func _path(name: String) -> String:
	return _isolation.directory.path_join(name)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	file.store_string(text)
	file.close()


func test_home_opens_settings_with_native_json_pickers_and_touch_targets() -> void:
	assert_eq(_screen().scene_file_path, HOME)
	assert_eq(_node("SettingsButton").text, "Settings & Backups")
	await _open_settings()
	assert_same(_node("Margin").get_script(), ScreenMargin)
	assert_string_contains(_node("PortableSaveHelp").text, "do not contain")
	for name in ["ExportButton", "ImportButton", "BackButton"]:
		assert_gte(_node(name).get_combined_minimum_size().y, 96.0)
	var export_dialog := _node("ExportDialog") as FileDialog
	var import_dialog := _node("ImportDialog") as FileDialog
	assert_eq(export_dialog.file_mode, FileDialog.FILE_MODE_SAVE_FILE)
	assert_eq(import_dialog.file_mode, FileDialog.FILE_MODE_OPEN_FILE)
	assert_eq(export_dialog.access, FileDialog.ACCESS_FILESYSTEM)
	assert_eq(import_dialog.access, FileDialog.ACCESS_FILESYSTEM)
	assert_true(export_dialog.use_native_dialog)
	assert_true(import_dialog.use_native_dialog)
	assert_eq(export_dialog.filters, PackedStringArray(["*.json ; JSON save files"]))
	var confirmation := _node("ReplaceDialog") as ConfirmationDialog
	assert_gte(confirmation.get_ok_button().get_combined_minimum_size().y, 96.0)
	assert_gte(confirmation.get_cancel_button().get_combined_minimum_size().y, 96.0)
	_node("BackButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)


func test_export_callback_writes_portable_file_without_touching_private_save() -> void:
	await _open_settings()
	var before := SaveManager.capture_state()
	var private_text := FileAccess.get_file_as_string(SaveManager.get_save_path())
	var path := _path("ui-export.json")
	_screen().call("_on_export_selected", path)
	assert_true(FileAccess.file_exists(path))
	assert_true(SaveManager.last_success, SaveManager.last_error)
	assert_eq(SaveManager.capture_state(), before)
	assert_eq(FileAccess.get_file_as_string(SaveManager.get_save_path()), private_text)
	assert_string_contains(_node("FeedbackLabel").text, "exported")
	var portable: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_eq(portable.format, ExternalSaveCodec.FORMAT_ID)
	assert_false(portable.payload.has("expedition"))


func test_restore_requires_confirmation_then_replaces_and_returns_home() -> void:
	GameState.gold = 111
	var path := _path("ui-import.json")
	SaveManager.export_external_save(path)
	assert_true(SaveManager.last_success, SaveManager.last_error)
	GameState.gold = 222
	SaveManager.save()
	assert_true(SaveManager.last_committed)
	await _open_settings()
	_screen().call("_on_import_selected", path)
	var confirmation := _node("ReplaceDialog") as ConfirmationDialog
	assert_true(confirmation.visible)
	assert_string_contains(confirmation.dialog_text, "replaces")
	assert_string_contains(confirmation.dialog_text, "active Expedition")
	assert_string_contains(confirmation.dialog_text, "completed Expedition report")
	assert_string_contains(_node("PortableSaveHelp").text, "active Expedition")
	assert_string_contains(_node("PortableSaveHelp").text, "completed Expedition report")
	assert_eq(GameState.gold, 222)
	_screen().call("cancel_draft")
	assert_false(confirmation.visible)
	assert_eq(_screen().scene_file_path, SETTINGS)
	assert_eq(GameState.gold, 222)
	_screen().call("_on_import_selected", path)
	confirmation.hide()
	confirmation.confirmed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)
	assert_eq(GameState.gold, 111)
	assert_string_contains(_node("FeedbackLabel").text, "not imported")


func test_failed_restore_stays_in_settings_and_back_preserves_company() -> void:
	var path := _path("invalid.json")
	_write(path, "{invalid")
	var before := SaveManager.capture_state()
	var disk := FileAccess.get_file_as_string(SaveManager.get_save_path())
	await _open_settings()
	_screen().call("_on_import_selected", path)
	var confirmation := _node("ReplaceDialog") as ConfirmationDialog
	confirmation.hide()
	confirmation.confirmed.emit()
	assert_eq(_screen().scene_file_path, SETTINGS)
	assert_eq(SaveManager.capture_state(), before)
	assert_eq(FileAccess.get_file_as_string(SaveManager.get_save_path()), disk)
	assert_string_contains(_node("FeedbackLabel").text, "valid JSON")
	_node("BackButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)
