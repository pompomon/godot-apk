extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
const REPORT := "res://scenes/ui/expedition_report/expedition_report_screen.tscn"
var _isolation: RefCounted
var _main: Control
var _root: Control
var _time := 1000
var _auto_accept_quit: bool


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	_time = 1000
	ExpeditionManager.clock = func() -> int: return _time
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


func _go(path: String, context: Dictionary = {}) -> void:
	UIManager.show_screen(path, context)
	await get_tree().process_frame
	assert_eq(_root.get_child(0).scene_file_path, path)


func _text(node: Node) -> String:
	var text: String = node.text + "\n" if node is Label or node is Button else ""
	for child in node.get_children():
		text += _text(child)
	return text


func test_authored_loot_and_event_rewards_are_reachable_and_seed_deterministic() -> void:
	var party := PartyData.new()
	for index in range(4):
		party.place_hero(index, GameState.roster[index])
	var found_loot := false
	var found_event := false
	for seed_value in range(64):
		var run := ExpeditionGenerator.generate(ExpeditionCatalog.GREEN_HOLLOW, party,
			seed_value, 60, _time, ExpeditionManager.balancing)
		assert_not_null(run)
		if run == null:
			return
		var repeated := ExpeditionGenerator.generate(ExpeditionCatalog.GREEN_HOLLOW, party,
			seed_value, 60, _time, ExpeditionManager.balancing)
		assert_eq(JSON.stringify(run.serialize(), "", true, true),
			JSON.stringify(repeated.serialize(), "", true, true))
		for step in run.steps:
			if not step.result.get("item_ids", []).is_empty():
				found_loot = found_loot or step.kind == ExpeditionStep.StepKind.LOOT
				found_event = found_event or step.kind == ExpeditionStep.StepKind.EVENT
		if found_loot and found_event:
			break
	assert_true(found_loot, "The authored Loot pool must produce equipment.")
	assert_true(found_event, "An authored Event must produce equipment.")
	assert_eq(ExpeditionCatalog.LOOT.item_pool.size(), 6)
	assert_eq(ExpeditionCatalog.LOOT.item_drop_chance, 0.5)


func test_live_loop_reveals_committed_rewards_levels_equips_and_reloads_without_duplicates() -> void:
	var party := PartyData.new()
	for index in range(4):
		var hero := GameState.roster[index]
		hero.xp = 90
		party.place_hero(index, hero)
	var selected_seed := -1
	for seed_value in range(64):
		var candidate := ExpeditionGenerator.generate(ExpeditionCatalog.GREEN_HOLLOW, party,
			seed_value, 60, _time, ExpeditionManager.balancing)
		if candidate == null:
			continue
		for step in candidate.steps:
			if not step.result.get("item_ids", []).is_empty():
				selected_seed = seed_value
				break
		if selected_seed >= 0:
			break
	assert_gte(selected_seed, 0)
	if selected_seed < 0:
		return
	GameState.expedition_seed = selected_seed
	GameState.expedition_sequence = 0
	assert_true(PartyFormationService.confirm(party, ExpeditionManager.balancing))
	ExpeditionManager.start_expedition(ExpeditionCatalog.GREEN_HOLLOW, GameState.current_party, 60)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	var run := ExpeditionManager.get_active_expedition()
	var frozen := run.serialize()
	var expected_ids: Array = []
	var expected_gold := GameState.gold
	for step in run.steps:
		expected_ids.append_array(step.result.get("item_ids", []))
		expected_gold += int(step.result.gold)
	await _go(REPORT)
	assert_false(_text(_root.get_child(0)).contains("Item:"))
	assert_false(_text(_root.get_child(0)).contains("XP credited:"))
	assert_eq(GameState.inventory.size(), 0)
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "before_primary_replace"
	_time = 1060
	ExpeditionManager.reveal_progress()
	assert_false(ExpeditionManager.last_committed)
	assert_eq(GameState.inventory.size(), 0)
	assert_eq(GameState.roster[0].xp, 90)
	assert_false(_text(_root.get_child(0)).contains("Item:"))
	SaveManager.fault_injector = Callable()
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(GameState.gold, expected_gold)
	assert_eq(GameState.inventory.size(), expected_ids.size())
	assert_string_contains(_text(_root.get_child(0)), "XP credited: +%d" % run.xp_award)
	for id in expected_ids:
		assert_string_contains(_text(_root.get_child(0)), "Item: " + ItemCatalog.item_by_id(id).display_name)
	for hero in GameState.roster:
		assert_eq(hero.xp, 90 + run.xp_award)
		assert_gt(hero.level, 1)
	var committed := SaveManager.capture_state()
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), committed)
	assert_eq(ExpeditionManager.get_active_expedition().serialize().steps, frozen.steps)
	var hero := GameState.roster[0]
	var item: ItemResource = GameState.inventory[0]
	var draft := EquipmentService.new(hero)
	if item.slot == "Weapon":
		draft.weapon = item
	else:
		draft.armor = item
	var preview := draft.preview_stats()
	assert_true(draft.confirm(), draft.last_error)
	assert_eq(HeroStats.compute_derived_stats(hero), preview)
	assert_eq(GameState.inventory.size(), expected_ids.size() - 1)
	assert_eq(ExpeditionManager.get_active_expedition().serialize().party_snapshot, frozen.party_snapshot)
	committed = SaveManager.capture_state()
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), committed)
	ExpeditionManager.acknowledge_report(ExpeditionManager.get_active_expedition())
	assert_true(ExpeditionManager.last_committed)
	ExpeditionManager.reveal_progress()
	assert_eq(GameState.roster[0].xp, 90 + run.xp_award)
	assert_eq(GameState.inventory.size(), expected_ids.size() - 1)
