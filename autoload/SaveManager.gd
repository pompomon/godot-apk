extends Node
## Versioned, validated snapshots and best-effort same-directory replacement.
## No fsync or cross-platform atomicity guarantees are available through these APIs.

const SAVE_VERSION := 5
const MAX_SAVE_BYTES := 1048576
const LEGACY_ROOT_KEYS := [
	"save_version", "roster", "recruitment_offers", "gold", "inventory",
	"unlocked_regions", "roster_capacity", "next_hero_id", "recruitment_seed",
	"recruitment_sequence", "offer_seeds",
]
const V2_ROOT_KEYS := LEGACY_ROOT_KEYS + ["current_party"]
const ROOT_KEYS := V2_ROOT_KEYS + ["expedition_seed", "expedition_sequence", "expedition"]
const LEGACY_HERO_KEYS := [
	"hero_id", "hero_name", "class_id", "level", "xp", "attributes", "trait_ids",
	"status", "equipped_weapon", "equipped_armor",
]
const HERO_KEYS := LEGACY_HERO_KEYS + ["recovery_ready_at"]

## Keep initialization I/O-free so tests can bind isolated storage before bootstrap.
var storage_directory: String = OS.get_user_data_dir()
var last_success: bool = false
var last_committed: bool = false
var last_error: String = ""
var last_warning: String = ""
var new_game_seed_override: int = -1
## Callable(stage: String) -> bool; true simulates an interrupted boundary.
var fault_injector: Callable


func get_save_path() -> String:
	return storage_directory.path_join("save.json")


func load_or_create() -> void:
	_clear_result()
	var primary := _read_validated(get_save_path())
	if not primary.is_empty():
		_apply_validated(primary)
		last_success = true
		ExpeditionManager.reveal_progress()
		return
	var backup := _read_validated(get_save_path() + ".bak")
	if not backup.is_empty():
		_apply_validated(backup)
		_write_snapshot(backup, false)
		var recovery_warning := "Recovered the company from the backup save."
		if not last_success:
			recovery_warning += " Primary restoration failed; the backup remains safe. Retry saving."
		retain_warning(recovery_warning)
		push_warning(last_warning)
		recovery_warning = last_warning
		ExpeditionManager.reveal_progress()
		retain_warning(recovery_warning)
		return
	var had_files := FileAccess.file_exists(get_save_path()) or FileAccess.file_exists(
		get_save_path() + ".bak")
	var seed := new_game_seed_override
	if seed == -1:
		seed = (int(Time.get_unix_time_from_system() * 1000000.0) + Time.get_ticks_usec()
			) % HeroCatalog.MAX_SAFE_INT
	if not RecruitmentService.initialize_new_game(seed):
		last_error = "New company creation failed: invalid content or seed."
		return
	save()
	if had_files:
		last_warning = "Neither primary nor backup was valid. A new company was created."
	if not last_success:
		last_warning += " The new company is not saved yet. Check storage and retry."
	if not last_warning.is_empty():
		push_warning(last_warning)


func save() -> void:
	_clear_result()
	if not GameState.initialized:
		last_error = "Company is not initialized; nothing was saved."
		return
	var snapshot := capture_state()
	if not validate_snapshot(snapshot):
		last_error = "Company data is invalid; the existing save was not replaced."
		return
	_write_snapshot(snapshot, true)


func _clear_result() -> void:
	last_success = false
	last_committed = false
	last_error = ""
	last_warning = ""


## Automatic observations must not erase recovery feedback before it can be read.
func retain_warning(previous: String) -> void:
	var lines := previous.split("\n", false)
	for line in last_warning.split("\n", false):
		if not lines.has(line):
			lines.append(line)
	last_warning = "\n".join(lines)


## Validate the original schema before normalizing; never repair malformed saves.
func migrate(data: Variant) -> Dictionary:
	if not data is Dictionary or not _integer(data.get("save_version"), 1, HeroCatalog.MAX_SAFE_INT):
		return {}
	match int(data.save_version):
		1, 2, 3, 4:
			var version := int(data.save_version)
			var keys := LEGACY_ROOT_KEYS if version == 1 else (V2_ROOT_KEYS if version == 2 else ROOT_KEYS)
			if not _validate_schema(data, version, keys):
				return {}
			if version >= 2 and not _validate_party(data):
				return {}
			if version >= 3 and (not _integer(data.expedition_seed) or not _integer(data.expedition_sequence) or not _validate_expedition_relations(data, version)):
				return {}
			var migrated: Dictionary = data.duplicate(true)
			migrated.save_version = SAVE_VERSION
			if version == 1:
				migrated.current_party = null
			if version < 3:
				migrated.expedition = null
				migrated.expedition_seed = migrated.recruitment_seed
				migrated.expedition_sequence = 0
				for hero in migrated.roster:
					if hero.status == "ON_EXPEDITION" or (version == 1 and hero.status == "ASSIGNED"):
						hero.status = "IDLE"
			elif version == 3 and migrated.expedition != null:
				migrated.expedition.planned_step_count = migrated.expedition.steps.size()
				migrated.expedition.retreat_ends_expedition = false
			if migrated.expedition != null:
				migrated.expedition.xp_award = 0
				migrated.expedition.recovery_seconds = 60
				migrated.expedition.rest_hp_percent = 0
			for hero in migrated.roster + migrated.recruitment_offers:
				if version < 4:
					hero.recovery_ready_at = 0
				elif hero.status == "WOUNDED" and hero.recovery_ready_at > 0:
					hero.status = "RESTING"
			return migrated if validate_snapshot(migrated) else {}
		SAVE_VERSION:
			return data if validate_snapshot(data) else {}
		_:
			return {}


func capture_state() -> Dictionary:
	var heroes: Array = []
	var offers: Array = []
	for hero in GameState.roster:
		heroes.append(_serialize_hero(hero))
	for hero in GameState.recruitment_offers:
		offers.append(_serialize_hero(hero))
	var regions: Array = []
	for id in GameState.unlocked_regions:
		regions.append(String(id))
	var inventory: Array = []
	for item in GameState.inventory:
		inventory.append(_serialize_item(item))
	return {
		"save_version": SAVE_VERSION, "roster": heroes, "recruitment_offers": offers,
		"gold": GameState.gold, "inventory": inventory,
		"unlocked_regions": regions, "roster_capacity": GameState.roster_capacity,
		"next_hero_id": GameState.next_hero_id, "recruitment_seed": GameState.recruitment_seed,
		"recruitment_sequence": GameState.recruitment_sequence,
		"offer_seeds": GameState.offer_seeds.duplicate(),
		"current_party": _serialize_party(GameState.current_party),
		"expedition_seed": GameState.expedition_seed, "expedition_sequence": GameState.expedition_sequence,
		"expedition": ExpeditionManager.serialize(),
	}


func _serialize_party(party: PartyData) -> Variant:
	if party == null:
		return null
	if not party.validation_error(true).is_empty():
		return {}
	var result := {}
	for slot in PartyData.SLOT_ORDER:
		var hero: HeroData = party.slots[slot]
		if hero != null and GameState.find_hero(hero.hero_id) != hero:
			return {}
		result[PartyData.SLOT_NAMES[slot]] = hero.hero_id if hero != null else null
	return result


func _serialize_item(item: ItemResource) -> Variant:
	if item == null:
		return null
	return String(item.item_id) if ItemCatalog.item_by_id(String(item.item_id)) == item else ""


func _serialize_hero(hero: HeroData) -> Dictionary:
	if hero == null or hero.hero_class == null:
		return {}
	var traits: Array = []
	for hero_trait in hero.traits:
		if hero_trait == null:
			return {}
		traits.append(String(hero_trait.trait_id))
	var statuses := HeroData.HeroStatus.keys()
	if hero.status < 0 or hero.status >= statuses.size():
		return {}
	return {
		"hero_id": hero.hero_id, "hero_name": hero.hero_name,
		"class_id": String(hero.hero_class.class_id), "level": hero.level, "xp": hero.xp,
		"attributes": hero.attributes.duplicate(), "trait_ids": traits,
		"status": statuses[hero.status],
		"recovery_ready_at": hero.recovery_ready_at,
		"equipped_weapon": _serialize_item(hero.equipped_weapon),
		"equipped_armor": _serialize_item(hero.equipped_armor),
	}


func validate_snapshot(data: Variant) -> bool:
	if not _validate_schema(data, SAVE_VERSION, ROOT_KEYS):
		return false
	if not _integer(data.expedition_seed) or not _integer(data.expedition_sequence) or not _validate_party(data):
		return false
	return _validate_expedition_relations(data)


func _validate_expedition_relations(data: Dictionary, version: int = SAVE_VERSION) -> bool:
	var participants := {}
	var running := false
	if data.expedition != null:
		var valid_run := ExpeditionData.valid(data.expedition) if version == SAVE_VERSION else (
			ExpeditionData.valid_legacy(data.expedition) if version == 3 else ExpeditionData.valid_version_four(data.expedition))
		if not valid_run:
			return false
		running = int(data.expedition.status) == ExpeditionData.Status.RUNNING
		if running and data.current_party != null:
			return false
		var roster_by_id := {}
		for hero in data.roster:
			roster_by_id[hero.hero_id] = hero
		for member in data.expedition.party_snapshot.values():
			if member == null:
				continue
			if not roster_by_id.has(member.hero_id):
				return false
			participants[member.hero_id] = true
			if running and roster_by_id[member.hero_id].status != "ON_EXPEDITION":
				return false
	for hero in data.roster:
		if hero.status == "ON_EXPEDITION" and (not running or not participants.has(hero.hero_id)):
			return false
	return true


func _validate_schema(data: Variant, version: int, keys: Array) -> bool:
	if not data is Dictionary or not HeroCatalog.has_exact_keys(data, keys):
		return false
	if not _integer(data.save_version, version, version):
		return false
	if not HeroCatalog.validate_catalog(HeroCatalog.classes(), HeroCatalog.traits()):
		return false
	if not _integer(data.gold) or not _integer(data.roster_capacity, 1, 12):
		return false
	if not _integer(data.next_hero_id, 1) or not _integer(data.recruitment_seed):
		return false
	if not _integer(data.recruitment_sequence):
		return false
	if not data.inventory is Array:
		return false
	if version < 5 and not data.inventory.is_empty():
		return false
	if version >= 5:
		if not ItemCatalog.validate_catalog():
			return false
		for id in data.inventory:
			if not _text(id) or ItemCatalog.item_by_id(id) == null:
				return false
	if not data.unlocked_regions is Array or data.unlocked_regions.size() > 1024:
		return false
	var regions := {}
	for id in data.unlocked_regions:
		if not _text(id) or regions.has(id):
			return false
		regions[id] = true
	if not data.roster is Array or data.roster.size() > int(data.roster_capacity):
		return false
	if not data.recruitment_offers is Array or data.recruitment_offers.size() != RecruitmentService.OFFER_COUNT:
		return false
	if not data.offer_seeds is Array or data.offer_seeds.size() != RecruitmentService.OFFER_COUNT:
		return false
	for seed in data.offer_seeds:
		if not _integer(seed):
			return false
	var ids := {}
	for hero in data.roster + data.recruitment_offers:
		if not _validate_hero(hero, version):
			return false
		var number := _hero_number(hero.hero_id)
		if number < 1 or number >= int(data.next_hero_id) or ids.has(hero.hero_id):
			return false
		ids[hero.hero_id] = true
	for hero in data.recruitment_offers:
		if hero.status != "IDLE" or hero.equipped_weapon != null or hero.equipped_armor != null:
			return false
	return true


func _validate_party(data: Dictionary) -> bool:
	var members := {}
	var roster_by_id := {}
	for hero in data.roster:
		roster_by_id[hero.hero_id] = hero
	if data.current_party != null:
		if not data.current_party is Dictionary or not HeroCatalog.has_exact_keys(
				data.current_party, PartyData.SLOT_NAMES):
			return false
		for slot in PartyData.SLOT_NAMES:
			var id: Variant = data.current_party[slot]
			if id == null:
				continue
			if not id is String or not roster_by_id.has(id) or members.has(id):
				return false
			if roster_by_id[id].status != "ASSIGNED":
				return false
			members[id] = true
		if members.is_empty():
			return false
	for hero in data.roster:
		if hero.status == "ASSIGNED" and not members.has(hero.hero_id):
			return false
	return true


func _validate_hero(data: Variant, version: int = SAVE_VERSION) -> bool:
	if not data is Dictionary or not HeroCatalog.has_exact_keys(data, HERO_KEYS if version >= 4 else LEGACY_HERO_KEYS):
		return false
	if not _text(data.hero_id) or not _text(data.hero_name) or not _text(data.class_id):
		return false
	var hero_class := HeroCatalog.class_by_id(data.class_id)
	if hero_class == null:
		return false
	if not _integer(data.level, 1, HeroCatalog.MAX_LEVEL) or not _integer(data.xp):
		return false
	if not data.status is String or data.status not in HeroData.HeroStatus.keys():
		return false
	if version >= 4:
		if not _integer(data.recovery_ready_at) or (data.recovery_ready_at > 0 and data.status != ("RESTING" if version >= 5 else "WOUNDED")):
			return false
	for key in ["equipped_weapon", "equipped_armor"]:
		if data[key] == null:
			continue
		if version < 5 or not _text(data[key]):
			return false
		var item := ItemCatalog.item_by_id(data[key])
		if item == null or item.slot != ("Weapon" if key == "equipped_weapon" else "Armor"):
			return false
	if not data.attributes is Dictionary or not HeroCatalog.has_exact_keys(data.attributes, HeroCatalog.ATTRIBUTES):
		return false
	for attribute in HeroCatalog.ATTRIBUTES:
		if not _integer(data.attributes[attribute], 0, HeroCatalog.MAX_ATTRIBUTE):
			return false
	if not data.trait_ids is Array or data.trait_ids.size() > 1:
		return false
	for id in data.trait_ids:
		if not _text(id) or HeroCatalog.trait_by_id(id) == null:
			return false
	return true


func _integer(value: Variant, minimum: int = 0, maximum: int = HeroCatalog.MAX_SAFE_INT) -> bool:
	if value is int:
		return value >= minimum and value <= maximum
	if value is float:
		return is_finite(value) and value >= minimum and value <= maximum and value == floor(value)
	return false


func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= 128


func _hero_number(id: String) -> int:
	if not id.begins_with("hero-"):
		return -1
	var suffix := id.trim_prefix("hero-")
	if suffix.is_empty() or suffix.length() > 16:
		return -1
	for character in suffix:
		if character < "0" or character > "9":
			return -1
	var number := suffix.to_int()
	if number < 1 or number > HeroCatalog.MAX_SAFE_INT or id != "hero-%d" % number:
		return -1
	return number


func _apply_validated(data: Dictionary) -> void:
	var roster: Array[HeroData] = []
	var offers: Array[HeroData] = []
	for hero in data.roster:
		roster.append(_deserialize_hero(hero))
	for hero in data.recruitment_offers:
		offers.append(_deserialize_hero(hero))
	GameState.roster = roster
	GameState.recruitment_offers = offers
	GameState.current_party = null
	if data.current_party != null:
		GameState.current_party = PartyData.new()
		for slot in PartyData.SLOT_ORDER:
			var id: Variant = data.current_party[PartyData.SLOT_NAMES[slot]]
			if id != null:
				GameState.current_party.slots[slot] = GameState.find_hero(id)
	GameState.gold = int(data.gold)
	GameState.roster_capacity = int(data.roster_capacity)
	GameState.next_hero_id = int(data.next_hero_id)
	GameState.recruitment_seed = int(data.recruitment_seed)
	GameState.recruitment_sequence = int(data.recruitment_sequence)
	GameState.expedition_seed = int(data.expedition_seed)
	GameState.expedition_sequence = int(data.expedition_sequence)
	ExpeditionManager.replace_from_save(data.expedition)
	GameState.offer_seeds.clear()
	for seed in data.offer_seeds:
		GameState.offer_seeds.append(int(seed))
	GameState.unlocked_regions.clear()
	for id in data.unlocked_regions:
		GameState.unlocked_regions.append(StringName(id))
	GameState.inventory.clear()
	for id in data.inventory:
		GameState.inventory.append(ItemCatalog.item_by_id(id))
	GameState.initialized = true


func _deserialize_hero(data: Dictionary) -> HeroData:
	var hero := HeroData.new(data.hero_id)
	hero.hero_name = data.hero_name
	hero.hero_class = HeroCatalog.class_by_id(data.class_id)
	hero.level = int(data.level)
	hero.xp = int(data.xp)
	for attribute in HeroCatalog.ATTRIBUTES:
		hero.attributes[attribute] = int(data.attributes[attribute])
	for id in data.trait_ids:
		hero.traits.append(HeroCatalog.trait_by_id(id))
	hero.status = HeroData.HeroStatus.keys().find(data.status) as HeroData.HeroStatus
	hero.recovery_ready_at = int(data.recovery_ready_at)
	hero.equipped_weapon = ItemCatalog.item_by_id(data.equipped_weapon) if data.equipped_weapon != null else null
	hero.equipped_armor = ItemCatalog.item_by_id(data.equipped_armor) if data.equipped_armor != null else null
	return hero


func _read_validated(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	if file.get_length() > MAX_SAVE_BYTES:
		file.close()
		return {}
	var text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		return {}
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {}
	var data := migrate(parser.data)
	return data if validate_snapshot(data) else {}


func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		last_error = "Cannot open save file (%s). Check device storage and retry." % error_string(
			FileAccess.get_open_error())
		return false
	file.store_string(text)
	var write_error := file.get_error()
	file.flush()
	var flush_error := file.get_error()
	file.close()
	if write_error != OK or flush_error != OK:
		last_error = "Could not write and flush the save. Check device storage and retry."
		return false
	return true


func _copy_validated_primary(primary: String, backup_temp: String) -> bool:
	var file := FileAccess.open(primary, FileAccess.READ)
	if file == null:
		last_error = "Could not read the previous save for backup; retry saving."
		return false
	var text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		last_error = "Could not read the previous save for backup; retry saving."
		return false
	if not _write_text(backup_temp, text):
		return false
	if _read_validated(backup_temp).is_empty():
		last_error = "Backup validation failed; the primary save was not replaced."
		return false
	return true


func _interrupted(stage: String) -> bool:
	if fault_injector.is_valid() and fault_injector.call(stage):
		last_error = "Save interrupted at %s; retry saving." % stage
		return true
	return false


func _write_snapshot(snapshot: Dictionary, preserve_primary: bool) -> void:
	var mkdir_error := DirAccess.make_dir_recursive_absolute(storage_directory)
	if mkdir_error != OK:
		last_error = "Cannot create save storage (%s). Check storage and retry." % error_string(mkdir_error)
		return
	var primary := get_save_path()
	var temp := primary + ".tmp"
	var backup := primary + ".bak"
	var backup_temp := primary + ".bak.tmp"
	if _interrupted("before_temp_write"):
		return
	var text := JSON.stringify(snapshot, "\t", true, true)
	if text.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		last_error = "Save exceeds the supported size; the existing save was not replaced."
		return
	if not _write_text(temp, text):
		return
	if _read_validated(temp).is_empty():
		last_error = "Temporary save validation failed; the primary was not replaced."
		return
	if _interrupted("after_temp_validation"):
		return
	if preserve_primary and not _read_validated(primary).is_empty():
		if not _copy_validated_primary(primary, backup_temp):
			return
		if _interrupted("after_backup_preparation"):
			return
		var backup_error := DirAccess.rename_absolute(backup_temp, backup)
		if backup_error != OK:
			last_error = "Could not replace the backup (%s); retry saving." % error_string(backup_error)
			return
		if _interrupted("after_backup_replace"):
			return
	if _interrupted("before_primary_replace"):
		return
	var replace_error := DirAccess.rename_absolute(temp, primary)
	if replace_error != OK:
		last_error = "Could not replace the save (%s); retry saving." % error_string(replace_error)
		return
	# The new primary is committed. Later diagnostics must not undo purchases.
	last_committed = true
	last_success = true
	if _interrupted("after_primary_replace"):
		last_warning = "The save was committed, but a later save step was interrupted."
		last_error = ""
