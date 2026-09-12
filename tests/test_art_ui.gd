extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
const HeroUI = preload("res://scenes/ui/hero_ui.gd")
const Art = preload("res://scenes/ui/art_catalog.gd")
const ScreenMargin = preload("res://scenes/ui/screen_margin.gd")
const HOME := "res://scenes/ui/home/home_screen.tscn"
const ROSTER := "res://scenes/ui/roster/roster_screen.tscn"
const DETAIL := "res://scenes/ui/hero_detail/hero_detail_screen.tscn"
const EQUIPMENT := "res://scenes/ui/equipment/equipment_screen.tscn"
const FORMATION := "res://scenes/ui/party_formation/party_formation_screen.tscn"
const REGION := "res://scenes/ui/region_select/region_select_screen.tscn"
const REPORT := "res://scenes/ui/expedition_report/expedition_report_screen.tscn"
var _isolation: RefCounted
var _main: Control
var _viewport: SubViewport
var _auto_accept_quit: bool
var _time := 1000


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	_auto_accept_quit = get_tree().auto_accept_quit
	_time = 1000
	ExpeditionManager.clock = func() -> int: return _time
	_viewport = add_child_autofree(SubViewport.new())
	_viewport.size = Vector2i(720, 1280)
	_main = load("res://main.tscn").instantiate()
	_viewport.add_child(_main)
	await get_tree().process_frame
	assert_true(SaveManager.last_success, SaveManager.last_error)


func after_each() -> void:
	_main.free()
	await get_tree().process_frame
	get_tree().auto_accept_quit = _auto_accept_quit
	_isolation.finish()


func _screen() -> Control:
	return _main.get_node("ScreenRoot").get_child(0)


func _node(name: String) -> Node:
	return _screen().find_child(name, true, false)


func _go(path: String, hero_id: String = "hero-1") -> void:
	UIManager.show_screen(path, {"hero_id": hero_id})
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, path)


func test_offer_portrait_survives_purchase_reordering_progression_and_reload() -> void:
	var offer := GameState.recruitment_offers[0]
	var id := offer.hero_id
	var expected := HeroUI.portrait_texture(offer)
	await _go(ROSTER)
	var card := _node("OfferList").get_child(0)
	assert_same(card.find_child("Portrait", true, false).texture, expected)
	card.get_node("Content/RecruitButton").pressed.emit()
	assert_same(GameState.find_hero(id), offer)
	var row := _node("RosterList").get_child(4)
	assert_same(row.find_child("Portrait", true, false).texture, expected)
	GameState.roster.reverse()
	assert_true(Leveling.grant_xp(offer, 100))
	offer.equipped_weapon = ItemCatalog.SHORT_SWORD
	offer.status = HeroData.HeroStatus.RESTING
	offer.recovery_ready_at = 1060
	SaveManager.save()
	assert_true(SaveManager.last_committed, SaveManager.last_error)
	SaveManager.load_or_create()
	await _go(DETAIL, id)
	assert_same(_node("Portrait").texture, expected)
	assert_same(_node("StatusIcon").texture, Art.status_icon(HeroData.HeroStatus.RESTING))
	assert_same(_node("WeaponIcon").texture, Art.item_icon("short_sword"))


func test_presenting_art_preserves_save_state_and_gameplay_seeds() -> void:
	var before := SaveManager.capture_state()
	var disk := FileAccess.get_file_as_string(SaveManager.get_save_path())
	for hero in GameState.roster + GameState.recruitment_offers:
		var row := HeroUI.hero_row(hero, func() -> void: pass)
		add_child_autofree(row)
		HeroUI.refresh_hero_header(row, hero)
		assert_same(row.find_child("Portrait", true, false).texture, HeroUI.portrait_texture(hero))
	assert_eq(SaveManager.capture_state(), before)
	assert_eq(FileAccess.get_file_as_string(SaveManager.get_save_path()), disk)


func test_equipment_icons_follow_draft_but_cancel_and_failed_confirm_preserve_ownership() -> void:
	GameState.inventory.assign([ItemCatalog.SHORT_SWORD])
	SaveManager.save()
	assert_true(SaveManager.last_committed)
	var before := SaveManager.capture_state()
	var portrait := HeroUI.portrait_texture(GameState.roster[0])
	await _go(EQUIPMENT)
	assert_same(_node("WeaponButton").icon, Art.equipment_icon(null, "Weapon"))
	assert_same(_node("Item_short_sword").icon, Art.item_icon("short_sword"))
	_node("Item_short_sword").pressed.emit()
	assert_same(_node("WeaponButton").icon, Art.item_icon("short_sword"))
	assert_same(_node("Portrait").texture, portrait)
	assert_eq(SaveManager.capture_state(), before)
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "before_primary_replace"
	_node("ConfirmButton").pressed.emit()
	assert_same(_node("WeaponButton").icon, Art.item_icon("short_sword"))
	assert_eq(SaveManager.capture_state(), before)
	_node("CancelButton").pressed.emit()
	await get_tree().process_frame
	assert_same(_node("WeaponIcon").texture, Art.equipment_icon(null, "Weapon"))
	SaveManager.fault_injector = Callable()
	await _go(EQUIPMENT)
	_node("Item_short_sword").pressed.emit()
	_node("ConfirmButton").pressed.emit()
	await get_tree().process_frame
	assert_same(_node("WeaponIcon").texture, Art.item_icon("short_sword"))
	assert_eq(_node("WeaponIcon").custom_minimum_size, Vector2(64, 64))
	assert_same(_node("Portrait").texture, portrait)


func test_formation_uses_stable_portraits_and_an_explicit_row_hint() -> void:
	var hero := GameState.roster[0]
	var before := SaveManager.capture_state()
	await _go(FORMATION)
	var row := _node("AvailableList").get_child(0)
	assert_eq(row.find_child("DetailHint", true, false).text, "Place in selected slot")
	assert_same(row.find_child("Portrait", true, false).texture, HeroUI.portrait_texture(hero))
	row.pressed.emit()
	var slot := _node("SlotGrid").get_child(0)
	assert_same(slot.get_node("Portrait").texture, HeroUI.portrait_texture(hero))
	assert_eq(SaveManager.capture_state(), before)
	_node("CancelButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(SaveManager.capture_state(), before)


func test_roster_gold_decoration_preserves_header_width_and_height() -> void:
	for amount in [100, 1000000]:
		GameState.gold = amount
		await _go(ROSTER)
		await get_tree().process_frame
		await get_tree().process_frame
		var gold: Label = _node("GoldLabel")
		var line := gold.get_parent() as HBoxContainer
		var text_width := gold.get_theme_font("font").get_string_size(
			gold.text, HORIZONTAL_ALIGNMENT_LEFT, -1, gold.get_theme_font_size("font_size")).x
		assert_eq(line.size_flags_horizontal, Control.SIZE_EXPAND_FILL)
		assert_gte(gold.size.x, text_width, "Gold remains readable on one line beside roster capacity.")
		assert_lte(line.get_parent().size.y, 64.0, "The fixed header must not consume the roster scroll area.")
		assert_lte(_node("RosterCountLabel").get_global_rect().end.x, 720.0)


func _dispatch() -> void:
	var party := PartyData.new()
	for index in GameState.roster.size():
		assert_true(party.place_hero(index, GameState.roster[index]))
	assert_true(PartyFormationService.confirm(party, ExpeditionManager.balancing))
	ExpeditionManager.start_expedition(ExpeditionCatalog.GREEN_HOLLOW, GameState.current_party, 60)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)


func test_report_portraits_use_frozen_identity_not_live_roster_or_unrevealed_outcomes() -> void:
	_dispatch()
	var report := ExpeditionManager.get_active_expedition()
	var frozen := report.serialize()
	var member: Dictionary = report.party_snapshot.slots[PartyData.SLOT_NAMES[PartyData.FormationSlot.FRONT_LEFT]]
	var expected := Art.portrait(member.hero_id, member.class_id)
	GameState.roster[0].hero_class = HeroCatalog.RANGER
	await _go(REPORT)
	var portraits := _node("DispatchedPartyArt")
	assert_eq(portraits.get_child_count(), 4)
	assert_same(portraits.get_child(0).texture, expected)
	assert_string_contains(portraits.get_child(0).tooltip_text, member.class_name)
	assert_same(_node("RegionBackdrop").texture, Art.region(report.region_id))
	assert_null(_node("StepKindIcon"))
	assert_null(_node("OutcomeIcon"))
	assert_eq(report.serialize(), frozen)
	await _go(HOME)
	await _go(REPORT)
	assert_same(_node("DispatchedPartyArt").get_child(0).texture, expected)


func test_report_only_adds_matching_encounter_art_after_each_step_is_revealed() -> void:
	_dispatch()
	var report := ExpeditionManager.get_active_expedition()
	var frozen := report.serialize()
	await _go(REPORT)
	assert_null(_node("EncounterArt"))
	for cursor in report.steps.size():
		_time = report.start_timestamp + (cursor + 1) * report.step_duration_seconds
		ExpeditionManager.observe_foreground()
		var row := _node("Step%d" % cursor)
		assert_not_null(row)
		var art := row.find_child("EncounterArt", true, false) as TextureRect
		var step: ExpeditionStep = report.steps[cursor]
		match step.kind:
			ExpeditionStep.StepKind.COMBAT:
				assert_not_null(art)
				assert_same(art.texture, Art.enemy(step.content_id))
			ExpeditionStep.StepKind.EVENT:
				assert_not_null(art)
				assert_same(art.texture, Art.event(step.content_id))
			_:
				assert_null(art)
		if cursor + 1 < report.steps.size():
			assert_null(_node("Step%d" % (cursor + 1)))
	assert_eq(report.serialize().steps, frozen.steps)


func test_shared_theme_decorations_and_design_touch_targets_cover_every_screen() -> void:
	var decorations := {
		HOME: {"HomeCrest": Art.decoration("home_crest"), "SectionDivider": Art.decoration("section_divider")},
		ROSTER: {"SectionDivider": Art.decoration("section_divider")},
		DETAIL: {"SectionDivider": Art.decoration("section_divider")},
		EQUIPMENT: {"SectionDivider": Art.decoration("section_divider")},
		FORMATION: {"FormationEmblem": Art.decoration("formation_emblem")},
		REGION: {"SectionDivider": Art.decoration("section_divider")},
	}
	for path in decorations:
		await _go(path)
		await get_tree().process_frame
		_assert_presentation_foundation(decorations[path])
	_dispatch()
	await _go(REPORT)
	await get_tree().process_frame
	_assert_presentation_foundation({"SectionDivider": Art.decoration("section_divider")})


func test_presentation_palette_meets_text_contrast_targets_and_never_uses_color_alone() -> void:
	assert_gte(_contrast(HeroUI.TEXT_COLOR, HeroUI.BACKGROUND_COLOR), 4.5)
	assert_gte(_contrast(HeroUI.MUTED_COLOR, HeroUI.BACKGROUND_COLOR), 4.5)
	assert_gte(_contrast(HeroUI.NOTICE_COLOR, HeroUI.BACKGROUND_COLOR), 4.5)
	assert_gte(_contrast(HeroUI.TEXT_COLOR, HeroUI.BUTTON_COLOR), 4.5)
	var hero := GameState.roster[0]
	for status in HeroData.HeroStatus.values():
		hero.status = status
		var badge := HeroUI.status_badge(hero)
		add_child_autofree(badge)
		assert_eq(badge.text, HeroUI.status_name(hero))
		assert_same(Art.status_icon(status), Art.STATUSES[status])
		assert_gte(_contrast(HeroUI.BADGE_TEXT_COLOR, HeroUI.status_badge_color(status)), 4.5)
		var style := badge.get_theme_stylebox("normal") as StyleBoxFlat
		assert_eq(style.bg_color, HeroUI.status_badge_color(status))


func test_visible_copy_has_no_known_placeholder_language() -> void:
	for path in [HOME, ROSTER, DETAIL, EQUIPMENT, FORMATION, REGION]:
		await _go(path)
		var copy := _visible_text(_screen()).to_lower()
		for placeholder in ["lorem ipsum", "todo", "expeditions are not available yet"]:
			assert_false(copy.contains(placeholder), "%s contains %s" % [path, placeholder])


func test_all_seven_screens_keep_art_crisp_passive_and_inside_portrait_width() -> void:
	GameState.roster[0].hero_name = "Alexandria of the Distant Northern Mountains and Moonlit Lakes"
	for path in [HOME, ROSTER, DETAIL, EQUIPMENT, FORMATION, REGION]:
		await _go(path)
		await _check_art_bounds()
		await _capture_preview(path.get_base_dir().get_file())
	for region in ExpeditionCatalog.regions():
		assert_same(_node("RegionBackdrop_%s" % region.region_id).texture, Art.region(String(region.region_id)))
	assert_same(_node("RegionButton_ashen_reach").icon, Art.utility_icon("locked"))
	_dispatch()
	await _go(REPORT)
	_time = 1012
	ExpeditionManager.reveal_progress()
	await _check_art_bounds()
	await _capture_preview("expedition_report")


func test_all_screens_resize_with_target_static_margins_and_no_horizontal_overflow() -> void:
	_dispatch()
	for path in [HOME, ROSTER, DETAIL, EQUIPMENT, FORMATION, REGION, REPORT]:
		await _go(path)
		var margin: MarginContainer = _node("Margin")
		var target_static: bool = path == ROSTER or path == FORMATION
		var authored_margins := PackedInt32Array([
			margin.get_theme_constant("margin_left"),
			margin.get_theme_constant("margin_top"),
			margin.get_theme_constant("margin_right"),
			margin.get_theme_constant("margin_bottom"),
		])
		if target_static:
			assert_null(margin.get_script())
		else:
			assert_same(margin.get_script(), ScreenMargin)
		for extent in [
			Vector2i(720, 1280), Vector2i(720, 1600), Vector2i(960, 1280),
			Vector2i(1065, 1280), Vector2i(720, 1280),
		]:
			_viewport.size = extent
			await _check_art_bounds()
			assert_eq(_screen().size, Vector2(extent))
			if target_static:
				assert_eq(PackedInt32Array([
					margin.get_theme_constant("margin_left"),
					margin.get_theme_constant("margin_top"),
					margin.get_theme_constant("margin_right"),
					margin.get_theme_constant("margin_bottom"),
				]), authored_margins)
			else:
				assert_lte(margin.get_child(0).size.x, ScreenMargin.MAX_CONTENT_WIDTH)
				assert_lte(absi(
					margin.get_theme_constant("margin_left")
					- margin.get_theme_constant("margin_right")
				), 1)
				assert_false(margin.get("_update_queued"))
				assert_false(margin.get("_updating"))
				assert_false(margin.resized.is_connected(Callable(margin, "_update_margins")))
			_check_control_widths(_screen(), extent.x)
			await _capture_preview("%s_%dx%d" % [path.get_base_dir().get_file(), extent.x, extent.y])


func test_screen_margins_defer_coalesce_and_skip_unchanged_updates() -> void:
	await _go(DETAIL)
	await get_tree().process_frame
	var margin := _node("Margin") as MarginContainer
	assert_eq(margin.get("_applied_margins"), PackedInt32Array([24, 24, 24, 24]))
	assert_false(margin.resized.is_connected(Callable(margin, "_update_margins")))
	assert_true(_viewport.size_changed.is_connected(Callable(margin, "_queue_margin_update")))
	watch_signals(margin)
	_viewport.size = Vector2i(960, 1280)
	margin.notification(NOTIFICATION_APPLICATION_RESUMED)
	margin.notification(NOTIFICATION_APPLICATION_RESUMED)
	assert_true(margin.get("_update_queued"))
	assert_eq([
		margin.get_theme_constant("margin_left"),
		margin.get_theme_constant("margin_top"),
		margin.get_theme_constant("margin_right"),
		margin.get_theme_constant("margin_bottom"),
	], [24, 24, 24, 24])
	await get_tree().process_frame
	assert_false(margin.get("_update_queued"))
	assert_eq([
		margin.get_theme_constant("margin_left"),
		margin.get_theme_constant("margin_top"),
		margin.get_theme_constant("margin_right"),
		margin.get_theme_constant("margin_bottom"),
	], [60, 24, 60, 24])
	assert_signal_emit_count(margin, "theme_changed", 1)
	assert_false(margin.get("_updating"))
	margin.notification(NOTIFICATION_APPLICATION_RESUMED)
	margin.notification(NOTIFICATION_APPLICATION_RESUMED)
	await get_tree().process_frame
	assert_signal_emit_count(margin, "theme_changed", 1)
	assert_false(margin.get("_update_queued"))
	assert_false(margin.get("_updating"))


func test_queued_screen_margin_update_ignores_a_detached_control() -> void:
	var margin := autofree(ScreenMargin.new()) as MarginContainer
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(margin)
	assert_true(margin.get("_update_queued"))
	_viewport.remove_child(margin)
	await get_tree().process_frame
	assert_false(margin.get("_update_queued"))
	assert_eq(margin.get("_applied_margins"), PackedInt32Array())


func test_safe_area_conversion_handles_scaling_window_offsets_and_invalid_rects() -> void:
	var extent := Vector2(720, 1600)
	var scaled := Transform2D(Vector2(1.5, 0), Vector2(0, 1.5), Vector2.ZERO)
	assert_eq(ScreenMargin.local_safe_rect(extent, Rect2(0, 60, 1080, 2280), scaled),
		Rect2(0, 40, 720, 1520))
	# A client window already below a system bar must not acquire that inset again.
	var offset := Transform2D(Vector2(1.5, 0), Vector2(0, 1.5), Vector2(0, 60))
	assert_eq(ScreenMargin.local_safe_rect(extent, Rect2(0, 60, 1080, 2400), offset),
		Rect2(Vector2.ZERO, extent))
	assert_eq(ScreenMargin.local_safe_rect(extent, Rect2(), scaled), Rect2(Vector2.ZERO, extent))
	assert_eq(ScreenMargin.local_safe_rect(extent, Rect2(-20, -20, 1200, 2500), scaled),
		Rect2(Vector2.ZERO, extent))
	assert_eq(ScreenMargin.local_safe_rect(extent, Rect2(5000, 5000, 20, 20), scaled),
		Rect2(Vector2.ZERO, extent))
	assert_eq(ScreenMargin.local_safe_rect(extent, Rect2(0, 60, 1080, 2280),
		Transform2D(Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)), Rect2(Vector2.ZERO, extent))


func _check_control_widths(parent: Node, width: float) -> void:
	for child in parent.get_children():
		if child is Control and child.is_visible_in_tree():
			assert_gte(child.get_global_rect().position.x, 0.0, str(child.get_path()))
			assert_lte(child.get_global_rect().end.x, width, str(child.get_path()))
		_check_control_widths(child, width)


func _visible_text(parent: Node) -> String:
	var result := ""
	if parent is Label and parent.visible:
		result += parent.text + "\n"
	elif parent is BaseButton and parent.visible:
		result += parent.text + "\n"
	for child in parent.get_children():
		result += _visible_text(child)
	return result


func _assert_presentation_foundation(decorations: Dictionary) -> void:
	var background := _node("Background") as ColorRect
	assert_not_null(background)
	assert_eq(background.color, HeroUI.BACKGROUND_COLOR)
	assert_not_null(_screen().theme)
	assert_true(_screen().theme.has_stylebox("normal", "Button"))
	assert_true(_screen().theme.has_stylebox("focus", "Button"))
	assert_true(_screen().theme.has_stylebox("normal", "OptionButton"))
	assert_true(_screen().theme.has_stylebox("fill", "ProgressBar"))
	assert_true(_screen().theme.has_stylebox("grabber", "VScrollBar"))
	for node_name in decorations:
		var image := _node(node_name) as TextureRect
		assert_not_null(image)
		assert_same(image.texture, decorations[node_name])
		assert_eq(image.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
		assert_eq(image.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	_assert_touch_targets(_screen())


func _assert_touch_targets(parent: Node) -> void:
	for child in parent.get_children():
		if child is BaseButton:
			assert_gte(child.get_combined_minimum_size().y, 96.0, str(child.get_path()))
		_assert_touch_targets(child)


func _contrast(first: Color, second: Color) -> float:
	var light := maxf(_luminance(first), _luminance(second))
	var dark := minf(_luminance(first), _luminance(second))
	return (light + 0.05) / (dark + 0.05)


func _luminance(color: Color) -> float:
	return (
		0.2126 * _linear_channel(color.r)
		+ 0.7152 * _linear_channel(color.g)
		+ 0.0722 * _linear_channel(color.b)
	)


func _linear_channel(value: float) -> float:
	return value / 12.92 if value <= 0.04045 else pow((value + 0.055) / 1.055, 2.4)


func _check_art_bounds() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var images := _art_images(_screen())
	assert_gt(images.size(), 0)
	for image in images:
		assert_not_null(image.texture)
		assert_eq(image.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, str(image.get_path()))
		assert_eq(image.mouse_filter, Control.MOUSE_FILTER_IGNORE)
		assert_eq(image.focus_mode, Control.FOCUS_NONE)
		assert_eq(image.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED, str(image.get_path()))
		assert_lte(image.get_global_rect().end.x, float(_viewport.size.x), image.name)
		assert_gte(image.get_global_rect().position.x, 0.0, image.name)


func _art_images(parent: Node) -> Array[TextureRect]:
	var images: Array[TextureRect] = []
	# find_children also returns Godot's internal overscroll TextureRects.
	for child in parent.get_children():
		if child is TextureRect:
			images.append(child)
		images.append_array(_art_images(child))
	return images


func _capture_preview(name: String) -> void:
	# Optional desktop evidence from the same UI test; never write during headless CI.
	var directory := OS.get_environment("ART_PREVIEW_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	assert_true(directory.begins_with("/tmp/"))
	if not directory.begins_with("/tmp/"):
		return
	assert_eq(DirAccess.make_dir_recursive_absolute(directory), OK)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await RenderingServer.frame_post_draw
	assert_eq(_viewport.get_texture().get_image().save_png(directory.path_join(name + ".png")), OK)
