extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
var _isolation: RefCounted


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success)


func after_each() -> void:
	_isolation.finish()


func _start() -> Dictionary:
	GameState.expedition_seed = 1
	var party := PartyData.new()
	for index in range(GameState.roster.size()):
		party.place_hero(index, GameState.roster[index])
	assert_true(PartyFormationService.confirm(party, ExpeditionManager.balancing))
	ExpeditionManager.start_expedition(ExpeditionCatalog.GREEN_HOLLOW, GameState.current_party, 60)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	return SaveManager.capture_state()


func _v4(snapshot: Dictionary) -> Dictionary:
	var legacy := snapshot.duplicate(true)
	legacy.save_version = 4
	legacy.erase("expedition_automation")
	if legacy.expedition != null:
		for key in ["xp_award", "recovery_seconds", "rest_hp_percent"]:
			legacy.expedition.erase(key)
		for step in legacy.expedition.steps:
			step.result.erase("item_ids")
	return legacy


func test_inventory_duplicates_equipment_and_independent_saved_level_round_trip() -> void:
	GameState.inventory.assign([ItemCatalog.SHORT_SWORD, ItemCatalog.SHORT_SWORD, ItemCatalog.ROBES])
	var hero := GameState.roster[0]
	hero.equipped_weapon = ItemCatalog.HUNTING_BOW
	hero.equipped_armor = ItemCatalog.CHAINMAIL
	hero.level = 17
	hero.xp = 0
	var expected := SaveManager.capture_state()
	assert_eq(expected.inventory, ["short_sword", "short_sword", "robes"])
	assert_eq(expected.roster[0].equipped_weapon, "hunting_bow")
	SaveManager.save()
	assert_true(SaveManager.last_committed, SaveManager.last_error)
	GameState.reset()
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), expected)
	assert_eq(GameState.inventory.get_typed_script(), ItemResource)
	assert_same(GameState.inventory[0], ItemCatalog.SHORT_SWORD)
	assert_same(GameState.inventory[0], GameState.inventory[1])
	assert_same(GameState.roster[0].equipped_armor, ItemCatalog.CHAINMAIL)


func test_item_ids_slots_offers_and_resource_identity_are_strict() -> void:
	var original := SaveManager.capture_state()
	for value in [null, {}, [null], [1], ["missing"], ["res://data/items/short_sword.tres"]]:
		var bad := original.duplicate(true)
		bad.inventory = value
		assert_false(SaveManager.validate_snapshot(bad), str(value))
	for field in ["equipped_weapon", "equipped_armor"]:
		for value in ["missing", "res://data/items/short_sword.tres", {}, true,
				"robes" if field == "equipped_weapon" else "short_sword"]:
			var bad := original.duplicate(true)
			bad.roster[0][field] = value
			assert_false(SaveManager.validate_snapshot(bad), str(value))
	var offer := original.duplicate(true)
	offer.recruitment_offers[0].equipped_weapon = "short_sword"
	assert_false(SaveManager.validate_snapshot(offer))
	GameState.inventory.append(ItemCatalog.SHORT_SWORD.duplicate(true))
	SaveManager.save()
	assert_false(SaveManager.last_committed, "Unregistered resource identity cannot be serialized by a copied ID.")


func test_checkpoint_restores_xp_levels_slots_inventory_and_canonical_identity() -> void:
	var hero := GameState.roster[0]
	var offer := GameState.recruitment_offers[0]
	GameState.inventory.assign([ItemCatalog.SHORT_SWORD, ItemCatalog.SHORT_SWORD])
	hero.equipped_armor = ItemCatalog.ROBES
	var before := SaveManager.capture_state()
	var checkpoint := GameState.checkpoint()
	for member in [hero, offer]:
		member.xp = 1000
		member.level = 10
		member.equipped_weapon = ItemCatalog.HUNTING_BOW
		member.equipped_armor = ItemCatalog.CHAINMAIL
	GameState.inventory.clear()
	GameState.restore_checkpoint(checkpoint)
	assert_eq(SaveManager.capture_state(), before)
	assert_same(GameState.roster[0], hero)
	assert_same(GameState.recruitment_offers[0], offer)


func test_v4_migration_preserves_combat_journal_exactly_and_adds_frozen_defaults() -> void:
	var legacy := _v4(_start())
	var original := legacy.duplicate(true)
	var migrated := SaveManager.migrate(legacy)
	assert_false(migrated.is_empty())
	assert_eq(legacy, original)
	assert_eq(migrated.expedition.steps, legacy.expedition.steps)
	assert_eq(migrated.expedition.party_snapshot, legacy.expedition.party_snapshot)
	assert_eq(migrated.expedition.xp_award, 0)
	assert_eq(migrated.expedition.recovery_seconds, 60)
	assert_eq(migrated.expedition.rest_hp_percent, 0)
	assert_true(SaveManager.validate_snapshot(migrated))
	var combat_count := 0
	for step in legacy.expedition.steps:
		if step.kind == ExpeditionStep.StepKind.COMBAT:
			combat_count += 1
	assert_gt(combat_count, 0)


func test_v4_migration_converts_only_positive_wounded_deadlines() -> void:
	var legacy := _v4(SaveManager.capture_state())
	legacy.roster[0].status = "WOUNDED"
	legacy.roster[0].recovery_ready_at = 1060
	legacy.roster[1].status = "WOUNDED"
	legacy.roster[2].status = "RESTING"
	var migrated := SaveManager.migrate(legacy)
	assert_eq(migrated.roster[0].status, "RESTING")
	assert_eq(migrated.roster[0].recovery_ready_at, 1060)
	assert_eq(migrated.roster[1].status, "WOUNDED")
	assert_eq(migrated.roster[2].status, "RESTING")
	for status in ["IDLE", "RESTING", "DEAD"]:
		var bad := legacy.duplicate(true)
		bad.roster[0].status = status
		assert_eq(SaveManager.migrate(bad), {}, "Do not repair invalid v4 deadline owner.")
	var file := FileAccess.open(SaveManager.get_save_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy, "", true, true))
	file.close()
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), migrated)
	ExpeditionManager.clock = func() -> int: return 1060
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed)
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.IDLE)
	assert_eq(GameState.roster[1].status, HeroData.HeroStatus.WOUNDED)


func test_completed_v4_report_keeps_xp_levels_journal_and_original_deadlines() -> void:
	var legacy := _v4(_start())
	var record: Dictionary = legacy.expedition
	record.status = ExpeditionData.Status.COMPLETED
	record.credited_elapsed_seconds = int(record.effective_end_timestamp) - int(record.start_timestamp)
	record.last_revealed_index = record.steps.size() - 1
	record.last_observed_utc = record.effective_end_timestamp
	var final := ExpeditionData.new(record).final_hero_states()
	for hero in legacy.roster:
		hero.status = "WOUNDED" if int(final[hero.hero_id].status) == HeroData.HeroStatus.WOUNDED else "IDLE"
		hero.recovery_ready_at = 9000 if hero.status == "WOUNDED" else 0
		hero.level = 17
		hero.xp = 7
	var migrated := SaveManager.migrate(legacy)
	assert_false(migrated.is_empty())
	assert_eq(migrated.expedition.steps, record.steps)
	var file := FileAccess.open(SaveManager.get_save_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy, "", true, true))
	file.close()
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), migrated)
	for hero in GameState.roster:
		assert_eq(hero.level, 17)
		assert_eq(hero.xp, 7)
		assert_eq(hero.recovery_ready_at, 9000 if hero.status == HeroData.HeroStatus.RESTING else 0)


func test_old_schemas_reject_new_items_and_fields_before_normalization() -> void:
	var legacy := _v4(_start())
	for key in ["xp_award", "recovery_seconds", "rest_hp_percent"]:
		var bad := legacy.duplicate(true)
		bad.expedition[key] = 0
		assert_eq(SaveManager.migrate(bad), {})
	var bad := legacy.duplicate(true)
	bad.expedition.steps[0].result.item_ids = []
	assert_eq(SaveManager.migrate(bad), {})
	for step in legacy.expedition.steps:
		if step.kind in [ExpeditionStep.StepKind.LOOT, ExpeditionStep.StepKind.EVENT]:
			var original: Dictionary = step.result.duplicate(true)
			step.result.item_ids = []
			assert_eq(SaveManager.migrate(legacy), {}, "Even empty item lists did not exist in v4.")
			step.result = original
	for version in [1, 2, 3, 4]:
		var old := _v4(SaveManager.capture_state())
		old.expedition = null
		for hero in old.roster:
			hero.status = "IDLE"
		old.save_version = version
		if version < 4:
			for hero in old.roster + old.recruitment_offers:
				hero.erase("recovery_ready_at")
		if version < 3:
			for key in ["expedition", "expedition_seed", "expedition_sequence", "expedition_automation"]:
				old.erase(key)
		if version == 1:
			old.erase("current_party")
		assert_false(SaveManager.migrate(old).is_empty())
		old.inventory = ["short_sword"]
		assert_eq(SaveManager.migrate(old), {})
		old.inventory = []
		old.roster[0].equipped_weapon = "short_sword"
		assert_eq(SaveManager.migrate(old), {})


func test_v5_requires_exact_frozen_integers_but_constructor_supports_legacy_callers() -> void:
	var snapshot := _start()
	for key in ["xp_award", "recovery_seconds", "rest_hp_percent"]:
		for value in [null, true, -1, 0.5, INF, NAN, HeroCatalog.MAX_SAFE_INT + 1]:
			var bad := snapshot.duplicate(true)
			bad.expedition[key] = value
			assert_false(SaveManager.validate_snapshot(bad), "%s=%s" % [key, value])
		var missing := snapshot.duplicate(true)
		missing.expedition.erase(key)
		assert_false(SaveManager.validate_snapshot(missing))
	for change in [["recovery_seconds", 0], ["rest_hp_percent", 101]]:
		var bad := snapshot.duplicate(true)
		bad.expedition[change[0]] = change[1]
		assert_false(SaveManager.validate_snapshot(bad))
	var legacy: Dictionary = _v4(snapshot).expedition
	var run := ExpeditionData.new(legacy)
	assert_true(ExpeditionData.valid(run.serialize()))
	assert_eq(run.xp_award, 0)
	assert_eq(run.rest_hp_percent, 0)
	assert_eq(run.recovery_seconds, 60)
