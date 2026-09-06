extends Control

const HeroUI = preload("res://scenes/ui/hero_ui.gd")
const HOME_SCREEN := "res://scenes/ui/home/home_screen.tscn"
var _party: PartyData
var _region: RegionResource
var _duration: OptionButton
var _start: Button
var _feedback: Label
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
	content.add_child(HeroUI.label("%s\nRecommended Party Power: %d (advisory only)" % [
		_region.display_name, _region.recommended_party_power], 34))
	content.add_child(HeroUI.label("Duration"))
	_duration = OptionButton.new()
	_duration.name = "DurationOptions"
	_duration.custom_minimum_size.y = 96
	for seconds in _region.duration_options_seconds:
		_duration.add_item("%d seconds" % seconds)
		_duration.set_item_metadata(_duration.item_count - 1, seconds)
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
	_refresh()


func _seconds() -> int:
	if _duration.selected < 0 or _duration.selected >= _duration.item_count:
		return 0
	var value: Variant = _duration.get_item_metadata(_duration.selected)
	return int(value) if ExpeditionCatalog.integer(value, 1) else 0


func _refresh() -> void:
	if _leaving or not is_inside_tree():
		return
	var error := ExpeditionManager.start_error(_region, _party, _seconds())
	_start.disabled = not error.is_empty()
	HeroUI.show_feedback(_feedback, error)


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
