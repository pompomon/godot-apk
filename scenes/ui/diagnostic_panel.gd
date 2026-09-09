extends VBoxContainer

const HeroUI = preload("res://scenes/ui/hero_ui.gd")
var _selection: Label


func _ready() -> void:
	name = "DiagnosticsPanel"
	add_child(HeroUI.label("Crash diagnostics · debug build", 32))
	var result := HeroUI.label(UIManager.diagnostics.summary(), 24)
	result.name = "LastDiagnosticLabel"
	add_child(result)
	add_child(HeroUI.label(
		"After a crash, relaunch and photograph the last milestone before trying again. "
		+ "Each new Roster/Formation visit replaces the trace. Compare D with A. "
		+ "B keeps texture lookup and layout but omits artwork drawing. "
		+ "C keeps artwork but fixes Hero-row and formation-slot heights; long text may overflow. "
		+ "D keeps baseline content sizing but uses the scene's static margins, without safe-area "
		+ "or centered-width updates.",
		24))
	_selection = HeroUI.label("", 24)
	_selection.name = "DiagnosticSelectionLabel"
	add_child(_selection)
	var group := ButtonGroup.new()
	for index in UIDiagnostics.MODE_NAMES.size():
		var button := HeroUI.button(UIDiagnostics.MODE_NAMES[index])
		button.name = "DiagnosticMode%d" % index
		button.toggle_mode = true
		button.button_group = group
		button.set_pressed_no_signal(index == UIManager.diagnostics.mode)
		button.pressed.connect(_select.bind(index))
		add_child(button)
	_select(UIManager.diagnostics.mode)


func _select(index: int) -> void:
	UIManager.diagnostics.select_mode(index)
	_selection.text = "Next attempt: %s" % UIDiagnostics.MODE_NAMES[UIManager.diagnostics.mode]
