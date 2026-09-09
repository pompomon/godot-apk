extends Control

const HeroUI = preload("res://scenes/ui/hero_ui.gd")
const HOME_SCREEN := "res://scenes/ui/home/home_screen.tscn"
const ROSTER_SCREEN := "res://scenes/ui/roster/roster_screen.tscn"
const BALANCING: BalancingConfig = preload("res://data/balancing/default_balancing.tres")

var draft: PartyData
var _origin: String = HOME_SCREEN
var _selected_slot: int = PartyData.FormationSlot.FRONT_LEFT
var _moving_from: int = -1
var _feedback_message: String = ""
var _leaving: bool = false
var _slot_buttons: Array[Button] = []


func configure(context: Dictionary) -> void:
	var origin: Variant = context.get("origin")
	_origin = ROSTER_SCREEN if origin is String and origin == "roster" else HOME_SCREEN


func _ready() -> void:
	HeroUI.apply_theme(self)
	draft = GameState.current_party.copy() if GameState.current_party != null else PartyData.new()
	for slot in PartyData.SLOT_ORDER:
		UIManager.diagnostics.mark("formation.slot.%d.begin" % slot)
		var button := _slot_button(slot)
		_slot_buttons.append(button)
		%SlotGrid.add_child(button)
		UIManager.diagnostics.mark("formation.slot.%d.added" % slot)
	%CancelButton.pressed.connect(cancel_draft)
	%ConfirmButton.pressed.connect(_confirm)
	%DisbandButton.pressed.connect(_disband)
	%RemoveButton.pressed.connect(_remove)
	%MoveButton.pressed.connect(_begin_move)
	ExpeditionManager.changed.connect(_refresh_expedition_state)
	ExpeditionManager.operation_failed.connect(_refresh_expedition_state)
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready():
		_refresh()


func _refresh_expedition_state() -> void:
	if _leaving or not is_inside_tree():
		return
	_feedback_message = ExpeditionManager.last_error
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel_draft()


func _slot_button(slot: int) -> Button:
	var button := HeroUI.button("")
	button.name = PartyData.SLOT_NAMES[slot]
	button.toggle_mode = true
	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	margin.add_theme_constant_override("margin_top", 88)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)
	var portrait := HeroUI.portrait(null, 64)
	portrait.position = Vector2(16, 16)
	portrait.size = Vector2(64, 64)
	button.add_child(portrait)
	var text := HeroUI.label("", 28)
	text.name = "SlotLabel"
	margin.add_child(text)
	if UIManager.diagnostics.fixed_rows():
		button.custom_minimum_size.y = 320
		UIManager.diagnostics.mark("layout.slot.fixed_height")
	else:
		var token := UIManager.diagnostics.generation
		margin.minimum_size_changed.connect(func() -> void:
			UIManager.diagnostics.mark_for(token, "layout.slot.minimum_change.begin")
			button.custom_minimum_size.y = maxf(160.0, margin.get_combined_minimum_size().y)
			UIManager.diagnostics.mark_for(token, "layout.slot.minimum_change.end"))
		button.custom_minimum_size.y = 160
	button.pressed.connect(_select_slot.bind(slot))
	return button


func _refresh() -> void:
	var editing_error := PartyFormationService.editing_error()
	var model_error := draft.validation_error()
	var blocked := not editing_error.is_empty() or not model_error.is_empty()
	for slot in PartyData.SLOT_ORDER:
		var button := _slot_buttons[slot]
		var hero: Variant = draft.slots.get(slot)
		var text := "%s\n%s" % [PartyData.SLOT_LABELS[slot], hero.hero_name if hero is HeroData else "Empty"]
		button.get_node("MarginContainer/SlotLabel").text = text
		var portrait: TextureRect = button.get_node("Portrait")
		var texture := HeroUI.portrait_texture(hero if hero is HeroData else null)
		portrait.texture = null if UIManager.diagnostics.hide_artwork() else texture
		button.set_pressed_no_signal(slot == _selected_slot)
		button.disabled = blocked
	%MemberCountLabel.text = "Party: %d / 4 Heroes" % draft.heroes().size()
	var names := PackedStringArray()
	for hero in draft.heroes():
		names.append("%s · %s" % [hero.hero_name, HeroUI.status_name(hero)])
	%MembersLabel.text = "\n".join(names) if not names.is_empty() else "No Heroes selected."
	var power := PartyEvaluator.compute_party_power(draft, BALANCING)
	%PowerLabel.text = "Party Power: %s" % (String.num(power, 2) if is_finite(power) else "Unavailable")
	%PenaltyLabel.text = "Size factor: %d / %s. %s" % [
		draft.heroes().size(), String.num(BALANCING.party_size_divisor, 2),
		"No front row: ×%s penalty." % String.num(BALANCING.missing_front_row_factor, 2)
			if not draft.has_front_row_hero() else "Front row present: no formation penalty."]
	var selected: Variant = draft.slots.get(_selected_slot)
	%RemoveButton.disabled = blocked or selected == null
	%MoveButton.disabled = blocked or selected == null or draft.heroes().size() == 4
	if _moving_from >= 0:
		%SelectionLabel.text = "Choose an empty destination slot to move the selected Hero."
	elif selected != null:
		%SelectionLabel.text = "Selected: %s. Move or remove this Hero, or select another empty slot." % PartyData.SLOT_LABELS[_selected_slot]
	else:
		%SelectionLabel.text = "Selected: %s. Tap an available Hero to place them." % PartyData.SLOT_LABELS[_selected_slot]
	var reason := PartyFormationService.validation_error(draft, BALANCING)
	%ConfirmButton.disabled = not reason.is_empty()
	%DisbandButton.visible = GameState.current_party != null
	%DisbandButton.disabled = not editing_error.is_empty()
	HeroUI.clear_children(%AvailableList)
	var available := 0
	for hero in GameState.roster:
		if not PartyFormationService.availability_error(hero).is_empty() or draft.contains_id(hero.hero_id):
			continue
		UIManager.diagnostics.mark("hero.available.%d.begin" % available)
		var row := HeroUI.hero_row(hero, _place.bind(hero), "Place in selected slot")
		row.name = "AvailableHero%d" % available
		row.tooltip_text = "Place %s in the selected empty slot" % hero.hero_name
		row.disabled = blocked or selected != null or _moving_from >= 0
		%AvailableList.add_child(row)
		UIManager.diagnostics.mark("hero.available.%d.added" % available)
		available += 1
	%NoAvailableLabel.visible = available == 0
	var feedback := _feedback_message
	if not reason.is_empty():
		feedback += ("\n" if not feedback.is_empty() else "") + reason
	HeroUI.show_feedback(%FeedbackLabel, feedback)


func _can_edit() -> bool:
	if _leaving or not is_inside_tree():
		return false
	_feedback_message = PartyFormationService.editing_error()
	if not _feedback_message.is_empty():
		_refresh()
		return false
	return true


func _select_slot(slot: int) -> void:
	if not _can_edit():
		return
	if _moving_from >= 0:
		if not draft.move_hero(_moving_from, slot):
			_feedback_message = "Choose an empty destination; occupied slots are never replaced."
			_refresh()
			return
		_moving_from = -1
	_selected_slot = slot
	_refresh()


func _place(hero: HeroData) -> void:
	if not _can_edit():
		return
	_feedback_message = PartyFormationService.availability_error(hero)
	if _feedback_message.is_empty() and not draft.place_hero(_selected_slot, hero):
		_feedback_message = "Choose an empty slot and an unselected Hero; occupied slots are never replaced."
	_refresh()


func _remove() -> void:
	if not _can_edit():
		return
	if not draft.remove_hero(_selected_slot):
		_feedback_message = "Select an occupied slot to remove its Hero."
	_moving_from = -1
	_refresh()


func _begin_move() -> void:
	if not _can_edit():
		return
	if draft.slots.get(_selected_slot) != null:
		_moving_from = _selected_slot
	_refresh()


func _confirm() -> void:
	if _leaving or not is_inside_tree():
		return
	if PartyFormationService.confirm(draft, BALANCING):
		_leaving = true
		UIManager.show_screen(HOME_SCREEN)
	else:
		_feedback_message = PartyFormationService.last_error + "\nCheck storage or selection, then retry."
		_refresh()


func _disband() -> void:
	if _leaving or not is_inside_tree():
		return
	if PartyFormationService.disband():
		_leaving = true
		UIManager.show_screen(HOME_SCREEN)
	else:
		_feedback_message = PartyFormationService.last_error + "\nCheck storage, then retry Disband."
		_refresh()


func cancel_draft() -> void:
	if not _leaving and is_inside_tree():
		_leaving = true
		UIManager.show_screen(_origin)
