extends Control

const HeroUI = preload("res://scenes/ui/hero_ui.gd")
const HOME_SCREEN := "res://scenes/ui/home/home_screen.tscn"
var _report: ExpeditionData
var _status: Label
var _feedback: Label
var _journal: VBoxContainer
var _acknowledge: Button
var _shown_cursor: int = -2
var _leaving: bool = false
var _backdrop: TextureRect
var _party_art: HBoxContainer
var _scroll: ScrollContainer
var _scroll_anchor: Control
var _anchor_y: float
var _restoring_scroll: bool = false


func _ready() -> void:
	HeroUI.apply_theme(self)
	_report = ExpeditionManager.get_active_expedition()
	var content := HeroUI.scrollable_content(self)
	_scroll = content.get_parent() as ScrollContainer
	content.add_child(HeroUI.label("Expedition Report", 44))
	_backdrop = HeroUI.region_banner(_report.region_id if _report != null else "")
	content.add_child(_backdrop)
	_status = HeroUI.label("")
	_status.name = "StatusLabel"
	content.add_child(_status)
	_feedback = HeroUI.label("")
	_feedback.name = "FeedbackLabel"
	content.add_child(_feedback)
	var retry := HeroUI.button("Check progress / Retry")
	retry.name = "RetryButton"
	retry.pressed.connect(_retry)
	content.add_child(retry)
	_acknowledge = HeroUI.button("Acknowledge completed report")
	_acknowledge.name = "AcknowledgeButton"
	_acknowledge.pressed.connect(_acknowledge_report)
	content.add_child(_acknowledge)
	var home := HeroUI.button("Home · Keep report")
	home.name = "HomeButton"
	home.pressed.connect(cancel_draft)
	content.add_child(home)
	_party_art = HBoxContainer.new()
	_party_art.name = "DispatchedPartyArt"
	_party_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_party_art)
	if _report != null:
		for member in _report.party_snapshot.slots.values():
			if member == null:
				continue
			var portrait := HeroUI.artwork(
				HeroUI.Art.portrait(member.hero_id, member.class_id), Vector2(64, 64))
			portrait.set_meta("hero_id", member.hero_id)
			portrait.tooltip_text = "%s · %s (at dispatch)" % [member.hero_name, member.class_name]
			_party_art.add_child(portrait)
	_journal = VBoxContainer.new()
	_journal.name = "Journal"
	content.add_child(_journal)
	ExpeditionManager.changed.connect(_refresh)
	ExpeditionManager.operation_failed.connect(_refresh)
	ExpeditionManager.reveal_progress()
	_refresh()


func _refresh() -> void:
	if _leaving or not is_inside_tree():
		return
	var available := _report != null and _report == ExpeditionManager.get_active_expedition()
	if available and _shown_cursor != _report.last_revealed_index:
		_remember_reading_position()
	_acknowledge.visible = available and _report.status == ExpeditionData.Status.COMPLETED
	_backdrop.visible = available
	_party_art.visible = available
	if not available:
		_status.text = "No report is available. Return Home."
		HeroUI.clear_children(_journal)
		_shown_cursor = -2
		_scroll_anchor = null
		HeroUI.show_feedback(_feedback, ExpeditionManager.last_error)
		return
	if UIManager.is_current_screen(self):
		ExpeditionManager.mark_report_viewed()
	_status.text = "%s · %s\nStep %d / %d · %d seconds remaining\nGold credited: %d" % [
		_report.region_name, "Running" if _report.status == ExpeditionData.Status.RUNNING else "Completed",
		_report.last_revealed_index + 1, _report.display_step_count(),
		_report.seconds_remaining(), _report.credited_gold()]
	if _report.status == ExpeditionData.Status.COMPLETED:
		_status.text += "\nXP credited: +%d per participating Hero" % _report.xp_award
	if _shown_cursor != _report.last_revealed_index:
		if _shown_cursor < 0 or _report.last_revealed_index < _shown_cursor:
			HeroUI.clear_children(_journal)
			_shown_cursor = -1
		if _report.last_revealed_index == -1:
			_journal.add_child(HeroUI.label("The Party has departed. The journal will appear as steps are revealed."))
		var steps := _report.steps
		for index in range(_shown_cursor + 1, _report.last_revealed_index + 1):
			var entry := _journal_entry(steps[index], index)
			_journal.add_child(entry)
			_journal.move_child(entry, 0)
		_shown_cursor = _report.last_revealed_index
	HeroUI.show_feedback(_feedback, ExpeditionManager.last_error)


func _journal_entry(step: ExpeditionStep, index: int) -> HBoxContainer:
	var text := "%d. %s\n%s\nGold: +%d" % [
		index + 1, step.title, step.journal_text, int(step.result.gold)]
	if step.kind == ExpeditionStep.StepKind.COMBAT:
		text += "\n" + _combat_text(step.result)
	for id in step.result.get("item_ids", []):
		var item := ItemCatalog.item_by_id(id)
		text += "\nItem: %s" % (item.display_name if item != null else id)
	var entry := HBoxContainer.new()
	entry.name = "Step%d" % index
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icons := VBoxContainer.new()
	icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(icons)
	var kind_icon := HeroUI.artwork(HeroUI.Art.journal_icon(step.kind))
	kind_icon.name = "StepKindIcon"
	icons.add_child(kind_icon)
	if step.kind == ExpeditionStep.StepKind.COMBAT:
		var outcome_icon := HeroUI.artwork(HeroUI.Art.outcome_icon(step.result.outcome))
		outcome_icon.name = "OutcomeIcon"
		icons.add_child(outcome_icon)
	for id in step.result.get("item_ids", []):
		icons.add_child(HeroUI.artwork(HeroUI.Art.item_icon(id), Vector2(64, 64)))
	entry.add_child(HeroUI.label(text))
	return entry


func _remember_reading_position() -> void:
	if _restoring_scroll or _shown_cursor < 0 or _journal.get_child_count() == 0:
		return
	var top := _scroll.get_global_rect().position.y
	var first: Control = _journal.get_child(0)
	if first.get_global_rect().position.y >= top - 2.0:
		if first.get_global_rect().position.y >= _scroll.get_global_rect().end.y:
			return
		_scroll_anchor = _journal
	else:
		for entry in _journal.get_children():
			if entry.get_global_rect().end.y > top:
				_scroll_anchor = entry
				break
	if _scroll_anchor != null:
		_anchor_y = _content_y(_scroll_anchor)
		_restoring_scroll = true
		_restore_reading_position()


func _content_y(control: Control) -> float:
	return _journal.position.y + (0.0 if control == _journal else control.position.y)


func _restore_reading_position() -> void:
	# Wait for wrapped labels and their parent containers to settle.
	await get_tree().process_frame
	await get_tree().process_frame
	if not _leaving and is_inside_tree() and is_instance_valid(_scroll_anchor):
		# Content coordinates preserve any touch scrolling during the layout update.
		_scroll.scroll_vertical += roundi(_content_y(_scroll_anchor) - _anchor_y)
	_scroll_anchor = null
	_restoring_scroll = false


func _combat_text(result: Dictionary) -> String:
	var lines := PackedStringArray(["Outcome: %s" % String(result.outcome).capitalize()])
	for round_entry in result.rounds:
		lines.append("Round %d" % int(round_entry.round_number))
		for action in round_entry.actions:
			var effect := "Miss"
			if action.hit:
				match action.effect:
					"Guard":
						effect = "Guard active"
					"Heal":
						effect = "Healing power: %d HP" % int(action.damage_or_heal)
					_:
						effect = "%d damage%s" % [
							int(action.damage_or_heal), " (critical)" if action.was_crit else ""]
			lines.append("%s · %s → %s: %s" % [
				action.actor_name, action.action_name, action.target_name, effect])
	return "\n".join(lines)


func _retry() -> void:
	if _leaving or not is_inside_tree():
		return
	ExpeditionManager.reveal_progress()
	_refresh()


func _acknowledge_report() -> void:
	if _leaving or not is_inside_tree():
		return
	ExpeditionManager.acknowledge_report(_report)
	if ExpeditionManager.last_committed:
		_leaving = true
		UIManager.show_screen(HOME_SCREEN)
	else:
		_refresh()


func cancel_draft() -> void:
	if not _leaving and is_inside_tree():
		_leaving = true
		UIManager.show_screen(HOME_SCREEN)
