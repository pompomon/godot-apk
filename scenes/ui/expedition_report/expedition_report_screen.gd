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


func _ready() -> void:
	HeroUI.apply_theme(self)
	_report = ExpeditionManager.get_active_expedition()
	var content := HeroUI.scrollable_content(self)
	content.add_child(HeroUI.label("Expedition Report", 44))
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
	_acknowledge.visible = available and _report.status == ExpeditionData.Status.COMPLETED
	if not available:
		_status.text = "No report is available. Return Home."
		HeroUI.clear_children(_journal)
		HeroUI.show_feedback(_feedback, ExpeditionManager.last_error)
		return
	if UIManager.is_current_screen(self):
		ExpeditionManager.mark_report_viewed()
	_status.text = "%s · %s\nStep %d / %d · %d seconds remaining\nGold credited: %d" % [
		_report.region_name, "Running" if _report.status == ExpeditionData.Status.RUNNING else "Completed",
		_report.last_revealed_index + 1, _report.display_step_count(),
		_report.seconds_remaining(), _report.credited_gold()]
	if _shown_cursor != _report.last_revealed_index:
		HeroUI.clear_children(_journal)
		_shown_cursor = _report.last_revealed_index
		if _shown_cursor == -1:
			_journal.add_child(HeroUI.label("The Party has departed. The journal will appear as steps are revealed."))
		var steps := _report.steps
		for index in range(_shown_cursor + 1):
			var step := steps[index]
			var text := "%d. %s\n%s\nGold: +%d" % [
				index + 1, step.title, step.journal_text, int(step.result.gold)]
			if step.kind == ExpeditionStep.StepKind.COMBAT:
				text += "\n" + _combat_text(step.result)
			_journal.add_child(HeroUI.label(text))
	HeroUI.show_feedback(_feedback, ExpeditionManager.last_error)


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
						effect = "Heal %d HP" % int(action.damage_or_heal)
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
