extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
const DETAIL := "res://scenes/ui/hero_detail/hero_detail_screen.tscn"
const EQUIPMENT := "res://scenes/ui/equipment/equipment_screen.tscn"
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
	assert_true(SaveManager.last_success)
	GameState.inventory.assign([ItemCatalog.SHORT_SWORD, ItemCatalog.SHORT_SWORD,
		ItemCatalog.LEATHER_ARMOR])
	SaveManager.save()
	assert_true(SaveManager.last_committed, SaveManager.last_error)


func after_each() -> void:
	_main.free()
	await get_tree().process_frame
	get_tree().auto_accept_quit = _auto_accept_quit
	_isolation.finish()


func _screen() -> Control:
	return _root.get_child(0)


func _node(node_name: String) -> Node:
	return _screen().find_child(node_name, true, false)


func _selector() -> Control:
	return _screen().get_node("EquipmentSelector") as Control


func _options() -> VBoxContainer:
	return _selector().find_child("ModalOptions", true, false) as VBoxContainer


func _open_items(slot: String = "Weapon") -> void:
	_node("%sButton" % slot).pressed.emit()
	assert_true(_selector().visible)


func _go(path: String, id: String = "hero-1") -> void:
	UIManager.show_screen(path, {"hero_id": id})
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, path)


func test_detail_navigation_preview_cancel_and_android_back_are_draft_only() -> void:
	await _go(DETAIL)
	_node("EquipmentButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, EQUIPMENT)
	var before := SaveManager.capture_state()
	_open_items()
	_node("Item_short_sword").pressed.emit()
	assert_string_contains(_node("StatPreview").text, "Attack:")
	assert_string_contains(_node("StatPreview").text, "→")
	assert_string_contains(_node("SlotsLabel").text, "Short Sword")
	assert_eq(SaveManager.capture_state(), before)
	_main.notification(NOTIFICATION_APPLICATION_PAUSED)
	assert_eq(SaveManager.capture_state(), before)
	_node("CancelButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, DETAIL)
	assert_string_contains(_node("WeaponLabel").text, "Empty")
	await _go(EQUIPMENT)
	_open_items()
	_main.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, EQUIPMENT)
	assert_false(_selector().visible)
	_open_items()
	_node("Item_short_sword").pressed.emit()
	_main.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, DETAIL)
	assert_eq(SaveManager.capture_state(), before)


func test_confirm_retry_unequip_and_correct_detail_refresh() -> void:
	await _go(EQUIPMENT)
	_open_items()
	assert_string_contains(_node("Item_short_sword").text, "×2")
	_node("Item_short_sword").pressed.emit()
	_node("ArmorButton").pressed.emit()
	_node("Item_leather_armor").pressed.emit()
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "before_primary_replace"
	_node("ConfirmButton").pressed.emit()
	assert_eq(_screen().scene_file_path, EQUIPMENT)
	assert_string_contains(_node("FeedbackLabel").text, "not saved")
	assert_null(GameState.roster[0].equipped_weapon)
	SaveManager.fault_injector = Callable()
	_node("ConfirmButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, DETAIL)
	assert_string_contains(_node("WeaponLabel").text, ItemCatalog.SHORT_SWORD.display_name)
	assert_string_contains(_node("ArmorLabel").text, ItemCatalog.LEATHER_ARMOR.display_name)
	assert_eq(GameState.inventory.size(), 1)
	await _go(EQUIPMENT)
	_open_items()
	_node("UnequipButton").pressed.emit()
	_node("ConfirmButton").pressed.emit()
	await get_tree().process_frame
	assert_null(GameState.roster[0].equipped_weapon)
	assert_eq(GameState.inventory.size(), 2)


func test_empty_inventory_missing_hero_and_status_changes_are_safe() -> void:
	GameState.inventory.clear()
	await _go(EQUIPMENT)
	_open_items()
	assert_null(_node("Item_short_sword"))
	assert_string_contains(_node("ModalEmptyLabel").text, "No weapon")
	await _go(EQUIPMENT, "missing-hero")
	assert_true(_node("ConfirmButton").disabled)
	_node("CancelButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(_screen().scene_file_path, ROSTER)
	await _go(EQUIPMENT)
	GameState.roster[0].status = HeroData.HeroStatus.ON_EXPEDITION
	ExpeditionManager.changed.emit()
	assert_true(_node("ConfirmButton").disabled)
	assert_string_contains(_node("FeedbackLabel").text, GameState.roster[0].status_label())


func test_open_detail_refreshes_xp_stats_and_recovery_after_commit_signal() -> void:
	await _go(DETAIL)
	var hero := GameState.roster[0]
	var old_attack: String = _node("AttackValue").text
	assert_true(Leveling.grant_xp(hero, 100))
	hero.status = HeroData.HeroStatus.RESTING
	hero.recovery_ready_at = 1060
	SaveManager.save()
	assert_true(SaveManager.last_committed, SaveManager.last_error)
	ExpeditionManager.changed.emit()
	assert_string_contains(_node("HeroSummaryLabel").text, "Level 2")
	assert_string_contains(_node("XPLabel").text, "100")
	assert_string_contains(_node("RecoveryNotice").text, "UTC")
	assert_ne(_node("AttackValue").text, old_attack)
	assert_false(_node("EquipmentButton").disabled)
	assert_eq(_node("XPProgressBar").value, 0.0)


func test_portrait_equipment_uses_scroll_and_touch_targets() -> void:
	_main.size = Vector2(720, 1280)
	await _go(EQUIPMENT)
	_open_items()
	await get_tree().process_frame
	var scroll := _screen().get_node("Margin/Scroll") as ScrollContainer
	var picker_scroll := _node("ModalScroll") as ScrollContainer
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	assert_eq(picker_scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	for name in ["WeaponButton", "ArmorButton", "ConfirmButton", "CancelButton",
			"Item_short_sword", "ModalCloseButton"]:
		var button := _node(name) as Button
		assert_gte(button.custom_minimum_size.y, 96.0, name)
		assert_eq(button.mouse_filter, Control.MOUSE_FILTER_PASS)
		assert_lte(button.size.x, 720.0, name)


func test_detail_prioritizes_equipment_before_attributes_and_progression() -> void:
	await _go(DETAIL)
	var content := _node("HeroContent")
	assert_lt(_node("EquipmentHeading").get_index(), _node("AttributesAndStats").get_index())
	assert_lt(_node("EquipmentButton").get_index(), _node("ProgressionHeading").get_index())
	assert_same(_node("EquipmentHeading").get_parent(), content)


func test_item_picker_filters_slots_and_blocks_the_screen_until_closed() -> void:
	await _go(EQUIPMENT)
	_open_items("Weapon")
	assert_string_contains(_node("ModalTitle").text, "weapon")
	assert_not_null(_node("Item_short_sword"))
	assert_null(_node("Item_leather_armor"))
	assert_eq(_selector().mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_eq(_selector().get_global_rect(), _screen().get_global_rect())
	_node("ModalCloseButton").pressed.emit()
	assert_false(_selector().visible)
	assert_eq(_options().get_child_count(), 0)
	_open_items("Armor")
	assert_string_contains(_node("ModalTitle").text, "armor")
	assert_null(_node("Item_short_sword"))
	assert_not_null(_node("Item_leather_armor"))
