extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
var _isolation: RefCounted
var _changed_class: HeroClassResource
var _original_ranges: Dictionary


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	_changed_class = null


func after_each() -> void:
	if _changed_class != null:
		_changed_class.base_attribute_ranges = _original_ranges
	_isolation.finish()


func _boot() -> Dictionary:
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success, SaveManager.last_error)
	return SaveManager.capture_state()


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	file.store_string(content)
	file.flush()
	file.close()


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file)
	var content := file.get_as_text()
	file.close()
	return content


func test_autoload_construction_and_capture_are_io_free() -> void:
	var manager: Node = autofree(load("res://autoload/SaveManager.gd").new())
	assert_false(GameState.initialized)
	assert_false(FileAccess.file_exists(SaveManager.get_save_path()))
	assert_eq(manager.get_save_path(), OS.get_user_data_dir().path_join("save.json"))
	assert_false(SaveManager.capture_state().is_empty())
	assert_false(FileAccess.file_exists(SaveManager.get_save_path()))
	SaveManager.save()
	assert_false(SaveManager.last_success)
	assert_false(SaveManager.last_error.is_empty())


func test_version_three_round_trip_every_field_and_maximum_seed() -> void:
	_boot()
	GameState.recruitment_seed = HeroCatalog.MAX_SAFE_INT
	GameState.recruitment_sequence = HeroCatalog.MAX_SAFE_INT
	GameState.offer_seeds.assign([0, 123, HeroCatalog.MAX_SAFE_INT])
	GameState.gold = HeroCatalog.MAX_SAFE_INT
	GameState.next_hero_id = HeroCatalog.MAX_SAFE_INT
	GameState.unlocked_regions.assign([&"forest", &"mountains"])
	var index := 0
	for hero in GameState.roster:
		hero.hero_name = "Persistent Hero %d" % index
		hero.level = 21 + index
		hero.xp = HeroCatalog.MAX_SAFE_INT - index
		hero.status = index as HeroData.HeroStatus
		if hero.status == HeroData.HeroStatus.ON_EXPEDITION:
			hero.status = HeroData.HeroStatus.WOUNDED
		hero.traits.assign([HeroCatalog.traits()[index]])
		index += 1
	GameState.current_party = PartyData.new()
	GameState.current_party.place_hero(0, GameState.roster[1])
	var expected := SaveManager.capture_state()
	var original_attributes := GameState.roster[0].attributes.duplicate()
	SaveManager.save()
	assert_true(SaveManager.last_success, SaveManager.last_error)
	assert_true(SaveManager.last_committed)
	GameState.reset()
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success, SaveManager.last_error)
	assert_eq(SaveManager.capture_state(), expected)
	assert_eq(GameState.roster[0].attributes, original_attributes)
	assert_eq(GameState.roster[0].traits.get_typed_script(), HeroTraitResource)
	assert_eq(GameState.offer_seeds.get_typed_builtin(), TYPE_INT)
	assert_eq(GameState.unlocked_regions.get_typed_builtin(), TYPE_STRING_NAME)
	assert_null(GameState.roster[0].equipped_weapon)
	assert_null(GameState.roster[0].equipped_armor)
	assert_same(GameState.roster[0].hero_class, HeroCatalog.KNIGHT)
	assert_same(GameState.roster[0].traits[0], HeroCatalog.HEARTY)


func test_all_statuses_are_valid_and_round_trip() -> void:
	_boot()
	for status in HeroData.HeroStatus.values():
		if status == HeroData.HeroStatus.ON_EXPEDITION:
			continue # Valid only with a matching running record; covered by expedition persistence tests.
		GameState.current_party = null
		GameState.roster[0].status = status as HeroData.HeroStatus
		if status == HeroData.HeroStatus.ASSIGNED:
			GameState.current_party = PartyData.new()
			GameState.current_party.place_hero(0, GameState.roster[0])
		SaveManager.save()
		assert_true(SaveManager.last_success)
		SaveManager.load_or_create()
		assert_eq(GameState.roster[0].status, status)


func test_integer_valued_json_floats_are_accepted_without_truncation() -> void:
	var snapshot := _boot()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	assert_eq(typeof(parsed.gold), TYPE_FLOAT)
	assert_true(SaveManager.validate_snapshot(parsed))
	parsed.gold = 100.25
	assert_false(SaveManager.validate_snapshot(parsed))


func test_original_rolls_survive_range_tuning_while_new_heroes_use_current_ranges() -> void:
	_boot()
	GameState.gold = 75
	SaveManager.save()
	assert_true(SaveManager.last_success)
	var expected := SaveManager.capture_state()
	var backup := _read(SaveManager.get_save_path() + ".bak")
	_changed_class = HeroCatalog.KNIGHT
	_original_ranges = _changed_class.base_attribute_ranges.duplicate(true)
	_changed_class.base_attribute_ranges["MIG"] = Vector2i(50, 55)
	assert_true(HeroCatalog.validate_class(_changed_class))
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success, SaveManager.last_error)
	assert_eq(SaveManager.last_warning, "")
	assert_eq(SaveManager.capture_state(), expected, "Original rolls are persisted snapshots.")
	assert_eq(_read(SaveManager.get_save_path() + ".bak"), backup)
	assert_lt(GameState.roster[0].attributes.MIG, 50)
	var generated := HeroGenerator.generate_hero("new-roll", 42, [_changed_class], [])
	assert_not_null(generated)
	assert_between(generated.attributes.MIG, 50, 55)
	var bounds_snapshot := expected.duplicate(true)
	bounds_snapshot.roster[0].attributes.MIG = HeroCatalog.MAX_ATTRIBUTE
	bounds_snapshot.roster[0].attributes.FOC = 0
	assert_true(SaveManager.validate_snapshot(bounds_snapshot))


func test_migration_rejects_unknown_versions_and_types() -> void:
	var snapshot := _boot()
	for version in [null, true, "1", -1, 0, 1.5, 5, HeroCatalog.MAX_SAFE_INT]:
		var invalid := snapshot.duplicate(true)
		invalid.save_version = version
		assert_eq(SaveManager.migrate(invalid), {}, str(version))
	assert_eq(SaveManager.migrate([]), {})
	assert_eq(SaveManager.migrate(snapshot), snapshot)


func test_root_validation_rejects_bad_types_bounds_and_missing_fields() -> void:
	var snapshot := _boot()
	var changes := [
		["save_version", "1"], ["save_version", 1], ["save_version", 5], ["save_version", true],
		["gold", -1], ["gold", 1.1], ["gold", true], ["gold", "100"],
		["gold", INF], ["gold", NAN], ["gold", HeroCatalog.MAX_SAFE_INT + 1],
		["roster_capacity", 0], ["roster_capacity", 13], ["roster_capacity", 3],
		["roster_capacity", 12.1], ["next_hero_id", 7], ["next_hero_id", 0],
		["next_hero_id", 8.1], ["next_hero_id", HeroCatalog.MAX_SAFE_INT + 1],
		["recruitment_seed", -1], ["recruitment_seed", true],
		["recruitment_seed", HeroCatalog.MAX_SAFE_INT + 1],
		["recruitment_sequence", -1], ["recruitment_sequence", 0.5],
		["recruitment_sequence", INF], ["recruitment_sequence", HeroCatalog.MAX_SAFE_INT + 1],
		["offer_seeds", []], ["offer_seeds", [0, -1, 2]],
		["offer_seeds", [0, 2.5, 2]], ["offer_seeds", [0, HeroCatalog.MAX_SAFE_INT + 1, 2]],
		["roster", {}], ["recruitment_offers", []], ["inventory", [1]],
		["unlocked_regions", [1]], ["unlocked_regions", [""]], ["unlocked_regions", ["a", "a"]],
	]
	for change in changes:
		var invalid := snapshot.duplicate(true)
		invalid[change[0]] = change[1]
		assert_false(SaveManager.validate_snapshot(invalid), str(change))
	for key in snapshot:
		var invalid := snapshot.duplicate(true)
		invalid.erase(key)
		assert_false(SaveManager.validate_snapshot(invalid), "Missing %s" % key)
	var extra := snapshot.duplicate(true)
	extra["selection"] = "hero-1"
	assert_false(SaveManager.validate_snapshot(extra))


func test_hero_validation_rejects_unknown_resources_ids_attributes_and_equipment() -> void:
	var snapshot := _boot()
	var changes := [
		["hero_id", ""], ["hero_id", "hero-0"], ["hero_id", "hero-01"],
		["hero_id", "hero-999999999999999999999999999"], ["hero_id", "hero-+1"],
		["hero_id", "hero-1.1"], ["hero_id", 1], ["hero_name", ""], ["hero_name", true],
		["class_id", "unknown"], ["class_id", "res://data/classes/knight.tres"],
		["level", 0], ["level", 1.5], ["level", HeroCatalog.MAX_LEVEL + 1],
		["xp", -1], ["xp", 2.3], ["xp", true], ["xp", HeroCatalog.MAX_SAFE_INT + 1],
		["status", "FAKE"], ["status", 1], ["equipped_weapon", {}], ["equipped_armor", "item-1"],
		["trait_ids", ["unknown"]], ["trait_ids", ["res://data/traits/hearty.tres"]],
		["trait_ids", [HeroCatalog.HEARTY.trait_id, HeroCatalog.HEARTY.trait_id]],
		["trait_ids", [null]], ["traits", []], ["attributes", []],
	]
	for change in changes:
		var invalid := snapshot.duplicate(true)
		invalid.roster[0][change[0]] = change[1]
		assert_false(SaveManager.validate_snapshot(invalid), str(change))
	for key in snapshot.roster[0]:
		var invalid := snapshot.duplicate(true)
		invalid.roster[0].erase(key)
		assert_false(SaveManager.validate_snapshot(invalid), "Missing hero %s" % key)
	for value in [null, true, "9", -1, 9.1, INF, NAN, HeroCatalog.MAX_ATTRIBUTE + 1]:
		var invalid := snapshot.duplicate(true)
		invalid.roster[0].attributes.MIG = value
		assert_false(SaveManager.validate_snapshot(invalid), "Attribute %s" % str(value))
	var missing := snapshot.duplicate(true)
	missing.roster[0].attributes.erase("FOC")
	assert_false(SaveManager.validate_snapshot(missing))


func test_ids_are_unique_across_roster_and_offers_and_counter_is_ahead() -> void:
	var snapshot := _boot()
	for paths in [["roster", 1, "roster", 0], ["recruitment_offers", 1, "recruitment_offers", 0],
			["recruitment_offers", 0, "roster", 0]]:
		var invalid := snapshot.duplicate(true)
		invalid[paths[0]][paths[1]].hero_id = invalid[paths[2]][paths[3]].hero_id
		assert_false(SaveManager.validate_snapshot(invalid))
	var invalid := snapshot.duplicate(true)
	invalid.recruitment_offers[0].status = "ASSIGNED"
	assert_false(SaveManager.validate_snapshot(invalid))


func test_validation_does_not_partially_mutate_live_state() -> void:
	var original := _boot()
	var invalid := original.duplicate(true)
	invalid.gold = 500
	invalid.roster[3].class_id = "missing"
	assert_false(SaveManager.validate_snapshot(invalid))
	assert_eq(SaveManager.capture_state(), original)
	GameState.roster[0].equipped_weapon = ItemResource.new()
	var disk := _read(SaveManager.get_save_path())
	SaveManager.save()
	assert_false(SaveManager.last_success)
	assert_false(SaveManager.last_committed)
	assert_eq(_read(SaveManager.get_save_path()), disk)


func test_missing_primary_uses_backup_without_modifying_it() -> void:
	var original := _boot()
	GameState.gold = 33
	SaveManager.save()
	var backup := _read(SaveManager.get_save_path() + ".bak")
	assert_eq(DirAccess.remove_absolute(SaveManager.get_save_path()), OK)
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success, SaveManager.last_error)
	assert_eq(SaveManager.capture_state(), original)
	assert_string_contains(SaveManager.last_warning, "Recovered")
	assert_eq(_read(SaveManager.get_save_path() + ".bak"), backup)
	assert_true(SaveManager.validate_snapshot(JSON.parse_string(_read(SaveManager.get_save_path()))))


func test_corrupt_primary_recovers_backup_and_valid_primary_wins() -> void:
	var original := _boot()
	GameState.gold = 33
	SaveManager.save()
	SaveManager.load_or_create()
	assert_eq(GameState.gold, 33)
	assert_eq(SaveManager.last_warning, "")
	var backup := _read(SaveManager.get_save_path() + ".bak")
	_write(SaveManager.get_save_path(), "{truncated")
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), original)
	assert_eq(_read(SaveManager.get_save_path() + ".bak"), backup)
	assert_string_contains(SaveManager.last_warning, "Recovered")


func test_unsupported_primary_version_recovers_valid_backup() -> void:
	var original := _boot()
	GameState.gold = 55
	SaveManager.save()
	var invalid := SaveManager.capture_state()
	invalid.save_version = 999
	_write(SaveManager.get_save_path(), JSON.stringify(invalid))
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), original)
	assert_string_contains(SaveManager.last_warning, "Recovered")


func test_recovery_restore_failure_preserves_backup_and_recovered_memory() -> void:
	var original := _boot()
	GameState.gold = 33
	SaveManager.save()
	var backup := _read(SaveManager.get_save_path() + ".bak")
	_write(SaveManager.get_save_path(), "invalid")
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "before_primary_replace"
	SaveManager.load_or_create()
	assert_false(SaveManager.last_success)
	assert_eq(SaveManager.capture_state(), original)
	assert_eq(_read(SaveManager.get_save_path() + ".bak"), backup)
	assert_string_contains(SaveManager.last_warning, "restoration failed")


func test_abandoned_temporary_files_are_never_promoted() -> void:
	var original := _boot()
	var abandoned := original.duplicate(true)
	abandoned.gold = 777
	_write(SaveManager.get_save_path() + ".tmp", JSON.stringify(abandoned))
	_write(SaveManager.get_save_path() + ".bak.tmp", JSON.stringify(abandoned))
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), original)
	DirAccess.remove_absolute(SaveManager.get_save_path())
	SaveManager.new_game_seed_override = 99
	SaveManager.load_or_create()
	assert_eq(GameState.gold, 100)
	assert_eq(GameState.recruitment_seed, 99)


func test_invalid_primary_and_backup_create_new_game_with_visible_warning() -> void:
	_write(SaveManager.get_save_path(), "invalid")
	_write(SaveManager.get_save_path() + ".bak", "also invalid")
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success)
	assert_eq(GameState.roster.size(), 4)
	assert_eq(GameState.gold, 100)
	assert_string_contains(SaveManager.last_warning, "Neither")


func test_every_precommit_interruption_preserves_loadable_old_primary() -> void:
	var original := _boot()
	for boundary in ["before_temp_write", "after_temp_validation", "after_backup_preparation",
			"after_backup_replace", "before_primary_replace"]:
		var before := _read(SaveManager.get_save_path())
		GameState.gold = 77
		SaveManager.fault_injector = func(stage: String) -> bool: return stage == boundary
		SaveManager.save()
		assert_false(SaveManager.last_success, boundary)
		assert_false(SaveManager.last_committed, boundary)
		assert_string_contains(SaveManager.last_error, boundary)
		assert_eq(_read(SaveManager.get_save_path()), before, boundary)
		SaveManager.fault_injector = Callable()
		SaveManager.load_or_create()
		assert_eq(SaveManager.capture_state(), original, boundary)


func test_postcommit_interruption_is_success_and_reload_uses_new_primary() -> void:
	_boot()
	GameState.gold = 42
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "after_primary_replace"
	SaveManager.save()
	assert_true(SaveManager.last_success)
	assert_true(SaveManager.last_committed)
	assert_eq(SaveManager.last_error, "")
	assert_false(SaveManager.last_warning.is_empty())
	SaveManager.fault_injector = Callable()
	SaveManager.load_or_create()
	assert_eq(GameState.gold, 42)


func test_filesystem_write_and_replace_failures_preserve_primary() -> void:
	_boot()
	var before := _read(SaveManager.get_save_path())
	var temp := SaveManager.get_save_path() + ".tmp"
	assert_eq(DirAccess.make_dir_absolute(temp), OK)
	GameState.gold = 22
	SaveManager.save()
	assert_false(SaveManager.last_success)
	assert_eq(_read(SaveManager.get_save_path()), before)
	DirAccess.remove_absolute(temp)
	var backup := SaveManager.get_save_path() + ".bak"
	assert_eq(DirAccess.make_dir_absolute(backup), OK)
	SaveManager.save()
	assert_false(SaveManager.last_success)
	assert_string_contains(SaveManager.last_error, "backup")
	assert_eq(_read(SaveManager.get_save_path()), before)


func test_failed_new_game_save_does_not_claim_persistence() -> void:
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "before_primary_replace"
	SaveManager.load_or_create()
	assert_true(GameState.initialized)
	assert_false(SaveManager.last_success)
	assert_false(SaveManager.last_committed)
	assert_false(FileAccess.file_exists(SaveManager.get_save_path()))
	assert_string_contains(SaveManager.last_warning, "not saved")
	SaveManager.fault_injector = Callable()
	SaveManager.save()
	assert_true(SaveManager.last_success)
