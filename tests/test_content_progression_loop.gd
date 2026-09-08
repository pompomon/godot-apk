extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
var _isolation: RefCounted
var _time := 1000


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	_time = 1000
	ExpeditionManager.clock = func() -> int: return _time
	SaveManager.load_or_create()
	assert_true(SaveManager.last_committed, SaveManager.last_error)


func after_each() -> void:
	_isolation.finish()


func test_normal_rewards_unlock_every_region_without_editing_gold_or_saves() -> void:
	var visited := {}
	for index in range(80):
		_time += 61
		ExpeditionManager.reveal_progress()
		var party := PartyData.new()
		for slot in range(4):
			assert_true(party.place_hero(slot, GameState.roster[slot]))
		assert_true(PartyFormationService.confirm(party, ExpeditionManager.balancing))
		var region := ExpeditionCatalog.GREEN_HOLLOW
		for candidate in ExpeditionCatalog.regions():
			if CompanyProgression.is_unlocked(candidate, GameState.unlocked_regions):
				region = candidate
		ExpeditionManager.start_expedition(region, GameState.current_party, region.duration_options_seconds[0])
		assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
		if not ExpeditionManager.last_committed:
			return
		visited[region.region_id] = true
		var run := ExpeditionManager.get_active_expedition()
		_time += region.duration_options_seconds[0]
		ExpeditionManager.reveal_progress()
		assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
		assert_eq(run.status, ExpeditionData.Status.COMPLETED)
		var committed := SaveManager.capture_state()
		SaveManager.load_or_create()
		assert_eq(SaveManager.capture_state(), committed, "Reload must not duplicate earned rewards.")
		ExpeditionManager.acknowledge_report(ExpeditionManager.get_active_expedition())
		assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
		if visited.size() == 3:
			break
	assert_eq(visited.size(), 3, "Authored rewards must support reaching and visiting all three Regions.")
	assert_eq(GameState.unlocked_regions, [&"green_hollow", &"ashen_reach", &"frostbound_pass"])
	assert_eq(GameState.roster_capacity, 20)
	assert_gt(GameState.roster[0].xp, 0)
