extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
const STAGES := ["before_temp_write", "after_temp_validation", "after_backup_preparation",
	"after_backup_replace", "before_primary_replace", "after_primary_replace"]
var _isolation: RefCounted
var _time := 1000
var _pool: Array[EncounterEntryResource]
var _items: Dictionary
var _chance: float
var _outcomes: Array[EventOutcomeResource]
var _loot: LootResource = ExpeditionCatalog.LOOT
var _region: RegionResource = ExpeditionCatalog.GREEN_HOLLOW
var _event: EventResource = ExpeditionCatalog.EVENTS[0]


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	_pool = ExpeditionCatalog.GREEN_HOLLOW.encounter_pool.duplicate()
	_items = ExpeditionCatalog.LOOT.item_pool.duplicate()
	_chance = ExpeditionCatalog.LOOT.item_drop_chance
	_outcomes = ExpeditionCatalog.EVENTS[0].outcomes.duplicate()
	_time = 1000
	ExpeditionManager.clock = func() -> int: return _time
	ExpeditionManager.balancing = ExpeditionManager.DEFAULT_BALANCING.duplicate(true)
	SaveManager.load_or_create()
	var entry := EncounterEntryResource.new()
	entry.kind = "Loot"
	entry.content_id = ExpeditionCatalog.LOOT.loot_id
	entry.weight = 1
	_region.encounter_pool.assign([entry])
	_loot.item_pool = {"short_sword": 1.0}
	_loot.item_drop_chance = 1.0


func after_each() -> void:
	_region.encounter_pool.assign(_pool)
	_loot.item_pool = _items
	_loot.item_drop_chance = _chance
	_event.outcomes.assign(_outcomes)
	_isolation.finish()


func _start() -> ExpeditionData:
	var party := PartyData.new()
	party.place_hero(0, GameState.roster[0])
	party.place_hero(3, GameState.roster[1])
	assert_true(PartyFormationService.confirm(party, ExpeditionManager.balancing))
	ExpeditionManager.start_expedition(ExpeditionCatalog.GREEN_HOLLOW, GameState.current_party, 60)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	return ExpeditionManager.get_active_expedition()


func test_frozen_xp_uses_selected_duration_and_loot_and_event_share_reveal_transaction() -> void:
	var run := _start()
	assert_eq(run.xp_award, Leveling.award(ExpeditionCatalog.GREEN_HOLLOW.recommended_party_power, 60))
	var record := run.serialize()
	record.steps[3].kind = ExpeditionStep.StepKind.EVENT
	record.steps[3].content_id = String(ExpeditionCatalog.EVENTS[0].event_id)
	record.steps[3].outcome_id = "historical"
	record.steps[3].result = {"gold": 7, "item_ids": ["robes", "robes"]}
	ExpeditionManager.replace_from_save(record)
	SaveManager.save()
	run = ExpeditionManager.get_active_expedition()
	ExpeditionManager.balancing.xp_award_coefficients.clear()
	ExpeditionManager.balancing.base_recovery_seconds = -1
	ExpeditionManager.balancing.recovery_hp_percent = -1
	_time = 1024
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(GameState.inventory, [ItemCatalog.SHORT_SWORD, ItemCatalog.ROBES, ItemCatalog.ROBES])
	assert_eq(GameState.roster[0].xp, 0)
	_time = 1060
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(GameState.inventory.size(), 6)
	for index in [0, 1]:
		assert_eq(GameState.roster[index].xp, run.xp_award)
	assert_eq(GameState.roster[2].xp, 0)
	var saved := SaveManager.capture_state()
	SaveManager.load_or_create()
	ExpeditionManager.reveal_progress()
	assert_eq(SaveManager.capture_state(), saved)
	ExpeditionManager.acknowledge_report(ExpeditionManager.get_active_expedition())
	assert_eq(GameState.inventory.size(), 6)
	assert_eq(GameState.roster[0].xp, run.xp_award)


func test_finalization_preflights_every_hero_and_rolls_back_all_rewards_at_save_boundaries() -> void:
	for stage in STAGES:
		SaveManager.fault_injector = Callable()
		_time = 1000
		assert_true(RecruitmentService.initialize_new_game(12345))
		SaveManager.save()
		GameState.roster[0].xp = 90
		GameState.roster[1].xp = 90
		var run := _start()
		var before := SaveManager.capture_state()
		var heroes := GameState.roster.duplicate()
		SaveManager.fault_injector = func(boundary: String) -> bool: return stage == boundary
		_time = 1060
		ExpeditionManager.reveal_progress()
		if stage == "after_primary_replace":
			assert_true(ExpeditionManager.last_committed)
		else:
			assert_false(ExpeditionManager.last_committed)
			assert_eq(SaveManager.capture_state(), before, stage)
			assert_eq(GameState.inventory.size(), 0)
			assert_eq(GameState.roster[0].level, 1)
		for index in range(heroes.size()):
			assert_same(GameState.roster[index], heroes[index])
		SaveManager.fault_injector = Callable()
		ExpeditionManager.reveal_progress()
		assert_eq(GameState.inventory.size(), 5)
		assert_eq(GameState.roster[0].xp, 90 + run.xp_award)
		assert_gt(GameState.roster[0].level, 1)
		var committed := SaveManager.capture_state()
		SaveManager.load_or_create()
		ExpeditionManager.reveal_progress()
		assert_eq(SaveManager.capture_state(), committed)


func test_xp_overflow_prevents_first_hero_items_gold_cursor_and_clock_mutation() -> void:
	var run := _start()
	GameState.roster[1].xp = HeroCatalog.MAX_SAFE_INT
	SaveManager.save()
	var before := SaveManager.capture_state()
	_time = 1060
	ExpeditionManager.reveal_progress()
	assert_false(ExpeditionManager.last_committed)
	assert_eq(SaveManager.capture_state(), before)
	assert_same(ExpeditionManager.get_active_expedition(), run)
	GameState.roster[1].xp -= run.xp_award
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(GameState.roster[1].xp, HeroCatalog.MAX_SAFE_INT)


func test_zero_frozen_award_skips_relevel_and_current_curve_validation() -> void:
	var run := _start()
	var record := run.serialize()
	record.xp_award = 0
	ExpeditionManager.replace_from_save(record)
	GameState.roster[0].xp = 100000
	GameState.roster[0].level = 1
	ExpeditionManager.balancing.xp_threshold_curve.clear()
	_time = 1060
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(GameState.roster[0].xp, 100000)
	assert_eq(GameState.roster[0].level, 1)


func test_item_generation_is_seeded_ordered_bounded_and_disabled_without_extra_draws() -> void:
	var party := PartyData.new()
	party.place_hero(0, GameState.roster[0])
	var region := ExpeditionCatalog.GREEN_HOLLOW
	var config := ExpeditionManager.balancing
	_loot.item_pool = {}
	var empty := ExpeditionGenerator.generate(region, party, 42, 60, 1000, config)
	_loot.item_pool = {"short_sword": 1.0}
	_loot.item_drop_chance = 0.0
	var disabled := ExpeditionGenerator.generate(region, party, 42, 60, 1000, config)
	assert_eq(empty.serialize(), disabled.serialize())
	_loot.item_drop_chance = 1.0
	_loot.item_pool = {"robes": 0.0, "short_sword": 1.0, "chainmail": 0.0}
	var first := ExpeditionGenerator.generate(region, party, 42, 60, 1000, config)
	var again := ExpeditionGenerator.generate(region, party, 42, 60, 1000, config)
	assert_eq(first.serialize(), again.serialize())
	for step in first.steps:
		if step.kind == ExpeditionStep.StepKind.LOOT:
			assert_eq(step.result.item_ids, ["short_sword"])
		else:
			assert_eq(step.result, {"gold": 0})
	_loot.item_pool = {"short_sword": 1.0, "robes": 3.0}
	var weighted := ExpeditionGenerator.generate(region, party, 42, 60, 1000, config)
	var reference := RandomNumberGenerator.new()
	reference.seed = 42
	for index in range(5):
		reference.randf()
	for index in [1, 3, 5, 7, 9]:
		assert_eq(weighted.steps[index].result.gold, reference.randi_range(_loot.min_gold, _loot.max_gold))
		reference.randf()
		assert_eq(weighted.steps[index].result.item_ids, ["short_sword" if reference.randf() * 4.0 < 1.0 else "robes"])
	var outcome := EventOutcomeResource.new()
	outcome.outcome_id = "items"
	outcome.journal_text = "Found supplies."
	outcome.result = {"gold": 3, "item_ids": ["robes", "robes"]}
	_event.outcomes.assign([outcome])
	var entry := EncounterEntryResource.new()
	entry.kind = "Event"
	entry.content_id = ExpeditionCatalog.EVENTS[0].event_id
	entry.weight = 1
	region.encounter_pool.assign([entry])
	var event_run := ExpeditionGenerator.generate(region, party, 42, 60, 1000, config)
	assert_not_null(event_run)
	assert_eq(event_run.steps[1].result, outcome.result)


func test_reward_payloads_and_authored_pools_reject_unknown_ids_nonfinite_weights_and_extras() -> void:
	for value in [{"gold": 0, "item_ids": ["missing"]}, {"gold": 0, "item_ids": [true]},
			{"gold": 0, "item_ids": "robes"}, {"gold": 0, "item_ids": [], "xp": 1},
			{"gold": 0, "item_ids": ["res://data/items/robes.tres"]}]:
		assert_false(ExpeditionCatalog.reward_payload(value), str(value))
	var ids: Array = []
	for index in range(16):
		ids.append("robes")
	assert_true(ExpeditionCatalog.reward_payload({"gold": 0, "item_ids": ids}))
	ids.append("robes")
	assert_false(ExpeditionCatalog.reward_payload({"gold": 0, "item_ids": ids}))
	assert_false(ExpeditionCatalog.reward_payload({"gold": 0, "item_ids": ["robes", "robes"]}, 1))
	for pool in [{"missing": 1}, {"robes": NAN}, {"robes": INF}, {"robes": -1}, {"robes": true}, {"robes": 0}]:
		_loot.item_pool = pool
		assert_false(ExpeditionCatalog.validate_loot(ExpeditionCatalog.LOOT))
	_loot.item_pool = {"robes": 1}
	for chance in [-0.1, 1.1, INF, NAN]:
		_loot.item_drop_chance = chance
		assert_false(ExpeditionCatalog.validate_loot(ExpeditionCatalog.LOOT))
