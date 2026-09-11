extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
const REGION: RegionResource = preload("res://data/regions/green_hollow.tres")
const STAGES := [
	"before_temp_write", "after_temp_validation", "after_backup_preparation",
	"after_backup_replace", "before_primary_replace", "after_primary_replace",
]
var _isolation: RefCounted
var _time: int = 1000
var _original_pool: Array[EncounterEntryResource] = []
var _original_durations: Array[int] = []


func before_each() -> void:
	_original_pool.assign(REGION.encounter_pool)
	_original_durations.assign(REGION.duration_options_seconds)
	var safe_entry := EncounterEntryResource.new()
	safe_entry.kind = "Loot"
	safe_entry.content_id = ExpeditionCatalog.LOOT.loot_id
	safe_entry.weight = 1.0
	var region := REGION
	region.encounter_pool = [safe_entry]
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	_time = 1000
	ExpeditionManager.clock = func() -> int: return _time
	ExpeditionManager.balancing = ExpeditionManager.DEFAULT_BALANCING.duplicate(true)
	ExpeditionManager.balancing.recovery_hp_percent = 0
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success, SaveManager.last_error)


func after_each() -> void:
	REGION.encounter_pool.assign(_original_pool)
	REGION.duration_options_seconds.assign(_original_durations)
	_isolation.finish()


func _confirm() -> PartyData:
	var party := PartyData.new()
	party.place_hero(3, GameState.roster[0])
	assert_true(PartyFormationService.confirm(party, ExpeditionManager.balancing))
	return GameState.current_party


func _start(run_count: int) -> ExpeditionData:
	var party := _confirm()
	ExpeditionManager.start_expedition(REGION, party, 60, run_count)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	return ExpeditionManager.get_active_expedition()


func _observe(now: int) -> void:
	_time = now
	ExpeditionManager.reveal_progress()


func _reset_company() -> void:
	SaveManager.fault_injector = Callable()
	_time = 1000
	assert_true(RecruitmentService.initialize_new_game(12345))
	SaveManager.save()
	assert_true(SaveManager.last_committed, SaveManager.last_error)


func test_automation_state_rejects_overflow_mismatched_totals_and_excess_resting_heroes() -> void:
	var state := ExpeditionAutomationState.create(REGION, _confirm(), 60, 2)
	assert_not_null(state)
	assert_true(ExpeditionAutomationState.valid(state.serialize()))
	var bad := state.serialize()
	bad.duration_seconds = HeroCatalog.MAX_SAFE_INT
	assert_false(ExpeditionAutomationState.valid(bad))
	bad = state.serialize()
	bad.completed_runs = 1
	bad.cumulative_gold = 3
	bad.summaries = [{
		"run_number": 1, "region_name": REGION.display_name, "outcome": "COMPLETED",
		"gold": 2, "item_count": 0, "xp_per_hero": 0, "resting_hero_count": 0,
	}]
	assert_false(ExpeditionAutomationState.valid(bad))
	bad.cumulative_gold = 2
	bad.summaries[0].resting_hero_count = 2
	assert_false(ExpeditionAutomationState.valid(bad))


func test_one_run_remains_manual_and_invalid_counts_do_not_mutate() -> void:
	var party := _confirm()
	var before := SaveManager.capture_state()
	for count in [0, ExpeditionAutomationState.MAX_REQUESTED_RUNS + 1]:
		ExpeditionManager.start_expedition(REGION, party, 60, count)
		assert_false(ExpeditionManager.last_committed)
		assert_eq(SaveManager.capture_state(), before)
	ExpeditionManager.start_expedition(REGION, party, 60, 1)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_true(ExpeditionManager.get_automation_state().is_empty())
	assert_eq(ExpeditionManager.get_active_expedition().party_snapshot.slots.BACK_RIGHT.hero_id,
		GameState.roster[0].hero_id)


func test_automated_start_preflights_frozen_gold_without_consuming_the_party() -> void:
	var party := _confirm()
	var candidate := ExpeditionGenerator.generate(
		REGION, party, ExpeditionManager.next_seed(), 60, _time, ExpeditionManager.balancing)
	assert_not_null(candidate)
	var reward_gold := 0
	for step in candidate.steps:
		reward_gold += int(step.result.gold)
	assert_gt(reward_gold, 0)
	GameState.gold = HeroCatalog.MAX_SAFE_INT
	SaveManager.save()
	assert_true(SaveManager.last_committed, SaveManager.last_error)
	var before := SaveManager.capture_state()
	ExpeditionManager.start_expedition(REGION, party, 60, 2)
	assert_false(ExpeditionManager.last_committed)
	assert_string_contains(ExpeditionManager.last_error, "Gold capacity")
	assert_eq(SaveManager.capture_state(), before)
	assert_same(GameState.current_party, party)
	assert_true(ExpeditionManager.get_automation_state().is_empty())


func test_catchup_is_bounded_reentrant_safe_and_preserves_sequential_timestamps() -> void:
	_start(10)
	var reenter := func() -> void: ExpeditionManager.reveal_progress()
	ExpeditionManager.changed.connect(reenter)
	_observe(2000)
	ExpeditionManager.changed.disconnect(reenter)
	var state := ExpeditionManager.get_automation_state()
	assert_eq(int(state.completed_runs), 4)
	assert_eq(int(state.pending_offline_seconds), 360)
	assert_eq(ExpeditionManager.get_active_expedition().start_timestamp, 1240)
	assert_eq(GameState.expedition_sequence, 5)
	_observe(1900)
	state = ExpeditionManager.get_automation_state()
	assert_eq(int(state.completed_runs), 8)
	assert_eq(int(state.pending_offline_seconds), 120)
	assert_eq(ExpeditionManager.get_active_expedition().start_timestamp, 1480,
		"Pending elapsed time keeps successor starts sequential across a clock rollback.")
	_observe(1900)
	state = ExpeditionManager.get_automation_state()
	assert_eq(int(state.completed_runs), 10)
	assert_eq(state.summaries.size(), 10)
	assert_eq(int(state.pending_offline_seconds), 0)
	assert_false(bool(state.enabled))
	assert_string_contains(String(state.stop_reason), "Completed all")
	assert_eq(ExpeditionManager.get_active_expedition().start_timestamp, 1540)
	assert_eq(ExpeditionManager.get_active_expedition().status, ExpeditionData.Status.COMPLETED)
	assert_eq(GameState.expedition_sequence, 10)
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.IDLE)
	assert_true(SaveManager.validate_snapshot(SaveManager.capture_state()))


func test_pending_catchup_round_trips_and_finishes_exactly_once() -> void:
	var first := _start(6)
	var first_seed := first.seed
	_observe(2000)
	var batched := SaveManager.capture_state()
	assert_eq(int(batched.expedition_automation.completed_runs), 4)
	assert_eq(int(batched.expedition_automation.pending_offline_seconds), 120)
	assert_ne(int(batched.expedition.seed), first_seed)
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success, SaveManager.last_error)
	var completed := SaveManager.capture_state()
	assert_eq(int(completed.expedition_automation.completed_runs), 6)
	assert_eq(completed.expedition_automation.summaries.size(), 6)
	assert_eq(int(completed.expedition_automation.pending_offline_seconds), 0)
	assert_eq(int(completed.expedition.status), ExpeditionData.Status.COMPLETED)
	assert_false(bool(completed.expedition_automation.enabled))
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), completed)


func test_cancel_finishes_only_the_current_run_and_survives_reload() -> void:
	var first := _start(3)
	ExpeditionManager.stop_automation_after_current()
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	var stopping := ExpeditionManager.get_automation_state()
	assert_true(bool(stopping.cancelled))
	assert_false(bool(stopping.enabled))
	assert_true(ExpeditionManager.is_expedition_active())
	_observe(1060)
	var stopped := ExpeditionManager.get_automation_state()
	assert_same(ExpeditionManager.get_active_expedition(), first)
	assert_eq(int(stopped.completed_runs), 1)
	assert_eq(stopped.summaries.size(), 1)
	assert_string_contains(String(stopped.stop_reason), "player")
	assert_false(ExpeditionManager.is_expedition_active())
	assert_eq(GameState.expedition_sequence, 1)
	var saved := SaveManager.capture_state()
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), saved)


func test_cancelling_the_final_run_normalizes_to_completed_series() -> void:
	_start(2)
	_observe(1060)
	assert_true(ExpeditionManager.is_expedition_active())
	assert_eq(int(ExpeditionManager.get_automation_state().completed_runs), 1)
	ExpeditionManager.stop_automation_after_current()
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	_observe(1120)
	var completed := ExpeditionManager.get_automation_state()
	assert_eq(int(completed.completed_runs), 2)
	assert_false(bool(completed.enabled))
	assert_false(bool(completed.cancelled))
	assert_eq(String(completed.stop_reason), "Completed all requested Expeditions.")


func test_series_stops_safely_when_the_next_duration_is_removed() -> void:
	_start(3)
	REGION.duration_options_seconds.assign([120])
	_observe(1060)
	var state := ExpeditionManager.get_automation_state()
	assert_eq(int(state.completed_runs), 1)
	assert_false(bool(state.enabled))
	assert_string_contains(String(state.stop_reason), "duration")
	assert_eq(int(state.pending_offline_seconds), 0)
	assert_eq(ExpeditionManager.get_active_expedition().status, ExpeditionData.Status.COMPLETED)
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.IDLE)
	assert_true(SaveManager.validate_snapshot(SaveManager.capture_state()))


func test_version_six_migrates_with_null_automation_without_rewriting_the_run() -> void:
	_start(1)
	var legacy := SaveManager.capture_state()
	legacy.save_version = 6
	legacy.erase("expedition_automation")
	var untouched := legacy.duplicate(true)
	var migrated := SaveManager.migrate(legacy)
	assert_eq(legacy, untouched)
	assert_eq(int(migrated.save_version), SaveManager.SAVE_VERSION)
	assert_null(migrated.expedition_automation)
	assert_eq(migrated.expedition, legacy.expedition)
	assert_true(SaveManager.validate_snapshot(migrated))
	var future_field := legacy.duplicate(true)
	future_field.expedition_automation = null
	assert_true(SaveManager.migrate(future_field).is_empty())


func test_completed_summary_and_running_cancellation_relations_are_strict() -> void:
	_start(2)
	var running := SaveManager.capture_state()
	var bad := running.duplicate(true)
	bad.expedition_automation.enabled = false
	bad.expedition_automation.stop_reason = "Stopped."
	assert_true(ExpeditionAutomationState.valid(bad.expedition_automation))
	assert_false(SaveManager.validate_snapshot(bad))
	ExpeditionManager.stop_automation_after_current()
	_observe(1060)
	var completed := SaveManager.capture_state()
	assert_true(SaveManager.validate_snapshot(completed))
	for key in ["gold", "item_count", "xp_per_hero"]:
		bad = completed.duplicate(true)
		bad.expedition_automation.summaries[-1][key] += 1
		var cumulative_key: String = {
			"gold": "cumulative_gold",
			"item_count": "cumulative_item_count",
			"xp_per_hero": "cumulative_xp_per_hero",
		}[key] as String
		bad.expedition_automation[cumulative_key] += 1
		assert_true(ExpeditionAutomationState.valid(bad.expedition_automation), key)
		assert_false(SaveManager.validate_snapshot(bad), key)
	for change in [
			["region_name", "Another Region"],
			["outcome", "RETREAT"],
	]:
		bad = completed.duplicate(true)
		bad.expedition_automation.summaries[-1][change[0]] = change[1]
		assert_true(ExpeditionAutomationState.valid(bad.expedition_automation), str(change))
		assert_false(SaveManager.validate_snapshot(bad), str(change))
	bad = completed.duplicate(true)
	bad.expedition_automation.summaries[-1].resting_hero_count = 1
	assert_true(ExpeditionAutomationState.valid(bad.expedition_automation))
	assert_false(SaveManager.validate_snapshot(bad))


func test_new_automation_transactions_cover_every_save_fault_boundary() -> void:
	for action in ["start", "stop", "rollover", "acknowledge"]:
		for stage in STAGES:
			_reset_company()
			var party := _confirm()
			if action != "start":
				ExpeditionManager.start_expedition(REGION, party, 60, 2 if action == "acknowledge" else 3)
				assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
			if action == "rollover":
				_time = 1060
			elif action == "acknowledge":
				_time = 1120
				ExpeditionManager.reveal_progress()
				assert_false(ExpeditionManager.is_expedition_active())
			var before := SaveManager.capture_state()
			var record := ExpeditionManager.get_active_expedition()
			SaveManager.fault_injector = func(boundary: String) -> bool: return boundary == stage
			_invoke_fault_action(action, party, record)
			var label := "%s / %s" % [action, stage]
			if stage == "after_primary_replace":
				assert_true(ExpeditionManager.last_committed, label)
				assert_false(SaveManager.last_warning.is_empty(), label)
				var committed := SaveManager.capture_state()
				SaveManager.fault_injector = Callable()
				SaveManager.load_or_create()
				assert_eq(SaveManager.capture_state(), committed, label)
			else:
				assert_false(ExpeditionManager.last_committed, label)
				assert_eq(SaveManager.capture_state(), before, label)
				assert_same(ExpeditionManager.get_active_expedition(), record, label)
				if action == "start":
					assert_same(GameState.current_party, party, label)
				SaveManager.fault_injector = Callable()
				_invoke_fault_action(action, party, record)
				assert_true(ExpeditionManager.last_committed, label)
				var committed := SaveManager.capture_state()
				SaveManager.load_or_create()
				assert_eq(SaveManager.capture_state(), committed, label)


func _invoke_fault_action(action: String, party: PartyData, record: ExpeditionData) -> void:
	match action:
		"start":
			ExpeditionManager.start_expedition(REGION, party, 60, 3)
		"stop":
			ExpeditionManager.stop_automation_after_current()
		"rollover":
			ExpeditionManager.reveal_progress()
		"acknowledge":
			ExpeditionManager.acknowledge_report(record)
