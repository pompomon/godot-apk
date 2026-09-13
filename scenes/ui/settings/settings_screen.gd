extends Control

const HeroUI = preload("res://scenes/ui/hero_ui.gd")
const HOME_SCREEN := "res://scenes/ui/home/home_screen.tscn"

var _feedback: Label
var _export_dialog: FileDialog
var _import_dialog: FileDialog
var _replace_dialog: ConfirmationDialog
var _pending_import_path: String = ""
var _leaving: bool = false


func _ready() -> void:
	HeroUI.apply_theme(self)
	var content := HeroUI.scrollable_content(self)
	var title := HeroUI.label("Settings", 44)
	title.name = "Title"
	content.add_child(title)
	HeroUI.add_section_divider(content)
	var help := HeroUI.label(
		"Portable backups contain Heroes, unequipped items, gold, and opened Regions. "
		+ "They do not contain the current Party, active Expedition, completed Expedition "
		+ "report, or automated plan.")
	help.name = "PortableSaveHelp"
	content.add_child(help)
	var export_button := HeroUI.button("Export portable backup")
	export_button.name = "ExportButton"
	export_button.pressed.connect(_choose_export)
	content.add_child(export_button)
	var import_button := HeroUI.button("Restore portable backup")
	import_button.name = "ImportButton"
	import_button.pressed.connect(_choose_import)
	content.add_child(import_button)
	_feedback = HeroUI.label("")
	_feedback.name = "FeedbackLabel"
	content.add_child(_feedback)
	var back_button := HeroUI.button("Back to Home")
	back_button.name = "BackButton"
	back_button.pressed.connect(cancel_draft)
	content.add_child(back_button)
	_export_dialog = _file_dialog(
		"Export portable backup", FileDialog.FILE_MODE_SAVE_FILE, "adventurers-march-save.json")
	_export_dialog.name = "ExportDialog"
	_export_dialog.file_selected.connect(_on_export_selected)
	add_child(_export_dialog)
	_import_dialog = _file_dialog(
		"Restore portable backup", FileDialog.FILE_MODE_OPEN_FILE)
	_import_dialog.name = "ImportDialog"
	_import_dialog.file_selected.connect(_on_import_selected)
	add_child(_import_dialog)
	_replace_dialog = ConfirmationDialog.new()
	_replace_dialog.name = "ReplaceDialog"
	_replace_dialog.title = "Replace Company?"
	_replace_dialog.dialog_text = (
		"Restoring replaces this Company. The current Party, active Expedition, completed "
		+ "Expedition report, and automated plan will be discarded. This cannot be merged.")
	_replace_dialog.ok_button_text = "Replace Company"
	_replace_dialog.get_ok_button().custom_minimum_size.y = 96
	_replace_dialog.get_cancel_button().custom_minimum_size.y = 96
	_replace_dialog.confirmed.connect(_confirm_import)
	_replace_dialog.canceled.connect(_cancel_import)
	add_child(_replace_dialog)
	_refresh()


func _file_dialog(title: String, mode: FileDialog.FileMode, filename: String = "") -> FileDialog:
	var dialog := FileDialog.new()
	dialog.title = title
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; JSON save files"])
	dialog.use_native_dialog = true
	dialog.size = Vector2i(640, 960)
	if not filename.is_empty():
		dialog.current_file = filename
	return dialog


func _choose_export() -> void:
	if not _leaving:
		_export_dialog.popup_centered_ratio(0.9)


func _choose_import() -> void:
	if not _leaving:
		_import_dialog.popup_centered_ratio(0.9)


func _on_export_selected(path: String) -> void:
	if _leaving:
		return
	SaveManager.export_external_save(path)
	_refresh("Portable backup exported." if SaveManager.last_success else "")


func _on_import_selected(path: String) -> void:
	if _leaving or path.strip_edges().is_empty():
		return
	_pending_import_path = path
	_replace_dialog.popup_centered()


func _confirm_import() -> void:
	if _leaving or _pending_import_path.is_empty():
		return
	var path := _pending_import_path
	_pending_import_path = ""
	SaveManager.import_external_save(path)
	if SaveManager.last_committed:
		_leaving = true
		UIManager.show_screen(HOME_SCREEN)
	else:
		_refresh()


func _cancel_import() -> void:
	_pending_import_path = ""


func _refresh(message: String = "") -> void:
	if not is_inside_tree():
		return
	HeroUI.show_feedback(_feedback, message)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel_draft()


func cancel_draft() -> void:
	if _replace_dialog.visible:
		_replace_dialog.hide()
		_cancel_import()
		return
	for dialog in [_export_dialog, _import_dialog]:
		if dialog.visible:
			dialog.hide()
			return
	if not _leaving and is_inside_tree():
		_leaving = true
		UIManager.show_screen(HOME_SCREEN)
