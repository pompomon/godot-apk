extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
var _isolation: RefCounted
var _original_enemies: Array[Dictionary]
var _original_skill_name: String
var _original_rounds: int
var _changed_group: EnemyGroupResource
var _changed_skill: SkillResource
var _changed_balancing: BalancingConfig


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	_changed_group = CombatCatalog.BANDIT_SKIRMISHERS
	_changed_skill = CombatCatalog.GUARD
	_original_enemies = _changed_group.enemies.duplicate(true)
	_original_skill_name = _changed_skill.display_name
	_changed_balancing = ExpeditionManager.DEFAULT_BALANCING
	_original_rounds = _changed_balancing.max_combat_rounds
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success)


func after_each() -> void:
	_changed_group.enemies = _original_enemies
	_changed_skill.display_name = _original_skill_name
	_changed_balancing.max_combat_rounds = _original_rounds
	_isolation.finish()


func _snapshot(count: int = 2) -> Dictionary:
	var party := PartyData.new()
	for index in range(count):
		party.place_hero(index, GameState.roster[index])
	var snapshot := ExpeditionPartySnapshot.capture(party, true).slots
	for member in snapshot.values():
		if member != null:
			member.derived_stats.MaxHP = 20
	return snapshot


func _states(snapshot: Dictionary) -> Dictionary:
	return ExpeditionPartySnapshot.new(snapshot).hero_states()


func _action(actor: String, target: String, amount: int, effect: String = "Physical",
		hit: bool = true, crit: bool = false, action_name: String = "Attack") -> Dictionary:
	var actor_hero := GameState.find_hero(actor)
	var target_hero := GameState.find_hero(target)
	return {
		"actor_id": actor, "target_id": target,
		"actor_name": actor_hero.hero_name if actor_hero != null else "Enemy " + actor,
		"target_name": target_hero.hero_name if target_hero != null else "Enemy " + target,
		"action_name": action_name, "effect": effect,
		"damage_or_heal": amount, "hit": hit, "was_crit": crit,
	}


func _victory(snapshot: Dictionary, current: Dictionary = {}) -> Dictionary:
	var states := _states(snapshot) if current.is_empty() else current.duplicate(true)
	var id: String = states.keys()[0]
	states[id].hp -= 7
	return {
		"gold": 0, "outcome": "VICTORY",
		"rounds": [{"round_number": 1, "actions": [
			_action("enemy-a", id, 7), _action(id, "enemy-a", 25),
		]}],
		"final_hero_states": states,
		"enemy_states": {"enemy-a": {"name": "Enemy enemy-a", "max_hp": 10, "hp": 0, "row": "Front"}},
	}


func _retreat(snapshot: Dictionary, round_count: int = 1, enemy_count: int = 1) -> Dictionary:
	var states := _states(snapshot)
	var enemies := {}
	for index in range(enemy_count):
		var id := "enemy-%d" % index
		enemies[id] = {"name": "Enemy " + id, "max_hp": 20, "hp": 20, "row": "Front"}
	var rounds: Array = []
	for number in range(1, round_count + 1):
		var actions: Array = []
		for id in states:
			actions.append(_action(id, enemies.keys()[0], 0, "Physical", false))
		for id in enemies:
			actions.append(_action(id, states.keys()[0], 0, "Physical", false))
		rounds.append({"round_number": number, "actions": actions})
	return {"gold": 0, "outcome": "RETREAT", "rounds": rounds,
		"final_hero_states": states, "enemy_states": enemies}


func _defeat(snapshot: Dictionary) -> Dictionary:
	var states := _states(snapshot)
	var rounds: Array = []
	for id in states:
		states[id] = {"hp": 0, "status": HeroData.HeroStatus.WOUNDED}
		var actions: Array = [_action("enemy-a", id, 30)]
		for survivor in states:
			if states[survivor].hp > 0:
				actions.append(_action(survivor, "enemy-a", 0, "Physical", false))
		rounds.append({"round_number": rounds.size() + 1, "actions": actions})
	return {"gold": 0, "outcome": "DEFEAT", "rounds": rounds,
		"final_hero_states": states,
		"enemy_states": {"enemy-a": {"name": "Enemy enemy-a", "max_hp": 10, "hp": 10, "row": "Front"}}}


func _record(snapshot: Dictionary, results: Array, planned: int = 0, terminal_retreat: bool = false) -> Dictionary:
	var steps: Array = []
	var terminal := -1
	for result in results:
		steps.append({"kind": ExpeditionStep.StepKind.TRAVEL, "content_id": "", "outcome_id": "",
			"title": "Travel", "journal_text": "On the road.", "result": {"gold": 0}})
		steps.append({"kind": ExpeditionStep.StepKind.COMBAT, "content_id": "bandit_skirmishers",
			"outcome_id": result.outcome, "title": "Frozen combat", "journal_text": "An encounter.",
			"result": result.duplicate(true)})
		if result.outcome == "DEFEAT" or (result.outcome == "RETREAT" and terminal_retreat):
			terminal = steps.size() - 1
	if planned == 0:
		planned = steps.size()
	@warning_ignore("integer_division")
	var slice: int = 60 / planned
	return {
		"region_id": "green_hollow", "region_name": "Green Hollow",
		"party_snapshot": ExpeditionPartySnapshot.new(snapshot).serialize(),
		"seed": 42, "start_timestamp": 1000, "duration_seconds": 60,
		"planned_step_count": planned, "retreat_ends_expedition": terminal_retreat,
		"xp_award": 0, "recovery_seconds": 60, "rest_hp_percent": 0,
		"step_duration_seconds": slice, "steps": steps, "terminal_step_index": terminal,
		"effective_end_timestamp": 1060 if terminal == -1 else 1000 + (terminal + 1) * slice,
		"last_observed_utc": 1000, "credited_elapsed_seconds": 0,
		"last_revealed_index": -1, "status": ExpeditionData.Status.RUNNING,
	}


func _complete(record: Dictionary) -> Dictionary:
	var completed := record.duplicate(true)
	completed.credited_elapsed_seconds = int(completed.effective_end_timestamp) - 1000
	completed.last_revealed_index = completed.steps.size() - 1
	completed.last_observed_utc = completed.effective_end_timestamp
	completed.status = ExpeditionData.Status.COMPLETED
	return completed


func _install(record: Dictionary) -> void:
	GameState.current_party = null
	ExpeditionManager.replace_from_save(record)
	var run := ExpeditionManager.get_active_expedition()
	var final := run.final_hero_states()
	for id in final:
		var hero := GameState.find_hero(id)
		hero.status = HeroData.HeroStatus.ON_EXPEDITION if run.status == ExpeditionData.Status.RUNNING else int(final[id].status) as HeroData.HeroStatus
		if hero.status == HeroData.HeroStatus.WOUNDED:
			hero.status = HeroData.HeroStatus.RESTING
		hero.recovery_ready_at = 2000 if hero.status == HeroData.HeroStatus.RESTING else 0


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file)
	var text := file.get_as_text()
	file.close()
	return text


func _changed(original: Dictionary, path: Array, value: Variant) -> Dictionary:
	var result := original.duplicate(true)
	var target: Variant = result
	for index in range(path.size() - 1):
		target = target[path[index]]
	target[path[-1]] = value
	return result


func test_combat_running_completed_and_terminal_saves_round_trip_exactly() -> void:
	var snapshot := _snapshot()
	for result in [_victory(snapshot), _retreat(snapshot), _defeat(snapshot)]:
		var record := _record(snapshot, [result], 10 if result.outcome == "DEFEAT" else 2)
		for saved_record in [record, _complete(record)]:
			_install(saved_record)
			SaveManager.save()
			assert_true(SaveManager.last_committed, SaveManager.last_error)
			var expected := SaveManager.capture_state()
			var encoded := JSON.stringify(expected, "", true, true)
			GameState.reset()
			SaveManager.load_or_create()
			assert_true(SaveManager.last_success, SaveManager.last_error)
			assert_eq(SaveManager.capture_state(), expected)
			assert_eq(JSON.stringify(SaveManager.capture_state(), "", true, true), encoded)
			var run := ExpeditionManager.get_active_expedition()
			assert_eq(run.final_hero_states(), result.final_hero_states)
			assert_eq(typeof(run.steps[1].result.rounds[0].round_number), TYPE_INT)
			assert_eq(typeof(run.steps[1].result.final_hero_states["hero-1"].hp), TYPE_INT)
			assert_eq(typeof(run.party_snapshot.slots.FRONT_LEFT.active_skill.cooldown_turns), TYPE_INT)


func test_historical_logs_ignore_live_enemy_skill_and_balancing_changes() -> void:
	var snapshot := _snapshot()
	_install(_record(snapshot, [_victory(snapshot)]))
	SaveManager.save()
	assert_true(SaveManager.last_committed)
	var original := SaveManager.capture_state()
	_changed_group.enemies.clear()
	_changed_skill.display_name = "Retuned guard"
	_changed_balancing.max_combat_rounds = 0
	assert_true(SaveManager.validate_snapshot(original))
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success, SaveManager.last_error)
	assert_eq(SaveManager.capture_state(), original)


func test_combat_provenance_carries_hp_and_returns_detached_final_states() -> void:
	var snapshot := _snapshot()
	var first := _victory(snapshot)
	var second := _victory(snapshot, first.final_hero_states)
	var record := _record(snapshot, [first, second])
	assert_true(ExpeditionData.valid(record))
	var run := ExpeditionData.new(record)
	assert_eq(run.final_hero_states()["hero-1"].hp, 6)
	var detached := run.final_hero_states()
	detached["hero-1"].hp = 20
	assert_eq(run.final_hero_states()["hero-1"].hp, 6)
	record.steps[3].result = _victory(snapshot)
	assert_false(ExpeditionData.valid(record), "A later combat cannot silently restore starting HP.")
	var current := _states(snapshot)
	current["hero-2"] = {"hp": 0, "status": HeroData.HeroStatus.WOUNDED}
	var result := _victory(snapshot, current)
	assert_true(CombatResult.valid(result, snapshot, current))
	result.final_hero_states["hero-2"] = {"hp": 1, "status": HeroData.HeroStatus.IDLE}
	assert_false(CombatResult.valid(result, snapshot, current))
	current["hero-1"].status = HeroData.HeroStatus.WOUNDED
	assert_false(CombatResult.valid(_victory(snapshot, current), snapshot, current))
	var untouched := first.duplicate(true)
	assert_true(CombatResult.valid(first, ExpeditionPartySnapshot.new(snapshot)))
	assert_eq(first, untouched)


func test_terminal_metadata_progress_and_clock_are_frozen_and_consistent() -> void:
	var snapshot := _snapshot()
	for result in [_defeat(snapshot), _retreat(snapshot)]:
		var record := _record(snapshot, [result], 10, true)
		assert_true(ExpeditionData.valid(record))
		var run := ExpeditionData.new(record)
		assert_eq(run.step_duration_seconds, 6)
		assert_eq(run.effective_end_timestamp, 1012)
		assert_eq(run.display_step_count(), 10)
		assert_eq(run.seconds_remaining(), 60)
		record.credited_elapsed_seconds = 6
		record.last_revealed_index = 0
		assert_true(ExpeditionData.valid(record))
		run = ExpeditionData.new(record)
		assert_eq(run.seconds_remaining(), 54)
		var completed := _complete(record)
		assert_true(ExpeditionData.valid(completed))
		run = ExpeditionData.new(completed)
		assert_eq(run.display_step_count(), 2)
		assert_eq(run.seconds_remaining(), 0)
		for change in [["terminal_step_index", -1], ["terminal_step_index", 0],
				["planned_step_count", 2], ["effective_end_timestamp", 1060],
				["credited_elapsed_seconds", 13], ["last_revealed_index", 2], ["status", 0]]:
			var bad := completed.duplicate(true)
			bad[change[0]] = change[1]
			assert_false(ExpeditionData.valid(bad), str(change))
		var later := _record(snapshot, [result, _retreat(snapshot)], 10, true)
		assert_false(ExpeditionData.valid(later), "Terminal encounters cannot retain later steps.")
	var retreat := _record(snapshot, [_retreat(snapshot), _victory(snapshot)])
	assert_true(ExpeditionData.valid(retreat))
	retreat.retreat_ends_expedition = true
	assert_false(ExpeditionData.valid(retreat))
	var victory := _record(snapshot, [_victory(snapshot)])
	victory.terminal_step_index = 1
	assert_false(ExpeditionData.valid(victory), "Victory is never a terminal truncation.")
	var old_caller := _record(snapshot, [_victory(snapshot)])
	old_caller.erase("planned_step_count")
	old_caller.erase("retreat_ends_expedition")
	assert_false(ExpeditionData.valid(old_caller))
	var constructed := ExpeditionData.new(old_caller)
	assert_eq(constructed.planned_step_count, 2)
	assert_false(constructed.retreat_ends_expedition)
	assert_true(ExpeditionData.valid(constructed.serialize()))


func test_strict_result_action_state_and_round_validation_rejects_malformed_variants() -> void:
	var snapshot := _snapshot()
	var original := _victory(snapshot)
	var object := RefCounted.new()
	for malformed in [null, [], true, "combat", 0, object]:
		assert_false(CombatResult.valid(malformed, snapshot))
		assert_false(CombatResult.valid(original, malformed))
		assert_false(CombatResult.valid(original, snapshot, malformed if malformed != null else {}))
	for key in original:
		var missing := original.duplicate(true)
		missing.erase(key)
		assert_false(CombatResult.valid(missing, snapshot), "Missing " + key)
	for key in original.rounds[0].actions[0]:
		var missing := original.duplicate(true)
		missing.rounds[0].actions[0].erase(key)
		assert_false(CombatResult.valid(missing, snapshot), "Missing action " + key)
	var cases := [
		[["gold"], 1], [["gold"], true], [["outcome"], "WIN"], [["outcome"], "RETREAT"],
		[["extra"], 0], [["rounds"], {}], [["rounds"], []], [["rounds", 0], object],
		[["rounds", 0, "round_number"], 0], [["rounds", 0, "round_number"], 2],
		[["rounds", 0, "round_number"], true], [["rounds", 0, "actions"], []],
		[["rounds", 0, "actions", 0], null], [["rounds", 0, "actions", 0, "extra"], 0],
		[["final_hero_states"], {}], [["final_hero_states", "hero-1"], []],
		[["final_hero_states", "hero-1", "hp"], 14], [["final_hero_states", "hero-1", "status"], 4],
		[["final_hero_states", "unknown"], {"hp": 1, "status": 0}],
		[["enemy_states"], {}], [["enemy_states", "enemy-a"], object],
		[["enemy_states", "enemy-a", "max_hp"], 0], [["enemy_states", "enemy-a", "hp"], 1],
		[["enemy_states", "enemy-a", "row"], "Unknown"], [["enemy_states", "enemy-a", "name"], ""],
	]
	for change in cases:
		assert_false(CombatResult.valid(_changed(original, change[0], change[1]), snapshot), str(change[0]))
	for key in ["actor_id", "target_id", "actor_name", "target_name", "action_name", "effect"]:
		for value in ["", "unknown", "x".repeat(129), 1, true, object, {}]:
			assert_false(CombatResult.valid(_changed(original, ["rounds", 0, "actions", 0, key], value), snapshot), key)
	for key in ["hit", "was_crit"]:
		for value in [0, 1, "true", null, object]:
			assert_false(CombatResult.valid(_changed(original, ["rounds", 0, "actions", 0, key], value), snapshot), key)
	for value in [-1, 1.5, true, INF, NAN, HeroCatalog.MAX_SAFE_INT + 1, object]:
		for path in [["gold"], ["final_hero_states", "hero-1", "hp"],
				["final_hero_states", "hero-1", "status"], ["enemy_states", "enemy-a", "max_hp"],
				["enemy_states", "enemy-a", "hp"], ["rounds", 0, "actions", 0, "damage_or_heal"]]:
			assert_false(CombatResult.valid(_changed(original, path, value), snapshot), str(path))
	var bad := original.duplicate(true)
	bad.rounds[0].actions.insert(1, bad.rounds[0].actions[0].duplicate(true))
	assert_false(CombatResult.valid(bad, snapshot), "One action per actor each round.")
	bad = original.duplicate(true)
	bad.rounds[0].actions.append(_action("hero-2", "enemy-a", 1))
	assert_false(CombatResult.valid(bad, snapshot), "No actions after combat ends.")
	bad = original.duplicate(true)
	bad.rounds[0].actions[0] = _action("hero-2", "hero-1", 7)
	assert_false(CombatResult.valid(bad, snapshot), "Damage cannot target allies.")
	bad = original.duplicate(true)
	bad.rounds[0].actions[0].hit = false
	assert_false(CombatResult.valid(bad, snapshot))
	var missing_skill := snapshot.duplicate(true)
	missing_skill.FRONT_LEFT.erase("active_skill")
	assert_false(CombatResult.valid(original, missing_skill))
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(original, "", true, true))
	assert_true(CombatResult.valid(parsed, snapshot))
	assert_eq(ExpeditionStep.new({"result": parsed}).result, original)


func test_heal_guard_miss_dead_actor_and_immediate_defeat_rules() -> void:
	var snapshot := _snapshot()
	snapshot.FRONT_LEFT.active_skill = CombatCatalog.MEND.snapshot()
	var current := _states(snapshot)
	current["hero-1"].hp = 10
	current["hero-2"] = {"hp": 0, "status": HeroData.HeroStatus.WOUNDED}
	var result := _retreat(snapshot)
	result.final_hero_states = current.duplicate(true)
	result.final_hero_states["hero-1"].hp = 20
	result.rounds[0].actions = [
		_action("hero-1", "hero-1", 50, "Heal", true, false, "Mend"),
		_action("enemy-0", "hero-1", 0, "Physical", false),
	]
	assert_true(CombatResult.valid(result, snapshot, current), "Healing is clamped, not its logged amount.")
	for change in [["hit", false], ["was_crit", true], ["target_id", "hero-2"]]:
		assert_false(CombatResult.valid(_changed(result, ["rounds", 0, "actions", 0, change[0]], change[1]), snapshot, current))
	result.rounds[0].actions[0] = _action("hero-2", "enemy-0", 1)
	assert_false(CombatResult.valid(result, snapshot, current), "Dead Heroes cannot act.")
	result.rounds[0].actions[0] = _action("hero-1", "hero-1", 0, "Heal", true, false, "Mend")
	result.final_hero_states = current.duplicate(true)
	assert_true(CombatResult.valid(result, snapshot, current), "A configured zero heal is valid.")
	snapshot.FRONT_LEFT.active_skill = CombatCatalog.GUARD.snapshot()
	result.rounds[0].actions[0] = _action("hero-1", "hero-1", 0, "Guard", true, false, "Guard")
	assert_true(CombatResult.valid(result, snapshot, current))
	for change in [["damage_or_heal", 1], ["hit", false], ["was_crit", true]]:
		assert_false(CombatResult.valid(_changed(result, ["rounds", 0, "actions", 0, change[0]], change[1]), snapshot, current))
	result.rounds[0].actions[0] = _action("hero-1", "enemy-0", 0, "Physical", false)
	assert_true(CombatResult.valid(result, snapshot, current))
	result.rounds[0].actions[0].was_crit = true
	assert_false(CombatResult.valid(result, snapshot, current))
	current["hero-1"] = {"hp": 0, "status": HeroData.HeroStatus.WOUNDED}
	result.outcome = "DEFEAT"
	result.rounds = []
	result.final_hero_states = current.duplicate(true)
	assert_true(CombatResult.valid(result, snapshot, current))
	result.outcome = "VICTORY"
	assert_false(CombatResult.valid(result, snapshot, current))


func test_integer_json_float_statuses_preserve_complete_hp_provenance() -> void:
	var snapshot := _snapshot()
	var current := _states(snapshot)
	current["hero-2"] = {"hp": 0, "status": HeroData.HeroStatus.WOUNDED}
	var result := _victory(snapshot, current)
	assert_true(CombatResult.valid(result, snapshot, current))
	var parsed_snapshot: Dictionary = JSON.parse_string(JSON.stringify(ExpeditionPartySnapshot.new(snapshot).serialize(), "", true, true))
	var parsed_current: Dictionary = JSON.parse_string(JSON.stringify(current, "", true, true))
	var parsed_result: Dictionary = JSON.parse_string(JSON.stringify(result, "", true, true))
	assert_eq(typeof(parsed_current["hero-1"].status), TYPE_FLOAT)
	assert_eq(typeof(parsed_current["hero-2"].status), TYPE_FLOAT)
	assert_eq(parsed_result.final_hero_states["hero-1"].status, 0.0)
	assert_eq(parsed_result.final_hero_states["hero-2"].status, 4.0)
	assert_true(CombatResult.valid(parsed_result, parsed_snapshot, parsed_current))
	for invalid in [0.5, 4.5, true, "0"]:
		parsed_result.final_hero_states["hero-1"].status = invalid
		assert_false(CombatResult.valid(parsed_result, parsed_snapshot, parsed_current))
	parsed_result.final_hero_states["hero-1"].status = 0.0
	assert_true(CombatResult.valid(parsed_result, parsed_snapshot, parsed_current))


func test_combat_step_identity_noncombat_payload_and_collection_bounds_remain_strict() -> void:
	var snapshot := _snapshot(4)
	var result := _retreat(snapshot, 100, 4)
	assert_true(CombatResult.valid(result, snapshot))
	var record := _record(snapshot, [result])
	for change in [["content_id", "unknown"], ["content_id", "res://data/encounters/bandit_skirmishers.tres"],
			["outcome_id", ""], ["outcome_id", "VICTORY"], ["kind", 0], ["kind", 1]]:
		var bad := record.duplicate(true)
		bad.steps[1][change[0]] = change[1]
		assert_false(ExpeditionData.valid(bad), str(change))
	record.steps[0].result = result
	assert_false(ExpeditionData.valid(record))
	var bad_result := result.duplicate(true)
	bad_result.rounds.append(result.rounds[0])
	assert_false(CombatResult.valid(bad_result, snapshot))
	bad_result = result.duplicate(true)
	bad_result.rounds[0].actions.append(result.rounds[0].actions[0])
	assert_false(CombatResult.valid(bad_result, snapshot))
	bad_result = result.duplicate(true)
	bad_result.enemy_states["enemy-extra"] = result.enemy_states["enemy-0"]
	assert_false(CombatResult.valid(bad_result, snapshot))
	bad_result = result.duplicate(true)
	bad_result.enemy_states["hero-1"] = bad_result.enemy_states["enemy-0"]
	bad_result.enemy_states.erase("enemy-0")
	assert_false(CombatResult.valid(bad_result, snapshot), "Hero and enemy IDs cannot collide.")


func test_nonterminal_round_requires_every_surviving_combatant_to_act() -> void:
	var snapshot := _snapshot()
	var original := _retreat(snapshot, 2)
	assert_true(CombatResult.valid(original, snapshot))
	for round_index in range(2):
		for action_index in range(original.rounds[round_index].actions.size()):
			var incomplete := original.duplicate(true)
			incomplete.rounds[round_index].actions.remove_at(action_index)
			assert_false(CombatResult.valid(incomplete, snapshot), "Missing surviving actor.")
	assert_true(CombatResult.valid(_victory(snapshot), snapshot), "Combat may end before all surviving actors take a turn.")
	assert_true(CombatResult.valid(_defeat(snapshot), snapshot), "Actors killed before their turn are not required to act.")


func test_five_twenty_round_encounters_fit_and_round_trip_without_log_loss() -> void:
	var snapshot := _snapshot(4)
	var combat := _retreat(snapshot, 20, 4)
	_install(_record(snapshot, [combat, combat, combat, combat, combat]))
	var expected := SaveManager.capture_state()
	assert_true(SaveManager.validate_snapshot(expected))
	assert_lt(JSON.stringify(expected, "\t", true, true).to_utf8_buffer().size(), SaveManager.MAX_SAVE_BYTES)
	SaveManager.save()
	assert_true(SaveManager.last_committed, SaveManager.last_error)
	GameState.reset()
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), expected)


func test_exact_size_limit_and_oversize_save_preserve_previous_primary_and_backup() -> void:
	var snapshot := _snapshot(4)
	var low := 1
	var high := 100
	var best := {}
	while low <= high:
		@warning_ignore("integer_division")
		var count: int = (low + high) / 2
		var combat := _retreat(snapshot, count, 4)
		_install(_record(snapshot, [combat, combat, combat, combat, combat]))
		var candidate := SaveManager.capture_state()
		if JSON.stringify(candidate, "\t", true, true).to_utf8_buffer().size() <= SaveManager.MAX_SAVE_BYTES:
			best = candidate
			low = count + 1
		else:
			high = count - 1
	assert_false(best.is_empty())
	var remaining := SaveManager.MAX_SAVE_BYTES - JSON.stringify(best, "\t", true, true).to_utf8_buffer().size()
	for step in best.expedition.steps:
		var amount := mini(remaining, 4096 - step.journal_text.length())
		step.journal_text += "x".repeat(amount)
		remaining -= amount
	assert_eq(remaining, 0)
	assert_true(SaveManager.validate_snapshot(best))
	assert_eq(JSON.stringify(best, "\t", true, true).to_utf8_buffer().size(), SaveManager.MAX_SAVE_BYTES)
	var exact: Dictionary = best.expedition.duplicate(true)
	best.expedition.steps[0].journal_text = best.expedition.steps[0].journal_text.left(-1)
	_install(best.expedition)
	SaveManager.save()
	assert_true(SaveManager.last_committed, SaveManager.last_error)
	assert_eq(_read(SaveManager.get_save_path()).to_utf8_buffer().size(), SaveManager.MAX_SAVE_BYTES - 1)
	_install(exact)
	SaveManager.save()
	assert_true(SaveManager.last_committed, SaveManager.last_error)
	var primary := _read(SaveManager.get_save_path())
	var backup := _read(SaveManager.get_save_path() + ".bak")
	assert_eq(primary.to_utf8_buffer().size(), SaveManager.MAX_SAVE_BYTES)
	for step in exact.steps:
		if step.journal_text.length() < 4096:
			step.journal_text += "x"
			break
	_install(exact)
	assert_true(SaveManager.validate_snapshot(SaveManager.capture_state()))
	SaveManager.save()
	assert_false(SaveManager.last_committed)
	assert_string_contains(SaveManager.last_error, "size")
	assert_eq(_read(SaveManager.get_save_path()), primary)
	assert_eq(_read(SaveManager.get_save_path() + ".bak"), backup)


func test_combat_completion_recovery_checkpoint_retries_all_save_boundaries() -> void:
	var snapshot := _snapshot()
	var record := _record(snapshot, [_defeat(snapshot)], 10)
	for boundary in ["before_temp_write", "after_temp_validation", "after_backup_preparation",
			"after_backup_replace", "before_primary_replace", "after_primary_replace"]:
		SaveManager.fault_injector = Callable()
		_install(record)
		SaveManager.save()
		assert_true(SaveManager.last_committed)
		var original := SaveManager.capture_state()
		var hero: HeroData = GameState.roster[0]
		var company_before := GameState.checkpoint()
		var manager_before := ExpeditionManager.checkpoint()
		_install(_complete(record))
		SaveManager.fault_injector = func(stage: String) -> bool: return stage == boundary
		SaveManager.save()
		if not SaveManager.last_committed:
			GameState.restore_checkpoint(company_before)
			ExpeditionManager.restore_checkpoint(manager_before)
			assert_eq(SaveManager.capture_state(), original, boundary)
			assert_eq(hero.recovery_ready_at, 0)
		else:
			assert_eq(boundary, "after_primary_replace")
			assert_eq(hero.recovery_ready_at, 2000)
			assert_false(SaveManager.last_warning.is_empty())
		assert_same(GameState.roster[0], hero)
		SaveManager.fault_injector = Callable()
		_install(_complete(record))
		SaveManager.save()
		assert_true(SaveManager.last_committed)
		var expected := SaveManager.capture_state()
		GameState.reset()
		SaveManager.load_or_create()
		assert_eq(SaveManager.capture_state(), expected, boundary)
