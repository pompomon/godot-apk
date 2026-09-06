extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
const BALANCING: BalancingConfig = preload("res://data/balancing/default_balancing.tres")
var _isolation: RefCounted


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success)


func after_each() -> void:
	_isolation.finish()


func _write(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	file.store_string(JSON.stringify(data))
	file.flush()
	file.close()


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file)
	var text := file.get_as_text()
	file.close()
	return text


func _legacy() -> Dictionary:
	var data := SaveManager.capture_state()
	data.erase("current_party")
	for key in ["expedition", "expedition_seed", "expedition_sequence"]:
		data.erase(key)
	for hero in data.roster + data.recruitment_offers:
		hero.erase("recovery_ready_at")
	data.save_version = 1
	return data


func _party() -> PartyData:
	var party := PartyData.new()
	party.place_hero(0, GameState.roster[0])
	party.place_hero(3, GameState.roster[1])
	return party


func test_null_partial_back_row_and_full_parties_round_trip_with_exact_roster_identity() -> void:
	for mapping in [[], [3], [0, 3], [0, 1, 3], [3, 2, 1, 0]]:
		assert_true(PartyFormationService.disband())
		var party := PartyData.new()
		for index in mapping.size():
			party.place_hero(mapping[index], GameState.roster[index])
		if not mapping.is_empty():
			assert_true(PartyFormationService.confirm(party, BALANCING))
		var expected := SaveManager.capture_state()
		assert_eq(expected.save_version, 4)
		assert_true(SaveManager.validate_snapshot(expected))
		GameState.reset()
		SaveManager.load_or_create()
		assert_eq(SaveManager.capture_state(), expected)
		if mapping.is_empty():
			assert_null(GameState.current_party)
			continue
		assert_eq(expected.current_party.keys(), PartyData.SLOT_NAMES)
		for slot in PartyData.SLOT_ORDER:
			var id: Variant = expected.current_party[PartyData.SLOT_NAMES[slot]]
			if id == null:
				assert_null(GameState.current_party.slots[slot])
			else:
				assert_same(GameState.current_party.slots[slot], GameState.find_hero(id))
				assert_eq(GameState.find_hero(id).status, HeroData.HeroStatus.ASSIGNED)


func test_loading_null_party_clears_previous_party_and_does_not_persist_drafts_or_power() -> void:
	var empty := SaveManager.capture_state()
	assert_true(PartyFormationService.confirm(_party(), BALANCING))
	_write(SaveManager.get_save_path(), empty)
	SaveManager.load_or_create()
	assert_null(GameState.current_party)
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.IDLE)
	var draft := _party()
	draft.move_hero(0, 2)
	SaveManager.save()
	assert_eq(SaveManager.capture_state(), empty)
	assert_eq(JSON.parse_string(_read(SaveManager.get_save_path())), JSON.parse_string(JSON.stringify(empty)))


func test_invalid_party_shape_members_status_orphans_and_offers_are_rejected() -> void:
	assert_true(PartyFormationService.confirm(_party(), BALANCING))
	var original := SaveManager.capture_state()
	for party_value in [null, [], true, "hero-1", {}, {"FRONT_LEFT": "hero-1"},
			{"FRONT_LEFT": null, "FRONT_RIGHT": null, "BACK_LEFT": null, "BACK_RIGHT": null}]:
		var invalid := original.duplicate(true)
		invalid.current_party = party_value
		assert_false(SaveManager.validate_snapshot(invalid), str(party_value))
	for value in [0, true, [], {}, "", "hero-999", GameState.recruitment_offers[0].hero_id,
			original.current_party.BACK_RIGHT]:
		var invalid := original.duplicate(true)
		invalid.current_party.FRONT_LEFT = value
		assert_false(SaveManager.validate_snapshot(invalid), str(value))
	for status in ["IDLE", "ON_EXPEDITION", "RESTING", "WOUNDED", "DEAD"]:
		var invalid := original.duplicate(true)
		invalid.roster[0].status = status
		assert_false(SaveManager.validate_snapshot(invalid))
	var extra := original.duplicate(true)
	extra.current_party["POWER"] = 100
	assert_false(SaveManager.validate_snapshot(extra))
	extra = original.duplicate(true)
	extra.current_party["EXTRA_SLOT"] = "hero-3"
	assert_false(SaveManager.validate_snapshot(extra))
	extra = original.duplicate(true)
	extra.roster[2].status = "ASSIGNED"
	assert_false(SaveManager.validate_snapshot(extra))
	assert_eq(SaveManager.capture_state(), original)


func test_save_rejects_noncanonical_member_even_with_same_stable_id() -> void:
	assert_true(PartyFormationService.confirm(_party(), BALANCING))
	var primary := _read(SaveManager.get_save_path())
	GameState.current_party.slots[0] = HeroData.new(GameState.roster[0].hero_id)
	SaveManager.save()
	assert_false(SaveManager.last_committed)
	assert_eq(_read(SaveManager.get_save_path()), primary)
	SaveManager.load_or_create()
	assert_same(GameState.current_party.slots[0], GameState.roster[0])


func test_version_one_migration_preserves_all_old_data_except_orphan_assigned() -> void:
	GameState.gold = 1000
	assert_true(RecruitmentService.recruit(GameState.recruitment_offers[0], BALANCING))
	assert_true(RecruitmentService.recruit(GameState.recruitment_offers[1], BALANCING))
	GameState.recruitment_seed = HeroCatalog.MAX_SAFE_INT
	GameState.recruitment_sequence = HeroCatalog.MAX_SAFE_INT
	GameState.offer_seeds.assign([0, 77, HeroCatalog.MAX_SAFE_INT])
	GameState.next_hero_id = HeroCatalog.MAX_SAFE_INT
	GameState.unlocked_regions.assign([&"forest", &"mountains"])
	var legacy := _legacy()
	for index in HeroData.HeroStatus.size():
		legacy.roster[index].status = HeroData.HeroStatus.keys()[index]
		legacy.roster[index].hero_name = "Legacy Hero %d" % index
		legacy.roster[index].level = 50 + index
		legacy.roster[index].xp = HeroCatalog.MAX_SAFE_INT - index
		legacy.roster[index].attributes.MIG = HeroCatalog.MAX_ATTRIBUTE
	var untouched := legacy.duplicate(true)
	var migrated := SaveManager.migrate(legacy)
	var expected := untouched.duplicate(true)
	expected.save_version = 4
	expected.current_party = null
	expected.expedition = null
	expected.expedition_seed = expected.recruitment_seed
	expected.expedition_sequence = 0
	expected.roster[1].status = "IDLE"
	expected.roster[2].status = "IDLE"
	for hero in expected.roster + expected.recruitment_offers:
		hero.recovery_ready_at = 0
	assert_eq(migrated, expected)
	assert_eq(legacy, untouched)
	assert_true(SaveManager.validate_snapshot(migrated))
	migrated.roster[0].attributes.MIG = 12
	migrated.recruitment_offers[0].trait_ids.clear()
	assert_eq(legacy, untouched, "Migration must not alias nested caller data.")


func test_malformed_legacy_input_cannot_be_laundered_by_normalization() -> void:
	var original := _legacy()
	var cases: Array = []
	var invalid := original.duplicate(true)
	invalid.current_party = null
	cases.append(invalid)
	invalid = original.duplicate(true)
	invalid.roster[0].status = "assigned"
	cases.append(invalid)
	invalid = original.duplicate(true)
	invalid.roster[0].status = null
	cases.append(invalid)
	invalid = original.duplicate(true)
	invalid.recruitment_offers[0].status = "ASSIGNED"
	cases.append(invalid)
	invalid = original.duplicate(true)
	invalid.roster[0].class_id = "missing"
	invalid.roster[0].status = "ASSIGNED"
	cases.append(invalid)
	invalid = original.duplicate(true)
	invalid.roster[0].attributes.MIG = NAN
	cases.append(invalid)
	invalid = original.duplicate(true)
	invalid.roster[0].attributes.erase("GUI")
	cases.append(invalid)
	invalid = original.duplicate(true)
	invalid.roster[1].hero_id = invalid.roster[0].hero_id
	cases.append(invalid)
	invalid = original.duplicate(true)
	invalid.roster[0].recovery_ready_at = 0
	cases.append(invalid)
	for key in original:
		invalid = original.duplicate(true)
		invalid.erase(key)
		cases.append(invalid)
	for data in cases:
		assert_eq(SaveManager.migrate(data), {})


func test_primary_version_one_upgrades_without_resetting_progress() -> void:
	var legacy := _legacy()
	legacy.gold = 732
	legacy.roster[0].status = "ASSIGNED"
	legacy.roster[1].status = "WOUNDED"
	legacy.roster[2].level = 42
	legacy.roster[2].xp = 765
	var expected := SaveManager.migrate(legacy)
	_write(SaveManager.get_save_path(), legacy)
	GameState.reset()
	SaveManager.new_game_seed_override = 987654
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success)
	assert_eq(SaveManager.last_warning, "")
	assert_eq(SaveManager.capture_state(), expected)
	SaveManager.save()
	assert_true(SaveManager.last_committed)
	assert_eq(JSON.parse_string(_read(SaveManager.get_save_path())), JSON.parse_string(JSON.stringify(expected)))
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), expected)


func test_backup_version_one_upgrades_primary_without_modifying_backup() -> void:
	var legacy := _legacy()
	legacy.gold = 411
	legacy.roster[0].status = "ASSIGNED"
	legacy.roster[1].status = "RESTING"
	var expected := SaveManager.migrate(legacy)
	_write(SaveManager.get_save_path() + ".bak", legacy)
	var backup := _read(SaveManager.get_save_path() + ".bak")
	_write(SaveManager.get_save_path(), {"broken": true})
	GameState.reset()
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success)
	assert_string_contains(SaveManager.last_warning, "Recovered")
	assert_eq(SaveManager.capture_state(), expected)
	assert_eq(_read(SaveManager.get_save_path() + ".bak"), backup)
	assert_eq(JSON.parse_string(_read(SaveManager.get_save_path())), JSON.parse_string(JSON.stringify(expected)))


func test_invalid_new_primary_recovers_committed_party_backup_without_partial_mutation() -> void:
	assert_true(PartyFormationService.confirm(_party(), BALANCING))
	var expected := SaveManager.capture_state()
	GameState.gold = 500
	SaveManager.save()
	var invalid := SaveManager.capture_state()
	invalid.current_party.FRONT_LEFT = GameState.recruitment_offers[0].hero_id
	_write(SaveManager.get_save_path(), invalid)
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), expected)
	assert_same(GameState.current_party.slots[0], GameState.roster[0])
	assert_string_contains(SaveManager.last_warning, "Recovered")
