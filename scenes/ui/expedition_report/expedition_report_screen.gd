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
	# The ORIGINAL planned count/time is shown while running; only once the terminal
	# step is revealed do we admit the run ended early with no time remaining.
	var terminal_revealed := _report.terminal_step_index != -1 and _report.last_revealed_index == _report.terminal_step_index
	if terminal_revealed:
		_status.text = "%s · Ended early\nStep %d / %d revealed · 0 seconds remaining\nGold credited: %d" % [
			_report.region_name, _report.last_revealed_index + 1, _report.candidate_step_count, _report.credited_gold()]
	else:
		_status.text = "%s · %s\nStep %d / %d · %d seconds remaining\nGold credited: %d" % [
			_report.region_name, "Running" if _report.status == ExpeditionData.Status.RUNNING else "Completed",
			_report.last_revealed_index + 1, _report.candidate_step_count,
			maxi(0, _report.duration_seconds - _report.credited_elapsed_seconds), _report.credited_gold()]
	if _shown_cursor != _report.last_revealed_index:
		HeroUI.clear_children(_journal)
		_shown_cursor = _report.last_revealed_index
		if _shown_cursor == -1:
			_journal.add_child(HeroUI.label("The Party has departed. The journal will appear as steps are revealed."))
		var names := _hero_names()
		var steps := _report.steps
		for index in range(_shown_cursor + 1):
			_journal.add_child(HeroUI.label(_journal_entry(index, steps[index], names)))
	HeroUI.show_feedback(_feedback, ExpeditionManager.last_error)


## Stable Hero ID -> display name from the frozen snapshot, so combat injuries can
## be shown without touching live roster resources.
func _hero_names() -> Dictionary:
	var names := {}
	for member in _report.party_snapshot.slots.values():
		if member != null:
			names[member.hero_id] = member.hero_name
	return names


func _journal_entry(index: int, step: ExpeditionStep, names: Dictionary) -> String:
	if step.kind != ExpeditionStep.StepKind.COMBAT:
		return "%d. %s\n%s\nGold: +%d" % [index + 1, step.title, step.journal_text, int(step.result.gold)]
	var result := step.result
	var lines: Array = ["%d. %s — %s" % [index + 1, step.title, String(result.outcome).capitalize()], step.journal_text]
	for round_entry in result.rounds:
		lines.append("Round %d:" % int(round_entry.round_number))
		for action in round_entry.actions:
			lines.append("  " + _action_line(action))
	var injuries: Array = []
	for hero_id in result.final_hero_states:
		if int(result.final_hero_states[hero_id].hp) == 0:
			injuries.append(String(names.get(hero_id, hero_id)))
	lines.append("Injuries: %s" % ("none" if injuries.is_empty() else ", ".join(injuries) + " down"))
	return "\n".join(lines)


func _action_line(action: Dictionary) -> String:
	var actor: String = action.actor_name
	var target: String = action.target_name
	var name: String = action.action_name
	match String(action.action_kind):
		"Guard":
			return "%s uses %s, bracing for the next blow." % [actor, name]
		"Heal":
			return "%s uses %s on %s, healing %d HP. (%s now %d HP)" % [
				actor, name, target, int(action.amount), target, int(action.result_hp)]
	if bool(action.was_miss):
		return "%s's %s misses %s." % [actor, name, target]
	var crit: String = " (critical!)" if bool(action.was_crit) else ""
	return "%s's %s hits %s for %d damage%s. (%s now %d HP)" % [
		actor, name, target, int(action.amount), crit, target, int(action.result_hp)]


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
