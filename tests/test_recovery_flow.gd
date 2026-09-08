extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
var _isolation: RefCounted
var _time := 1000


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	_time = 1000
	ExpeditionManager.clock = func() -> int: return _time
	ExpeditionManager.balancing = ExpeditionManager.DEFAULT_BALANCING.duplicate(true)
	SaveManager.load_or_create()


func after_each() -> void:
	_isolation.finish()


func _install(hp: int, percentage: int = 25, outcome: String = "VICTORY") -> ExpeditionData:
	var hero := GameState.roster[0]
	var party := PartyData.new()
	party.place_hero(0, hero)
	var snapshot := ExpeditionPartySnapshot.capture(party, true).slots
	snapshot.FRONT_LEFT.derived_stats.MaxHP = 100
	var state := {"hp": hp, "status": HeroData.HeroStatus.WOUNDED if hp == 0 else HeroData.HeroStatus.IDLE}
	if hp == 0:
		outcome = "DEFEAT"
	var actions: Array = [{
		"actor_id": "enemy", "actor_name": "Enemy", "target_id": hero.hero_id, "target_name": hero.hero_name,
		"action_name": "Attack", "effect": "Physical", "damage_or_heal": 100 - hp, "hit": true, "was_crit": false,
	}]
	if hp > 0:
		actions.append({
			"actor_id": hero.hero_id, "actor_name": hero.hero_name, "target_id": "enemy", "target_name": "Enemy",
			"action_name": "Attack", "effect": "Physical", "damage_or_heal": 1 if outcome == "VICTORY" else 0,
			"hit": outcome == "VICTORY", "was_crit": false,
		})
	var terminal := outcome != "VICTORY"
	var result := {"gold": 0, "outcome": outcome, "rounds": [{"round_number": 1, "actions": actions}],
		"final_hero_states": {hero.hero_id: state},
		"enemy_states": {"enemy": {"name": "Enemy", "max_hp": 1, "hp": 0 if outcome == "VICTORY" else 1, "row": "Front"}}}
	var record := {
		"region_id": "green_hollow", "region_name": "Green Hollow", "party_snapshot": snapshot,
		"seed": 42, "start_timestamp": 1000, "duration_seconds": 60,
		"step_duration_seconds": 6 if terminal else 30,
		"planned_step_count": 10 if terminal else 2, "retreat_ends_expedition": true,
		"xp_award": 100, "recovery_seconds": 60, "rest_hp_percent": percentage,
		"terminal_step_index": 1 if terminal else -1, "effective_end_timestamp": 1012 if terminal else 1060,
		"steps": [
			{"kind": ExpeditionStep.StepKind.TRAVEL, "content_id": "", "outcome_id": "", "title": "Travel",
				"journal_text": "The road.", "result": {"gold": 0}},
			{"kind": ExpeditionStep.StepKind.COMBAT, "content_id": "bandit_skirmishers", "outcome_id": outcome,
				"title": "Combat", "journal_text": "A fight.", "result": result}],
	}
	var run := ExpeditionData.new(record)
	assert_true(ExpeditionData.valid(run.serialize()))
	hero.status = HeroData.HeroStatus.ON_EXPEDITION
	hero.recovery_ready_at = 0
	ExpeditionManager.replace_from_save(run.serialize())
	SaveManager.save()
	assert_true(SaveManager.last_committed, SaveManager.last_error)
	return ExpeditionManager.get_active_expedition()


func test_rest_threshold_uses_dispatch_hp_inclusive_boundary_and_never_changes_combat_maps() -> void:
	for hp in [24, 25, 26, 0]:
		_time = 1000
		assert_true(RecruitmentService.initialize_new_game(12345))
		var run := _install(hp)
		var frozen := run.serialize()
		var hero := GameState.roster[0]
		hero.level = 20
		hero.equipped_armor = ItemCatalog.CHAINMAIL
		ExpeditionManager.balancing.recovery_hp_percent = 100
		ExpeditionManager.balancing.base_recovery_seconds = 1
		_time = 5000
		ExpeditionManager.reveal_progress()
		assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
		assert_eq(hero.status, HeroData.HeroStatus.RESTING if hp <= 25 else HeroData.HeroStatus.IDLE)
		assert_eq(hero.recovery_ready_at, 5060 if hp <= 25 else 0)
		assert_eq(hero.xp, 100, "Defeat and Victory both grant the frozen selected-duration award.")
		assert_eq(run.serialize().steps, frozen.steps)
		assert_eq(run.serialize().party_snapshot, frozen.party_snapshot)


func test_terminal_retreat_grants_full_frozen_xp_and_legacy_percentage_does_not_rest_survivors() -> void:
	var run := _install(1, 0, "RETREAT")
	var hero := GameState.roster[0]
	_time = 1012
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(run.credited_elapsed_seconds, 12)
	assert_eq(run.duration_seconds, 60)
	assert_eq(hero.xp, 100)
	assert_eq(hero.level, 2)
	assert_eq(hero.status, HeroData.HeroStatus.IDLE)
	assert_eq(hero.recovery_ready_at, 0)


func test_resting_deadline_survives_reload_recovers_only_when_due_and_is_retryable() -> void:
	_install(25)
	_time = 5000
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed)
	SaveManager.load_or_create()
	var hero := GameState.roster[0]
	assert_eq(hero.status, HeroData.HeroStatus.RESTING)
	assert_eq(hero.recovery_ready_at, 5060)
	_time = 5059
	ExpeditionManager.reveal_progress()
	assert_eq(hero.status, HeroData.HeroStatus.RESTING)
	var before := SaveManager.capture_state()
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "before_primary_replace"
	_time = 5060
	ExpeditionManager.reveal_progress()
	assert_false(ExpeditionManager.last_committed)
	assert_eq(SaveManager.capture_state(), before)
	assert_same(GameState.roster[0], hero)
	SaveManager.fault_injector = Callable()
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed)
	assert_eq(hero.status, HeroData.HeroStatus.IDLE)
	assert_eq(hero.recovery_ready_at, 0)
	assert_eq(hero.xp, 100)


func test_dispatch_rejects_frozen_recovery_deadline_overflow_without_mutation() -> void:
	var party := PartyData.new()
	party.place_hero(0, GameState.roster[0])
	assert_true(PartyFormationService.confirm(party, ExpeditionManager.balancing))
	var before := SaveManager.capture_state()
	ExpeditionManager.balancing.base_recovery_seconds = HeroCatalog.MAX_SAFE_INT
	ExpeditionManager.start_expedition(ExpeditionCatalog.GREEN_HOLLOW, GameState.current_party, 60)
	assert_false(ExpeditionManager.last_committed)
	assert_string_contains(ExpeditionManager.last_error, "recovery deadline")
	assert_eq(SaveManager.capture_state(), before)
