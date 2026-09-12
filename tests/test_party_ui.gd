extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
const HOME := "res://scenes/ui/home/home_screen.tscn"
const ROSTER := "res://scenes/ui/roster/roster_screen.tscn"
const DETAIL := "res://scenes/ui/hero_detail/hero_detail_screen.tscn"
const FORMATION := "res://scenes/ui/party_formation/party_formation_screen.tscn"
const BALANCING: BalancingConfig = preload("res://data/balancing/default_balancing.tres")
var _isolation: RefCounted
var _main: Control
var _root: Control
var _auto_accept_quit: bool
var _emulate_touch: bool
var _expedition_script: Script

class ActiveExpedition:
	extends "res://autoload/ExpeditionManager.gd"

	func is_expedition_active() -> bool:
		return true


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	_auto_accept_quit = get_tree().auto_accept_quit
	_emulate_touch = Input.emulate_touch_from_mouse
	_expedition_script = ExpeditionManager.get_script()


func after_each() -> void:
	if is_instance_valid(_main):
		_main.free()
	_main = null
	await get_tree().process_frame
	get_tree().auto_accept_quit = _auto_accept_quit
	Input.emulate_touch_from_mouse = _emulate_touch
	ExpeditionManager.set_script(_expedition_script)
	_isolation.finish()


func _boot(viewport: SubViewport = null) -> void:
	_main = load("res://main.tscn").instantiate()
	if viewport == null:
		add_child(_main)
	else:
		viewport.add_child(_main)
	_root = _main.get_node("ScreenRoot")
	await get_tree().process_frame
	assert_true(SaveManager.last_success, SaveManager.last_error)


func _screen() -> Control:
	return _root.get_child(0)


func _draft() -> PartyData:
	return _screen().get("draft") as PartyData


func _open_formation() -> void:
	_screen().get_node("%FormationButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, FORMATION)


func _slot(slot: int) -> Button:
	return _screen().get_node("%SlotGrid").get_child(slot) as Button


func _selector() -> Control:
	return _screen().get_node("HeroSelector") as Control


func _available_list() -> VBoxContainer:
	return _selector().find_child("ModalOptions", true, false) as VBoxContainer


func _open_picker(slot: int) -> void:
	if _selector().visible:
		_selector().call("close")
	_slot(slot).pressed.emit()
	assert_true(_selector().visible)


func _close_picker() -> void:
	if _selector().visible:
		_selector().call("close")


func _available(hero_id: String) -> Button:
	for row in _available_list().get_children():
		if row.get_meta("hero_id") == hero_id:
			return row as Button
	return null


func _place(index: int, slot: int) -> void:
	_open_picker(slot)
	var row := _available(GameState.roster[index].hero_id)
	assert_not_null(row)
	if row != null:
		row.pressed.emit()


func _confirm() -> void:
	_screen().get_node("%ConfirmButton").pressed.emit()
	await get_tree().process_frame


func _disk() -> String:
	var file := FileAccess.open(SaveManager.get_save_path(), FileAccess.READ)
	var result := file.get_as_text()
	file.close()
	return result


func test_home_draft_live_power_move_remove_and_cancel_do_not_mutate_or_save() -> void:
	await _boot()
	assert_eq(_screen().get_node("%FormationButton").text, "Form Party")
	assert_string_contains(_screen().get_node("%PartySummaryLabel").text, "No confirmed")
	var before := SaveManager.capture_state()
	var disk := _disk()
	await _open_formation()
	assert_false(_selector().visible)
	_open_picker(0)
	assert_eq(_available_list().get_child_count(), 4)
	_close_picker()
	assert_true(_screen().get_node("%ConfirmButton").disabled)
	assert_string_contains(_screen().get_node("%FeedbackLabel").text, "at least one")
	_place(0, 2)
	assert_false(_screen().get_node("%ConfirmButton").disabled)
	assert_null(_available(GameState.roster[0].hero_id))
	assert_string_contains(_screen().get_node("%PowerLabel").text,
		String.num(PartyEvaluator.compute_party_power(_draft(), BALANCING), 2))
	assert_string_contains(_screen().get_node("%PenaltyLabel").text, "×0.85")
	assert_eq(_screen().get_node("%MemberCountLabel").text, "Party: 1 / 4 Heroes")
	_screen().get_node("%MoveButton").pressed.emit()
	_slot(0).pressed.emit()
	assert_same(_draft().slots[0], GameState.roster[0])
	assert_null(_draft().slots[2])
	assert_string_contains(_screen().get_node("%PenaltyLabel").text, "no formation penalty")
	_screen().get_node("%RemoveButton").pressed.emit()
	assert_eq(_draft().heroes(), [])
	assert_true(_screen().get_node("%ConfirmButton").disabled)
	_open_picker(0)
	assert_eq(_available_list().get_child_count(), 4)
	_close_picker()
	assert_eq(SaveManager.capture_state(), before)
	assert_eq(_disk(), disk)
	_screen().get_node("%CancelButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)
	assert_eq(SaveManager.capture_state(), before)
	assert_eq(_disk(), disk)


func test_confirm_edit_replace_and_cold_restart_keep_statuses_and_summary() -> void:
	await _boot()
	await _open_formation()
	_place(0, 0)
	_place(1, 3)
	await _confirm()
	assert_eq(_screen().scene_file_path, HOME)
	assert_eq(_screen().get_node("%FormationButton").text, "Edit Party")
	assert_string_contains(_screen().get_node("%PartySummaryLabel").text, "2 / 4")
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.ASSIGNED)
	await _open_formation()
	assert_same(_draft().slots[0], GameState.roster[0])
	assert_same(_draft().slots[3], GameState.roster[1])
	_open_picker(1)
	assert_eq(_available_list().get_child_count(), 2)
	_close_picker()
	_slot(0).pressed.emit()
	_screen().get_node("%RemoveButton").pressed.emit()
	_open_picker(0)
	assert_not_null(_available(GameState.roster[0].hero_id), "Retained Assigned Hero may be re-added.")
	_close_picker()
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.ASSIGNED)
	_place(2, 1)
	await _confirm()
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.IDLE)
	assert_eq(GameState.roster[1].status, HeroData.HeroStatus.ASSIGNED)
	assert_eq(GameState.roster[2].status, HeroData.HeroStatus.ASSIGNED)
	var expected := SaveManager.capture_state()
	_main.free()
	_main = null
	GameState.reset()
	await _boot()
	assert_eq(_screen().scene_file_path, HOME)
	assert_eq(SaveManager.capture_state(), expected)
	assert_same(GameState.current_party.slots[1], GameState.roster[2])
	assert_same(GameState.current_party.slots[3], GameState.roster[1])


func test_cancel_edit_preserves_old_party_and_roster_origin() -> void:
	await _boot()
	await _open_formation()
	_place(0, 0)
	await _confirm()
	_screen().get_node("%CompanyRosterButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, ROSTER)
	var expected := SaveManager.capture_state()
	var disk := _disk()
	await _open_formation()
	_slot(0).pressed.emit()
	_screen().get_node("%RemoveButton").pressed.emit()
	_place(2, 2)
	_screen().get_node("%CancelButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, ROSTER)
	assert_eq(SaveManager.capture_state(), expected)
	assert_eq(_disk(), disk)
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.ASSIGNED)


func test_roster_and_hero_detail_show_assigned_after_confirmation() -> void:
	await _boot()
	await _open_formation()
	_place(0, 0)
	await _confirm()
	_screen().get_node("%CompanyRosterButton").pressed.emit()
	await get_tree().process_frame
	var row := _screen().get_node("%RosterList").get_child(0)
	assert_eq(row.find_child("StatusBadge", true, false).text, "Assigned")
	row.pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, DETAIL)
	assert_string_contains(_screen().get_node("%HeroSummaryLabel").text, "Assigned")
	_screen().get_node("%BackButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, ROSTER)


func test_failed_confirm_and_disband_preserve_visible_draft_and_allow_retry() -> void:
	await _boot()
	await _open_formation()
	_place(0, 0)
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "before_primary_replace"
	await _confirm()
	assert_eq(_screen().scene_file_path, FORMATION)
	assert_null(GameState.current_party)
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.IDLE)
	assert_same(_draft().slots[0], GameState.roster[0])
	assert_string_contains(_screen().get_node("%FeedbackLabel").text, "not saved")
	assert_false(_screen().get_node("%ConfirmButton").disabled)
	SaveManager.fault_injector = Callable()
	await _confirm()
	assert_eq(_screen().scene_file_path, HOME)
	await _open_formation()
	assert_true(_screen().get_node("%DisbandButton").visible)
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "before_primary_replace"
	_screen().get_node("%DisbandButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, FORMATION)
	assert_same(GameState.current_party.slots[0], GameState.roster[0])
	assert_string_contains(_screen().get_node("%FeedbackLabel").text, "Disband was not saved")
	assert_false(_screen().get_node("%DisbandButton").disabled)
	SaveManager.fault_injector = Callable()
	_screen().get_node("%DisbandButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)
	assert_null(GameState.current_party)
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.IDLE)
	SaveManager.load_or_create()
	assert_null(GameState.current_party)


func test_postcommit_warning_is_visible_on_home_without_undoing_formation() -> void:
	await _boot()
	await _open_formation()
	_place(0, 0)
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "after_primary_replace"
	await _confirm()
	assert_eq(_screen().scene_file_path, HOME)
	assert_not_null(GameState.current_party)
	assert_string_contains(_screen().get_node("%FeedbackLabel").text, "committed")


func test_pause_and_screen_exit_only_preserve_committed_party() -> void:
	await _boot()
	await _open_formation()
	_place(0, 0)
	_main.notification(NOTIFICATION_APPLICATION_PAUSED)
	assert_null(JSON.parse_string(_disk()).current_party)
	await _confirm()
	var expected := SaveManager.capture_state()
	await _open_formation()
	_screen().get_node("%RemoveButton").pressed.emit()
	_place(1, 3)
	_main.notification(NOTIFICATION_APPLICATION_PAUSED)
	assert_true(SaveManager.last_committed)
	var saved := _disk()
	_main.free()
	_main = null
	assert_eq(_disk(), saved)
	GameState.reset()
	await _boot()
	assert_eq(SaveManager.capture_state(), expected)


func test_android_back_and_ui_cancel_discard_draft_without_quitting_or_saving() -> void:
	await _boot()
	assert_false(ProjectSettings.get_setting("application/config/quit_on_go_back"))
	assert_false(get_tree().quit_on_go_back)
	assert_false(get_tree().auto_accept_quit)
	await _open_formation()
	var before := _disk()
	_open_picker(0)
	_main.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, FORMATION)
	assert_false(_selector().visible)
	assert_eq(_disk(), before)
	_place(0, 0)
	_main.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)
	assert_null(GameState.current_party)
	assert_eq(_disk(), before)
	UIManager.show_screen(ROSTER)
	await get_tree().process_frame
	await _open_formation()
	_open_picker(3)
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	_screen().get_viewport().push_input(event, true)
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, FORMATION)
	assert_false(_selector().visible)
	_place(1, 3)
	_screen().get_viewport().push_input(event, true)
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, ROSTER)
	assert_eq(_disk(), before)


func test_origin_context_is_whitelisted_and_cannot_select_an_arbitrary_screen() -> void:
	await _boot()
	for origin in [null, 42, [], HOME, DETAIL, "res://unknown.tscn", "home"]:
		UIManager.show_screen(FORMATION, {"origin": origin})
		await get_tree().process_frame
		_screen().get_node("%CancelButton").pressed.emit()
		await get_tree().process_frame
		assert_eq(_screen().scene_file_path, HOME)


func test_unavailable_heroes_are_not_selectable_and_empty_state_is_visible() -> void:
	await _boot()
	for index in 4:
		GameState.roster[index].status = [HeroData.HeroStatus.RESTING, HeroData.HeroStatus.WOUNDED,
			HeroData.HeroStatus.DEAD, HeroData.HeroStatus.ON_EXPEDITION][index]
	await _open_formation()
	_open_picker(0)
	assert_eq(_available_list().get_child_count(), 0)
	assert_true(_selector().find_child("ModalEmptyLabel", true, false).visible)
	assert_true(_screen().get_node("%ConfirmButton").disabled)
	_screen().call("_place", GameState.recruitment_offers[0])
	assert_eq(_draft().heroes(), [])
	assert_string_contains(_screen().get_node("%FeedbackLabel").text, "no longer")


func test_occupied_slots_and_duplicate_heroes_are_never_silently_replaced() -> void:
	await _boot()
	await _open_formation()
	_place(0, 0)
	_screen().call("_place", GameState.roster[1])
	assert_same(_draft().slots[0], GameState.roster[0])
	assert_eq(_draft().heroes().size(), 1)
	assert_string_contains(_screen().get_node("%FeedbackLabel").text, "never replaced")
	_place(1, 1)
	_screen().get_node("%MoveButton").pressed.emit()
	_slot(0).pressed.emit()
	assert_same(_draft().slots[0], GameState.roster[0])
	assert_same(_draft().slots[1], GameState.roster[1])
	assert_string_contains(_screen().get_node("%FeedbackLabel").text, "never replaced")
	_slot(3).pressed.emit()
	assert_same(_draft().slots[3], GameState.roster[1])


func test_invalid_or_stale_draft_disables_confirm_and_shows_validation_feedback() -> void:
	await _boot()
	await _open_formation()
	_place(0, 0)
	SaveManager.load_or_create()
	_screen().notification(NOTIFICATION_APPLICATION_RESUMED)
	assert_true(_screen().get_node("%ConfirmButton").disabled)
	assert_string_contains(_screen().get_node("%FeedbackLabel").text, "no longer")
	await _confirm()
	assert_eq(_screen().scene_file_path, FORMATION)
	assert_null(GameState.current_party)
	_draft().slots[0] = "invalid"
	_screen().call("_refresh")
	assert_true(_screen().get_node("%ConfirmButton").disabled)
	assert_string_contains(_screen().get_node("%PowerLabel").text, "Unavailable")


func test_active_expedition_disables_actions_and_callbacks_revalidate() -> void:
	await _boot()
	await _open_formation()
	_place(0, 0)
	await _confirm()
	await _open_formation()
	var before := SaveManager.capture_state()
	ExpeditionManager.set_script(ActiveExpedition)
	_screen().notification(NOTIFICATION_APPLICATION_RESUMED)
	assert_true(_screen().get_node("%ConfirmButton").disabled)
	assert_true(_screen().get_node("%DisbandButton").disabled)
	assert_true(_slot(0).disabled)
	assert_string_contains(_screen().get_node("%FeedbackLabel").text, "active Expedition")
	_screen().get_node("%RemoveButton").pressed.emit()
	_screen().get_node("%ConfirmButton").pressed.emit()
	_screen().get_node("%DisbandButton").pressed.emit()
	assert_eq(SaveManager.capture_state(), before)
	assert_same(_draft().slots[0], GameState.roster[0])
	_screen().get_node("%CancelButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)
	assert_true(_screen().get_node("%FormationButton").disabled)


func test_portrait_long_names_wrap_and_controls_pass_scroll_input() -> void:
	await _boot()
	_main.size = Vector2(720, 1280)
	for hero in GameState.roster:
		hero.hero_name = "Alexandria of the Distant Northern Mountains and Moonlit Lakes of the Ancient Silver Shield Order"
	await _open_formation()
	_place(0, 0)
	_open_picker(1)
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll := _screen().get_node("%Scroll") as ScrollContainer
	var picker_scroll := _selector().find_child("ModalScroll", true, false) as ScrollContainer
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	assert_eq(picker_scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	assert_gt(scroll.get_v_scroll_bar().max_value, scroll.size.y)
	assert_lte(_screen().get_node("%SlotGrid").size.x, scroll.size.x)
	for button in _screen().get_node("%SlotGrid").get_children():
		assert_eq(button.mouse_filter, Control.MOUSE_FILTER_PASS)
		assert_gte(button.size.y, 160.0)
		var label := button.get_node("MarginContainer/SlotLabel")
		assert_eq(label.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
		assert_lte(label.size.x, button.size.x)
	for row in _available_list().get_children():
		assert_eq(row.mouse_filter, Control.MOUSE_FILTER_PASS)
		assert_lte(row.size.x, picker_scroll.size.x)
	for name in ["MoveButton", "RemoveButton", "DisbandButton"]:
		assert_eq(_screen().get_node("%" + name).mouse_filter, Control.MOUSE_FILTER_PASS)
	_assert_labels_ignore_input(_screen())


func test_all_idle_heroes_render_in_static_margin_scroll_at_reported_sizes() -> void:
	var viewport: SubViewport = add_child_autofree(SubViewport.new())
	viewport.size = Vector2i(1065, 1280)
	await _boot(viewport)
	await _open_formation()
	_open_picker(0)
	var expected_ids := PackedStringArray()
	for hero in GameState.roster:
		assert_eq(hero.status, HeroData.HeroStatus.IDLE)
		expected_ids.append(hero.hero_id)
	var margin := _screen().get_node("Margin") as MarginContainer
	assert_null(margin.get_script())
	var scroll := _selector().find_child("ModalScroll", true, false) as ScrollContainer
	for extent in [
		Vector2i(720, 1280), Vector2i(720, 1600),
		Vector2i(960, 1280), Vector2i(1065, 1280),
	]:
		viewport.size = extent
		await get_tree().process_frame
		await get_tree().process_frame
		assert_eq([
			margin.get_theme_constant("margin_left"),
			margin.get_theme_constant("margin_top"),
			margin.get_theme_constant("margin_right"),
			margin.get_theme_constant("margin_bottom"),
		], [24, 24, 24, 24])
		var list := _available_list()
		assert_true(list.is_visible_in_tree())
		assert_eq(list.get_child_count(), expected_ids.size())
		assert_false(_selector().find_child("ModalEmptyLabel", true, false).visible)
		for index in expected_ids.size():
			var row := list.get_child(index) as Button
			assert_eq(row.get_meta("hero_id"), expected_ids[index])
			assert_true(row.is_visible_in_tree())
			assert_gte(row.size.y, 144.0)
		var last_row := list.get_child(list.get_child_count() - 1) as Button
		scroll.ensure_control_visible(last_row)
		await get_tree().process_frame
		assert_true(scroll.get_global_rect().intersection(last_row.get_global_rect()).has_area())


func _assert_labels_ignore_input(node: Node) -> void:
	if node is Label:
		assert_eq(node.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	for child in node.get_children():
		_assert_labels_ignore_input(child)


func _mouse_button(viewport: Viewport, position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = position
	event.global_position = position
	event.pressed = pressed
	viewport.push_input(event, true)


func _touch(viewport: Viewport, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = position
	event.pressed = pressed
	viewport.push_input(event, true)


func _swipe(viewport: Viewport, button: Button) -> void:
	# push_input bypasses Input's touch-to-mouse emulation; deliver both streams.
	var position := button.get_global_rect().get_center()
	_touch(viewport, position, true)
	_mouse_button(viewport, position, true)
	for step in 3:
		var event := InputEventScreenDrag.new()
		event.index = 0
		event.relative = Vector2(0, -40)
		position += event.relative
		event.position = position
		viewport.push_input(event, true)
		var mouse := InputEventMouseMotion.new()
		mouse.button_mask = MOUSE_BUTTON_MASK_LEFT
		mouse.position = position
		mouse.global_position = position
		mouse.relative = event.relative
		viewport.push_input(mouse, true)
		await get_tree().process_frame
	_touch(viewport, position, false)
	_mouse_button(viewport, position, false)
	await get_tree().process_frame


func test_touch_swipes_do_not_select_slots_or_heroes_but_taps_place_once() -> void:
	Input.emulate_touch_from_mouse = true
	var viewport: SubViewport = add_child_autofree(SubViewport.new())
	viewport.size = Vector2i(720, 1280)
	await _boot(viewport)
	for hero in GameState.roster:
		hero.hero_name = "Alexandria of the Distant Northern Mountains and Moonlit Lakes of the Ancient Silver Shield Order"
	await _open_formation()
	await get_tree().process_frame
	var scroll := _screen().get_node("%Scroll") as ScrollContainer
	scroll.ensure_control_visible(_slot(2))
	await get_tree().process_frame
	await _swipe(viewport, _slot(2))
	assert_eq(_screen().get("_selected_slot"), 0, "Dragging a slot must not select it.")
	assert_gt(scroll.scroll_vertical, 0)
	_open_picker(2)
	var row := _available(GameState.roster[0].hero_id)
	var picker_scroll := _selector().find_child("ModalScroll", true, false) as ScrollContainer
	picker_scroll.ensure_control_visible(row)
	await get_tree().process_frame
	var before := picker_scroll.scroll_vertical
	await _swipe(viewport, row)
	assert_gt(picker_scroll.scroll_vertical, before)
	assert_eq(_draft().heroes(), [])
	assert_null(GameState.current_party)
	picker_scroll.ensure_control_visible(row)
	await get_tree().process_frame
	var position := row.get_global_rect().get_center()
	_mouse_button(viewport, position, true)
	_mouse_button(viewport, position, false)
	assert_eq(_draft().heroes().size(), 1)
	assert_same(_draft().slots[2], GameState.roster[0])
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.IDLE)
	await get_tree().process_frame
