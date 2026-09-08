extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
const HeroUI = preload("res://scenes/ui/hero_ui.gd")
const Art = preload("res://scenes/ui/art_catalog.gd")
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
		assert_lte(image.get_global_rect().end.x, 720.0, image.name)
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
