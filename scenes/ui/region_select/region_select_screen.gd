extends Control

const HeroUI = preload("res://scenes/ui/hero_ui.gd")
const HOME_SCREEN := "res://scenes/ui/home/home_screen.tscn"
var _party: PartyData
var _region: RegionResource
var _duration: OptionButton
var _start: Button
var _feedback: Label
var _gold: Label
var _recommendation: Label
var _region_buttons: Dictionary = {}
var _requirements: Dictionary = {}
var _leaving: bool = false


func _ready() -> void:
	HeroUI.apply_theme(self)
	var content := HeroUI.scrollable_content(self)
	content.add_child(HeroUI.label("Choose an Expedition", 44))
	_party = GameState.current_party
	_region = ExpeditionCatalog.GREEN_HOLLOW
	var summary := HeroUI.label("No confirmed Party. Return Home and form one.")
	summary.name = "PartySummary"
	if _party != null:
		var power := PartyEvaluator.compute_party_power(_party, ExpeditionManager.balancing)
		summary.text = "Party: %d / 4 Heroes · Power: %s" % [
			_party.heroes().size(), String.num(power, 2) if is_finite(power) else "Unavailable"]
		for slot in PartyData.SLOT_ORDER:
			var hero: Variant = _party.slots.get(slot)
			if hero is HeroData:
				summary.text += "\n%s: %s · %s" % [PartyData.SLOT_LABELS[slot], hero.hero_name, HeroUI.class_name_for(hero)]
	content.add_child(summary)
	_gold = HeroUI.label("")
	_gold.name = "GoldLabel"
	content.add_child(_gold)
	content.add_child(HeroUI.label(
		"Reach held-gold milestones to unlock Regions permanently. Gold is not spent.", 24))
	var regions := VBoxContainer.new()
	regions.name = "RegionList"
	content.add_child(regions)
	var group := ButtonGroup.new()
	for region in ExpeditionCatalog.regions():
		var choice := HeroUI.button("")
		choice.name = "RegionButton_%s" % region.region_id
		choice.toggle_mode = true
		choice.button_group = group
		choice.pressed.connect(_select_region.bind(region))
		regions.add_child(choice)
		_region_buttons[region.region_id] = choice
		var requirement := HeroUI.label("", 24)
		requirement.name = "RegionRequirement_%s" % region.region_id
		regions.add_child(requirement)
		_requirements[region.region_id] = requirement
	_recommendation = HeroUI.label("", 34)
	_recommendation.name = "RegionSummary"
	content.add_child(_recommendation)
	content.add_child(HeroUI.label("Duration"))
	_duration = OptionButton.new()
	_duration.name = "DurationOptions"
	_duration.custom_minimum_size.y = 96
	_duration.mouse_filter = Control.MOUSE_FILTER_PASS
	_duration.get_popup().add_theme_constant_override("v_separation", 64)
	content.add_child(_duration)
	_duration.item_selected.connect(func(_index: int) -> void: _refresh())
	_feedback = HeroUI.label("")
	_feedback.name = "FeedbackLabel"
	content.add_child(_feedback)
	_start = HeroUI.button("Start Expedition")
	_start.name = "StartButton"
	_start.pressed.connect(_dispatch)
	content.add_child(_start)
	var cancel := HeroUI.button("Cancel · Home")
	cancel.name = "CancelButton"
	cancel.pressed.connect(cancel_draft)
	content.add_child(cancel)
	ExpeditionManager.changed.connect(_refresh)
	ExpeditionManager.operation_failed.connect(_show_operation_error)
	_update_durations()
	_refresh()


func _select_region(region: RegionResource) -> void:
	if _leaving or not is_inside_tree():
		return
	if _region != region:
		_region = region
		_update_durations()
	_refresh()


func _update_durations() -> void:
	_duration.clear()
	for seconds in _region.duration_options_seconds:
		_duration.add_item("%d seconds" % seconds)
		_duration.set_item_metadata(_duration.item_count - 1, seconds)
	if _duration.item_count > 0:
		_duration.select(0)


func _seconds() -> int:
	if _duration.selected < 0 or _duration.selected >= _duration.item_count:
		return 0
	var value: Variant = _duration.get_item_metadata(_duration.selected)
	return int(value) if ExpeditionCatalog.integer(value, 1) else 0


func _refresh() -> void:
	if _leaving or not is_inside_tree():
		return
	_gold.text = "Held gold: %d" % GameState.gold
	for region in ExpeditionCatalog.regions():
		var unlocked := CompanyProgression.is_unlocked(region, GameState.unlocked_regions)
		var choice: Button = _region_buttons[region.region_id]
		choice.text = "%s\n%s%s" % [
			region.display_name, "Selected · " if region == _region else "",
			"Unlocked" if unlocked else "Locked"]
		choice.set_pressed_no_signal(region == _region)
		var requirement: Label = _requirements[region.region_id]
		requirement.text = CompanyProgression.requirement_text(region)
		var capacity := int(ExpeditionManager.balancing.region_roster_capacities.get(region.region_id, 0))
		if capacity > 0:
			requirement.text += " · Roster cap: %d" % capacity
		if not unlocked and region.unlock_condition.get("kind") == "gold":
			var threshold := int(region.unlock_condition.value)
			requirement.text += "\nHeld gold: %d / %d" % [GameState.gold, threshold]
	_recommendation.text = "%s\nRecommended Party Power: %d (advisory only)" % [
		_region.display_name, _region.recommended_party_power]
	var error := ExpeditionManager.start_error(_region, _party, _seconds())
	_start.disabled = not error.is_empty()
	HeroUI.show_feedback(_feedback, error)


func _show_operation_error() -> void:
	_refresh()
	if not _leaving and is_inside_tree():
		HeroUI.show_feedback(_feedback, ExpeditionManager.last_error)


func _dispatch() -> void:
	if _leaving or not is_inside_tree():
		return
	ExpeditionManager.start_expedition(_region, _party, _seconds())
	if ExpeditionManager.last_committed:
		_leaving = true
		UIManager.show_screen(HOME_SCREEN)
	else:
		_refresh()
		HeroUI.show_feedback(_feedback, ExpeditionManager.last_error)


func cancel_draft() -> void:
	if not _leaving and is_inside_tree():
		_leaving = true
		UIManager.show_screen(HOME_SCREEN)
