extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
const HOME := "res://scenes/ui/home/home_screen.tscn"
const REGION := "res://scenes/ui/region_select/region_select_screen.tscn"
const ROSTER := "res://scenes/ui/roster/roster_screen.tscn"
var _isolation: RefCounted
var _main: Control
var _root: Control
var _auto_accept_quit: bool


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	_auto_accept_quit = get_tree().auto_accept_quit
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


func _go(path: String) -> void:
	UIManager.show_screen(path)
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, path)


func _confirm() -> void:
	var party := PartyData.new()
	party.place_hero(3, GameState.roster[0])
	assert_true(PartyFormationService.confirm(party, ExpeditionManager.balancing))


func _select(region: RegionResource) -> void:
	_node("RegionButton_%s" % region.region_id).pressed.emit()


func _assert_offered_durations(region: RegionResource) -> void:
	var durations := _node("DurationOptions") as OptionButton
	assert_eq(durations.item_count, region.duration_options_seconds.size())
	for index in durations.item_count:
		assert_eq(durations.get_item_metadata(index), region.duration_options_seconds[index])
	assert_eq(durations.selected, 0)
	assert_string_contains(_node("RegionSummary").text, region.display_name)
	assert_string_contains(_node("RegionSummary").text, str(region.recommended_party_power))
	assert_string_contains(_node("RegionSummary").text, "advisory only")


func test_initial_regions_show_locks_requirements_and_reject_locked_dispatch() -> void:
	_confirm()
	await _go(REGION)
	var before := SaveManager.capture_state()
	assert_eq(ExpeditionCatalog.regions().size(), 3)
	assert_string_contains(_node("GoldLabel").text, "100")
	assert_string_contains(_node("PartySummary").text, "1 / 4")
	assert_false(_node("StartButton").disabled, "Partial, back-row-only Parties remain valid.")
	for region in ExpeditionCatalog.regions():
		var choice := _node("RegionButton_%s" % region.region_id) as Button
		assert_false(choice.disabled, "Locked Regions remain selectable for inspection.")
		assert_gte(choice.custom_minimum_size.y, 96.0)
		assert_eq(choice.mouse_filter, Control.MOUSE_FILTER_PASS)
		var requirement := _node("RegionRequirement_%s" % region.region_id) as Label
		assert_eq(requirement.mouse_filter, Control.MOUSE_FILTER_IGNORE)
		assert_string_contains(requirement.text, CompanyProgression.requirement_text(region))
		assert_string_contains(requirement.text, str(
			ExpeditionManager.balancing.region_roster_capacities[region.region_id]))
		_select(region)
		_assert_offered_durations(region)
		if region == ExpeditionCatalog.GREEN_HOLLOW:
			assert_string_contains(choice.text, "Unlocked")
			assert_false(_node("StartButton").disabled)
		else:
			assert_string_contains(choice.text, "Locked")
			assert_true(_node("StartButton").disabled)
			assert_string_contains(requirement.text, "100 / %d" % int(region.unlock_condition.value))
			var error := ExpeditionManager.start_error(
				region, GameState.current_party, region.duration_options_seconds[0])
			assert_false(error.is_empty())
			assert_eq(_node("FeedbackLabel").text, error)
			ExpeditionManager.start_expedition(
				region, GameState.current_party, region.duration_options_seconds[0])
			assert_false(ExpeditionManager.last_committed, "Backend also rejects bypassed UI.")
			_node("StartButton").pressed.emit()
			assert_false(ExpeditionManager.last_committed)
			assert_eq(SaveManager.capture_state(), before)
			assert_null(ExpeditionManager.get_active_expedition())


func test_region_switch_resets_offered_duration_and_stale_party_is_rejected() -> void:
	_confirm()
	GameState.gold = 400
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	await _go(REGION)
	for region in ExpeditionCatalog.regions():
		_select(region)
		_assert_offered_durations(region)
		var durations := _node("DurationOptions") as OptionButton
		durations.select(durations.item_count - 1)
		durations.item_selected.emit(durations.selected)
		assert_false(_node("StartButton").disabled)
	_select(ExpeditionCatalog.GREEN_HOLLOW)
	_assert_offered_durations(ExpeditionCatalog.GREEN_HOLLOW)
	assert_true(PartyFormationService.disband())
	_confirm()
	var replacement := GameState.current_party
	var before := SaveManager.capture_state()
	_node("StartButton").pressed.emit()
	assert_false(ExpeditionManager.last_committed)
	assert_true(_node("StartButton").disabled)
	assert_string_contains(_node("FeedbackLabel").text, "Party changed")
	assert_same(GameState.current_party, replacement)
	assert_eq(SaveManager.capture_state(), before)


func test_failed_unlock_stays_locked_then_committed_change_refreshes_same_controls() -> void:
	_confirm()
	await _go(REGION)
	var region := ExpeditionCatalog.region_by_id("ashen_reach")
	_select(region)
	var screen := _screen()
	var button := _node("RegionButton_ashen_reach")
	var requirement := _node("RegionRequirement_ashen_reach")
	var durations := _node("DurationOptions") as OptionButton
	durations.select(durations.item_count - 1)
	var selected_duration: Variant = durations.get_item_metadata(durations.selected)
	var party := GameState.current_party
	GameState.gold = 200
	var before := SaveManager.capture_state()
	watch_signals(ExpeditionManager)
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "before_primary_replace"
	ExpeditionManager.reveal_progress()
	assert_false(ExpeditionManager.last_committed)
	assert_signal_not_emitted(ExpeditionManager, "changed")
	assert_eq(SaveManager.capture_state(), before)
	assert_false(CompanyProgression.is_unlocked(region, GameState.unlocked_regions))
	assert_eq(GameState.roster_capacity, 12)
	assert_string_contains(button.text, "Locked")
	assert_true(_node("StartButton").disabled)
	assert_string_contains(_node("FeedbackLabel").text, "not saved")
	SaveManager.fault_injector = Callable()
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_signal_emit_count(ExpeditionManager, "changed", 1)
	assert_same(_screen(), screen)
	assert_same(_node("RegionButton_ashen_reach"), button)
	assert_same(_node("RegionRequirement_ashen_reach"), requirement)
	assert_same(_node("DurationOptions"), durations)
	assert_same(GameState.current_party, party)
	assert_eq(durations.get_item_metadata(durations.selected), selected_duration)
	assert_true(button.button_pressed)
	assert_string_contains(button.text, "Unlocked")
	assert_false(_node("StartButton").disabled)
	assert_eq(GameState.roster_capacity, 16)
	assert_string_contains(_node("RegionButton_frostbound_pass").text, "Locked")


func test_selected_unlocked_region_dispatches_and_persists_its_own_duration() -> void:
	_confirm()
	GameState.gold = 200
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	await _go(REGION)
	var region := ExpeditionCatalog.region_by_id("ashen_reach")
	_select(region)
	var durations := _node("DurationOptions") as OptionButton
	durations.select(durations.item_count - 1)
	durations.item_selected.emit(durations.selected)
	var seconds := int(durations.get_item_metadata(durations.selected))
	assert_false(_node("StartButton").disabled)
	_node("StartButton").pressed.emit()
	await get_tree().process_frame
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(_screen().scene_file_path, HOME)
	var run := ExpeditionManager.get_active_expedition()
	assert_not_null(run)
	assert_eq(run.region_id, String(region.region_id))
	assert_eq(run.duration_seconds, seconds)
	assert_string_contains(_node("ExpeditionLabel").text, region.display_name)
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success, SaveManager.last_error)
	assert_eq(ExpeditionManager.get_active_expedition().region_id, String(region.region_id))
	assert_eq(ExpeditionManager.get_active_expedition().duration_seconds, seconds)


func test_full_roster_unlock_refreshes_capacity_and_offers_without_rebuilding_rows() -> void:
	while GameState.roster.size() < GameState.roster_capacity:
		var hero := HeroGenerator.generate_hero(GameState.reserve_hero_id(),
			12345 + GameState.roster.size(), HeroCatalog.classes(), HeroCatalog.traits())
		assert_not_null(hero)
		GameState.roster.append(hero)
	await _go(ROSTER)
	var list := _node("RosterList")
	var row := list.get_child(0)
	var offers := _node("OfferList")
	var offer := offers.get_child(0)
	var count := _node("RosterCountLabel")
	var notice := _node("CompanyProgressionLabel")
	assert_string_contains(count.text, "12 / 12")
	assert_string_contains(notice.text, "Roster full")
	assert_string_contains(notice.text, "Green Hollow: 12")
	assert_string_contains(notice.text, "Next roster cap: 16")
	assert_string_contains(notice.text, "100 / 200")
	assert_true(offer.get_node("Content/RecruitButton").disabled)
	GameState.gold = 200
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "before_primary_replace"
	ExpeditionManager.reveal_progress()
	assert_false(ExpeditionManager.last_committed)
	assert_string_contains(count.text, "12 / 12")
	assert_string_contains(notice.text, "Roster full")
	assert_true(offer.get_node("Content/RecruitButton").disabled)
	SaveManager.fault_injector = Callable()
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_same(_node("RosterList"), list)
	assert_same(list.get_child(0), row)
	assert_same(_node("OfferList"), offers)
	assert_same(offers.get_child(0), offer)
	assert_same(_node("RosterCountLabel"), count)
	assert_same(_node("CompanyProgressionLabel"), notice)
	assert_string_contains(count.text, "12 / 16")
	assert_false(notice.text.contains("Roster full"))
	assert_string_contains(notice.text, "Ashen Reach: 16")
	assert_string_contains(notice.text, "Next roster cap: 20")
	assert_string_contains(notice.text, "200 / 400")
	assert_false(offer.get_node("Content/RecruitButton").disabled)
	assert_false(offer.get_node("Content/AvailabilityLabel").visible)


func test_unlocks_and_capacity_remain_visible_after_spending_and_reload() -> void:
	GameState.gold = 400
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	await _go(ROSTER)
	assert_string_contains(_node("CompanyProgressionLabel").text, "Frostbound Pass: 20")
	assert_string_contains(_node("CompanyProgressionLabel").text, "No higher roster cap")
	for _purchase in 3:
		_node("OfferList").get_child(0).get_node("Content/RecruitButton").pressed.emit()
		assert_true(SaveManager.last_committed, SaveManager.last_error)
	assert_eq(GameState.gold, 100)
	assert_eq(GameState.roster.size(), 7)
	assert_eq(GameState.roster_capacity, 20)
	assert_string_contains(_node("RosterCountLabel").text, "7 / 20")
	assert_string_contains(_node("CompanyProgressionLabel").text, "Frostbound Pass: 20")
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success, SaveManager.last_error)
	assert_eq(GameState.gold, 100)
	assert_eq(GameState.roster_capacity, 20)
	_confirm()
	await _go(REGION)
	for region in ExpeditionCatalog.regions():
		assert_true(CompanyProgression.is_unlocked(region, GameState.unlocked_regions))
		_select(region)
		assert_string_contains(_node("RegionButton_%s" % region.region_id).text, "Unlocked")
		assert_false(_node("StartButton").disabled)


func test_locked_region_cancel_and_android_back_preserve_confirmed_party() -> void:
	_confirm()
	var party := GameState.current_party
	var before := SaveManager.capture_state()
	for use_android_back in [false, true]:
		await _go(REGION)
		_select(ExpeditionCatalog.region_by_id("frostbound_pass"))
		assert_true(_node("StartButton").disabled)
		if use_android_back:
			_main.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
		else:
			_node("CancelButton").pressed.emit()
		await get_tree().process_frame
		assert_eq(_screen().scene_file_path, HOME)
		assert_same(GameState.current_party, party)
		assert_eq(SaveManager.capture_state(), before)
		assert_eq(_node("ExpeditionButton").text, "Choose Region")


func test_region_choices_fit_portrait_scroll_and_pass_touch_input() -> void:
	_confirm()
	_main.size = Vector2(720, 1280)
	await _go(REGION)
	await get_tree().process_frame
	var scroll := _node("Scroll") as ScrollContainer
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	assert_gt(scroll.get_v_scroll_bar().max_value, scroll.size.y)
	for region in ExpeditionCatalog.regions():
		var button := _node("RegionButton_%s" % region.region_id) as Button
		assert_lte(button.size.x, scroll.size.x)
		assert_gte(button.size.y, 96.0)
		assert_eq(button.mouse_filter, Control.MOUSE_FILTER_PASS)
		var requirement := _node("RegionRequirement_%s" % region.region_id) as Label
		assert_lte(requirement.size.x, scroll.size.x)
		assert_eq(requirement.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	var duration := _node("DurationOptions") as OptionButton
	assert_lte(duration.size.x, scroll.size.x)
	assert_gte(duration.size.y, 96.0)
	assert_eq(duration.mouse_filter, Control.MOUSE_FILTER_PASS)
	assert_gte(duration.get_popup().get_theme_constant("v_separation"), 64)
