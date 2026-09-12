extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
const Art = preload("res://scenes/ui/art_catalog.gd")
const HOME := "res://scenes/ui/home/home_screen.tscn"
const REGION := "res://scenes/ui/region_select/region_select_screen.tscn"
const REPORT := "res://scenes/ui/expedition_report/expedition_report_screen.tscn"
const ROSTER := "res://scenes/ui/roster/roster_screen.tscn"
const DETAIL := "res://scenes/ui/hero_detail/hero_detail_screen.tscn"
const FORMATION := "res://scenes/ui/party_formation/party_formation_screen.tscn"
var _isolation: RefCounted
var _main: Control
var _root: Control
var _time: int = 1000
var _auto_accept_quit: bool
var _pool: Array[EncounterEntryResource]
var _enemy_states: Array[Dictionary]
var _enemy_name: String
var _terminal_retreat: bool
var _travel_text: String
var _emulate_touch: bool


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	var region := ExpeditionCatalog.GREEN_HOLLOW
	_pool = region.encounter_pool.duplicate()
	_terminal_retreat = region.retreat_ends_expedition
	_travel_text = region.travel_text
	region.encounter_pool.assign(_pool.filter(
		func(entry: EncounterEntryResource) -> bool: return entry.kind != "Combat"))
	var enemies := CombatCatalog.BANDIT_SKIRMISHERS
	_enemy_states = enemies.enemies.duplicate(true)
	_enemy_name = enemies.display_name
	_auto_accept_quit = get_tree().auto_accept_quit
	_emulate_touch = Input.emulate_touch_from_mouse
	_time = 1000
	ExpeditionManager.clock = func() -> int: return _time
	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	_root = _main.get_node("ScreenRoot")
	await get_tree().process_frame
	assert_true(SaveManager.last_success, SaveManager.last_error)


func after_each() -> void:
	_main.free()
	await get_tree().process_frame
	get_tree().auto_accept_quit = _auto_accept_quit
	Input.emulate_touch_from_mouse = _emulate_touch
	var region := ExpeditionCatalog.GREEN_HOLLOW
	region.encounter_pool.assign(_pool)
	region.retreat_ends_expedition = _terminal_retreat
	region.travel_text = _travel_text
	var enemies := CombatCatalog.BANDIT_SKIRMISHERS
	enemies.enemies.assign(_enemy_states)
	enemies.display_name = _enemy_name
	_isolation.finish()


func _screen() -> Control:
	return _root.get_child(0)


func _node(node_name: String) -> Node:
	return _screen().find_child(node_name, true, false)


func _go(path: String, context: Dictionary = {}) -> void:
	UIManager.show_screen(path, context)
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, path)


func _confirm() -> void:
	var party := PartyData.new()
	party.place_hero(3, GameState.roster[0])
	assert_true(PartyFormationService.confirm(party, ExpeditionManager.balancing))


func _dispatch() -> void:
	_confirm()
	await _go(REGION)
	_node("StartButton").pressed.emit()
	await get_tree().process_frame
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(_screen().scene_file_path, HOME)


func _dispatch_automated(run_count: int) -> void:
	_confirm()
	await _go(REGION)
	var options := _node("RunCountOptions") as OptionButton
	options.select(run_count - 1)
	options.item_selected.emit(run_count - 1)
	assert_eq(options.get_item_metadata(options.selected), run_count)
	assert_eq(_node("StartButton").text, "Start Automated Series")
	_node("StartButton").pressed.emit()
	await get_tree().process_frame
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(_screen().scene_file_path, HOME)


func _visible_text(node: Node) -> String:
	var result := ""
	if node is Control and not node.is_visible_in_tree():
		return result
	if node is Label or node is Button:
		result += node.text + "\n"
	for child in node.get_children():
		result += _visible_text(child)
	return result


func test_region_summary_duration_errors_cancel_and_android_back_preserve_party() -> void:
	assert_true(_node("ExpeditionButton").disabled)
	await _go(REGION)
	assert_true(_node("StartButton").disabled)
	assert_string_contains(_node("FeedbackLabel").text, "confirmed Party")
	_confirm()
	await _go(REGION)
	var party := GameState.current_party
	var saved := SaveManager.capture_state()
	assert_string_contains(_node("PartySummary").text, "1 / 4")
	assert_string_contains(_node("PartySummary").text, "Back right")
	assert_string_contains(_visible_text(_screen()), "advisory only")
	assert_eq(_node("DurationOptions").item_count, 1)
	assert_eq(_node("DurationOptions").get_item_metadata(0), 60)
	assert_false(_node("StartButton").disabled)
	_node("CancelButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)
	assert_same(GameState.current_party, party)
	await _go(REGION)
	_main.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)
	assert_eq(SaveManager.capture_state(), saved)
	assert_same(GameState.current_party, party)


func test_multiple_durations_invalid_selection_stale_party_and_start_save_retry() -> void:
	_confirm()
	var region := ExpeditionCatalog.GREEN_HOLLOW
	var durations := region.duration_options_seconds.duplicate()
	region.duration_options_seconds.assign([60, 120])
	await _go(REGION)
	assert_eq(_node("DurationOptions").item_count, 2)
	_node("DurationOptions").select(1)
	_node("DurationOptions").item_selected.emit(1)
	assert_false(_node("StartButton").disabled)
	_node("DurationOptions").set_item_metadata(1, "bad")
	_node("StartButton").pressed.emit()
	assert_false(ExpeditionManager.last_committed)
	assert_true(_node("FeedbackLabel").visible)
	_node("DurationOptions").set_item_metadata(1, 120)
	var before := SaveManager.capture_state()
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "before_primary_replace"
	_node("StartButton").pressed.emit()
	assert_false(ExpeditionManager.last_committed)
	assert_eq(SaveManager.capture_state(), before)
	assert_string_contains(_node("FeedbackLabel").text, "not saved")
	assert_false(_node("StartButton").disabled)
	SaveManager.fault_injector = Callable()
	assert_true(PartyFormationService.disband())
	_confirm()
	_node("StartButton").pressed.emit()
	assert_false(ExpeditionManager.last_committed, "Old screen cannot dispatch a newly confirmed Party.")
	await _go(REGION)
	_node("DurationOptions").select(1)
	_node("StartButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)
	assert_eq(ExpeditionManager.get_active_expedition().duration_seconds, 120)
	region.duration_options_seconds.assign(durations)


func test_automated_series_selection_stop_retry_and_report_acknowledgment() -> void:
	await _dispatch_automated(3)
	assert_string_contains(_node("AutomationLabel").text, "0 / 3 completed")
	assert_string_contains(_node("AutomationLabel").text, "Current run 1")
	assert_true(_node("StopAutomationButton").visible)
	SaveManager.fault_injector = func(stage: String) -> bool:
		return stage == "before_primary_replace"
	_node("StopAutomationButton").pressed.emit()
	assert_true(bool(ExpeditionManager.get_automation_state().enabled))
	assert_string_contains(_node("FeedbackLabel").text, "not saved")
	assert_true(_node("StopAutomationButton").visible)
	SaveManager.fault_injector = Callable()
	_node("StopAutomationButton").pressed.emit()
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_false(bool(ExpeditionManager.get_automation_state().enabled))
	assert_string_contains(_node("AutomationLabel").text, "Stopping after this run")
	_time = 1060
	ExpeditionManager.observe_foreground()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, REPORT)
	assert_string_contains(_node("SeriesStatusLabel").text, "1 / 3 completed")
	assert_string_contains(_node("SeriesStatusLabel").text, "Stopped by the player")
	assert_true(_node("AcknowledgeButton").visible)
	_node("AcknowledgeButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)
	assert_true(ExpeditionManager.get_automation_state().is_empty())


func test_automated_report_switches_to_successor_and_retains_compact_history() -> void:
	await _dispatch_automated(2)
	var first := ExpeditionManager.get_active_expedition()
	_node("ExpeditionButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, REPORT)
	_time = 1060
	ExpeditionManager.observe_foreground()
	var second := ExpeditionManager.get_active_expedition()
	assert_ne(second, first)
	assert_eq(second.start_timestamp, first.effective_end_timestamp)
	assert_eq(int(ExpeditionManager.get_automation_state().completed_runs), 1)
	assert_string_contains(_node("SeriesStatusLabel").text, "Run 1")
	assert_eq(_node("Journal").get_child_count(), 1)
	assert_string_contains(_visible_text(_node("Journal")), "departed")
	_time = 1120
	ExpeditionManager.observe_foreground()
	assert_false(ExpeditionManager.is_expedition_active())
	assert_eq(int(ExpeditionManager.get_automation_state().completed_runs), 2)
	assert_string_contains(_node("SeriesStatusLabel").text, "2 / 2 completed")
	assert_string_contains(_node("SeriesStatusLabel").text, "Run 2")
	assert_string_contains(_node("SeriesStatusLabel").text, "Completed all requested")
	assert_true(_node("AcknowledgeButton").visible)
	_node("HomeButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)
	var terminal_status: String = _node("AutomationLabel").text
	assert_string_contains(terminal_status, "Last completed run 2")
	assert_false(terminal_status.contains("Current run"))


func test_running_and_partial_report_never_disclose_unrevealed_results() -> void:
	await _dispatch()
	assert_false(_node("FormationButton").visible)
	assert_string_contains(_node("ExpeditionLabel").text, "Step 0 / 10")
	assert_string_contains(_node("ExpeditionLabel").text, "60 seconds remaining")
	_node("ExpeditionButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, REPORT)
	assert_false(_node("AcknowledgeButton").visible)
	var run := ExpeditionManager.get_active_expedition()
	for step in run.steps:
		assert_false(_visible_text(_node("Journal")).contains(step.journal_text))
	assert_string_contains(_node("StatusLabel").text, "Gold credited: 0")
	_time = 1012
	ExpeditionManager.observe_foreground()
	assert_eq(_node("Journal").get_child_count(), 2)
	assert_string_contains(_visible_text(_node("Journal")), run.steps[1].journal_text)
	for index in [3, 5, 7, 9]:
		if run.steps[index].title != run.steps[1].title:
			assert_false(_visible_text(_node("Journal")).contains(run.steps[index].title))
	var journal_row := _node("Journal").get_child(0)
	_time = 1013
	ExpeditionManager.observe_foreground()
	assert_same(_node("Journal").get_child(0), journal_row, "Clock-only ticks preserve journal layout.")
	_main.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)
	assert_same(ExpeditionManager.get_active_expedition(), run)


func test_report_prepends_single_steps_and_catchup_batches_without_mutating_saved_order() -> void:
	await _dispatch()
	var run := ExpeditionManager.get_active_expedition()
	var frozen_steps: Array = run.serialize().steps
	await _go(REPORT)
	assert_string_contains(_visible_text(_node("Journal")), "departed")
	_time = 1012
	ExpeditionManager.observe_foreground()
	_assert_journal_order(2)
	var oldest := _node("Journal").get_child(1)
	_time = 1018
	ExpeditionManager.observe_foreground()
	_assert_journal_order(3)
	assert_same(_node("Journal").get_child(2), oldest)
	_time = 1048
	ExpeditionManager.observe_foreground()
	_assert_journal_order(8)
	assert_same(_node("Journal").get_child(7), oldest)
	var shown := _node("Journal").get_children()
	ExpeditionManager.observe_foreground()
	assert_eq(_node("Journal").get_children(), shown)
	assert_null(_node("Step8"))
	var saved := run.serialize()
	await _go(HOME)
	await _go(REPORT)
	_assert_journal_order(8)
	assert_eq(run.serialize(), saved)
	SaveManager.load_or_create()
	await _go(REPORT)
	_assert_journal_order(8)
	_time = 1060
	ExpeditionManager.observe_foreground()
	_assert_journal_order(10)
	assert_true(_node("AcknowledgeButton").visible)
	assert_eq(ExpeditionManager.get_active_expedition().serialize().steps, frozen_steps)
	SaveManager.load_or_create()
	await _go(REPORT)
	_assert_journal_order(10)


func _assert_journal_order(count: int) -> void:
	var journal := _node("Journal")
	assert_eq(journal.get_child_count(), count)
	for index in count:
		var step_index := count - index - 1
		assert_eq(journal.get_child(index).name, StringName("Step%d" % step_index))
		assert_true(_visible_text(journal.get_child(index)).begins_with("%d. " % (step_index + 1)))


func _settle_report_layout() -> void:
	for frame in 4:
		await get_tree().process_frame


func _open_long_report() -> void:
	var region := ExpeditionCatalog.GREEN_HOLLOW
	region.travel_text = _travel_text.repeat(12)
	await _dispatch()
	await _go(REPORT)
	_time = 1024
	ExpeditionManager.observe_foreground()
	await _settle_report_layout()


func test_prepending_preserves_older_reading_position_through_batches_retry_and_completion() -> void:
	await _open_long_report()
	var scroll := _node("Scroll") as ScrollContainer
	var journal := _node("Journal") as VBoxContainer
	var anchor := journal.get_child(1) as Control
	scroll.scroll_vertical = int(journal.position.y + anchor.position.y + 40)
	await _settle_report_layout()
	assert_lt(journal.get_child(0).get_global_rect().end.y, scroll.get_global_rect().position.y)
	var anchor_y := anchor.get_global_rect().position.y
	_time = 1036
	ExpeditionManager.observe_foreground()
	_time = 1048
	ExpeditionManager.observe_foreground()
	scroll.scroll_vertical += 20
	anchor_y -= 20.0
	await _settle_report_layout()
	_assert_journal_order(8)
	assert_same(_node("Step2"), anchor)
	assert_almost_eq(anchor.get_global_rect().position.y, anchor_y, 1.0)
	var scroll_position := scroll.scroll_vertical
	_time = 1049
	ExpeditionManager.observe_foreground()
	await _settle_report_layout()
	assert_eq(scroll.scroll_vertical, scroll_position, "Clock-only updates do not move the reader.")
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "before_primary_replace"
	_time = 1054
	ExpeditionManager.observe_foreground()
	await _settle_report_layout()
	_assert_journal_order(8)
	assert_null(_node("Step8"))
	anchor_y = anchor.get_global_rect().position.y
	SaveManager.fault_injector = Callable()
	_node("RetryButton").pressed.emit()
	await _settle_report_layout()
	_assert_journal_order(9)
	assert_almost_eq(anchor.get_global_rect().position.y, anchor_y, 1.0)
	_time = 1060
	ExpeditionManager.observe_foreground()
	await _settle_report_layout()
	_assert_journal_order(10)
	assert_almost_eq(anchor.get_global_rect().position.y, anchor_y, 1.0,
		"Completion's status and acknowledgment controls must not displace the reader.")


func test_reader_at_journal_start_sees_latest_entry_and_navigation_cancels_pending_restore() -> void:
	await _open_long_report()
	var scroll := _node("Scroll") as ScrollContainer
	var journal := _node("Journal") as VBoxContainer
	scroll.scroll_vertical = int(journal.position.y)
	await _settle_report_layout()
	var start_y := journal.get_global_rect().position.y
	_time = 1036
	ExpeditionManager.observe_foreground()
	await _settle_report_layout()
	_assert_journal_order(6)
	assert_almost_eq(journal.get_child(0).get_global_rect().position.y, start_y, 1.0)
	_time = 1048
	ExpeditionManager.observe_foreground()
	_node("HomeButton").pressed.emit()
	await _settle_report_layout()
	assert_eq(_screen().scene_file_path, HOME)


func test_reveals_wait_for_held_swipes_and_inertia_without_cancelling_the_gesture() -> void:
	Input.emulate_touch_from_mouse = true
	var viewport: SubViewport = add_child_autofree(SubViewport.new())
	viewport.size = Vector2i(720, 1280)
	_main.free()
	await get_tree().process_frame
	_main = load("res://main.tscn").instantiate()
	viewport.add_child(_main)
	_root = _main.get_node("ScreenRoot")
	await get_tree().process_frame
	await _open_long_report()
	var scroll := _node("Scroll") as ScrollContainer
	var journal := _node("Journal") as VBoxContainer
	scroll.scroll_vertical = int(journal.position.y + 100)
	await _settle_report_layout()
	watch_signals(scroll)
	var position := scroll.get_global_rect().get_center()
	_report_mouse_button(viewport, position, true)
	for index in 3:
		position.y -= 40
		_report_mouse_motion(viewport, position, Vector2(0, -40))
		await get_tree().create_timer(0.02).timeout
	assert_signal_emit_count(scroll, "scroll_started", 1)
	var before := scroll.scroll_vertical
	_time = 1036
	ExpeditionManager.observe_foreground()
	await _settle_report_layout()
	_assert_journal_order(4)
	assert_eq(ExpeditionManager.get_active_expedition().last_revealed_index, 5,
		"Only presentation waits for scrolling; committed progress continues.")
	position.y -= 40
	_report_mouse_motion(viewport, position, Vector2(0, -40))
	await get_tree().create_timer(0.02).timeout
	assert_gt(scroll.scroll_vertical, before, "A held swipe still moves after a reveal.")
	assert_signal_not_emitted(scroll, "scroll_ended")
	_report_mouse_button(viewport, position, false)
	before = scroll.scroll_vertical
	_time = 1048
	ExpeditionManager.observe_foreground()
	await _settle_report_layout()
	assert_gt(scroll.scroll_vertical, before, "The release still has inertial scrolling.")
	await get_tree().create_timer(1.5).timeout
	await _settle_report_layout()
	assert_signal_emit_count(scroll, "scroll_ended", 1)
	_assert_journal_order(8)


func _report_mouse_button(viewport: Viewport, position: Vector2, pressed: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = position
	touch.pressed = pressed
	viewport.push_input(touch, true)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = position
	event.global_position = position
	event.pressed = pressed
	viewport.push_input(event, true)


func _report_mouse_motion(viewport: Viewport, position: Vector2, relative: Vector2) -> void:
	var touch := InputEventScreenDrag.new()
	touch.index = 0
	touch.position = position
	touch.relative = relative
	viewport.push_input(touch, true)
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = position
	event.global_position = position
	event.relative = relative
	viewport.push_input(event, true)


func test_newest_first_report_keeps_combat_rounds_and_actions_chronological() -> void:
	_combat_fixture("RETREAT")
	var region := ExpeditionCatalog.GREEN_HOLLOW
	region.retreat_ends_expedition = false
	ExpeditionManager.balancing.max_combat_rounds = 3
	await _dispatch()
	await _go(REPORT)
	_time = 1012
	ExpeditionManager.observe_foreground()
	_assert_journal_order(2)
	var text := _visible_text(_node("Step1"))
	var rounds: Array = ExpeditionManager.get_active_expedition().steps[1].result.rounds
	assert_eq(rounds.size(), 3)
	var offset := 0
	for round_entry in rounds:
		var round_position := text.find("Round %d\n" % int(round_entry.round_number), offset)
		assert_gte(round_position, offset)
		offset = round_position + 1
		for action in round_entry.actions:
			var action_position := text.find("%s · %s → %s:" % [
				action.actor_name, action.action_name, action.target_name], offset)
			assert_gte(action_position, offset)
			offset = action_position + 1


func test_failed_dispatch_can_retry_on_same_screen_with_canonical_party_identity() -> void:
	_confirm()
	await _go(REGION)
	var screen := _screen()
	var party := GameState.current_party
	var summary: String = _node("PartySummary").text
	var before := SaveManager.capture_state()
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "before_primary_replace"
	_node("StartButton").pressed.emit()
	assert_false(ExpeditionManager.last_committed)
	assert_same(_screen(), screen)
	assert_same(GameState.current_party, party)
	assert_eq(SaveManager.capture_state(), before)
	assert_eq(_node("PartySummary").text, summary)
	assert_false(_node("StartButton").disabled)
	SaveManager.fault_injector = Callable()
	_node("StartButton").pressed.emit()
	await get_tree().process_frame
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(_screen().scene_file_path, HOME)
	assert_null(GameState.current_party)
	assert_eq(GameState.expedition_sequence, int(before.expedition_sequence) + 1)


func test_completion_routes_once_report_survives_home_and_acknowledgment_retries() -> void:
	await _dispatch()
	_time = 1060
	ExpeditionManager.observe_foreground()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, REPORT)
	assert_string_contains(_node("StatusLabel").text, "Completed")
	assert_eq(_node("Journal").get_child_count(), 10)
	assert_true(_node("AcknowledgeButton").visible)
	var report := ExpeditionManager.get_active_expedition()
	_node("HomeButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)
	assert_true(_node("FormationButton").visible)
	await _go(HOME)
	assert_eq(_screen().scene_file_path, HOME, "Returning Home does not force report repeatedly.")
	_node("FormationButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, FORMATION)
	_main.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)
	await _go(REPORT)
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "after_temp_validation"
	_node("AcknowledgeButton").pressed.emit()
	assert_same(ExpeditionManager.get_active_expedition(), report)
	assert_true(_node("AcknowledgeButton").visible)
	assert_string_contains(_node("FeedbackLabel").text, "not saved")
	SaveManager.fault_injector = Callable()
	_node("AcknowledgeButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)
	assert_null(ExpeditionManager.get_active_expedition())
	await _go(REPORT)
	assert_string_contains(_node("StatusLabel").text, "No report")
	assert_false(_node("AcknowledgeButton").visible)


func test_foreground_timer_and_focus_resume_work_off_home_without_duplicate_writes() -> void:
	await _dispatch()
	await _go(ROSTER)
	var row := _node("RosterList").get_child(0)
	var writes := [0]
	SaveManager.fault_injector = func(stage: String) -> bool:
		if stage == "before_temp_write":
			writes[0] += 1
		return false
	_time = 1012
	ExpeditionManager._timer.timeout.emit()
	assert_eq(ExpeditionManager.get_active_expedition().last_revealed_index, 1)
	assert_eq(writes[0], 1)
	assert_same(_node("RosterList").get_child(0), row)
	assert_string_contains(_node("GoldLabel").text, str(GameState.gold))
	ExpeditionManager.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_time = 1024
	ExpeditionManager._timer.timeout.emit()
	assert_eq(writes[0], 1, "No background polling saves.")
	ExpeditionManager.notification(NOTIFICATION_APPLICATION_RESUMED)
	ExpeditionManager.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_eq(writes[0], 2, "Duplicate same-time resume/focus writes are suppressed.")
	assert_eq(ExpeditionManager.get_active_expedition().last_revealed_index, 3)
	var id := GameState.roster[0].hero_id
	await _go(DETAIL, {"hero_id": id})
	var stats := _node("AttributesAndStats").get_child(0)
	_time = 1060
	ExpeditionManager._timer.timeout.emit()
	assert_false(ExpeditionManager.is_expedition_active())
	assert_string_contains(_node("HeroSummaryLabel").text, "Idle")
	assert_same(_node("AttributesAndStats").get_child(0), stats)
	assert_eq(_screen().scene_file_path, DETAIL)
	UIManager.show_screen(HOME)
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, REPORT, "Completion discovered off Home routes on Home entry.")


func test_progress_save_error_stays_retryable_without_future_journal_and_stale_report_safe() -> void:
	await _dispatch()
	await _go(REPORT)
	var run := ExpeditionManager.get_active_expedition()
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "before_temp_write"
	_time = 1012
	ExpeditionManager.observe_foreground()
	assert_eq(run.last_revealed_index, -1)
	assert_string_contains(_node("FeedbackLabel").text, "not saved")
	assert_false(_visible_text(_node("Journal")).contains(run.steps[1].journal_text))
	SaveManager.fault_injector = Callable()
	_node("RetryButton").pressed.emit()
	assert_eq(run.last_revealed_index, 1)
	assert_string_contains(_visible_text(_node("Journal")), run.steps[1].journal_text)
	SaveManager.load_or_create()
	_screen().call("_refresh")
	assert_string_contains(_node("StatusLabel").text, "No report")
	_screen().call("_acknowledge_report")
	assert_false(ExpeditionManager.last_committed)
	assert_not_null(ExpeditionManager.get_active_expedition())


func test_outgoing_home_cannot_redirect_or_consume_completion_route() -> void:
	await _dispatch()
	var home := _screen()
	home.tree_exiting.connect(func() -> void:
		_time = 1060
		ExpeditionManager.reveal_progress(), CONNECT_ONE_SHOT)
	await _go(ROSTER)
	assert_false(ExpeditionManager.is_expedition_active())
	UIManager.show_screen(HOME)
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, REPORT, "Only a current rooted Home consumes completion routing.")


func test_recovery_feedback_remains_visible_after_boot_catchup_and_foreground_tick() -> void:
	await _dispatch()
	SaveManager.save()
	assert_eq(DirAccess.remove_absolute(SaveManager.get_save_path()), OK)
	_time = 1012
	SaveManager.load_or_create()
	assert_string_contains(_node("FeedbackLabel").text, "Recovered")
	assert_eq(ExpeditionManager.get_active_expedition().last_revealed_index, 1)
	_time = 1013
	ExpeditionManager.observe_foreground()
	assert_string_contains(_node("FeedbackLabel").text, "Recovered")
	assert_true(_node("FeedbackLabel").visible)
	assert_eq(_screen().scene_file_path, HOME)


func test_cancel_latches_start_and_acknowledgment_before_deferred_navigation() -> void:
	_confirm()
	await _go(REGION)
	var before := SaveManager.capture_state()
	var writes := [0]
	SaveManager.fault_injector = func(stage: String) -> bool:
		if stage == "before_temp_write":
			writes[0] += 1
		return false
	_screen().call("cancel_draft")
	_screen().call("_dispatch")
	assert_eq(SaveManager.capture_state(), before)
	assert_eq(writes[0], 0, "Cancel wins over a same-frame Start callback.")
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)
	await _go(REGION)
	_node("StartButton").pressed.emit()
	await get_tree().process_frame
	_time = 1060
	ExpeditionManager.reveal_progress()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, REPORT)
	var completed := SaveManager.capture_state()
	writes[0] = 0
	_screen().call("cancel_draft")
	_screen().call("_acknowledge_report")
	_screen().call("_retry")
	assert_eq(SaveManager.capture_state(), completed)
	assert_eq(writes[0], 0, "Keeping the report wins over same-frame acknowledgment/retry.")
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)
	assert_not_null(ExpeditionManager.get_active_expedition())


func test_successful_navigation_latches_duplicate_transaction_callbacks() -> void:
	_confirm()
	await _go(REGION)
	_screen().call("_dispatch")
	var started := SaveManager.capture_state()
	assert_true(ExpeditionManager.last_committed)
	_screen().call("_dispatch")
	_screen().call("cancel_draft")
	assert_true(ExpeditionManager.last_committed, "An outgoing duplicate cannot overwrite committed diagnostics.")
	assert_eq(SaveManager.capture_state(), started)
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)
	_time = 1060
	ExpeditionManager.reveal_progress()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, REPORT)
	_screen().call("_acknowledge_report")
	var acknowledged := SaveManager.capture_state()
	assert_true(ExpeditionManager.last_committed)
	_screen().call("_acknowledge_report")
	_screen().call("_retry")
	assert_true(ExpeditionManager.last_committed)
	assert_eq(SaveManager.capture_state(), acknowledged)
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)
	assert_null(ExpeditionManager.get_active_expedition())


func _combat_fixture(outcome: String) -> void:
	var entry := EncounterEntryResource.new()
	entry.kind = "Combat"
	entry.content_id = &"bandit_skirmishers"
	entry.weight = 1.0
	var region := ExpeditionCatalog.GREEN_HOLLOW
	region.encounter_pool.assign([entry])
	region.retreat_ends_expedition = outcome == "RETREAT"
	var enemies := CombatCatalog.BANDIT_SKIRMISHERS
	enemies.display_name = "Hidden ambush"
	enemies.enemies.assign([{
		"combatant_id": "hidden-raider", "display_name": "Hidden raider",
		"row": "Front", "basic_attack_target_rule": "FrontRowFirst",
		"derived_stats": {"MaxHP": 100000, "Attack": 10000 if outcome == "DEFEAT" else 1,
			"MagicPower": 0, "Defense": 0, "Evasion": 0.0,
			"Initiative": 10000, "CritChance": 0.0},
	}])
	ExpeditionManager.balancing = ExpeditionManager.DEFAULT_BALANCING.duplicate(true)
	ExpeditionManager.balancing.base_hit_chance = 1.0
	ExpeditionManager.balancing.min_hit_chance = 1.0
	ExpeditionManager.balancing.max_hit_chance = 1.0
	ExpeditionManager.balancing.max_crit_chance = 0.0
	ExpeditionManager.balancing.max_combat_rounds = 20 if outcome == "DEFEAT" else 1


func test_terminal_combat_is_hidden_until_committed_and_saved_log_survives_retuning() -> void:
	_combat_fixture("DEFEAT")
	await _dispatch()
	var run := ExpeditionManager.get_active_expedition()
	assert_eq(run.steps.size(), 2)
	assert_string_contains(_node("ExpeditionLabel").text, "Step 0 / 10")
	assert_string_contains(_node("ExpeditionLabel").text, "60 seconds remaining")
	_time = 1011
	ExpeditionManager.observe_foreground()
	assert_string_contains(_node("ExpeditionLabel").text, "Step 1 / 10")
	assert_string_contains(_node("ExpeditionLabel").text, "49 seconds remaining")
	await _go(REPORT)
	assert_false(_visible_text(_screen()).contains("Hidden ambush"))
	assert_false(_visible_text(_screen()).contains("Hidden raider"))
	assert_false(_visible_text(_screen()).contains("Defeat"))
	assert_null(_node("OutcomeIcon"), "Hidden outcomes must not leak through art.")
	var enemies := CombatCatalog.BANDIT_SKIRMISHERS
	enemies.display_name = "Retuned group"
	enemies.enemies.clear()
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "before_primary_replace"
	_time = 1012
	ExpeditionManager.observe_foreground()
	assert_eq(run.last_revealed_index, 0)
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.ON_EXPEDITION)
	assert_string_contains(_node("FeedbackLabel").text, "not saved")
	assert_false(_visible_text(_node("Journal")).contains("Hidden raider"))
	assert_false(_node("AcknowledgeButton").visible)
	assert_null(_node("OutcomeIcon"), "A failed save must not reveal an outcome icon.")
	SaveManager.fault_injector = Callable()
	_node("RetryButton").pressed.emit()
	assert_eq(run.status, ExpeditionData.Status.COMPLETED)
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.RESTING)
	assert_string_contains(_node("StatusLabel").text, "Step 2 / 2")
	assert_string_contains(_node("StatusLabel").text, "0 seconds remaining")
	var journal := _visible_text(_node("Journal"))
	assert_string_contains(journal, "Hidden ambush")
	assert_string_contains(journal, "Hidden raider")
	assert_string_contains(journal, "Outcome: Defeat")
	assert_string_contains(journal, "Round 1")
	assert_string_contains(journal, "damage")
	assert_same(_node("OutcomeIcon").texture, Art.outcome_icon("DEFEAT"))
	assert_false(journal.contains("Retuned group"))
	assert_true(_node("AcknowledgeButton").visible)
	var gold := GameState.gold
	SaveManager.load_or_create()
	await _go(REPORT)
	assert_eq(_visible_text(_node("Journal")), journal)
	assert_eq(GameState.gold, gold)
	_node("HomeButton").pressed.emit()
	await get_tree().process_frame
	assert_string_contains(_node("ExpeditionLabel").text, "Step 2 / 2")
	assert_string_contains(_node("ExpeditionLabel").text, "0 seconds remaining")


func test_terminal_retreat_report_shows_guard_and_releases_survivor_after_reload() -> void:
	_combat_fixture("RETREAT")
	await _dispatch()
	await _go(REPORT)
	_time = 1012
	ExpeditionManager.observe_foreground()
	assert_string_contains(_visible_text(_node("Journal")), "Outcome: Retreat")
	assert_string_contains(_visible_text(_node("Journal")), "Guard active")
	assert_string_contains(_node("StatusLabel").text, "0 seconds remaining")
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.IDLE)
	assert_eq(GameState.roster[0].recovery_ready_at, 0)
	var text := _visible_text(_node("Journal"))
	SaveManager.load_or_create()
	await _go(REPORT)
	assert_eq(_visible_text(_node("Journal")), text)


func test_combat_log_formats_overheal_as_healing_power() -> void:
	await _go(REPORT)
	var result := {
		"outcome": "VICTORY", "rounds": [{"round_number": 1, "actions": [
			{"actor_name": "Ranger", "action_name": "Aimed Shot", "target_name": "Wolf",
				"effect": "Physical", "damage_or_heal": 0, "hit": false, "was_crit": false},
			{"actor_name": "Wizard", "action_name": "Firebolt", "target_name": "Wolf",
				"effect": "Magic", "damage_or_heal": 17, "hit": true, "was_crit": true},
			{"actor_name": "Cleric", "action_name": "Mend", "target_name": "Knight",
				"effect": "Heal", "damage_or_heal": 9, "hit": true, "was_crit": false},
			{"actor_name": "Knight", "action_name": "Guard", "target_name": "Knight",
				"effect": "Guard", "damage_or_heal": 0, "hit": true, "was_crit": false},
		]}],
	}
	assert_eq(_screen().call("_combat_text", result), "\n".join([
		"Outcome: Victory", "Round 1",
		"Ranger · Aimed Shot → Wolf: Miss",
		"Wizard · Firebolt → Wolf: 17 damage (critical)",
		"Cleric · Mend → Knight: Healing power: 9 HP",
		"Knight · Guard → Knight: Guard active",
	]))


func test_recovery_refreshes_roster_detail_and_party_draft_only_after_commit() -> void:
	var first := GameState.roster[0]
	var second := GameState.roster[1]
	first.status = HeroData.HeroStatus.RESTING
	first.recovery_ready_at = 1010
	second.status = HeroData.HeroStatus.RESTING
	second.recovery_ready_at = 1020
	SaveManager.save()
	assert_true(SaveManager.last_committed)
	await _go(ROSTER)
	var row := _node("RosterList").get_child(0)
	assert_string_contains(_visible_text(row), "Resting")
	var status_icon: TextureRect = row.find_child("StatusIcon", true, false)
	assert_same(status_icon.texture, Art.status_icon(HeroData.HeroStatus.RESTING))
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "before_temp_write"
	_time = 1010
	ExpeditionManager._timer.timeout.emit()
	assert_same(status_icon.texture, Art.status_icon(HeroData.HeroStatus.RESTING))
	assert_same(_node("RosterList").get_child(0), row)
	SaveManager.fault_injector = Callable()
	ExpeditionManager._timer.timeout.emit()
	assert_same(_node("RosterList").get_child(0), row)
	assert_string_contains(_visible_text(row), "Idle")
	assert_same(row.find_child("StatusIcon", true, false), status_icon)
	assert_same(status_icon.texture, Art.status_icon(HeroData.HeroStatus.IDLE))
	await _go(DETAIL, {"hero_id": second.hero_id})
	assert_string_contains(_node("HeroSummaryLabel").text, "Resting")
	_time = 1020
	ExpeditionManager._timer.timeout.emit()
	assert_string_contains(_node("HeroSummaryLabel").text, "Idle")
	first.status = HeroData.HeroStatus.RESTING
	first.recovery_ready_at = 1030
	SaveManager.save()
	await _go(FORMATION)
	_screen().call("_place", second)
	var draft: PartyData = _screen().get("draft")
	var before := draft.slots.duplicate()
	_node("SlotGrid").get_child(1).pressed.emit()
	assert_eq(_node("ModalOptions").get_child_count(), 2)
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "before_temp_write"
	_time = 1030
	ExpeditionManager._timer.timeout.emit()
	assert_eq(first.status, HeroData.HeroStatus.RESTING)
	assert_eq(_node("ModalOptions").get_child_count(), 2)
	assert_eq(draft.slots, before)
	assert_string_contains(_node("FeedbackLabel").text, "not saved")
	SaveManager.fault_injector = Callable()
	ExpeditionManager._timer.timeout.emit()
	assert_eq(first.status, HeroData.HeroStatus.IDLE)
	assert_eq(_node("ModalOptions").get_child_count(), 3)
	assert_same(_screen().get("draft"), draft)
	assert_eq(draft.slots, before)
	assert_null(GameState.current_party, "Recovery never confirms the scene-local draft.")


func test_home_exposes_recovery_retry_without_an_expedition_or_report() -> void:
	var hero := GameState.roster[0]
	hero.status = HeroData.HeroStatus.RESTING
	hero.recovery_ready_at = 1010
	SaveManager.save()
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "before_primary_replace"
	_time = 1010
	ExpeditionManager._timer.timeout.emit()
	assert_null(ExpeditionManager.get_active_expedition())
	assert_eq(hero.status, HeroData.HeroStatus.RESTING)
	assert_true(_node("RetryProgressButton").visible)
	assert_string_contains(_node("FeedbackLabel").text, "not saved")
	SaveManager.fault_injector = Callable()
	_node("RetryProgressButton").pressed.emit()
	assert_eq(hero.status, HeroData.HeroStatus.IDLE)
	assert_eq(hero.recovery_ready_at, 0)
	assert_false(_node("RetryProgressButton").visible)
