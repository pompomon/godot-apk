extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
const REGION: RegionResource = preload("res://data/regions/green_hollow.tres")
const STAGES := ["before_temp_write", "after_temp_validation", "after_backup_preparation",
	"after_backup_replace", "before_primary_replace", "after_primary_replace"]
var _isolation: RefCounted
var _time: int = 1000
var _original_pool: Array[EncounterEntryResource] = []


func before_each() -> void:
	var region := REGION
	_original_pool.assign(region.encounter_pool)
	region.encounter_pool.assign(_original_pool.filter(
		func(entry: EncounterEntryResource) -> bool: return entry.kind != "Combat"))
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	_time = 1000
	ExpeditionManager.clock = func() -> int: return _time
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success)


func after_each() -> void:
	var region := REGION
	region.encounter_pool.assign(_original_pool)
	_isolation.finish()


func _confirm() -> PartyData:
	var draft := PartyData.new()
	draft.place_hero(3, GameState.roster[0])
	assert_true(PartyFormationService.confirm(draft, ExpeditionManager.balancing))
	return GameState.current_party


func _start() -> ExpeditionData:
	var party := _confirm()
	ExpeditionManager.start_expedition(REGION, party, 60)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	return ExpeditionManager.get_active_expedition()


func _observe(now: int) -> void:
	_time = now
	ExpeditionManager.reveal_progress()


func test_start_consumes_confirmed_party_only_and_retains_independent_rng() -> void:
	var party := _confirm()
	var hero := party.heroes()[0]
	var recruitment := [GameState.recruitment_seed, GameState.recruitment_sequence, GameState.offer_seeds.duplicate()]
	var sequence := GameState.expedition_sequence
	ExpeditionManager.start_expedition(REGION, party.copy(), 60)
	assert_false(ExpeditionManager.last_committed)
	assert_same(GameState.current_party, party)
	ExpeditionManager.start_expedition(REGION, party, 60)
	assert_true(ExpeditionManager.last_committed)
	assert_null(GameState.current_party)
	assert_eq(hero.status, HeroData.HeroStatus.ON_EXPEDITION)
	assert_eq(GameState.expedition_sequence, sequence + 1)
	assert_eq([GameState.recruitment_seed, GameState.recruitment_sequence, GameState.offer_seeds], recruitment)
	assert_true(ExpeditionManager.is_expedition_active())
	assert_false(PartyFormationService.editing_error().is_empty())
	var saved := SaveManager.capture_state()
	ExpeditionManager.start_expedition(REGION, party, 60)
	assert_false(ExpeditionManager.last_committed)
	assert_eq(SaveManager.capture_state(), saved)


func test_start_rejects_stale_region_party_status_and_invalid_config_without_mutation() -> void:
	var party := _confirm()
	var saved := SaveManager.capture_state()
	for region in [null, REGION.duplicate(true)]:
		ExpeditionManager.start_expedition(region, party, 60)
		assert_false(ExpeditionManager.last_committed)
		assert_eq(SaveManager.capture_state(), saved)
	for seconds in [0, -1, 61, HeroCatalog.MAX_SAFE_INT]:
		ExpeditionManager.start_expedition(REGION, party, seconds)
		assert_false(ExpeditionManager.last_committed)
		assert_eq(SaveManager.capture_state(), saved)
	GameState.roster[0].status = HeroData.HeroStatus.IDLE
	ExpeditionManager.start_expedition(REGION, party, 60)
	assert_false(ExpeditionManager.last_committed)
	GameState.roster[0].status = HeroData.HeroStatus.ASSIGNED
	ExpeditionManager.balancing = ExpeditionManager.DEFAULT_BALANCING.duplicate(true)
	ExpeditionManager.balancing.max_offline_delta_seconds = 0
	ExpeditionManager.start_expedition(REGION, party, 60)
	assert_false(ExpeditionManager.last_committed)
	assert_eq(SaveManager.capture_state(), saved)
	ExpeditionManager.balancing = ExpeditionManager.DEFAULT_BALANCING
	ExpeditionManager.clock = func() -> float: return 1000.25
	ExpeditionManager.start_expedition(REGION, party, 60)
	assert_false(ExpeditionManager.last_committed)
	assert_eq(SaveManager.capture_state(), saved)


func test_clock_slices_no_step_saves_repetition_and_completed_noops() -> void:
	var run := _start()
	var writes: Array = []
	SaveManager.fault_injector = func(stage: String) -> bool:
		writes.append(stage)
		return false
	_observe(1000)
	assert_eq(writes, [])
	for pair in [[1001, -1], [1005, -1], [1006, 0], [1011, 0], [1012, 1], [1059, 8]]:
		_observe(pair[0])
		assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
		assert_eq(run.last_revealed_index, pair[1])
		assert_eq(run.last_observed_utc, pair[0])
		assert_eq(run.credited_elapsed_seconds, pair[0] - 1000)
		assert_eq(GameState.gold, 100 + run.credited_gold())
	assert_eq(writes.count("before_temp_write"), 6)
	_observe(1060)
	assert_false(ExpeditionManager.is_expedition_active())
	assert_eq(run.status, ExpeditionData.Status.COMPLETED)
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.IDLE)
	var saved := SaveManager.capture_state()
	var count := writes.size()
	_observe(9000)
	assert_eq(SaveManager.capture_state(), saved)
	assert_eq(writes.size(), count)
	assert_true(ExpeditionManager.take_completion_route())
	assert_false(ExpeditionManager.take_completion_route())


func test_negative_and_capped_deltas_persist_without_recomputing_from_start() -> void:
	var run := _start()
	ExpeditionManager.balancing = ExpeditionManager.DEFAULT_BALANCING.duplicate(true)
	ExpeditionManager.balancing.max_offline_delta_seconds = 7
	_observe(1005)
	assert_eq(run.credited_elapsed_seconds, 5)
	_observe(900)
	assert_eq(run.last_observed_utc, 900)
	assert_eq(run.credited_elapsed_seconds, 5)
	assert_eq(run.last_revealed_index, -1)
	_observe(100000)
	assert_eq(run.credited_elapsed_seconds, 12)
	assert_eq(run.last_revealed_index, 1)
	var saved := SaveManager.capture_state()
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), saved)
	_observe(100000)
	assert_eq(SaveManager.capture_state(), saved)
	_observe(100100)
	assert_eq(ExpeditionManager.get_active_expedition().credited_elapsed_seconds, 19)
	assert_eq(ExpeditionManager.get_active_expedition().last_observed_utc, 100100)


func test_gold_overflow_is_retryable_and_rolls_back_clock_cursor_and_completion() -> void:
	var run := _start()
	var reward_total := 0
	for step in run.steps:
		reward_total += int(step.result.gold)
	assert_gt(reward_total, 0)
	GameState.gold = HeroCatalog.MAX_SAFE_INT
	SaveManager.save()
	var saved := SaveManager.capture_state()
	_observe(1060)
	assert_false(ExpeditionManager.last_committed)
	assert_false(ExpeditionManager.last_error.is_empty())
	assert_eq(SaveManager.capture_state(), saved)
	assert_same(ExpeditionManager.get_active_expedition(), run)
	GameState.gold -= reward_total
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(GameState.gold, HeroCatalog.MAX_SAFE_INT)
	assert_eq(run.status, ExpeditionData.Status.COMPLETED)
	SaveManager.load_or_create()
	assert_eq(GameState.gold, HeroCatalog.MAX_SAFE_INT)
	assert_eq(ExpeditionManager.get_active_expedition().status, ExpeditionData.Status.COMPLETED)


func test_bad_observation_config_or_clock_never_changes_progress() -> void:
	_start()
	var saved := SaveManager.capture_state()
	ExpeditionManager.balancing = ExpeditionManager.DEFAULT_BALANCING.duplicate(true)
	ExpeditionManager.balancing.max_offline_delta_seconds = 0
	_observe(1012)
	assert_false(ExpeditionManager.last_committed)
	assert_eq(SaveManager.capture_state(), saved)
	ExpeditionManager.balancing.max_offline_delta_seconds = 86400
	for invalid in [null, true, "1", -1, INF, NAN]:
		ExpeditionManager.balancing.encounter_kind_weight_multipliers.Loot = invalid
		_observe(1012)
		assert_false(ExpeditionManager.last_committed)
		assert_eq(SaveManager.capture_state(), saved)
	ExpeditionManager.balancing = ExpeditionManager.DEFAULT_BALANCING
	for invalid in [null, true, -1, INF, NAN, 1000.1, HeroCatalog.MAX_SAFE_INT + 1]:
		ExpeditionManager.clock = func() -> Variant: return invalid
		ExpeditionManager.reveal_progress()
		assert_false(ExpeditionManager.last_committed)
		assert_eq(SaveManager.capture_state(), saved)


func test_completed_report_allows_reformation_but_blocks_dispatch_until_acknowledged() -> void:
	var run := _start()
	_observe(1060)
	var party := _confirm()
	var hero := GameState.roster[0]
	assert_eq(hero.status, HeroData.HeroStatus.ASSIGNED)
	ExpeditionManager.reveal_progress()
	assert_eq(hero.status, HeroData.HeroStatus.ASSIGNED, "Completed runs never finalize again.")
	ExpeditionManager.start_expedition(REGION, party, 60)
	assert_false(ExpeditionManager.last_committed)
	SaveManager.load_or_create()
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.ASSIGNED)
	assert_not_null(ExpeditionManager.get_active_expedition())
	ExpeditionManager.acknowledge_report(run)
	assert_false(ExpeditionManager.last_committed, "A stale pre-load report cannot acknowledge the new record.")
	ExpeditionManager.acknowledge_report(ExpeditionManager.get_active_expedition())
	assert_true(ExpeditionManager.last_committed)
	assert_null(ExpeditionManager.get_active_expedition())
	ExpeditionManager.start_expedition(REGION, GameState.current_party, 60)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)


func test_acknowledgment_rejects_running_null_or_stale_requests() -> void:
	var run := _start()
	var saved := SaveManager.capture_state()
	for request in [null, ExpeditionData.new(), run]:
		ExpeditionManager.acknowledge_report(request)
		assert_false(ExpeditionManager.last_committed)
		assert_eq(SaveManager.capture_state(), saved)


func test_maximum_rng_values_round_trip_wrap_safely_and_do_not_touch_recruitment() -> void:
	var party := _confirm()
	GameState.expedition_seed = HeroCatalog.MAX_SAFE_INT
	GameState.expedition_sequence = 0
	ExpeditionManager.start_expedition(REGION, party, 60)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(ExpeditionManager.get_active_expedition().seed, HeroCatalog.MAX_SAFE_INT)
	var saved := SaveManager.capture_state()
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), saved)
	_observe(1060)
	ExpeditionManager.acknowledge_report(ExpeditionManager.get_active_expedition())
	party = _confirm()
	GameState.expedition_sequence = HeroCatalog.MAX_SAFE_INT
	ExpeditionManager.start_expedition(REGION, party, 60)
	assert_true(ExpeditionManager.last_committed)
	assert_eq(GameState.expedition_sequence, 0)
	assert_eq(ExpeditionManager.get_active_expedition().seed, HeroCatalog.MAX_SAFE_INT - 1)


func test_all_save_fault_boundaries_for_start_reveal_finalize_and_acknowledgment() -> void:
	for action in ["start", "clock", "reveal", "finalize", "acknowledge"]:
		for stage in STAGES:
			SaveManager.fault_injector = Callable()
			_time = 1000
			assert_true(RecruitmentService.initialize_new_game(12345))
			SaveManager.save()
			var party := _confirm()
			if action != "start":
				ExpeditionManager.start_expedition(REGION, party, 60)
				assert_true(ExpeditionManager.last_committed)
			if action == "acknowledge":
				_observe(1060)
			var before := SaveManager.capture_state()
			var hero := GameState.roster[0]
			var record := ExpeditionManager.get_active_expedition()
			var changed_count := [0]
			var completed_count := [0]
			var changed_callback := func() -> void: changed_count[0] += 1
			var completed_callback := func() -> void: completed_count[0] += 1
			ExpeditionManager.changed.connect(changed_callback)
			ExpeditionManager.completed.connect(completed_callback)
			SaveManager.fault_injector = func(boundary: String) -> bool: return boundary == stage
			match action:
				"start": ExpeditionManager.start_expedition(REGION, party, 60)
				"clock": _observe(1001)
				"reveal": _observe(1012)
				"finalize": _observe(1060)
				"acknowledge": ExpeditionManager.acknowledge_report(record)
			var label := "%s / %s" % [action, stage]
			if stage == "after_primary_replace":
				assert_true(ExpeditionManager.last_committed, label)
				assert_eq(changed_count[0], 1, label)
				assert_eq(completed_count[0], 1 if action == "finalize" else 0, label)
				assert_false(SaveManager.last_warning.is_empty())
				var after := SaveManager.capture_state()
				SaveManager.fault_injector = Callable()
				SaveManager.load_or_create()
				assert_eq(SaveManager.capture_state(), after, label)
			else:
				assert_false(ExpeditionManager.last_committed, label)
				assert_eq(SaveManager.capture_state(), before, label)
				assert_same(GameState.roster[0], hero, label)
				assert_same(ExpeditionManager.get_active_expedition(), record, label)
				if action == "start":
					assert_same(GameState.current_party, party, label)
				assert_eq(changed_count[0], 0, label)
				assert_eq(completed_count[0], 0, label)
				SaveManager.fault_injector = Callable()
				match action:
					"start": ExpeditionManager.start_expedition(REGION, party, 60)
					"acknowledge": ExpeditionManager.acknowledge_report(record)
					_: ExpeditionManager.reveal_progress()
				assert_true(ExpeditionManager.last_committed, label)
				var committed := SaveManager.capture_state()
				SaveManager.load_or_create()
				ExpeditionManager.reveal_progress()
				assert_eq(SaveManager.capture_state(), committed, label + " retry/reload is idempotent")
			ExpeditionManager.changed.disconnect(changed_callback)
			ExpeditionManager.completed.disconnect(completed_callback)
