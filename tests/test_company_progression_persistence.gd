extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
const STAGES := ["before_temp_write", "after_temp_validation", "after_backup_preparation",
	"after_backup_replace", "before_primary_replace", "after_primary_replace"]
var _isolation: RefCounted
var _time := 1000
var _pool: Array[EncounterEntryResource]
var _items: Dictionary
var _chance: float
var _min_gold: int
var _max_gold: int
var _notifications: Array = []


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	_time = 1000
	_notifications.clear()
	ExpeditionManager.clock = func() -> int: return _time
	ExpeditionManager.balancing = ExpeditionManager.DEFAULT_BALANCING.duplicate(true)
	_pool = ExpeditionCatalog.GREEN_HOLLOW.encounter_pool.duplicate()
	_items = ExpeditionCatalog.LOOT.item_pool.duplicate()
	_chance = ExpeditionCatalog.LOOT.item_drop_chance
	_min_gold = ExpeditionCatalog.LOOT.min_gold
	_max_gold = ExpeditionCatalog.LOOT.max_gold
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success, SaveManager.last_error)
	var entry := EncounterEntryResource.new()
	entry.kind = "Loot"
	entry.content_id = ExpeditionCatalog.LOOT.loot_id
	entry.weight = 1.0
	var region := ExpeditionCatalog.GREEN_HOLLOW
	region.encounter_pool.assign([entry])
	var loot := ExpeditionCatalog.LOOT
	loot.min_gold = 60
	loot.max_gold = 60
	loot.item_pool = {"short_sword": 1.0}
	loot.item_drop_chance = 1.0
	ExpeditionManager.changed.connect(_record_change)


func after_each() -> void:
	ExpeditionManager.changed.disconnect(_record_change)
	var region := ExpeditionCatalog.GREEN_HOLLOW
	region.encounter_pool.assign(_pool)
	var loot := ExpeditionCatalog.LOOT
	loot.item_pool = _items
	loot.item_drop_chance = _chance
	loot.min_gold = _min_gold
	loot.max_gold = _max_gold
	_isolation.finish()


func _record_change() -> void:
	_notifications.append({
		"committed": SaveManager.last_committed,
		"snapshot": SaveManager.capture_state(),
		"disk": JSON.parse_string(FileAccess.get_file_as_string(SaveManager.get_save_path())),
	})


func _write(snapshot: Dictionary, suffix: String = "") -> void:
	var file := FileAccess.open(SaveManager.get_save_path() + suffix, FileAccess.WRITE)
	assert_not_null(file)
	file.store_string(JSON.stringify(snapshot, "", true, true))
	file.close()


func _start() -> ExpeditionData:
	var party := PartyData.new()
	for index in range(GameState.roster.size()):
		assert_true(party.place_hero(index, GameState.roster[index]))
	assert_true(PartyFormationService.confirm(party, ExpeditionManager.balancing))
	ExpeditionManager.start_expedition(ExpeditionCatalog.GREEN_HOLLOW, GameState.current_party, 60)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	return ExpeditionManager.get_active_expedition()


func test_new_company_starts_with_green_hollow_and_saved_capacity() -> void:
	assert_eq(GameState.unlocked_regions, [&"green_hollow"])
	assert_eq(GameState.roster_capacity, 12)
	assert_eq(SaveManager.capture_state().save_version, SaveManager.SAVE_VERSION)
	var saved := SaveManager.capture_state()
	ExpeditionManager.reveal_progress()
	assert_eq(SaveManager.capture_state(), saved)
	assert_true(_notifications.is_empty(), "An unchanged idle observation must not save or publish.")


func test_new_company_progression_preflight_failure_preserves_the_previous_company() -> void:
	var before := SaveManager.capture_state()
	var hero := GameState.roster[0]
	ExpeditionManager.balancing.region_roster_capacities.clear()
	assert_false(RecruitmentService.initialize_new_game(6789))
	assert_eq(SaveManager.capture_state(), before)
	assert_same(GameState.roster[0], hero)
	assert_true(_notifications.is_empty())


func test_reward_observation_commits_gold_unlocks_capacity_items_xp_and_cursor_together() -> void:
	var run := _start()
	_notifications.clear()
	_time = 1012
	ExpeditionManager.reveal_progress()
	assert_eq(GameState.gold, 160)
	assert_eq(GameState.unlocked_regions, [&"green_hollow"])
	_time = 1024
	ExpeditionManager.reveal_progress()
	assert_eq(GameState.gold, 220)
	assert_eq(GameState.unlocked_regions, [&"green_hollow", &"ashen_reach"])
	assert_eq(GameState.roster_capacity, 16)
	assert_eq(run.last_revealed_index, 3)
	_time = 1060
	ExpeditionManager.reveal_progress()
	assert_eq(GameState.gold, 400)
	assert_eq(GameState.unlocked_regions, [&"green_hollow", &"ashen_reach", &"frostbound_pass"])
	assert_eq(GameState.roster_capacity, 20)
	assert_eq(GameState.inventory.size(), 5)
	assert_eq(run.status, ExpeditionData.Status.COMPLETED)
	for hero in GameState.roster:
		assert_eq(hero.xp, run.xp_award)
		assert_eq(hero.status, HeroData.HeroStatus.IDLE)
	for notification in _notifications:
		assert_true(notification.committed)
		assert_eq(notification.disk, JSON.parse_string(JSON.stringify(notification.snapshot, "", true, true)))
	var saved := SaveManager.capture_state()
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), saved)
	ExpeditionManager.acknowledge_report(ExpeditionManager.get_active_expedition())
	assert_eq(GameState.gold, 400)
	assert_eq(GameState.roster_capacity, 20)


func test_all_save_boundaries_rollback_every_reward_and_never_publish_before_commit() -> void:
	for stage in STAGES:
		SaveManager.fault_injector = Callable()
		_time = 1000
		assert_true(RecruitmentService.initialize_new_game(12345))
		SaveManager.save()
		var run := _start()
		var before := SaveManager.capture_state()
		var heroes := GameState.roster.duplicate()
		var saved_text := FileAccess.get_file_as_string(SaveManager.get_save_path())
		_notifications.clear()
		SaveManager.fault_injector = func(boundary: String) -> bool: return boundary == stage
		_time = 1060
		ExpeditionManager.reveal_progress()
		if stage != "after_primary_replace":
			assert_false(ExpeditionManager.last_committed, stage)
			assert_eq(SaveManager.capture_state(), before, stage)
			assert_eq(FileAccess.get_file_as_string(SaveManager.get_save_path()), saved_text, stage)
			assert_true(_notifications.is_empty(), stage)
		else:
			assert_true(ExpeditionManager.last_committed)
			assert_eq(_notifications.size(), 1)
			assert_true(_notifications[0].committed)
			assert_false(SaveManager.last_warning.is_empty())
		assert_same(ExpeditionManager.get_active_expedition(), run)
		for index in range(heroes.size()):
			assert_same(GameState.roster[index], heroes[index])
		SaveManager.fault_injector = Callable()
		ExpeditionManager.reveal_progress()
		assert_eq(GameState.gold, 400)
		assert_eq(GameState.roster_capacity, 20)
		assert_eq(GameState.inventory.size(), 5)
		var committed := SaveManager.capture_state()
		SaveManager.load_or_create()
		assert_eq(SaveManager.capture_state(), committed)


func test_idle_load_and_foreground_observe_existing_gold_without_a_run() -> void:
	for stage in STAGES:
		SaveManager.fault_injector = Callable()
		assert_true(RecruitmentService.initialize_new_game(12345))
		GameState.gold = 400
		SaveManager.save()
		var before := SaveManager.capture_state()
		_notifications.clear()
		SaveManager.fault_injector = func(boundary: String) -> bool: return boundary == stage
		GameState.reset()
		SaveManager.load_or_create()
		assert_null(ExpeditionManager.get_active_expedition())
		if stage != "after_primary_replace":
			assert_eq(SaveManager.capture_state(), before, stage)
			assert_true(_notifications.is_empty(), stage)
		else:
			assert_eq(GameState.roster_capacity, 20)
			assert_eq(_notifications.size(), 1)
		SaveManager.fault_injector = Callable()
		ExpeditionManager._lifecycle_enabled = true
		ExpeditionManager._foreground = true
		ExpeditionManager.observe_foreground()
		assert_eq(GameState.roster_capacity, 20)
		assert_eq(GameState.unlocked_regions.size(), 3)
		assert_eq(GameState.gold, 400)
		ExpeditionManager._lifecycle_enabled = false


func test_spending_reload_and_lower_capacity_tuning_do_not_relock() -> void:
	GameState.gold = 400
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed)
	for index in range(4):
		assert_true(RecruitmentService.recruit(GameState.recruitment_offers[0], ExpeditionManager.balancing))
	assert_eq(GameState.gold, 0)
	ExpeditionManager.balancing.region_roster_capacities = {
		"green_hollow": 4, "ashen_reach": 8, "frostbound_pass": 12}
	var saved := SaveManager.capture_state()
	GameState.reset()
	SaveManager.load_or_create()
	ExpeditionManager.reveal_progress()
	assert_eq(SaveManager.capture_state(), saved)
	assert_eq(GameState.roster_capacity, 20)
	assert_true(CompanyProgression.is_unlocked(ExpeditionCatalog.FROSTBOUND_PASS, GameState.unlocked_regions))


func test_unlock_expands_a_full_roster_and_recruitment_uses_committed_capacity() -> void:
	GameState.gold = 10000
	for index in range(8):
		assert_true(RecruitmentService.recruit(GameState.recruitment_offers[0], ExpeditionManager.balancing))
	assert_eq(GameState.roster.size(), 12)
	var offer := GameState.recruitment_offers[0]
	assert_string_contains(RecruitmentService.availability_error(offer.hero_id, ExpeditionManager.balancing), "Roster full")
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "before_primary_replace"
	ExpeditionManager.reveal_progress()
	assert_eq(GameState.roster_capacity, 12)
	assert_false(RecruitmentService.availability_error(offer.hero_id, ExpeditionManager.balancing).is_empty())
	SaveManager.fault_injector = Callable()
	ExpeditionManager.reveal_progress()
	assert_eq(GameState.roster_capacity, 20)
	assert_eq(RecruitmentService.availability_error(offer.hero_id, ExpeditionManager.balancing), "")
	assert_true(RecruitmentService.recruit(offer, ExpeditionManager.balancing))
	assert_eq(GameState.roster.size(), 13)
	SaveManager.load_or_create()
	assert_eq(GameState.roster.size(), 13)
	assert_eq(GameState.roster_capacity, 20)


func test_dispatch_rechecks_saved_unlocks_and_keeps_power_advisory() -> void:
	GameState.gold = 400
	var party := PartyData.new()
	assert_true(party.place_hero(3, GameState.roster[0]))
	assert_true(PartyFormationService.confirm(party, ExpeditionManager.balancing))
	var before := SaveManager.capture_state()
	var region := ExpeditionCatalog.ASHEN_REACH
	var duration := region.duration_options_seconds[0]
	assert_string_contains(ExpeditionManager.start_error(region, GameState.current_party, duration), "locked")
	ExpeditionManager.start_expedition(region, GameState.current_party, duration)
	assert_false(ExpeditionManager.last_committed)
	assert_eq(SaveManager.capture_state(), before)
	ExpeditionManager.reveal_progress()
	assert_eq(ExpeditionManager.start_error(region, GameState.current_party, duration), "")
	ExpeditionManager.start_expedition(region, GameState.current_party, duration)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_lte(FileAccess.get_file_as_string(SaveManager.get_save_path()).to_utf8_buffer().size(), SaveManager.MAX_SAVE_BYTES)


func test_malformed_live_progression_tuning_blocks_mutation_but_not_frozen_save_validation() -> void:
	_start()
	var before := SaveManager.capture_state()
	ExpeditionManager.balancing.region_roster_capacities.clear()
	assert_true(SaveManager.validate_snapshot(before))
	_time = 1060
	_notifications.clear()
	ExpeditionManager.reveal_progress()
	assert_false(ExpeditionManager.last_committed)
	assert_string_contains(ExpeditionManager.last_error, "Company progression")
	assert_eq(SaveManager.capture_state(), before)
	assert_true(_notifications.is_empty())
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), before)
	assert_eq(SaveManager.last_warning, "", "Malformed live tuning cannot invalidate a saved frozen journal.")
	ExpeditionManager.balancing.region_roster_capacities = ExpeditionManager.DEFAULT_BALANCING.region_roster_capacities.duplicate()
	ExpeditionManager.reveal_progress()
	assert_eq(GameState.gold, 400)
	assert_eq(GameState.roster_capacity, 20)


func test_v5_active_and_completed_saves_preserve_frozen_combat_rewards_equipment_and_levels() -> void:
	var region := ExpeditionCatalog.GREEN_HOLLOW
	region.encounter_pool.assign(_pool)
	GameState.expedition_seed = 1
	GameState.roster[0].level = 17
	GameState.roster[0].xp = 7
	GameState.roster[0].equipped_weapon = ItemCatalog.SHORT_SWORD
	GameState.roster[0].equipped_armor = ItemCatalog.ROBES
	GameState.inventory.assign([ItemCatalog.SHORT_SWORD, ItemCatalog.SHORT_SWORD])
	_start()
	var combat_count := 0
	for now in [1000, 1060]:
		_time = now
		ExpeditionManager.reveal_progress()
		var legacy := SaveManager.capture_state()
		legacy.save_version = 5
		legacy.erase("expedition_automation")
		legacy.roster_capacity = 12
		legacy.unlocked_regions = ["green_hollow", "reserved-before-m7", "ashen_reach"]
		var untouched := legacy.duplicate(true)
		var expected := legacy.duplicate(true)
		expected.save_version = SaveManager.SAVE_VERSION
		expected.expedition_automation = null
		expected.unlocked_regions = ["green_hollow", "ashen_reach"]
		var migrated := SaveManager.migrate(legacy)
		assert_eq(migrated, expected)
		assert_eq(legacy, untouched)
		assert_true(SaveManager.validate_snapshot(migrated))
		assert_eq(migrated.expedition, legacy.expedition, "V5 journals, snapshots, clocks and rewards remain exact.")
		assert_eq(migrated.roster, legacy.roster)
		assert_eq(migrated.inventory, legacy.inventory)
		for step in legacy.expedition.steps:
			if step.kind == ExpeditionStep.StepKind.COMBAT:
				combat_count += 1
				assert_false(step.result.rounds.is_empty())
		var observed := CompanyProgression.preview(int(expected.gold), expected.unlocked_regions, 12, ExpeditionManager.balancing)
		expected.unlocked_regions = []
		for id in observed.unlocked_regions:
			expected.unlocked_regions.append(String(id))
		expected.roster_capacity = observed.roster_capacity
		_write(legacy)
		GameState.reset()
		SaveManager.load_or_create()
		assert_eq(SaveManager.capture_state(), expected)
		assert_eq(SaveManager.capture_state().expedition, untouched.expedition)
	assert_gt(combat_count, 0)


func test_v5_keeps_its_exact_expedition_schema_instead_of_using_v4_validation() -> void:
	_start()
	var original := SaveManager.capture_state()
	original.save_version = 5
	original.erase("expedition_automation")
	assert_false(SaveManager.migrate(original).is_empty())
	for key in ["xp_award", "recovery_seconds", "rest_hp_percent"]:
		var missing := original.duplicate(true)
		missing.expedition.erase(key)
		assert_eq(SaveManager.migrate(missing), {}, key)
	var invalid := original.duplicate(true)
	invalid.expedition.xp_award = -1
	assert_eq(SaveManager.migrate(invalid), {})
	invalid = original.duplicate(true)
	invalid.roster[0].status = "WOUNDED"
	invalid.roster[0].recovery_ready_at = 1200
	assert_eq(SaveManager.migrate(invalid), {}, "Do not apply the v4 Wounded repair to a malformed v5 save.")


func test_legacy_versions_validate_original_capacity_and_ids_before_normalization() -> void:
	for version in [1, 2, 3, 4, 5]:
		var legacy := SaveManager.capture_state()
		legacy.save_version = version
		legacy.erase("expedition_automation")
		legacy.unlocked_regions = ["reserved", "green_hollow", "ashen_reach", "res://old/region.tres"]
		if version < 4:
			for hero in legacy.roster + legacy.recruitment_offers:
				hero.erase("recovery_ready_at")
		if version < 3:
			for key in ["expedition", "expedition_seed", "expedition_sequence"]:
				legacy.erase(key)
		if version == 1:
			legacy.erase("current_party")
		var migrated := SaveManager.migrate(legacy)
		assert_false(migrated.is_empty(), str(version))
		assert_eq(migrated.unlocked_regions, ["green_hollow", "ashen_reach"])
		assert_eq(migrated.roster_capacity, 12, "Migration itself awards no capacity.")
		for capacity in [13, 20, CompanyProgression.MAX_ROSTER_CAPACITY]:
			var invalid := legacy.duplicate(true)
			invalid.roster_capacity = capacity
			assert_eq(SaveManager.migrate(invalid), {}, "%d capacity %d" % [version, capacity])
		for ids in [["reserved", "reserved"], [""], [true], [null]]:
			var invalid := legacy.duplicate(true)
			invalid.unlocked_regions = ids
			assert_eq(SaveManager.migrate(invalid), {}, "Never filter first and launder invalid legacy IDs.")


func test_v6_capacity_is_bounded_independently_of_live_tuning_and_ids_are_known_unique() -> void:
	var original := SaveManager.capture_state()
	for capacity in [13, 16, 20, 32, CompanyProgression.MAX_ROSTER_CAPACITY]:
		var snapshot := original.duplicate(true)
		snapshot.roster_capacity = capacity
		assert_true(SaveManager.validate_snapshot(snapshot), str(capacity))
	for ids in [["unknown"], ["res://data/regions/green_hollow.tres"], ["green_hollow", "green_hollow"]]:
		var invalid := original.duplicate(true)
		invalid.unlocked_regions = ids
		assert_false(SaveManager.validate_snapshot(invalid))
		assert_eq(SaveManager.migrate(invalid), {}, "V6 must not normalize invalid IDs like legacy schemas.")
	GameState.roster_capacity = 32
	SaveManager.save()
	SaveManager.load_or_create()
	assert_eq(GameState.roster_capacity, 32)


func test_every_shipped_trait_id_round_trips_as_the_registered_resource() -> void:
	var traits := HeroCatalog.traits()
	assert_eq(traits.size(), 8)
	for trait_resource in traits:
		GameState.roster[0].traits.assign([trait_resource])
		SaveManager.save()
		assert_true(SaveManager.last_committed)
		var expected := SaveManager.capture_state()
		assert_eq(expected.roster[0].trait_ids, [String(trait_resource.trait_id)])
		GameState.reset()
		SaveManager.load_or_create()
		assert_eq(SaveManager.capture_state(), expected)
		assert_same(GameState.roster[0].traits[0], trait_resource)


func test_recovered_legacy_backup_is_not_overwritten_by_its_unlock_observation() -> void:
	var legacy := SaveManager.capture_state()
	legacy.save_version = 5
	legacy.erase("expedition_automation")
	legacy.gold = 400
	legacy.unlocked_regions = ["reserved-before-m7"]
	_write(legacy, ".bak")
	var backup := FileAccess.get_file_as_string(SaveManager.get_save_path() + ".bak")
	_write({"invalid": true})
	GameState.reset()
	SaveManager.load_or_create()
	assert_true(SaveManager.last_committed)
	assert_eq(GameState.roster_capacity, 20)
	assert_eq(GameState.unlocked_regions, [&"green_hollow", &"ashen_reach", &"frostbound_pass"])
	assert_string_contains(SaveManager.last_warning, "Recovered")
	assert_eq(FileAccess.get_file_as_string(SaveManager.get_save_path() + ".bak"), backup)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveManager.get_save_path()))
	assert_eq(int(saved.save_version), SaveManager.SAVE_VERSION)
	assert_eq(int(saved.gold), 400)
