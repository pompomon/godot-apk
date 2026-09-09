extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
const HeroUI = preload("res://scenes/ui/hero_ui.gd")
const HOME := "res://scenes/ui/home/home_screen.tscn"
const ROSTER := "res://scenes/ui/roster/roster_screen.tscn"
const DETAIL := "res://scenes/ui/hero_detail/hero_detail_screen.tscn"
var _isolation: RefCounted
var _main: Control
var _root: Control
var _auto_accept_quit: bool
var _emulate_touch_from_mouse: bool


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	_auto_accept_quit = get_tree().auto_accept_quit
	_emulate_touch_from_mouse = Input.emulate_touch_from_mouse


func after_each() -> void:
	if is_instance_valid(_main):
		_main.free()
	_main = null
	get_tree().auto_accept_quit = _auto_accept_quit
	Input.emulate_touch_from_mouse = _emulate_touch_from_mouse
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


func _labels(node: Node) -> String:
	var text := ""
	if node is Label:
		text = node.text + "\n"
	for child in node.get_children():
		text += _labels(child)
	return text


func test_real_main_home_roster_detail_back_and_purchase() -> void:
	await _boot()
	assert_eq(_screen().scene_file_path, HOME)
	assert_string_contains(_labels(_screen()), "100")
	_screen().get_node("%CompanyRosterButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, ROSTER)
	var roster_list := _screen().get_node("%RosterList")
	assert_eq(roster_list.get_child_count(), 4)
	assert_eq(_screen().get_node("%OfferList").get_child_count(), 3)
	for index in GameState.roster.size():
		var hero := GameState.roster[index]
		var row := roster_list.get_child(index)
		assert_eq(row.get_meta("hero_id"), hero.hero_id)
		assert_string_contains(_labels(row), hero.hero_name)
		assert_string_contains(_labels(row), hero.hero_class.display_name)
		assert_string_contains(_labels(row), "Idle")
		var status_badge := row.find_child("StatusBadge", true, false) as Label
		assert_eq(status_badge.text, "Idle")
		assert_true(status_badge.has_theme_stylebox_override("normal"))
		assert_gte(row.custom_minimum_size.y, 96.0)
	roster_list.get_child(2).pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, DETAIL)
	assert_eq(_screen().get_node("%HeroNameLabel").text, GameState.roster[2].hero_name)
	var details := _labels(_screen())
	for key in HeroCatalog.ATTRIBUTES + HeroCatalog.STATS:
		assert_string_contains(details, key)
	assert_string_contains(details, "Cumulative XP: 0")
	assert_string_contains(details, "Weapon: Empty")
	assert_string_contains(details, "Armor: Empty")
	assert_eq(_screen().get_node("%XPProgressBar").value, 0.0)
	_screen().get_node("%BackButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, ROSTER)
	var purchased_id := GameState.recruitment_offers[0].hero_id
	_screen().get_node("%OfferList").get_child(0).get_node("Content/RecruitButton").pressed.emit()
	assert_eq(GameState.gold, 0)
	assert_eq(GameState.roster.size(), 5)
	assert_eq(GameState.roster[4].hero_id, purchased_id)
	assert_eq(_screen().get_node("%RosterList").get_child_count(), 5)
	for card in _screen().get_node("%OfferList").get_children():
		assert_true(card.get_node("Content/RecruitButton").disabled)
		assert_string_contains(card.get_node("Content/AvailabilityLabel").text, "Not enough gold")
	_screen().get_node("%BackButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, HOME)
	assert_string_contains(_labels(_screen()), "Gold: 0")
	SaveManager.load_or_create()
	assert_eq(GameState.roster[4].hero_id, purchased_id)
	assert_eq(GameState.gold, 0)


func test_context_is_copied_per_deferred_request_before_ready() -> void:
	await _boot()
	var captured: Array[String] = []
	_root.child_entered_tree.connect(func(screen: Node) -> void:
		if screen.scene_file_path == DETAIL:
			screen.ready.connect(func() -> void:
				captured.append(screen.get_node("%HeroNameLabel").text)))
	var context := {"hero_id": GameState.roster[0].hero_id, "extra": {"nested": "one"}}
	UIManager.show_screen(DETAIL, context)
	context.hero_id = GameState.roster[1].hero_id
	UIManager.show_screen(DETAIL, context)
	context.hero_id = "missing"
	await get_tree().process_frame
	assert_eq(captured, [GameState.roster[0].hero_name, GameState.roster[1].hero_name])
	assert_eq(_screen().get_node("%HeroNameLabel").text, GameState.roster[1].hero_name)


func test_missing_invalid_and_deleted_selection_are_safe() -> void:
	await _boot()
	for context in [{}, {"hero_id": null}, {"hero_id": 42}, {"hero_id": "hero-999"}]:
		UIManager.show_screen(DETAIL, context)
		await get_tree().process_frame
		assert_true(_screen().get_node("%MissingHeroLabel").visible)
		assert_false(_screen().get_node("%HeroContent").visible)
		assert_eq(_screen().get_node("%HeroNameLabel").text, "Hero unavailable")
	var id := GameState.roster[0].hero_id
	UIManager.show_screen(DETAIL, {"hero_id": id})
	GameState.roster.remove_at(0)
	await get_tree().process_frame
	assert_true(_screen().get_node("%MissingHeroLabel").visible)
	_screen().get_node("%BackButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, ROSTER)


func test_save_failure_and_capacity_reasons_are_visible() -> void:
	await _boot()
	UIManager.show_screen(ROSTER)
	await get_tree().process_frame
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "before_primary_replace"
	_screen().get_node("%OfferList").get_child(0).get_node("Content/RecruitButton").pressed.emit()
	assert_eq(GameState.gold, 100)
	assert_eq(GameState.roster.size(), 4)
	assert_string_contains(_screen().get_node("%FeedbackLabel").text, "not saved")
	GameState.roster_capacity = 4
	UIManager.show_screen(ROSTER)
	await get_tree().process_frame
	for card in _screen().get_node("%OfferList").get_children():
		assert_true(card.get_node("Content/RecruitButton").disabled)
		assert_string_contains(card.get_node("Content/AvailabilityLabel").text, "Roster full")


func test_traits_xp_status_and_recovery_notice_are_inspectable() -> void:
	await _boot()
	var hero := GameState.roster[0]
	hero.traits.clear()
	hero.level = 5
	hero.xp = 234
	hero.status = HeroData.HeroStatus.WOUNDED
	SaveManager.last_warning = "Recovered the company from the backup save."
	UIManager.show_screen(DETAIL, {"hero_id": hero.hero_id})
	await get_tree().process_frame
	var text := _labels(_screen())
	assert_string_contains(text, "No traits")
	assert_string_contains(text, "Wounded")
	assert_string_contains(text, "Level 5")
	assert_string_contains(text, "Cumulative XP: 234")
	assert_string_contains(text, "Next level:")
	assert_string_contains(text, "Recovered")
	hero.traits.append(HeroCatalog.LIGHTFOOTED)
	UIManager.show_screen(DETAIL, {"hero_id": hero.hero_id})
	await get_tree().process_frame
	assert_string_contains(_labels(_screen()), HeroCatalog.LIGHTFOOTED.description)


func test_pause_saves_initialized_state_only() -> void:
	var bootstrap: Control = autofree(load("res://main.tscn").instantiate())
	bootstrap.notification(NOTIFICATION_APPLICATION_PAUSED)
	assert_false(FileAccess.file_exists(SaveManager.get_save_path()))
	await _boot()
	GameState.gold = 73
	_main.notification(NOTIFICATION_APPLICATION_PAUSED)
	assert_true(SaveManager.last_committed)
	SaveManager.load_or_create()
	assert_eq(GameState.gold, 73)


func test_portrait_layout_wraps_long_names_and_scrolls_inspection_content() -> void:
	await _boot()
	_main.size = Vector2(720, 1280)
	var hero := GameState.roster[0]
	hero.hero_name = "Alexandria of the Distant Northern Mountains and Moonlit Lakes"
	hero.hero_class = hero.hero_class.duplicate(true)
	hero.hero_class.display_name = "Knight of the Ancient Order of the Silver Shield"
	UIManager.show_screen(ROSTER)
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll := _screen().get_node("%Scroll") as ScrollContainer
	var row := _screen().get_node("%RosterList").get_child(0) as Button
	assert_lte(row.size.x, scroll.size.x)
	assert_gte(row.size.y, 144.0)
	assert_gt(scroll.get_v_scroll_bar().max_value, scroll.size.y)
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	for card in _screen().get_node("%OfferList").get_children():
		assert_lte(card.size.x, scroll.size.x)
		var text := _labels(card)
		for key in HeroCatalog.ATTRIBUTES + HeroCatalog.STATS:
			assert_string_contains(text, key)
		assert_string_contains(text, "Traits")
		assert_string_contains(text, "Price: 100 gold")
	row.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	scroll = _screen().get_node("%Scroll")
	assert_gt(scroll.get_v_scroll_bar().max_value, scroll.size.y)
	assert_lte(_screen().get_node("%HeroNameLabel").size.x, scroll.size.x)
	assert_eq(_screen().get_node("%HeroNameLabel").autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)


func test_status_badges_fit_one_line_in_rows_offers_and_formation_after_refresh() -> void:
	var viewport: SubViewport = add_child_autofree(SubViewport.new())
	viewport.size = Vector2i(720, 1280)
	await _boot(viewport)
	var hero := GameState.roster[0]
	hero.hero_name = "Alexandria of the Distant Northern Mountains and Moonlit Lakes"
	UIManager.show_screen(ROSTER)
	await get_tree().process_frame
	var row := _screen().get_node("%RosterList").get_child(0)
	for status in HeroData.HeroStatus.values():
		hero.status = status as HeroData.HeroStatus
		HeroUI.refresh_hero_header(row, hero)
		await get_tree().process_frame
		await get_tree().process_frame
		_assert_single_line_badge(row, HeroUI.status_name(hero))
		assert_eq(row.find_child("HeroName", true, false).autowrap_mode,
			TextServer.AUTOWRAP_WORD_SMART)
		assert_lte(row.size.x, _screen().get_node("%Scroll").size.x)
	for card in _screen().get_node("%OfferList").get_children():
		_assert_single_line_badge(card, "Idle")
	hero.status = HeroData.HeroStatus.IDLE
	UIManager.show_screen("res://scenes/ui/party_formation/party_formation_screen.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	for available in _screen().get_node("%AvailableList").get_children():
		_assert_single_line_badge(available, "Idle")


func _assert_single_line_badge(parent: Control, expected: String) -> void:
	var badge := parent.find_child("StatusBadge", true, false) as Label
	var icon := parent.find_child("StatusIcon", true, false) as TextureRect
	assert_eq(badge.text, expected)
	assert_eq(badge.get_line_count(), 1)
	assert_eq(badge.autowrap_mode, TextServer.AUTOWRAP_OFF)
	var text_width := badge.get_theme_font("font").get_string_size(
		badge.text, HORIZONTAL_ALIGNMENT_LEFT, -1, badge.get_theme_font_size("font_size")).x
	assert_gte(badge.size.x, text_width + badge.get_theme_stylebox("normal").get_minimum_size().x)
	assert_almost_eq(badge.get_global_rect().get_center().y, icon.get_global_rect().get_center().y, 1.0)
	assert_gte(badge.get_global_rect().position.x, icon.get_global_rect().end.x)
	assert_lte(badge.get_global_rect().end.x, parent.get_global_rect().end.x)


func test_scroll_rows_cards_and_recruit_buttons_pass_touch_input() -> void:
	await _boot()
	assert_eq(_screen().get_node("%CompanyRosterButton").mouse_filter, Control.MOUSE_FILTER_PASS)
	UIManager.show_screen(ROSTER)
	await get_tree().process_frame
	for row in _screen().get_node("%RosterList").get_children():
		assert_eq(row.mouse_filter, Control.MOUSE_FILTER_PASS)
		_assert_labels_ignore_input(row)
	for card in _screen().get_node("%OfferList").get_children():
		assert_eq(card.mouse_filter, Control.MOUSE_FILTER_PASS)
		assert_eq(card.get_node("Content/RecruitButton").mouse_filter, Control.MOUSE_FILTER_PASS)
		_assert_labels_ignore_input(card)


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


func _swipe_from_button(viewport: Viewport, button: Button) -> void:
	# push_input bypasses Input's touch-to-mouse emulation; deliver both event streams.
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


func test_touch_swipes_scroll_without_activation_and_taps_still_recruit() -> void:
	Input.emulate_touch_from_mouse = true
	assert_true(DisplayServer.is_touchscreen_available())
	var viewport: SubViewport = add_child_autofree(SubViewport.new())
	viewport.size = Vector2i(720, 1280)
	await _boot(viewport)
	UIManager.show_screen(ROSTER)
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll := _screen().get_node("%Scroll") as ScrollContainer
	var row := _screen().get_node("%RosterList").get_child(0) as Button
	await _swipe_from_button(viewport, row)
	assert_eq(_screen().scene_file_path, ROSTER, "Dragging a row must not open detail.")
	assert_gt(scroll.scroll_vertical, 0, "Touch drag must reach ScrollContainer.")
	var button := _screen().get_node("%OfferList").get_child(0).get_node("Content/RecruitButton") as Button
	scroll.ensure_control_visible(button)
	await get_tree().process_frame
	var before := scroll.scroll_vertical
	await _swipe_from_button(viewport, button)
	assert_gt(scroll.scroll_vertical, before, "Offer card and button must pass touch drags.")
	assert_eq(GameState.gold, 100)
	assert_eq(GameState.roster.size(), 4)
	scroll.ensure_control_visible(button)
	await get_tree().process_frame
	var position := button.get_global_rect().get_center()
	_mouse_button(viewport, position, true)
	_mouse_button(viewport, position, false)
	assert_eq(GameState.gold, 0, "An ordinary button tap still recruits exactly once.")
	assert_eq(GameState.roster.size(), 5)
	await get_tree().process_frame
