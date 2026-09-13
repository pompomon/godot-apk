extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
const PRECOMMIT_STAGES := [
	"before_temp_write", "after_temp_validation", "after_backup_preparation",
	"after_backup_replace", "before_primary_replace",
]
var _isolation: RefCounted


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success, SaveManager.last_error)


func after_each() -> void:
	_isolation.finish()


func _path(name: String) -> String:
	return _isolation.directory.path_join(name)


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	file.store_string(text)
	file.flush()
	file.close()


func _write_json(path: String, data: Variant) -> void:
	_write_text(path, JSON.stringify(data, "\t", true, true))


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file)
	var text := file.get_as_text()
	file.close()
	return text


func _read_json(path: String) -> Dictionary:
	return JSON.parse_string(_read_text(path))


func _portable(path: String = "") -> Dictionary:
	if path.is_empty():
		path = _path("portable.json")
	SaveManager.export_external_save(path)
	assert_true(SaveManager.last_success, SaveManager.last_error)
	return _read_json(path)


func _party() -> PartyData:
	var party := PartyData.new()
	assert_true(party.place_hero(0, GameState.roster[0]))
	return party


func _legacy(snapshot: Dictionary, version: int) -> Dictionary:
	var result := snapshot.duplicate(true)
	result.save_version = version
	if version < 7:
		result.erase("expedition_automation")
	if version < 4:
		for hero in result.roster + result.recruitment_offers:
			hero.erase("recovery_ready_at")
	if version < 3:
		for key in ["expedition", "expedition_seed", "expedition_sequence"]:
			result.erase(key)
	if version < 2:
		result.erase("current_party")
	return result


func test_export_is_deterministic_strict_and_contains_only_durable_state() -> void:
	GameState.roster.reverse()
	var hero := GameState.find_hero("hero-1")
	hero.hero_name = "Portable Hero"
	hero.level = 27
	hero.xp = 4567
	hero.attributes.MIG = 42
	hero.traits.assign([HeroCatalog.HEARTY])
	hero.equipped_weapon = ItemCatalog.HUNTING_BOW
	hero.equipped_armor = ItemCatalog.ROBES
	GameState.find_hero("hero-2").status = HeroData.HeroStatus.RESTING
	GameState.find_hero("hero-2").recovery_ready_at = 4321
	GameState.find_hero("hero-3").status = HeroData.HeroStatus.WOUNDED
	GameState.find_hero("hero-4").status = HeroData.HeroStatus.DEAD
	GameState.inventory.assign(
		[ItemCatalog.SHORT_SWORD, ItemCatalog.ROBES, ItemCatalog.SHORT_SWORD])
	GameState.gold = 400
	GameState.unlocked_regions.assign(
		[&"frostbound_pass", &"green_hollow", &"ashen_reach"])
	GameState.roster_capacity = 20
	SaveManager.save()
	assert_true(SaveManager.last_committed, SaveManager.last_error)
	var first_path := _path("first.json")
	var second_path := _path("second.json")
	var document := _portable(first_path)
	SaveManager.export_external_save(second_path)
	assert_true(SaveManager.last_success, SaveManager.last_error)
	assert_false(SaveManager.last_committed)
	assert_eq(_read_text(first_path), _read_text(second_path))
	assert_true(HeroCatalog.has_exact_keys(document, ExternalSaveCodec.ROOT_KEYS))
	assert_true(HeroCatalog.has_exact_keys(
		document.payload, ExternalSaveCodec.PAYLOAD_KEYS))
	assert_eq(document.format, ExternalSaveCodec.FORMAT_ID)
	assert_eq(int(document.schema_version), ExternalSaveCodec.SCHEMA_VERSION)
	assert_eq(document.extensions, {})
	for excluded in [
			"current_party", "recruitment_offers", "roster_capacity", "next_hero_id",
			"recruitment_seed", "recruitment_sequence", "offer_seeds",
			"expedition_seed", "expedition_sequence", "expedition",
			"expedition_automation",
	]:
		assert_false(document.has(excluded), excluded)
		assert_false(document.payload.has(excluded), excluded)
	assert_eq(document.payload.items, ["robes", "short_sword", "short_sword"])
	assert_eq(
		document.payload.opened_stages,
		["ashen_reach", "frostbound_pass", "green_hollow"])
	assert_eq(document.payload.heroes.map(
		func(value: Dictionary) -> String: return value.hero_id),
		["hero-1", "hero-2", "hero-3", "hero-4"])
	var exported: Dictionary = document.payload.heroes[0]
	assert_eq(exported.hero_name, "Portable Hero")
	assert_eq(int(exported.level), 27)
	assert_eq(int(exported.xp), 4567)
	assert_eq(int(exported.attributes.MIG), 42)
	assert_eq(exported.trait_ids, ["hearty"])
	assert_eq(exported.equipped_weapon, "hunting_bow")
	assert_eq(exported.equipped_armor, "robes")
	assert_eq(document.payload.heroes[1].status, "RESTING")
	assert_eq(int(document.payload.heroes[1].recovery_ready_at), 4321)
	assert_eq(document.payload.heroes[2].status, "WOUNDED")
	assert_eq(document.payload.heroes[3].status, "DEAD")


func test_confirmed_party_active_automation_and_completed_report_are_never_exported() -> void:
	assert_true(PartyFormationService.confirm(_party(), ExpeditionManager.balancing))
	var confirmed := _portable(_path("confirmed.json"))
	assert_eq(confirmed.payload.heroes[0].status, "IDLE")
	assert_eq(int(confirmed.payload.heroes[0].recovery_ready_at), 0)
	ExpeditionManager.start_expedition(
		ExpeditionCatalog.GREEN_HOLLOW, GameState.current_party, 60, 2)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	var active := _portable(_path("active.json"))
	assert_string_contains(SaveManager.last_warning, "exclude")
	assert_eq(active.payload.heroes[0].status, "IDLE")
	assert_false(active.payload.has("expedition"))
	assert_false(active.payload.has("expedition_automation"))
	ExpeditionManager.stop_automation_after_current()
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	ExpeditionManager.clock = func() -> int: return 1060
	ExpeditionManager.reveal_progress()
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	assert_false(ExpeditionManager.is_expedition_active())
	var completed := _portable(_path("completed.json"))
	assert_false(completed.payload.has("expedition"))
	assert_false(completed.payload.has("expedition_automation"))
	assert_ne(completed.payload.heroes[0].status, "ON_EXPEDITION")


func test_import_replaces_company_rebuilds_runtime_state_and_survives_restart() -> void:
	GameState.gold = 400
	GameState.inventory.assign(
		[ItemCatalog.SHORT_SWORD, ItemCatalog.SHORT_SWORD, ItemCatalog.ROBES])
	GameState.roster[0].equipped_weapon = ItemCatalog.HUNTING_BOW
	GameState.roster[1].status = HeroData.HeroStatus.RESTING
	GameState.roster[1].recovery_ready_at = 5000
	GameState.roster[2].status = HeroData.HeroStatus.WOUNDED
	GameState.roster[3].status = HeroData.HeroStatus.DEAD
	var source := _path("company.json")
	_portable(source)
	for hero in GameState.roster:
		hero.status = HeroData.HeroStatus.IDLE
		hero.recovery_ready_at = 0
	GameState.gold = 7
	GameState.inventory.clear()
	assert_true(PartyFormationService.confirm(_party(), ExpeditionManager.balancing))
	ExpeditionManager.start_expedition(
		ExpeditionCatalog.GREEN_HOLLOW, GameState.current_party, 60, 2)
	assert_true(ExpeditionManager.last_committed, ExpeditionManager.last_error)
	var replaced: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(SaveManager.get_save_path()))
	SaveManager.import_external_save(source)
	assert_true(SaveManager.last_committed, SaveManager.last_error)
	assert_true(SaveManager.last_success)
	assert_string_contains(SaveManager.last_warning, "not imported")
	assert_eq(GameState.gold, 400)
	assert_eq(GameState.inventory.size(), 3)
	assert_same(GameState.inventory[0], ItemCatalog.ROBES)
	assert_eq(GameState.inventory.count(ItemCatalog.SHORT_SWORD), 2)
	assert_same(GameState.roster[0].equipped_weapon, ItemCatalog.HUNTING_BOW)
	assert_eq(GameState.roster[1].status, HeroData.HeroStatus.RESTING)
	assert_eq(GameState.roster[1].recovery_ready_at, 5000)
	assert_eq(GameState.roster[2].status, HeroData.HeroStatus.WOUNDED)
	assert_eq(GameState.roster[3].status, HeroData.HeroStatus.DEAD)
	assert_null(GameState.current_party)
	assert_null(ExpeditionManager.get_active_expedition())
	assert_eq(ExpeditionManager.get_automation_state(), {})
	assert_eq(
		GameState.unlocked_regions,
		[&"green_hollow", &"ashen_reach", &"frostbound_pass"])
	assert_eq(GameState.roster_capacity, 20)
	assert_eq(GameState.recruitment_offers.size(), RecruitmentService.OFFER_COUNT)
	assert_eq(GameState.next_hero_id, 8)
	var all_ids := {}
	for hero in GameState.roster + GameState.recruitment_offers:
		assert_false(all_ids.has(hero.hero_id))
		all_ids[hero.hero_id] = true
	assert_eq(
		JSON.parse_string(FileAccess.get_file_as_string(
			SaveManager.get_save_path() + ".bak")),
		replaced)
	var imported := SaveManager.capture_state()
	SaveManager.import_external_save(source)
	assert_eq(SaveManager.capture_state(), imported)
	GameState.reset()
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success, SaveManager.last_error)
	assert_eq(SaveManager.capture_state(), imported)


func test_existing_private_save_versions_one_through_seven_are_imported() -> void:
	var current := SaveManager.capture_state()
	current.roster[0].hero_name = "Legacy Portable Hero"
	for version in range(1, SaveManager.SAVE_VERSION + 1):
		var path := _path("private-v%d.json" % version)
		_write_json(path, _legacy(current, version))
		GameState.gold = 1
		SaveManager.save()
		assert_true(SaveManager.last_committed)
		SaveManager.import_external_save(path)
		assert_true(SaveManager.last_committed, "v%d: %s" % [version, SaveManager.last_error])
		assert_eq(GameState.roster[0].hero_name, "Legacy Portable Hero", str(version))
		assert_null(GameState.current_party)
		assert_null(ExpeditionManager.get_active_expedition())


func test_optional_extensions_and_forward_compatibility_do_not_mutate_input() -> void:
	var document := _portable()
	document.schema_version = 2
	document.minimum_reader_version = 1
	document.extensions = {"example.org:note": {"enabled": true, "labels": ["one", "two"]}}
	var original := document.duplicate(true)
	var decoded := ExternalSaveCodec.decode(document, SaveManager.MAX_INVENTORY_ITEMS)
	assert_false(decoded.has("error"), decoded.get("error", ""))
	assert_eq(document, original)
	assert_eq(decoded.document.extensions, original.extensions)
	assert_eq(decoded.warnings.size(), 2)
	var path := _path("forward.json")
	_write_json(path, document)
	SaveManager.import_external_save(path)
	assert_true(SaveManager.last_committed, SaveManager.last_error)
	assert_string_contains(SaveManager.last_warning, "forward-compatible")
	assert_string_contains(SaveManager.last_warning, "example.org:note")
	var before := SaveManager.capture_state()
	var disk := FileAccess.get_file_as_string(SaveManager.get_save_path())
	document.minimum_reader_version = 2
	_write_json(path, document)
	SaveManager.import_external_save(path)
	assert_false(SaveManager.last_committed)
	assert_string_contains(SaveManager.last_error, "requires reader")
	assert_eq(SaveManager.capture_state(), before)
	assert_eq(FileAccess.get_file_as_string(SaveManager.get_save_path()), disk)


func test_external_validation_rejects_types_ids_content_and_limits() -> void:
	var original := _portable()
	var invalid_documents: Array = []
	var invalid := original.duplicate(true)
	invalid.payload.gold = 1.5
	invalid_documents.append(invalid)
	invalid = original.duplicate(true)
	invalid.payload.heroes.append(invalid.payload.heroes[0].duplicate(true))
	invalid_documents.append(invalid)
	invalid = original.duplicate(true)
	invalid.payload.heroes[0].hero_id = "hero-0"
	invalid_documents.append(invalid)
	invalid = original.duplicate(true)
	invalid.payload.heroes[0].class_id = "missing"
	invalid_documents.append(invalid)
	invalid = original.duplicate(true)
	invalid.payload.heroes[0].equipped_weapon = "robes"
	invalid_documents.append(invalid)
	invalid = original.duplicate(true)
	invalid.payload.items = ["missing"]
	invalid_documents.append(invalid)
	invalid = original.duplicate(true)
	invalid.payload.items.resize(SaveManager.MAX_INVENTORY_ITEMS + 1)
	invalid.payload.items.fill("short_sword")
	invalid_documents.append(invalid)
	invalid = original.duplicate(true)
	invalid.payload.opened_stages = ["green_hollow", "green_hollow"]
	invalid_documents.append(invalid)
	invalid = original.duplicate(true)
	invalid.payload.opened_stages = ["unknown"]
	invalid_documents.append(invalid)
	invalid = original.duplicate(true)
	invalid.extensions = {"not-namespaced": true}
	invalid_documents.append(invalid)
	invalid = original.duplicate(true)
	invalid.extensions = {"example.org:value": INF}
	invalid_documents.append(invalid)
	for document in invalid_documents:
		var decoded := ExternalSaveCodec.decode(
			document, SaveManager.MAX_INVENTORY_ITEMS)
		assert_true(decoded.has("error"), str(document))
	var exhausted := original.duplicate(true)
	exhausted.payload.heroes[0].hero_id = "hero-%d" % HeroCatalog.MAX_SAFE_INT
	var rebuilt := ExternalSaveCodec.build_internal(
		exhausted, SaveManager.SAVE_VERSION, SaveManager.MAX_INVENTORY_ITEMS,
		ExpeditionManager.balancing)
	assert_true(rebuilt.has("error"))
	assert_string_contains(rebuilt.error, "no room")


func test_malformed_oversized_and_invalid_imports_never_mutate_company_or_disk() -> void:
	var before := SaveManager.capture_state()
	var disk := FileAccess.get_file_as_string(SaveManager.get_save_path())
	var malformed := _path("malformed.json")
	_write_text(malformed, "{broken")
	SaveManager.import_external_save(malformed)
	assert_false(SaveManager.last_committed)
	assert_string_contains(SaveManager.last_error, "valid JSON")
	assert_eq(SaveManager.capture_state(), before)
	assert_eq(FileAccess.get_file_as_string(SaveManager.get_save_path()), disk)
	var oversized := _path("oversized.json")
	_write_text(oversized, " ".repeat(SaveManager.MAX_SAVE_BYTES + 1))
	SaveManager.import_external_save(oversized)
	assert_false(SaveManager.last_committed)
	assert_string_contains(SaveManager.last_error, "exceeds")
	assert_eq(SaveManager.capture_state(), before)
	assert_eq(FileAccess.get_file_as_string(SaveManager.get_save_path()), disk)
	var invalid := _portable()
	invalid.payload.heroes[0].trait_ids = ["missing"]
	var invalid_path := _path("invalid.json")
	_write_json(invalid_path, invalid)
	SaveManager.import_external_save(invalid_path)
	assert_false(SaveManager.last_committed)
	assert_eq(SaveManager.capture_state(), before)
	assert_eq(FileAccess.get_file_as_string(SaveManager.get_save_path()), disk)


func test_every_precommit_import_failure_preserves_live_and_primary_state() -> void:
	GameState.gold = 111
	var path := _path("import.json")
	_portable(path)
	GameState.gold = 222
	SaveManager.save()
	assert_true(SaveManager.last_committed)
	var before := SaveManager.capture_state()
	for stage in PRECOMMIT_STAGES:
		var disk := FileAccess.get_file_as_string(SaveManager.get_save_path())
		SaveManager.fault_injector = (
			func(boundary: String) -> bool: return boundary == stage)
		SaveManager.import_external_save(path)
		assert_false(SaveManager.last_committed, stage)
		assert_eq(SaveManager.capture_state(), before, stage)
		assert_eq(FileAccess.get_file_as_string(SaveManager.get_save_path()), disk, stage)
	SaveManager.fault_injector = Callable()


func test_postcommit_import_warning_applies_state_and_restart_uses_it() -> void:
	GameState.gold = 111
	var path := _path("import.json")
	_portable(path)
	GameState.gold = 222
	SaveManager.save()
	SaveManager.fault_injector = (
		func(stage: String) -> bool: return stage == "after_primary_replace")
	SaveManager.import_external_save(path)
	assert_true(SaveManager.last_committed)
	assert_true(SaveManager.last_success)
	assert_eq(GameState.gold, 111)
	assert_string_contains(SaveManager.last_warning, "committed")
	assert_string_contains(SaveManager.last_warning, "not imported")
	SaveManager.fault_injector = Callable()
	var expected := SaveManager.capture_state()
	GameState.reset()
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), expected)


func test_export_protects_private_files_and_preserves_existing_destination_on_failure() -> void:
	var primary := FileAccess.get_file_as_string(SaveManager.get_save_path())
	for path in [
			SaveManager.get_save_path(), SaveManager.get_save_path() + ".bak",
			SaveManager.get_save_path() + ".tmp",
			SaveManager.get_save_path() + ".bak.tmp",
	]:
		SaveManager.export_external_save(path)
		assert_false(SaveManager.last_success)
		assert_string_contains(SaveManager.last_error, "outside")
	assert_eq(FileAccess.get_file_as_string(SaveManager.get_save_path()), primary)
	var destination := _path("existing.json")
	_write_text(destination, "old portable data")
	assert_eq(DirAccess.make_dir_absolute(destination + ".tmp"), OK)
	SaveManager.export_external_save(destination)
	assert_false(SaveManager.last_success)
	assert_eq(_read_text(destination), "old portable data")
