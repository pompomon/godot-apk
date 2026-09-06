extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
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


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	_auto_accept_quit = get_tree().auto_accept_quit
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
