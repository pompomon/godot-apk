extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
const HeroUI = preload("res://scenes/ui/hero_ui.gd")
const HOME := "res://scenes/ui/home/home_screen.tscn"
const ROSTER := "res://scenes/ui/roster/roster_screen.tscn"
const FORMATION := "res://scenes/ui/party_formation/party_formation_screen.tscn"
var _isolation: RefCounted
var _previous_diagnostics: UIDiagnostics
var _previous_environment: String
var _had_environment: bool
var _auto_accept_quit: bool
var _viewport: SubViewport
var _main: Control


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	_previous_diagnostics = UIManager.diagnostics
	UIManager.diagnostics = UIDiagnostics.new()
	_had_environment = OS.has_environment("UI_DIAGNOSTICS")
	_previous_environment = OS.get_environment("UI_DIAGNOSTICS")
	OS.set_environment("UI_DIAGNOSTICS", "1")
	_auto_accept_quit = get_tree().auto_accept_quit
	_viewport = add_child_autofree(SubViewport.new())
	_viewport.size = Vector2i(720, 1280)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func after_each() -> void:
	if is_instance_valid(_main):
		_main.free()
	_main = null
	await get_tree().process_frame
	UIManager.diagnostics = _previous_diagnostics
	if _had_environment:
		OS.set_environment("UI_DIAGNOSTICS", _previous_environment)
	else:
		OS.unset_environment("UI_DIAGNOSTICS")
	get_tree().auto_accept_quit = _auto_accept_quit
	_isolation.finish()


func _boot() -> void:
	_main = load("res://main.tscn").instantiate()
	_viewport.add_child(_main)
	await get_tree().process_frame
	assert_true(SaveManager.last_success, SaveManager.last_error)


func _screen() -> Control:
	return _main.get_node("ScreenRoot").get_child(0)


func _go(path: String) -> void:
	UIManager.show_screen(path)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, path)


func _path() -> String:
	return SaveManager.get_save_path().get_base_dir().path_join("ui-diagnostics.jsonl")


func _stages() -> Array:
	var stages := []
	for line in FileAccess.get_file_as_string(_path()).split("\n", false):
		var data: Variant = JSON.parse_string(line)
		if data is Dictionary:
			stages.append(data.stage)
	return stages


func test_disabled_probe_does_not_read_write_or_change_presentation() -> void:
	var diagnostics := UIDiagnostics.new()
	diagnostics.initialize(_isolation.directory, false)
	diagnostics.select_mode(UIDiagnostics.Mode.NO_ARTWORK)
	diagnostics.begin_navigation(ROSTER, _viewport)
	diagnostics.mark("hero.row.begin")
	assert_false(diagnostics.enabled)
	assert_false(diagnostics.hide_artwork())
	assert_false(diagnostics.fixed_rows())
	assert_false(diagnostics.static_margins())
	assert_eq(diagnostics.mode, UIDiagnostics.Mode.BASELINE)
	assert_eq(diagnostics.last_record, {})
	assert_false(FileAccess.file_exists(_path()))


func test_trace_survives_restart_and_ignores_partial_final_line() -> void:
	var diagnostics := UIDiagnostics.new()
	diagnostics.initialize(_isolation.directory, true)
	diagnostics.select_mode(UIDiagnostics.Mode.STATIC_MARGINS)
	diagnostics.begin_navigation(ROSTER, _viewport)
	diagnostics.mark("layout.screen_margins.static")
	var last := diagnostics.last_record.duplicate(true)
	var file := FileAccess.open(_path(), FileAccess.READ_WRITE)
	file.seek_end()
	file.store_string("{\"probe\":")
	file.close()
	var bytes := FileAccess.get_file_as_bytes(_path())
	var restarted := UIDiagnostics.new()
	restarted.initialize(_isolation.directory, true)
	assert_eq(restarted.last_record, last)
	assert_eq(restarted.mode, UIDiagnostics.Mode.STATIC_MARGINS)
	assert_eq(FileAccess.get_file_as_bytes(_path()), bytes, "Reading must not erase evidence.")
	assert_string_contains(restarted.summary(), "layout.screen_margins.static")


func test_malformed_and_oversized_traces_fail_without_touching_company() -> void:
	await _boot()
	var company := FileAccess.get_file_as_bytes(SaveManager.get_save_path())
	for text in ["not JSON\n", "{\"probe\":1,\"mode\":9000}\n", "x".repeat(UIDiagnostics.MAX_BYTES + 1)]:
		var file := FileAccess.open(_path(), FileAccess.WRITE)
		file.store_string(text)
		file.close()
		var diagnostics := UIDiagnostics.new()
		diagnostics.initialize(_isolation.directory, true)
		assert_eq(diagnostics.last_record, {})
		assert_false(diagnostics.last_error.is_empty())
		assert_eq(FileAccess.get_file_as_bytes(SaveManager.get_save_path()), company)


func test_trace_is_bounded_and_contains_no_hero_or_company_data() -> void:
	await _boot()
	GameState.roster[0].hero_name = "PRIVATE HERO NAME"
	await _go(ROSTER)
	for index in 200:
		UIManager.diagnostics.mark("test.marker.%d" % index)
	var text := FileAccess.get_file_as_string(_path())
	assert_lte(text.to_utf8_buffer().size(), UIDiagnostics.MAX_BYTES)
	assert_lte(_stages().size(), UIDiagnostics.MAX_MARKERS)
	assert_false(text.contains("PRIVATE HERO NAME"))
	assert_false(text.contains("hero-1"))
	assert_false(text.contains("recruitment_seed"))
	var before := text
	UIManager.diagnostics.mark("hero.row.begin")
	assert_eq(FileAccess.get_file_as_string(_path()), before)


func test_home_boot_and_mode_selection_preserve_last_attempt_and_company_files() -> void:
	await _boot()
	assert_false(FileAccess.file_exists(_path()), "Booting Home must not erase or create evidence.")
	var company := FileAccess.get_file_as_bytes(SaveManager.get_save_path())
	var state := SaveManager.capture_state()
	_screen().find_child("DiagnosticMode1", true, false).pressed.emit()
	_screen().get_node("%CompanyRosterButton").pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var trace := FileAccess.get_file_as_bytes(_path())
	_main.free()
	_main = null
	await _boot()
	assert_eq(FileAccess.get_file_as_bytes(_path()), trace)
	assert_eq(FileAccess.get_file_as_bytes(SaveManager.get_save_path()), company)
	assert_eq(SaveManager.capture_state(), state)
	var result := _screen().find_child("LastDiagnosticLabel", true, false) as Label
	assert_string_contains(result.text, "B · No artwork drawing")
	assert_string_contains(result.text, "Company Roster")
	_screen().find_child("DiagnosticMode2", true, false).pressed.emit()
	assert_eq(FileAccess.get_file_as_bytes(_path()), trace, "Mode choice is for the next attempt.")
	assert_string_contains(result.text, "B · No artwork drawing")


func test_modes_are_mutually_exclusive_and_locked_for_current_screen() -> void:
	var diagnostics := UIDiagnostics.new()
	diagnostics.initialize(_isolation.directory, true)
	for mode in UIDiagnostics.Mode.values():
		diagnostics.stop()
		diagnostics.select_mode(mode)
		diagnostics.begin_navigation(ROSTER, _viewport)
		assert_eq(diagnostics.hide_artwork(), mode == UIDiagnostics.Mode.NO_ARTWORK)
		assert_eq(diagnostics.fixed_rows(), mode == UIDiagnostics.Mode.FIXED_ROWS)
		assert_eq(diagnostics.static_margins(), mode == UIDiagnostics.Mode.STATIC_MARGINS)
		diagnostics.select_mode((mode + 1) % UIDiagnostics.Mode.values().size())
		assert_eq(diagnostics.mode, mode)
	diagnostics.stop()
	diagnostics.select_mode(999)
	assert_eq(diagnostics.mode, UIDiagnostics.Mode.STATIC_MARGINS)
	diagnostics.begin_navigation(HOME, _viewport)
	assert_false(diagnostics.hide_artwork())
	assert_false(diagnostics.fixed_rows())
	assert_false(diagnostics.static_margins())


func test_artwork_comparison_preserves_lookup_extents_layout_and_input() -> void:
	await _boot()
	await _go(ROSTER)
	var baseline_row := _screen().get_node("%RosterList").get_child(0) as Button
	var baseline_size := baseline_row.size
	var baseline_portrait := baseline_row.find_child("Portrait", true, false) as TextureRect
	var extent := baseline_portrait.custom_minimum_size
	var texture := baseline_portrait.texture
	await _go(HOME)
	UIManager.diagnostics.select_mode(UIDiagnostics.Mode.NO_ARTWORK)
	await _go(ROSTER)
	var row := _screen().get_node("%RosterList").get_child(0) as Button
	var portrait := row.find_child("Portrait", true, false) as TextureRect
	assert_null(portrait.texture)
	assert_same(HeroUI.portrait_texture(GameState.roster[0]), texture, "Lookup is not bypassed.")
	assert_eq(portrait.custom_minimum_size, extent)
	assert_almost_eq(row.size, baseline_size, Vector2.ONE)
	assert_eq(row.mouse_filter, Control.MOUSE_FILTER_PASS)
	assert_eq(portrait.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_true(row.get_child(0).minimum_size_changed.get_connections().size() > 0)
	for image in _screen().find_children("*", "TextureRect", true, false):
		if image.name in ["Portrait", "ClassIcon", "StatusIcon", "GoldIcon"]:
			assert_null(image.texture)
	HeroUI.refresh_hero_header(row, GameState.roster[0])
	assert_null(row.find_child("StatusIcon", true, false).texture)


func test_fixed_sizing_comparison_keeps_art_and_skips_only_row_and_slot_measurements() -> void:
	await _boot()
	UIManager.diagnostics.select_mode(UIDiagnostics.Mode.FIXED_ROWS)
	await _go(FORMATION)
	var row := _screen().get_node("%AvailableList").get_child(0) as Button
	var slot := _screen().get_node("%SlotGrid").get_child(0) as Button
	assert_not_null(row.find_child("Portrait", true, false).texture)
	assert_eq(row.custom_minimum_size.y, 400.0)
	assert_eq(slot.custom_minimum_size.y, 320.0)
	assert_eq(row.get_child(0).minimum_size_changed.get_connections().size(), 0)
	assert_eq(slot.get_node("MarginContainer").minimum_size_changed.get_connections().size(), 0)
	assert_false(_stages().has("layout.row.initial_measure.begin"))
	assert_true(_stages().has("layout.row.fixed_height"))
	assert_true(_stages().has("layout.slot.fixed_height"))


func test_static_margin_comparison_keeps_baseline_content_and_bypasses_dynamic_updates() -> void:
	await _boot()
	var static_button := _screen().find_child("DiagnosticMode3", true, false) as Button
	assert_not_null(static_button)
	static_button.pressed.emit()
	assert_eq(UIManager.diagnostics.mode, UIDiagnostics.Mode.STATIC_MARGINS)
	await _go(ROSTER)
	var margin := _screen().get_node("Margin") as MarginContainer
	var row := _screen().get_node("%RosterList").get_child(0) as Button
	assert_not_null(row.find_child("Portrait", true, false).texture)
	assert_true(row.get_child(0).minimum_size_changed.get_connections().size() > 0)
	assert_eq([
		margin.get_theme_constant("margin_left"),
		margin.get_theme_constant("margin_top"),
		margin.get_theme_constant("margin_right"),
		margin.get_theme_constant("margin_bottom"),
	], [24, 24, 24, 24])
	assert_true(_stages().has("layout.screen_margins.static"))
	assert_false(_stages().has("layout.screen_margins.begin"))
	_viewport.size = Vector2i(960, 1280)
	await get_tree().process_frame
	await get_tree().process_frame
	margin.notification(NOTIFICATION_APPLICATION_RESUMED)
	assert_eq([
		margin.get_theme_constant("margin_left"),
		margin.get_theme_constant("margin_top"),
		margin.get_theme_constant("margin_right"),
		margin.get_theme_constant("margin_bottom"),
	], [24, 24, 24, 24])
	await _go(HOME)
	await _go(FORMATION)
	margin = _screen().get_node("Margin") as MarginContainer
	var slot := _screen().get_node("%SlotGrid").get_child(0) as Button
	row = _screen().get_node("%AvailableList").get_child(0) as Button
	assert_not_null(row.find_child("Portrait", true, false).texture)
	assert_true(row.get_child(0).minimum_size_changed.get_connections().size() > 0)
	assert_true(slot.get_node("MarginContainer").minimum_size_changed.get_connections().size() > 0)
	assert_eq(margin.get_theme_constant("margin_left"), 24)
	assert_eq(margin.get_theme_constant("margin_right"), 24)
	assert_true(_stages().has("layout.screen_margins.static"))
	assert_false(_stages().has("layout.screen_margins.begin"))


func test_every_mode_keeps_formation_drafts_local_and_confirm_cancel_functional() -> void:
	await _boot()
	for mode in UIDiagnostics.Mode.values():
		UIManager.diagnostics.select_mode(mode)
		var state := SaveManager.capture_state()
		var company := FileAccess.get_file_as_bytes(SaveManager.get_save_path())
		await _go(FORMATION)
		_screen().get_node("%AvailableList").get_child(0).pressed.emit()
		assert_eq(SaveManager.capture_state(), state)
		assert_eq(FileAccess.get_file_as_bytes(SaveManager.get_save_path()), company)
		_screen().get_node("%CancelButton").pressed.emit()
		await get_tree().process_frame
		assert_eq(_screen().scene_file_path, HOME)
		assert_eq(SaveManager.capture_state(), state)
		await _go(FORMATION)
		_screen().get_node("%AvailableList").get_child(0).pressed.emit()
		_screen().get_node("%ConfirmButton").pressed.emit()
		await get_tree().process_frame
		assert_eq(_screen().scene_file_path, HOME)
		assert_not_null(GameState.current_party)
		assert_eq(GameState.current_party.heroes()[0].status, HeroData.HeroStatus.ASSIGNED)
		assert_true(PartyFormationService.disband())


func test_every_mode_keeps_recruitment_and_save_results_functional() -> void:
	await _boot()
	for mode in UIDiagnostics.Mode.values():
		UIManager.diagnostics.select_mode(mode)
		GameState.gold = 100
		var size_before := GameState.roster.size()
		await _go(ROSTER)
		var id := GameState.recruitment_offers[0].hero_id
		_screen().get_node("%OfferList").get_child(0).get_node("Content/RecruitButton").pressed.emit()
		assert_true(SaveManager.last_committed, SaveManager.last_error)
		assert_eq(GameState.gold, 0)
		assert_eq(GameState.roster.size(), size_before + 1)
		assert_not_null(GameState.find_hero(id))
		await _go(HOME)


func test_navigation_construction_layout_and_real_draw_have_distinct_markers() -> void:
	await _boot()
	await _go(ROSTER)
	var stages := _stages()
	for stage in ["navigation.begin", "navigation.before_load", "navigation.after_instantiate",
			"navigation.before_ready", "hero.roster.0.begin", "hero.header.constructed",
			"hero.roster.0.added", "navigation.after_ready", "layout.root_sized"]:
		assert_true(stages.has(stage), stage)
	assert_lt(stages.find("navigation.before_ready"), stages.find("hero.roster.0.begin"))
	assert_lt(stages.find("hero.roster.0.added"), stages.find("navigation.after_ready"))
	var margin_stages := [
		"layout.screen_margins.begin",
		"layout.screen_margins.calculation.begin",
		"layout.screen_margins.calculation.end",
		"layout.screen_margins.overrides.begin",
		"layout.screen_margins.override.left.begin",
		"layout.screen_margins.override.left.end",
		"layout.screen_margins.override.top.begin",
		"layout.screen_margins.override.top.end",
		"layout.screen_margins.override.right.begin",
		"layout.screen_margins.override.right.end",
		"layout.screen_margins.override.bottom.begin",
		"layout.screen_margins.override.bottom.end",
		"layout.screen_margins.overrides.end",
		"layout.screen_margins.end",
	]
	for stage in margin_stages:
		assert_true(stages.has(stage), stage)
	for index in margin_stages.size() - 1:
		assert_lt(stages.find(margin_stages[index]), stages.find(margin_stages[index + 1]))
	if DisplayServer.get_name() == "headless":
		assert_true(stages.has("render.unavailable_headless"))
		assert_false(stages.has("render.first_draw.end"))
		assert_false(UIManager.diagnostics.last_record.first_draw_finished)
	else:
		await RenderingServer.frame_post_draw
		stages = _stages()
		assert_true(stages.has("render.first_draw.begin"))
		assert_true(stages.has("render.first_draw.end"))
		assert_lt(stages.find("navigation.after_ready"), stages.find("render.first_draw.begin"))
		assert_lt(stages.find("render.first_draw.begin"), stages.find("render.first_draw.end"))
		assert_true(UIManager.diagnostics.last_record.first_draw_finished)


func test_outgoing_callbacks_and_untracked_screens_cannot_overwrite_trace() -> void:
	await _boot()
	await _go(ROSTER)
	var probe := _screen().get_node("DiagnosticFrameProbe")
	var token := UIManager.diagnostics.generation
	UIManager.show_screen(HOME)
	UIManager.show_screen(FORMATION)
	await get_tree().process_frame
	assert_false(is_instance_valid(probe))
	UIManager.diagnostics.mark_for(token, "stale.callback")
	assert_false(_stages().has("stale.callback"))
	assert_eq(UIManager.diagnostics.last_record.screen, "Party Formation")
	await _go(HOME)
	var trace := FileAccess.get_file_as_bytes(_path())
	UIManager.diagnostics.mark("untracked.callback")
	assert_eq(FileAccess.get_file_as_bytes(_path()), trace)


func test_diagnostic_write_failure_does_not_change_save_manager_results() -> void:
	await _boot()
	var company := FileAccess.get_file_as_bytes(SaveManager.get_save_path())
	var results := [SaveManager.last_success, SaveManager.last_committed,
		SaveManager.last_error, SaveManager.last_warning]
	var diagnostics := UIDiagnostics.new()
	diagnostics.initialize(_isolation.directory.path_join("missing"), true)
	diagnostics.begin_navigation(ROSTER, _viewport)
	assert_false(diagnostics.last_error.is_empty())
	assert_eq(diagnostics.last_record, {})
	assert_eq(FileAccess.get_file_as_bytes(SaveManager.get_save_path()), company)
	assert_eq([SaveManager.last_success, SaveManager.last_committed,
		SaveManager.last_error, SaveManager.last_warning], results)
