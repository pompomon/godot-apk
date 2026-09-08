extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
const REGION: RegionResource = preload("res://data/regions/green_hollow.tres")
const GROUP: EnemyGroupResource = preload("res://data/encounters/bandit_skirmishers.tres")
const STAGES := ["before_temp_write", "after_temp_validation", "after_backup_preparation",
	"after_backup_replace", "before_primary_replace", "after_primary_replace"]
var _isolation: RefCounted
var _time: int = 1000
var _pool: Array[EncounterEntryResource]
var _travel_count: int
var _terminal_retreat: bool
var _enemies: Array[Dictionary]
var _guard_effect: String
var _region: RegionResource = REGION
var _group: EnemyGroupResource = GROUP
var _guard: SkillResource = CombatCatalog.GUARD


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	_pool = REGION.encounter_pool.duplicate()
	_travel_count = REGION.travel_step_count
	_terminal_retreat = REGION.retreat_ends_expedition
	_enemies = GROUP.enemies.duplicate(true)
	_guard_effect = CombatCatalog.GUARD.effect
	_time = 1000
	ExpeditionManager.clock = func() -> int: return _time
	ExpeditionManager.balancing = ExpeditionManager.DEFAULT_BALANCING.duplicate(true)
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success)


func after_each() -> void:
	_region.encounter_pool = _pool
	_region.travel_step_count = _travel_count
	_region.retreat_ends_expedition = _terminal_retreat
	_group.enemies = _enemies
	_guard.effect = _guard_effect
	_isolation.finish()


func _configure(outcome: String, count: int = 5, terminal_retreat: bool = false,
		casualty: bool = false) -> void:
	var combat := EncounterEntryResource.new()
	combat.kind = "Combat"
	combat.content_id = GROUP.group_id
	combat.weight = 1.0
	_region.encounter_pool = [combat]
	_region.travel_step_count = count
	_region.retreat_ends_expedition = terminal_retreat
	_group.enemies = [{
		"combatant_id": "fixture-enemy", "display_name": "Fixture enemy",
		"row": "Front", "basic_attack_target_rule": "FrontRowFirst",
		"derived_stats": {"MaxHP": 1 if outcome == "VICTORY" else 100000,
			"Attack": 10000 if outcome == "DEFEAT" or casualty else 1,
			"MagicPower": 0, "Defense": 0, "Evasion": 0.0,
			"Initiative": 10000, "CritChance": 0.0},
	}]
	var balancing := ExpeditionManager.balancing
	balancing.base_hit_chance = 1.0
	balancing.min_hit_chance = 1.0
	balancing.max_hit_chance = 1.0
	balancing.max_crit_chance = 0.0
	balancing.max_combat_rounds = 20 if outcome == "DEFEAT" else 1


func _confirm(indices: Array = [0, 1]) -> PartyData:
	var draft := PartyData.new()
	for index in range(indices.size()):
		draft.place_hero(0 if index == 0 else 3, GameState.roster[indices[index]])
	assert_true(PartyFormationService.confirm(draft, ExpeditionManager.balancing))
	return GameState.current_party


func _dispatch(party: PartyData) -> ExpeditionData:
	ExpeditionManager.start_expedition(REGION, party, 60)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	return ExpeditionManager.get_active_expedition()


func _start() -> ExpeditionData:
	return _dispatch(_confirm())


func _observe(now: int) -> void:
	_time = now
	ExpeditionManager.reveal_progress()


func _rewarding_defeat() -> ExpeditionData:
	_configure("DEFEAT")
	var loot := EncounterEntryResource.new()
	loot.kind = "Loot"
	loot.content_id = ExpeditionCatalog.LOOT.loot_id
	loot.weight = 1.0
	_region.encounter_pool = [_region.encounter_pool[0], loot]
	var party := _confirm()
	for seed in range(64):
		var candidate := ExpeditionGenerator.generate(REGION, party, seed, 60, _time, ExpeditionManager.balancing)
		if candidate != null and candidate.terminal_step_index > 1 and candidate.steps.size() < candidate.planned_step_count:
			GameState.expedition_seed = seed
			GameState.expedition_sequence = 0
			return _dispatch(party)
	fail_test("The controlled pool must yield a rewarded prefix and early Defeat.")
	return null


func _wound(hero: HeroData, deadline: int) -> void:
	hero.status = HeroData.HeroStatus.RESTING if deadline > 0 else HeroData.HeroStatus.WOUNDED
	hero.recovery_ready_at = deadline


func _track_writes() -> Array:
	var writes: Array = []
	SaveManager.fault_injector = func(stage: String) -> bool:
		writes.append(stage)
		return false
	return writes


func test_combat_states_remain_frozen_and_on_expedition_until_final_observation() -> void:
	_configure("RETREAT")
	var run := _start()
	var frozen := run.serialize()
	var final_states := run.final_hero_states()
	assert_eq(run.steps.size(), 10)
	assert_eq(run.terminal_step_index, -1)
	var first_hp: int = run.steps[1].result.final_hero_states["hero-1"].hp
	assert_lt(final_states["hero-1"].hp, first_hp, "Later Combats carry damage rather than healing.")
	GameState.roster.reverse()
	for now in [1012, 1024, 1036, 1048, 1059]:
		_observe(now)
		assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
		for id in final_states:
			assert_eq(GameState.find_hero(id).status, HeroData.HeroStatus.ON_EXPEDITION)
			assert_eq(GameState.find_hero(id).recovery_ready_at, 0)
		assert_eq(run.serialize().steps, frozen.steps)
	_observe(1060)
	assert_eq(run.final_hero_states(), final_states)
	for id in final_states:
		assert_gt(final_states[id].hp, 0)
		assert_eq(GameState.find_hero(id).status, HeroData.HeroStatus.IDLE)
		assert_eq(GameState.find_hero(id).recovery_ready_at, 0)
	assert_eq(run.serialize().party_snapshot, frozen.party_snapshot)


func test_zero_hp_rests_on_victory_and_retreat_while_survivors_become_idle() -> void:
	for outcome in ["VICTORY", "RETREAT"]:
		_time = 1000
		assert_true(RecruitmentService.initialize_new_game(12345))
		SaveManager.save()
		_configure(outcome, 1, true, true)
		var run := _start()
		var result := run.steps[1].result
		assert_eq(result.outcome, outcome)
		assert_eq(result.final_hero_states["hero-1"], {"hp": 0, "status": HeroData.HeroStatus.WOUNDED})
		assert_gt(result.final_hero_states["hero-2"].hp, 0)
		_observe(1059)
		assert_eq(GameState.find_hero("hero-1").status, HeroData.HeroStatus.ON_EXPEDITION)
		_observe(1060)
		assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
		assert_eq(GameState.find_hero("hero-1").status, HeroData.HeroStatus.RESTING)
		assert_eq(GameState.find_hero("hero-1").recovery_ready_at, 1120)
		assert_eq(GameState.find_hero("hero-2").status, HeroData.HeroStatus.IDLE)
		assert_eq(GameState.find_hero("hero-2").recovery_ready_at, 0)
		assert_eq(GameState.find_hero("hero-3").status, HeroData.HeroStatus.IDLE)


func test_early_defeat_after_long_absence_caps_elapsed_and_starts_recovery_at_observation() -> void:
	var run := _rewarding_defeat()
	assert_not_null(run)
	if run == null:
		return
	var frozen_steps: Array = run.serialize().steps
	assert_lt(run.steps.size(), run.planned_step_count)
	assert_eq(run.step_duration_seconds, 6)
	assert_eq(run.display_step_count(), 10)
	var expected_gold := 100
	for step in run.steps:
		expected_gold += int(step.result.gold)
	assert_gt(expected_gold, 100)
	_observe(1000000)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(run.credited_elapsed_seconds, run.effective_end_timestamp - run.start_timestamp)
	assert_eq(run.last_observed_utc, 1000000)
	assert_eq(run.last_revealed_index, run.steps.size() - 1)
	assert_eq(run.status, ExpeditionData.Status.COMPLETED)
	assert_eq(GameState.gold, expected_gold)
	for id in run.final_hero_states():
		assert_eq(GameState.find_hero(id).status, HeroData.HeroStatus.RESTING)
		assert_eq(GameState.find_hero(id).recovery_ready_at, 1000060)
	assert_eq(run.serialize().steps, frozen_steps)
	var saved := SaveManager.capture_state()
	var writes := _track_writes()
	_observe(1000059)
	assert_eq(SaveManager.capture_state(), saved)
	assert_eq(writes, [])


func test_terminal_retreat_reveals_only_saved_steps_without_wounding_survivors() -> void:
	_configure("RETREAT", 5, true)
	var run := _start()
	assert_eq(run.terminal_step_index, 1)
	assert_eq(run.effective_end_timestamp, 1012)
	assert_eq(run.duration_seconds, 60)
	_observe(1011)
	assert_eq(run.last_revealed_index, 0)
	assert_eq(run.display_step_count(), 10)
	for id in run.final_hero_states():
		assert_eq(GameState.find_hero(id).status, HeroData.HeroStatus.ON_EXPEDITION)
	_observe(900000)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(run.credited_elapsed_seconds, 12)
	assert_eq(run.last_revealed_index, 1)
	assert_eq(run.display_step_count(), 2)
	for id in run.final_hero_states():
		assert_eq(GameState.find_hero(id).status, HeroData.HeroStatus.IDLE)
		assert_eq(GameState.find_hero(id).recovery_ready_at, 0)


func test_historical_observation_ignores_live_combat_tuning_skills_and_enemies() -> void:
	_configure("VICTORY")
	var run := _start()
	var frozen_steps: Array = run.serialize().steps
	_group.enemies = []
	_guard.effect = "Invalid"
	_region.retreat_ends_expedition = true
	_region.encounter_pool = []
	ExpeditionManager.balancing.max_combat_rounds = 0
	ExpeditionManager.balancing.skill_damage_multipliers.clear()
	ExpeditionManager.balancing.encounter_kind_weight_multipliers = {"Combat": NAN, "Event": NAN, "Loot": NAN}
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success, SaveManager.last_error)
	run = ExpeditionManager.get_active_expedition()
	_observe(1060)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(run.status, ExpeditionData.Status.COMPLETED)
	assert_eq(run.serialize().steps, frozen_steps)
	assert_eq(GameState.find_hero("hero-1").status, HeroData.HeroStatus.IDLE)


func test_due_recovery_without_a_run_preserves_legacy_states_and_avoids_tick_writes() -> void:
	var wounded := GameState.roster[0]
	_wound(wounded, 1060)
	_wound(GameState.roster[1], 0)
	GameState.roster[2].status = HeroData.HeroStatus.RESTING
	SaveManager.save()
	assert_true(SaveManager.last_committed)
	var writes := _track_writes()
	watch_signals(ExpeditionManager)
	for now in [1000, 1059, 900]:
		_observe(now)
		assert_eq(wounded.status, HeroData.HeroStatus.RESTING)
	assert_eq(writes, [])
	ExpeditionManager._lifecycle_enabled = true
	ExpeditionManager._foreground = false
	_time = 1060
	ExpeditionManager.observe_foreground()
	assert_eq(writes, [])
	ExpeditionManager._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(writes.count("before_temp_write"), 1)
	assert_eq(wounded.status, HeroData.HeroStatus.IDLE)
	assert_eq(wounded.recovery_ready_at, 0)
	assert_eq(GameState.roster[1].status, HeroData.HeroStatus.WOUNDED)
	assert_eq(GameState.roster[1].recovery_ready_at, 0)
	assert_eq(GameState.roster[2].status, HeroData.HeroStatus.RESTING)
	assert_signal_emit_count(ExpeditionManager, "changed", 1)
	assert_signal_not_emitted(ExpeditionManager, "completed")
	var saved := SaveManager.capture_state()
	for now in [1060, 1061, 1000000]:
		_observe(now)
	assert_eq(writes.count("before_temp_write"), 1)
	assert_eq(SaveManager.capture_state(), saved)


func test_recovery_works_at_same_observed_timestamp_and_during_another_run() -> void:
	_configure("VICTORY")
	var run := _dispatch(_confirm([1]))
	var recovering := GameState.roster[0]
	_wound(recovering, 1000)
	_wound(GameState.roster[2], 1012)
	SaveManager.save()
	assert_true(SaveManager.last_committed)
	var before := run.clock_checkpoint()
	var writes := _track_writes()
	_observe(1000)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(recovering.status, HeroData.HeroStatus.IDLE)
	assert_eq(recovering.recovery_ready_at, 0)
	assert_eq(run.clock_checkpoint(), before)
	_observe(1000)
	assert_eq(writes.count("before_temp_write"), 1)
	_observe(1012)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(writes.count("before_temp_write"), 2)
	assert_eq(run.last_revealed_index, 1)
	assert_eq(GameState.roster[2].status, HeroData.HeroStatus.IDLE)
	assert_eq(GameState.roster[2].recovery_ready_at, 0)
	assert_eq(GameState.roster[1].status, HeroData.HeroStatus.ON_EXPEDITION)
	assert_true(ExpeditionManager.is_expedition_active())


func test_deferred_offline_completion_restart_and_acknowledgment_are_exactly_once() -> void:
	var run := _rewarding_defeat()
	assert_not_null(run)
	if run == null:
		return
	watch_signals(ExpeditionManager)
	ExpeditionManager._lifecycle_enabled = true
	_time = 5000
	ExpeditionManager.observe_foreground.call_deferred()
	assert_signal_not_emitted(ExpeditionManager, "completed")
	assert_true(ExpeditionManager.is_expedition_active())
	await get_tree().process_frame
	assert_signal_emit_count(ExpeditionManager, "completed", 1)
	assert_signal_emit_count(ExpeditionManager, "changed", 1)
	assert_false(ExpeditionManager.is_expedition_active())
	assert_true(ExpeditionManager.take_completion_route())
	assert_false(ExpeditionManager.take_completion_route())
	var saved := SaveManager.capture_state()
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success)
	ExpeditionManager.observe_foreground.call_deferred()
	await get_tree().process_frame
	assert_eq(SaveManager.capture_state(), saved)
	assert_signal_emit_count(ExpeditionManager, "completed", 1)
	assert_true(ExpeditionManager.take_completion_route())
	assert_false(ExpeditionManager.take_completion_route())
	ExpeditionManager.acknowledge_report(run)
	assert_false(ExpeditionManager.last_committed)
	ExpeditionManager.acknowledge_report(ExpeditionManager.get_active_expedition())
	assert_true(ExpeditionManager.last_committed)
	assert_null(ExpeditionManager.get_active_expedition())
	assert_eq(GameState.gold, saved.gold)
	SaveManager.load_or_create()
	_observe(5060)
	assert_true(ExpeditionManager.last_committed)
	for id in run.final_hero_states():
		assert_eq(GameState.find_hero(id).status, HeroData.HeroStatus.IDLE)
		assert_eq(GameState.find_hero(id).recovery_ready_at, 0)
	assert_null(ExpeditionManager.get_active_expedition())
	assert_eq(GameState.gold, saved.gold)
	assert_false(ExpeditionManager.take_completion_route())
	assert_signal_emit_count(ExpeditionManager, "completed", 1)


func test_all_save_fault_stages_restore_or_commit_combat_finalization_and_recovery() -> void:
	for action in ["finalize", "recover"]:
		for stage in STAGES:
			SaveManager.fault_injector = Callable()
			_time = 1000
			assert_true(RecruitmentService.initialize_new_game(12345))
			SaveManager.save()
			var run := _rewarding_defeat()
			if run == null:
				return
			_wound(GameState.roster[2], 1001)
			SaveManager.save()
			if action == "recover":
				_observe(5000)
				ExpeditionManager.mark_report_viewed()
			var before := SaveManager.capture_state()
			var own_before := ExpeditionManager.checkpoint()
			var heroes := GameState.roster.duplicate()
			var changed_count := [0]
			var completed_count := [0]
			var changed_callback := func() -> void:
				assert_true(SaveManager.last_committed, "Never present an uncommitted mutation.")
				changed_count[0] += 1
			var completed_callback := func() -> void: completed_count[0] += 1
			ExpeditionManager.changed.connect(changed_callback)
			ExpeditionManager.completed.connect(completed_callback)
			SaveManager.fault_injector = func(boundary: String) -> bool: return boundary == stage
			_observe(5000 if action == "finalize" else 5060)
			var label := "%s / %s" % [action, stage]
			if stage == "after_primary_replace":
				assert_true(ExpeditionManager.last_committed, label)
				assert_false(SaveManager.last_warning.is_empty(), label)
				assert_eq(changed_count[0], 1, label)
				assert_eq(completed_count[0], 1 if action == "finalize" else 0, label)
			else:
				assert_false(ExpeditionManager.last_committed, label)
				assert_eq(SaveManager.capture_state(), before, label)
				assert_eq(ExpeditionManager.checkpoint(), own_before, label)
				assert_same(ExpeditionManager.get_active_expedition(), run, label)
				for index in range(heroes.size()):
					assert_same(GameState.roster[index], heroes[index], label)
				assert_eq(changed_count[0], 0, label)
				assert_eq(completed_count[0], 0, label)
			SaveManager.fault_injector = Callable()
			if stage != "after_primary_replace":
				_observe(5100)
				assert_true(ExpeditionManager.last_committed, label)
			var deadline := (5060 if stage == "after_primary_replace" else 5160) if action == "finalize" else 0
			for id in run.final_hero_states():
				var hero := GameState.find_hero(id)
				assert_eq(hero.status, HeroData.HeroStatus.RESTING if action == "finalize" else HeroData.HeroStatus.IDLE, label)
				assert_eq(hero.recovery_ready_at, deadline, label)
			assert_eq(GameState.roster[2].status, HeroData.HeroStatus.IDLE, label)
			assert_eq(GameState.roster[2].recovery_ready_at, 0, label)
			assert_eq(changed_count[0], 1, label)
			assert_eq(completed_count[0], 1 if action == "finalize" else 0, label)
			var committed := SaveManager.capture_state()
			ExpeditionManager.reveal_progress()
			assert_eq(SaveManager.capture_state(), committed, label + " repeated observation")
			SaveManager.load_or_create()
			assert_true(SaveManager.last_success, label)
			ExpeditionManager.reveal_progress()
			assert_eq(SaveManager.capture_state(), committed, label + " reload")
			assert_eq(changed_count[0], 1, label)
			assert_eq(completed_count[0], 1 if action == "finalize" else 0, label)
			ExpeditionManager.changed.disconnect(changed_callback)
			ExpeditionManager.completed.disconnect(completed_callback)


func test_recovery_deadline_bounds_reject_before_mutation_and_accept_maximum_exactly() -> void:
	_configure("DEFEAT")
	var party := _confirm()
	var before := SaveManager.capture_state()
	for invalid in [0, -1, HeroCatalog.MAX_SAFE_INT + 1]:
		ExpeditionManager.balancing.base_recovery_seconds = invalid
		ExpeditionManager.start_expedition(REGION, party, 60)
		assert_false(ExpeditionManager.last_committed)
		assert_eq(SaveManager.capture_state(), before)
	ExpeditionManager.balancing.base_recovery_seconds = 60
	var run := _dispatch(party)
	_wound(GameState.roster[2], 1001)
	SaveManager.save()
	var saved := SaveManager.capture_state()
	ExpeditionManager.balancing.base_recovery_seconds = -1
	for now in [HeroCatalog.MAX_SAFE_INT, HeroCatalog.MAX_SAFE_INT - 59]:
		_observe(now)
		assert_false(ExpeditionManager.last_committed)
		assert_eq(SaveManager.capture_state(), saved)
	_observe(HeroCatalog.MAX_SAFE_INT - 60)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(run.credited_elapsed_seconds, 12)
	for id in run.final_hero_states():
		assert_eq(GameState.find_hero(id).recovery_ready_at, HeroCatalog.MAX_SAFE_INT)
	assert_eq(GameState.roster[2].status, HeroData.HeroStatus.IDLE)
	_observe(HeroCatalog.MAX_SAFE_INT)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	for id in run.final_hero_states():
		assert_eq(GameState.find_hero(id).status, HeroData.HeroStatus.IDLE)
		assert_eq(GameState.find_hero(id).recovery_ready_at, 0)


func test_gold_overflow_blocks_terminal_finalization_and_due_recovery_together() -> void:
	var run := _rewarding_defeat()
	if run == null:
		return
	var reward := 0
	for step in run.steps:
		reward += int(step.result.gold)
	assert_gt(reward, 0)
	_wound(GameState.roster[2], 1001)
	GameState.gold = HeroCatalog.MAX_SAFE_INT
	SaveManager.save()
	var saved := SaveManager.capture_state()
	_observe(5000)
	assert_false(ExpeditionManager.last_committed)
	assert_eq(SaveManager.capture_state(), saved)
	assert_same(ExpeditionManager.get_active_expedition(), run)
	GameState.gold -= reward
	ExpeditionManager.balancing.base_recovery_seconds = 7
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(GameState.gold, HeroCatalog.MAX_SAFE_INT)
	assert_eq(run.status, ExpeditionData.Status.COMPLETED)
	for id in run.final_hero_states():
		assert_eq(GameState.find_hero(id).recovery_ready_at, 5060)
	assert_eq(GameState.roster[2].status, HeroData.HeroStatus.IDLE)
	assert_eq(GameState.roster[2].recovery_ready_at, 0)


func test_recovery_rejects_invalid_clock_and_state_without_mutating_any_hero() -> void:
	_wound(GameState.roster[0], 1000)
	SaveManager.save()
	var saved := SaveManager.capture_state()
	for invalid in [null, true, -1, INF, NAN, 1000.1, HeroCatalog.MAX_SAFE_INT + 1]:
		ExpeditionManager.clock = func() -> Variant: return invalid
		ExpeditionManager.reveal_progress()
		assert_false(ExpeditionManager.last_committed)
		assert_eq(SaveManager.capture_state(), saved)
	ExpeditionManager.clock = func() -> int: return 1000
	GameState.gold = -1
	var invalid_state := SaveManager.capture_state()
	ExpeditionManager.reveal_progress()
	assert_false(ExpeditionManager.last_committed)
	assert_eq(SaveManager.capture_state(), invalid_state)
	GameState.gold = 100
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.IDLE)
	assert_eq(GameState.roster[0].recovery_ready_at, 0)


func test_invalid_combat_dispatch_keeps_party_sequence_gold_statuses_and_save_unchanged() -> void:
	_configure("VICTORY")
	var party := _confirm()
	var saved := SaveManager.capture_state()
	var primary := FileAccess.get_file_as_string(SaveManager.get_save_path())
	var original_enemies := _group.enemies.duplicate(true)
	_group.enemies = []
	ExpeditionManager.start_expedition(REGION, party, 60)
	assert_false(ExpeditionManager.last_committed)
	assert_eq(SaveManager.capture_state(), saved)
	_group.enemies = original_enemies
	_guard.effect = "Invalid"
	ExpeditionManager.start_expedition(REGION, party, 60)
	assert_false(ExpeditionManager.last_committed)
	assert_eq(SaveManager.capture_state(), saved)
	_guard.effect = _guard_effect
	ExpeditionManager.balancing.max_combat_rounds = 0
	ExpeditionManager.start_expedition(REGION, party, 60)
	assert_false(ExpeditionManager.last_committed)
	assert_eq(SaveManager.capture_state(), saved)
	ExpeditionManager.balancing.max_combat_rounds = 1
	_time = HeroCatalog.MAX_SAFE_INT - 59
	ExpeditionManager.start_expedition(REGION, party, 60)
	assert_false(ExpeditionManager.last_committed)
	assert_eq(SaveManager.capture_state(), saved)
	assert_same(GameState.current_party, party)
	assert_null(ExpeditionManager.get_active_expedition())
	assert_eq(FileAccess.get_file_as_string(SaveManager.get_save_path()), primary)
