class_name ExternalSaveCodec
extends RefCounted
## Pure portable-save projection, validation, migration, and reconstruction.

const FORMAT_ID := "adventurers-march-portable-save"
const SCHEMA_VERSION := 1
const MINIMUM_READER_VERSION := 1
const MAX_COLLECTION_ENTRIES := 1024
const MAX_EXTENSION_DEPTH := 16
const ROOT_KEYS := [
	"format", "schema_version", "minimum_reader_version", "payload", "extensions",
]
const PAYLOAD_KEYS := ["heroes", "items", "gold", "opened_stages"]
const HERO_KEYS := [
	"hero_id", "hero_name", "class_id", "level", "xp", "attributes", "trait_ids",
	"status", "recovery_ready_at", "equipped_weapon", "equipped_armor",
]
const TRANSIENT_STATUSES := ["ASSIGNED", "ON_EXPEDITION"]


static func encode(snapshot: Variant, maximum_items: int) -> Dictionary:
	if not snapshot is Dictionary:
		return _failure("Company data is not a dictionary.")
	for key in ["roster", "inventory", "gold", "unlocked_regions"]:
		if not snapshot.has(key):
			return _failure("Company data is missing %s." % key)
	if not snapshot.roster is Array or not snapshot.inventory is Array \
			or not snapshot.unlocked_regions is Array:
		return _failure("Company collections are malformed.")
	var heroes: Array = []
	for value in snapshot.roster:
		var hero := _canonical_hero(value)
		if hero.is_empty():
			return _failure("A Hero could not be exported.")
		heroes.append(hero)
	heroes.sort_custom(_hero_before)
	var items: Array = []
	for value in snapshot.inventory:
		items.append(String(value))
	items.sort()
	var stages: Array = []
	for value in snapshot.unlocked_regions:
		stages.append(String(value))
	stages.sort()
	var document := {
		"format": FORMAT_ID,
		"schema_version": SCHEMA_VERSION,
		"minimum_reader_version": MINIMUM_READER_VERSION,
		"payload": {
			"heroes": heroes,
			"items": items,
			"gold": snapshot.gold,
			"opened_stages": stages,
		},
		"extensions": {},
	}
	var decoded := decode(document, maximum_items)
	if decoded.has("error"):
		return decoded
	return {"document": decoded.document}


static func decode(data: Variant, maximum_items: int) -> Dictionary:
	if maximum_items < 0:
		return _failure("Portable item capacity is invalid.")
	if not data is Dictionary or not HeroCatalog.has_exact_keys(data, ROOT_KEYS):
		return _failure("Portable save envelope is malformed.")
	if data.format != FORMAT_ID:
		return _failure("This is not an Adventurer's March portable save.")
	if not _integer(data.schema_version, 1) or not _integer(data.minimum_reader_version, 1):
		return _failure("Portable save version fields are invalid.")
	var source_version := int(data.schema_version)
	var minimum_reader := int(data.minimum_reader_version)
	if minimum_reader > source_version:
		return _failure("Portable save reader requirements are invalid.")
	if minimum_reader > SCHEMA_VERSION:
		return _failure(
			"Portable save schema %d requires reader version %d." % [
				source_version, minimum_reader])
	if source_version < 1:
		return _failure("Portable save schema %d is unsupported." % source_version)
	if source_version == 1 and minimum_reader != 1:
		return _failure("Portable save schema 1 has an invalid reader requirement.")
	if not _validate_v1(data, maximum_items):
		return _failure("Portable save data failed schema validation.")
	var warnings: Array[String] = []
	if source_version > SCHEMA_VERSION:
		warnings.append(
			"Imported forward-compatible portable schema %d as schema %d." % [
				source_version, SCHEMA_VERSION])
	var extension_names: Array = data.extensions.keys()
	extension_names.sort()
	if not extension_names.is_empty():
		warnings.append("Ignored optional extensions: %s." % ", ".join(extension_names))
	var document := _canonical_document(data)
	return {"document": document, "warnings": warnings}


static func build_internal(
		document: Variant, internal_version: int, maximum_items: int,
		balancing: BalancingConfig
) -> Dictionary:
	var decoded := decode(document, maximum_items)
	if decoded.has("error"):
		return decoded
	if internal_version < 1 or balancing == null:
		return _failure("Current save configuration is unavailable.")
	var payload: Dictionary = decoded.document.payload
	var heroes: Array = payload.heroes.duplicate(true)
	var maximum_hero_number := 0
	for hero in heroes:
		maximum_hero_number = maxi(maximum_hero_number, _hero_number(hero.hero_id))
	if maximum_hero_number > (
			HeroCatalog.MAX_SAFE_INT - RecruitmentService.OFFER_COUNT - 1):
		return _failure("Hero IDs leave no room to reconstruct recruitment offers.")
	var offer_ids: Array[String] = []
	for offset in RecruitmentService.OFFER_COUNT:
		offer_ids.append("hero-%d" % (maximum_hero_number + offset + 1))
	var recruitment_seed := _derived_seed(payload, "recruitment")
	var expedition_seed := _derived_seed(payload, "expedition")
	var generated := RecruitmentService.generate_offers(
		recruitment_seed, offer_ids, HeroCatalog.classes(), HeroCatalog.traits())
	if generated.size() != RecruitmentService.OFFER_COUNT:
		return _failure("Recruitment offers could not be reconstructed.")
	var offers: Array = []
	var offer_seeds: Array = []
	for index in generated.size():
		offers.append(_serialize_generated_hero(generated[index]))
		offer_seeds.append(RecruitmentService.seed_at(recruitment_seed, index))
	var starting_capacity := maxi(12, heroes.size())
	var progression := CompanyProgression.preview(
		int(payload.gold), payload.opened_stages, starting_capacity, balancing)
	if progression.has("error"):
		return _failure("Company progression could not be reconstructed.")
	var regions: Array = []
	for id in progression.unlocked_regions:
		regions.append(String(id))
	return {
		"snapshot": {
			"save_version": internal_version,
			"roster": heroes,
			"recruitment_offers": offers,
			"gold": int(payload.gold),
			"inventory": payload.items.duplicate(),
			"unlocked_regions": regions,
			"roster_capacity": int(progression.roster_capacity),
			"next_hero_id": maximum_hero_number + RecruitmentService.OFFER_COUNT + 1,
			"recruitment_seed": recruitment_seed,
			"recruitment_sequence": RecruitmentService.OFFER_COUNT,
			"offer_seeds": offer_seeds,
			"current_party": null,
			"expedition_seed": expedition_seed,
			"expedition_sequence": 0,
			"expedition": null,
			"expedition_automation": null,
		},
		"warnings": decoded.warnings,
	}


static func _validate_v1(data: Dictionary, maximum_items: int) -> bool:
	if not data.payload is Dictionary or not HeroCatalog.has_exact_keys(
			data.payload, PAYLOAD_KEYS):
		return false
	if not data.extensions is Dictionary or data.extensions.size() > MAX_COLLECTION_ENTRIES:
		return false
	for key in data.extensions:
		if not _extension_name(key) or not _json_safe(data.extensions[key]):
			return false
	var payload: Dictionary = data.payload
	if not _integer(payload.gold):
		return false
	if not payload.items is Array or payload.items.size() > maximum_items:
		return false
	for id in payload.items:
		if not _text(id) or ItemCatalog.item_by_id(id) == null:
			return false
	if not payload.opened_stages is Array \
			or payload.opened_stages.size() > MAX_COLLECTION_ENTRIES:
		return false
	var stages := {}
	for id in payload.opened_stages:
		if not _text(id) or stages.has(id) or ExpeditionCatalog.region_by_id(id) == null:
			return false
		stages[id] = true
	if not payload.heroes is Array \
			or payload.heroes.size() > CompanyProgression.MAX_ROSTER_CAPACITY:
		return false
	var hero_ids := {}
	for hero in payload.heroes:
		if not _validate_hero(hero):
			return false
		if hero_ids.has(hero.hero_id):
			return false
		hero_ids[hero.hero_id] = true
	return true


static func _validate_hero(data: Variant) -> bool:
	if not data is Dictionary or not HeroCatalog.has_exact_keys(data, HERO_KEYS):
		return false
	if not _text(data.hero_id) or _hero_number(data.hero_id) < 1:
		return false
	if not _text(data.hero_name) or not _text(data.class_id) \
			or HeroCatalog.class_by_id(data.class_id) == null:
		return false
	if not _integer(data.level, 1, HeroCatalog.MAX_LEVEL) or not _integer(data.xp):
		return false
	if not data.status is String or data.status not in HeroData.HeroStatus.keys():
		return false
	if not _integer(data.recovery_ready_at):
		return false
	if data.recovery_ready_at > 0 and data.status != "RESTING":
		return false
	for key in ["equipped_weapon", "equipped_armor"]:
		if data[key] == null:
			continue
		if not _text(data[key]):
			return false
		var item := ItemCatalog.item_by_id(data[key])
		if item == null or item.slot != (
				"Weapon" if key == "equipped_weapon" else "Armor"):
			return false
	if not data.attributes is Dictionary or not HeroCatalog.has_exact_keys(
			data.attributes, HeroCatalog.ATTRIBUTES):
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


static func _canonical_document(data: Dictionary) -> Dictionary:
	var heroes: Array = []
	for value in data.payload.heroes:
		heroes.append(_canonical_hero(value))
	heroes.sort_custom(_hero_before)
	var items: Array = []
	for value in data.payload.items:
		items.append(String(value))
	items.sort()
	var stages: Array = []
	for value in data.payload.opened_stages:
		stages.append(String(value))
	stages.sort()
	return {
		"format": FORMAT_ID,
		"schema_version": SCHEMA_VERSION,
		"minimum_reader_version": MINIMUM_READER_VERSION,
		"payload": {
			"heroes": heroes,
			"items": items,
			"gold": int(data.payload.gold),
			"opened_stages": stages,
		},
		"extensions": data.extensions.duplicate(true),
	}


static func _canonical_hero(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var attributes := {}
	var source_attributes: Variant = value.get("attributes")
	if not source_attributes is Dictionary:
		return {}
	for attribute in HeroCatalog.ATTRIBUTES:
		attributes[attribute] = int(source_attributes.get(attribute))
	var traits: Array = []
	var source_traits: Variant = value.get("trait_ids")
	if not source_traits is Array:
		return {}
	for id in source_traits:
		traits.append(String(id))
	traits.sort()
	var status := String(value.get("status", ""))
	var recovery_ready_at: Variant = value.get("recovery_ready_at")
	if status in TRANSIENT_STATUSES:
		status = "IDLE"
		recovery_ready_at = 0
	return {
		"hero_id": String(value.get("hero_id", "")),
		"hero_name": String(value.get("hero_name", "")),
		"class_id": String(value.get("class_id", "")),
		"level": int(value.get("level")),
		"xp": int(value.get("xp")),
		"attributes": attributes,
		"trait_ids": traits,
		"status": status,
		"recovery_ready_at": int(recovery_ready_at),
		"equipped_weapon": value.get("equipped_weapon"),
		"equipped_armor": value.get("equipped_armor"),
	}


static func _serialize_generated_hero(hero: HeroData) -> Dictionary:
	var attributes := {}
	for attribute in HeroCatalog.ATTRIBUTES:
		attributes[attribute] = hero.attributes[attribute]
	var traits: Array = []
	for hero_trait in hero.traits:
		traits.append(String(hero_trait.trait_id))
	traits.sort()
	return {
		"hero_id": hero.hero_id,
		"hero_name": hero.hero_name,
		"class_id": String(hero.hero_class.class_id),
		"level": hero.level,
		"xp": hero.xp,
		"attributes": attributes,
		"trait_ids": traits,
		"status": "IDLE",
		"recovery_ready_at": 0,
		"equipped_weapon": null,
		"equipped_armor": null,
	}


static func _derived_seed(payload: Dictionary, domain: String) -> int:
	var digest := ("%s:%s" % [
		domain, JSON.stringify(payload, "", true, true)]).sha256_text()
	var result := 0
	for character in digest.substr(0, 13):
		var nibble := "0123456789abcdef".find(character)
		if nibble < 0:
			return 0
		result = result * 16 + nibble
	return result


static func _hero_before(left: Dictionary, right: Dictionary) -> bool:
	return _hero_number(left.hero_id) < _hero_number(right.hero_id)


static func _hero_number(id: String) -> int:
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


static func _integer(
		value: Variant, minimum: int = 0, maximum: int = HeroCatalog.MAX_SAFE_INT
) -> bool:
	if value is int:
		return value >= minimum and value <= maximum
	return value is float and is_finite(value) and value >= minimum \
		and value <= maximum and value == floor(value)


static func _text(value: Variant, maximum: int = 128) -> bool:
	return value is String and not value.strip_edges().is_empty() \
		and value.length() <= maximum


static func _extension_name(value: Variant) -> bool:
	if not value is String or value.length() > 128:
		return false
	var name: String = value
	var separator := name.find(":")
	return separator > 0 and separator < name.length() - 1


static func _json_safe(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_EXTENSION_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL:
			return true
		TYPE_INT:
			return value >= -HeroCatalog.MAX_SAFE_INT and value <= HeroCatalog.MAX_SAFE_INT
		TYPE_FLOAT:
			return is_finite(value) and value >= -HeroCatalog.MAX_SAFE_INT \
				and value <= HeroCatalog.MAX_SAFE_INT
		TYPE_STRING:
			return value.length() <= 4096
		TYPE_ARRAY:
			if value.size() > MAX_COLLECTION_ENTRIES:
				return false
			for entry in value:
				if not _json_safe(entry, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			if value.size() > MAX_COLLECTION_ENTRIES:
				return false
			for key in value:
				if not key is String or key.length() > 128 \
						or not _json_safe(value[key], depth + 1):
					return false
			return true
		_:
			return false


static func _failure(message: String) -> Dictionary:
	return {"error": message}
