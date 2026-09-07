extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
const REGION: RegionResource = preload("res://data/regions/green_hollow.tres")
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


func _start() -> Dictionary:
	var party := PartyData.new()
	party.place_hero(0, GameState.roster[0])
	party.place_hero(3, GameState.roster[1])
	assert_true(PartyFormationService.confirm(party, ExpeditionManager.balancing))
	ExpeditionManager.start_expedition(REGION, GameState.current_party, 60)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	return SaveManager.capture_state()


func _write(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	file.store_string(JSON.stringify(value, "", true, true))
	file.close()


func test_running_and_completed_round_trip_without_regeneration() -> void:
	_start()
	_time = 1025
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed)
	var running := SaveManager.capture_state()
	var encoded := JSON.stringify(running, "", true, true)
	GameState.reset()
	assert_null(ExpeditionManager.get_active_expedition())
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), running)
	assert_eq(JSON.stringify(SaveManager.capture_state(), "", true, true), encoded)
	assert_eq(ExpeditionManager.get_active_expedition().last_revealed_index, 3)
	_time = 1060
	SaveManager.load_or_create()
	var completed := SaveManager.capture_state()
	assert_eq(completed.expedition.status, ExpeditionData.Status.COMPLETED)
	assert_eq(completed.expedition.last_revealed_index, 9)
	assert_gt(completed.gold, 100)
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.IDLE)
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), completed)
	assert_false(ExpeditionManager.is_expedition_active())


func test_live_combat_journals_fit_complete_saves_and_reload_without_log_loss() -> void:
	var region := REGION
	region.encounter_pool.assign(_original_pool)
	var combat_count := 0
	for seed_value in [1, 2]:
		assert_true(RecruitmentService.initialize_new_game(12345))
		GameState.expedition_seed = seed_value
		var party := PartyData.new()
		for index in range(GameState.roster.size()):
			assert_true(party.place_hero(index, GameState.roster[index]))
		assert_true(PartyFormationService.confirm(party, ExpeditionManager.balancing))
		ExpeditionManager.start_expedition(region, GameState.current_party, 60)
		assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
		var original := SaveManager.capture_state()
		assert_true(SaveManager.validate_snapshot(original))
		if original.expedition == null:
			continue
		for step in original.expedition.steps:
			if step.kind == ExpeditionStep.StepKind.COMBAT:
				combat_count += 1
				assert_false(step.result.rounds.is_empty())
		var encoded := JSON.stringify(original, "", true, true)
		var saved_text := FileAccess.get_file_as_string(SaveManager.get_save_path())
		assert_lte(saved_text.to_utf8_buffer().size(), SaveManager.MAX_SAVE_BYTES)
		assert_eq(JSON.parse_string(saved_text), JSON.parse_string(encoded))
		GameState.reset()
		SaveManager.load_or_create()
		assert_true(SaveManager.last_success, SaveManager.last_error)
		assert_eq(JSON.stringify(SaveManager.capture_state(), "", true, true), encoded)
	assert_gt(combat_count, 0, "The live-pool save check must include generated Combat logs.")


func test_saved_outcomes_and_snapshot_ignore_changed_encounters_and_class_statistics() -> void:
	var original := _start()
	var region := REGION
	var loot := ExpeditionCatalog.LOOT
	var region_count := region.travel_step_count
	var loot_min := loot.min_gold
	var loot_max := loot.max_gold
	var event := ExpeditionCatalog.events()[0]
	var outcomes := event.outcomes.duplicate()
	var hero_class := HeroCatalog.KNIGHT
	var bases := hero_class.derived_stat_bases.duplicate(true)
	var targeting := hero_class.basic_attack_target_rule
	region.travel_step_count = 7
	loot.min_gold = 1000
	loot.max_gold = 2000
	event.outcomes.clear()
	hero_class.derived_stat_bases.MaxHP = 300
	hero_class.basic_attack_target_rule = "AnySlot"
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success, SaveManager.last_error)
	assert_eq(SaveManager.capture_state(), original)
	assert_ne(ExpeditionManager.get_active_expedition().party_snapshot.slots.FRONT_LEFT.derived_stats,
		HeroStats.compute_derived_stats(GameState.roster[0]))
	_time = 1060
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_eq(ExpeditionManager.get_active_expedition().steps[1].serialize(), original.expedition.steps[1])
	region.travel_step_count = region_count
	loot.min_gold = loot_min
	loot.max_gold = loot_max
	event.outcomes.assign(outcomes)
	hero_class.derived_stat_bases = bases
	hero_class.basic_attack_target_rule = targeting


func test_rejects_malformed_numbers_timing_cursors_state_and_unknown_fields() -> void:
	var original := _start()
	var changes := [
		["region_id", "missing"], ["region_id", "res://data/regions/green_hollow.tres"],
		["region_name", ""], ["seed", -1], ["seed", true], ["seed", HeroCatalog.MAX_SAFE_INT + 1],
		["start_timestamp", -1], ["start_timestamp", HeroCatalog.MAX_SAFE_INT],
		["duration_seconds", 0], ["duration_seconds", 61], ["duration_seconds", 59],
		["step_duration_seconds", 0], ["step_duration_seconds", 5], ["step_duration_seconds", 6.1],
		["effective_end_timestamp", 1059], ["last_observed_utc", -1], ["last_observed_utc", INF],
		["credited_elapsed_seconds", -1], ["credited_elapsed_seconds", 61], ["credited_elapsed_seconds", 6],
		["last_revealed_index", 0], ["last_revealed_index", -2], ["last_revealed_index", 10],
		["terminal_step_index", 0], ["terminal_step_index", -2], ["status", 1], ["status", 2],
		["steps", []], ["steps", {}], ["party_snapshot", {}], ["status", "RUNNING"],
		["planned_step_count", 0], ["planned_step_count", 9], ["planned_step_count", 1026],
		["planned_step_count", 8], ["planned_step_count", true], ["planned_step_count", 10.5],
		["retreat_ends_expedition", 0], ["retreat_ends_expedition", "false"],
	]
	for change in changes:
		var bad := original.duplicate(true)
		bad.expedition[change[0]] = change[1]
		assert_false(SaveManager.validate_snapshot(bad), str(change))
	for key in original.expedition:
		var bad := original.duplicate(true)
		bad.expedition.erase(key)
		assert_false(SaveManager.validate_snapshot(bad), "Missing %s" % key)
	for key in ["expedition_seed", "expedition_sequence"]:
		for value in [null, true, "1", -1, 0.5, NAN, INF, HeroCatalog.MAX_SAFE_INT + 1]:
			var bad := original.duplicate(true)
			bad[key] = value
			assert_false(SaveManager.validate_snapshot(bad), "%s=%s" % [key, value])
	var bad := original.duplicate(true)
	bad.expedition["extra"] = 1
	assert_false(SaveManager.validate_snapshot(bad))
	bad = original.duplicate(true)
	bad.expedition.steps.pop_back()
	assert_false(SaveManager.validate_snapshot(bad))
	bad = original.duplicate(true)
	bad.expedition.credited_elapsed_seconds = 60
	bad.expedition.last_revealed_index = 9
	assert_false(SaveManager.validate_snapshot(bad), "Fully revealed RUNNING is invalid.")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(original, "", true, true))
	assert_true(SaveManager.validate_snapshot(parsed))
	parsed.expedition.seed = 1.25
	assert_false(SaveManager.validate_snapshot(parsed))
	assert_eq(SaveManager.capture_state(), original)


func test_rejects_bad_step_payloads_unknown_ids_and_overflowing_total_gold() -> void:
	var original := _start()
	for change in [["kind", 3], ["kind", 99], ["kind", 1.5], ["kind", 0], ["content_id", "missing"],
			["content_id", ""], ["title", ""], ["journal_text", ""], ["outcome_id", "unexpected"],
			["result", {}], ["result", {"gold": -1}], ["result", {"gold": 1.5}],
			["result", {"gold": true}], ["result", {"gold": INF}], ["result", {"gold": NAN}],
			["result", {"gold": HeroCatalog.MAX_SAFE_INT + 1}], ["result", {"gold": 0, "items": []}]]:
		var bad := original.duplicate(true)
		bad.expedition.steps[1][change[0]] = change[1]
		assert_false(SaveManager.validate_snapshot(bad), str(change))
	for key in original.expedition.steps[1]:
		var bad := original.duplicate(true)
		bad.expedition.steps[1].erase(key)
		assert_false(SaveManager.validate_snapshot(bad))
	var bad := original.duplicate(true)
	bad.expedition.steps[0].result.gold = 1
	assert_false(SaveManager.validate_snapshot(bad))
	bad = original.duplicate(true)
	bad.expedition.steps[1].result.gold = HeroCatalog.MAX_SAFE_INT
	bad.expedition.steps[3].result.gold = 1
	assert_false(SaveManager.validate_snapshot(bad))


func test_frozen_party_validation_and_roster_status_relations_are_strict() -> void:
	var original := _start()
	for change in [["hero_id", "hero-999"], ["hero_id", GameState.recruitment_offers[0].hero_id],
			["hero_name", ""], ["class_id", "missing"], ["class_name", ""], ["level", 0],
			["attributes", {}], ["derived_stats", {}], ["basic_attack_target_rule", "All"]]:
		var bad := original.duplicate(true)
		bad.expedition.party_snapshot.FRONT_LEFT[change[0]] = change[1]
		assert_false(SaveManager.validate_snapshot(bad), str(change))
	for key in original.expedition.party_snapshot.FRONT_LEFT:
		var bad := original.duplicate(true)
		bad.expedition.party_snapshot.FRONT_LEFT.erase(key)
		assert_false(SaveManager.validate_snapshot(bad))
	for value in [-1, NAN, INF, 1.5, true, HeroCatalog.MAX_SAFE_INT + 1]:
		var bad := original.duplicate(true)
		bad.expedition.party_snapshot.FRONT_LEFT.derived_stats.MaxHP = value
		assert_false(SaveManager.validate_snapshot(bad))
	for value in [-1, NAN, INF, 1.1, true]:
		var bad := original.duplicate(true)
		bad.expedition.party_snapshot.FRONT_LEFT.derived_stats.Evasion = value
		assert_false(SaveManager.validate_snapshot(bad))
	for value in ["", "zzzzzzzzzzzzzzzz", "000000000000f07f", "000000000000f87f", {}, [], "0000"]:
		var bad := original.duplicate(true)
		bad.expedition.party_snapshot.FRONT_LEFT.derived_stats.Evasion = value
		assert_false(SaveManager.validate_snapshot(bad), "Invalid exact float representation: %s" % str(value))
	for status in ["IDLE", "ASSIGNED", "RESTING", "DEAD", "WOUNDED"]:
		var bad := original.duplicate(true)
		bad.roster[0].status = status
		assert_false(SaveManager.validate_snapshot(bad))
	var bad := original.duplicate(true)
	bad.expedition.party_snapshot.BACK_RIGHT = bad.expedition.party_snapshot.FRONT_LEFT.duplicate(true)
	assert_false(SaveManager.validate_snapshot(bad))
	bad = original.duplicate(true)
	bad.expedition = null
	assert_false(SaveManager.validate_snapshot(bad), "No orphan OnExpedition without a run.")
	bad = original.duplicate(true)
	bad.roster[2].status = "ON_EXPEDITION"
	assert_false(SaveManager.validate_snapshot(bad))
	bad = original.duplicate(true)
	bad.current_party = {"FRONT_LEFT": "hero-3", "FRONT_RIGHT": null, "BACK_LEFT": null, "BACK_RIGHT": null}
	bad.roster[2].status = "ASSIGNED"
	assert_false(SaveManager.validate_snapshot(bad), "Running and pending Party cannot coexist.")
	_time = 1060
	ExpeditionManager.reveal_progress()
	bad = SaveManager.capture_state()
	bad.roster[0].status = "ON_EXPEDITION"
	assert_false(SaveManager.validate_snapshot(bad), "Completed report cannot leave OnExpedition Heroes.")


func test_v2_migration_validates_original_party_before_releasing_legacy_on_expedition() -> void:
	var party := PartyData.new()
	party.place_hero(3, GameState.roster[0])
	assert_true(PartyFormationService.confirm(party, ExpeditionManager.balancing))
	var legacy := SaveManager.capture_state()
	for key in ["expedition", "expedition_seed", "expedition_sequence"]:
		legacy.erase(key)
	for hero in legacy.roster + legacy.recruitment_offers:
		hero.erase("recovery_ready_at")
	legacy.save_version = 2
	legacy.roster[1].status = "ON_EXPEDITION"
	legacy.unlocked_regions = ["forest", "arbitrary-old-region"]
	var expected := legacy.duplicate(true)
	expected.save_version = 4
	expected.expedition = null
	expected.expedition_seed = expected.recruitment_seed
	expected.expedition_sequence = 0
	expected.roster[1].status = "IDLE"
	for hero in expected.roster + expected.recruitment_offers:
		hero.recovery_ready_at = 0
	assert_eq(SaveManager.migrate(legacy), expected)
	_write(SaveManager.get_save_path(), legacy)
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), expected)
	assert_same(GameState.current_party.slots[3], GameState.roster[0])
	for status in ["IDLE", "ON_EXPEDITION"]:
		var bad := legacy.duplicate(true)
		bad.roster[0].status = status
		assert_eq(SaveManager.migrate(bad), {}, "Do not launder an invalid v2 Party.")
	var orphan := legacy.duplicate(true)
	orphan.roster[2].status = "ASSIGNED"
	assert_eq(SaveManager.migrate(orphan), {})
	var future_field := legacy.duplicate(true)
	future_field.roster[0].recovery_ready_at = 0
	assert_eq(SaveManager.migrate(future_field), {})


func _version_three(snapshot: Dictionary) -> Dictionary:
	var legacy := snapshot.duplicate(true)
	legacy.save_version = 3
	for hero in legacy.roster + legacy.recruitment_offers:
		hero.erase("recovery_ready_at")
	if legacy.expedition != null:
		legacy.expedition.erase("planned_step_count")
		legacy.expedition.erase("retreat_ends_expedition")
	return legacy


func test_version_three_running_and_completed_records_migrate_without_rewriting_history() -> void:
	_start()
	for now in [1025, 1060]:
		_time = now
		ExpeditionManager.reveal_progress()
		var expected := SaveManager.capture_state()
		var legacy := _version_three(expected)
		var original := legacy.duplicate(true)
		var migrated := SaveManager.migrate(legacy)
		assert_eq(migrated, expected)
		assert_eq(legacy, original)
		_write(SaveManager.get_save_path(), legacy)
		GameState.reset()
		SaveManager.load_or_create()
		assert_true(SaveManager.last_success, SaveManager.last_error)
		assert_eq(SaveManager.capture_state(), expected)
		assert_eq(JSON.stringify(SaveManager.capture_state(), "", true, true), JSON.stringify(expected, "", true, true))
		assert_eq(ExpeditionManager.get_active_expedition().planned_step_count, 10)
		assert_false(ExpeditionManager.get_active_expedition().retreat_ends_expedition)
		migrated.expedition.steps[0].title = "Detached migration"
		assert_eq(legacy, original)


func test_version_three_rejects_malformed_originals_and_future_fields_before_migration() -> void:
	var legacy := _version_three(_start())
	var cases: Array = []
	for key in legacy.expedition:
		var bad := legacy.duplicate(true)
		bad.expedition.erase(key)
		cases.append(bad)
	for change in [["planned_step_count", 10], ["retreat_ends_expedition", false],
			["terminal_step_index", 9], ["effective_end_timestamp", 1012],
			["last_revealed_index", 0], ["credited_elapsed_seconds", true], ["status", 1]]:
		var bad := legacy.duplicate(true)
		bad.expedition[change[0]] = change[1]
		cases.append(bad)
	var bad := legacy.duplicate(true)
	bad.roster[0].recovery_ready_at = 0
	cases.append(bad)
	bad = legacy.duplicate(true)
	bad.roster[0].status = "IDLE"
	cases.append(bad)
	bad = legacy.duplicate(true)
	bad.expedition.steps[1].kind = ExpeditionStep.StepKind.COMBAT
	cases.append(bad)
	bad = legacy.duplicate(true)
	bad.expedition.party_snapshot.FRONT_LEFT.active_skill = CombatCatalog.GUARD.snapshot()
	cases.append(bad)
	bad = legacy.duplicate(true)
	bad.expedition.steps[1].result = {"gold": 0, "outcome": "VICTORY"}
	cases.append(bad)
	for invalid in cases:
		assert_eq(SaveManager.migrate(invalid), {}, str(invalid))
	var original := legacy.duplicate(true)
	assert_false(SaveManager.migrate(legacy).is_empty())
	assert_eq(legacy, original)


func test_missing_or_corrupt_primary_recovers_expedition_backup_and_clears_stale_state() -> void:
	for corruption in ["missing", "corrupt"]:
		GameState.reset()
		assert_true(RecruitmentService.initialize_new_game(12345))
		SaveManager.save()
		var expected := _start()
		SaveManager.save()
		if corruption == "missing":
			assert_eq(DirAccess.remove_absolute(SaveManager.get_save_path()), OK)
		else:
			_write(SaveManager.get_save_path(), {"bad": true})
		GameState.reset()
		SaveManager.load_or_create()
		assert_false(SaveManager.last_warning.is_empty())
		assert_eq(SaveManager.capture_state(), expected)
		assert_true(ExpeditionManager.is_expedition_active())
		assert_true(RecruitmentService.initialize_new_game(12345))
		assert_null(ExpeditionManager.get_active_expedition())
		var new_company := SaveManager.capture_state()
		_write(SaveManager.get_save_path(), new_company)
		_start()
		_write(SaveManager.get_save_path(), new_company)
		SaveManager.load_or_create()
		assert_null(ExpeditionManager.get_active_expedition())
		assert_eq(SaveManager.capture_state(), new_company)


func test_recovery_warning_survives_immediate_offline_progress_save() -> void:
	_start()
	SaveManager.save()
	assert_eq(DirAccess.remove_absolute(SaveManager.get_save_path()), OK)
	_time = 1060
	SaveManager.load_or_create()
	assert_eq(ExpeditionManager.get_active_expedition().status, ExpeditionData.Status.COMPLETED)
	assert_string_contains(SaveManager.last_warning, "Recovered")
	assert_true(SaveManager.last_committed)
	var saved := SaveManager.capture_state()
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), saved)


func test_missing_and_corrupt_recovery_feedback_survives_first_foreground_delta_and_postcommit_warning() -> void:
	_start()
	for corruption in ["missing", "corrupt"]:
		SaveManager.fault_injector = Callable()
		SaveManager.save()
		if corruption == "missing":
			assert_eq(DirAccess.remove_absolute(SaveManager.get_save_path()), OK)
		else:
			_write(SaveManager.get_save_path(), {"bad": true})
		_time += 12
		SaveManager.load_or_create()
		assert_true(ExpeditionManager.is_expedition_active())
		assert_true(SaveManager.last_success)
		assert_true(SaveManager.last_committed)
		assert_true(ExpeditionManager.last_committed)
		assert_string_contains(SaveManager.last_warning, "Recovered")
		var run := ExpeditionManager.get_active_expedition()
		var cursor := run.last_revealed_index
		var elapsed := run.credited_elapsed_seconds
		var gold := GameState.gold
		var warning := SaveManager.last_warning
		_time += 1
		ExpeditionManager.reveal_progress()
		assert_true(ExpeditionManager.last_committed)
		assert_eq(run.last_revealed_index, cursor)
		assert_eq(run.credited_elapsed_seconds, elapsed + 1)
		assert_eq(GameState.gold, gold)
		assert_eq(SaveManager.last_warning, warning, "The first foreground clock save retains recovery feedback.")
		SaveManager.fault_injector = func(stage: String) -> bool: return stage == "after_primary_replace"
		for index in range(2):
			_time += 1
			ExpeditionManager.reveal_progress()
			assert_true(SaveManager.last_success)
			assert_true(SaveManager.last_committed)
			assert_true(ExpeditionManager.last_committed)
			assert_eq(SaveManager.last_error, "")
			assert_string_contains(SaveManager.last_warning, "Recovered")
			assert_string_contains(SaveManager.last_warning, "committed")
			assert_eq(SaveManager.last_warning.split("\n", false).size(), 2, "Repeated warnings merge without duplication.")
