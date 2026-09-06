class_name ExpeditionPartySnapshot
extends RefCounted
## No live Hero/Resource references. Combat can read frozen stats and targeting by ID.

const LEGACY_MEMBER_KEYS := ["hero_id", "hero_name", "class_id", "class_name", "level",
	"attributes", "derived_stats", "basic_attack_target_rule"]
const MEMBER_KEYS := LEGACY_MEMBER_KEYS + ["skill"]
const SKILL_KEYS := ["skill_id", "display_name", "kind", "target_rule", "multiplier_id", "cooldown"]
var _slots: Dictionary
var slots: Dictionary:
	get:
		return _slots.duplicate(true)


func _init(data: Dictionary = {}) -> void:
	_slots = data.duplicate(true)
	for member in _slots.values():
		if member != null:
			for key in ["Evasion", "CritChance"]:
				var value: Variant = member.derived_stats[key]
				if value is String:
					member.derived_stats[key] = value.hex_decode().decode_double(0)


func serialize() -> Dictionary:
	var data := _slots.duplicate(true)
	for member in data.values():
		if member != null:
			for key in ["Evasion", "CritChance"]:
				# Godot's JSON decimal parser can round a double by one ULP.
				# Preserve the exact frozen HeroStats value as eight allowlisted bytes.
				member.derived_stats[key] = PackedFloat64Array([float(member.derived_stats[key])]).to_byte_array().hex_encode()
	return data


static func capture(party: PartyData) -> ExpeditionPartySnapshot:
	if party == null or not party.validation_error(true).is_empty():
		return null
	var data := {}
	for slot in PartyData.SLOT_ORDER:
		var hero: HeroData = party.slots[slot]
		var member: Variant = null
		if hero != null:
			var stats := HeroStats.compute_derived_stats(hero)
			var attributes := HeroStats.effective_attributes(hero)
			var skill := _capture_skill(hero.hero_class)
			if stats.is_empty() or attributes.is_empty() or skill.is_empty():
				return null
			member = {
				"hero_id": hero.hero_id, "hero_name": hero.hero_name,
				"class_id": String(hero.hero_class.class_id), "class_name": hero.hero_class.display_name,
				"level": hero.level, "attributes": attributes, "derived_stats": stats,
				"basic_attack_target_rule": hero.hero_class.basic_attack_target_rule, "skill": skill,
			}
		data[PartyData.SLOT_NAMES[slot]] = member
	return ExpeditionPartySnapshot.new(data) if valid(data) else null


static func _capture_skill(hero_class: HeroClassResource) -> Dictionary:
	var skill := CombatCatalog.skill_by_id(String(hero_class.skill_id))
	if skill == null or not CombatCatalog.validate_skill(skill) or String(skill.class_id) != String(hero_class.class_id):
		return {}
	return {
		"skill_id": String(skill.skill_id), "display_name": skill.display_name, "kind": skill.kind,
		"target_rule": skill.target_rule, "multiplier_id": String(skill.multiplier_id), "cooldown": skill.cooldown,
	}


func hero_states() -> Dictionary:
	var result := {}
	for member in _slots.values():
		if member != null:
			result[member.hero_id] = {"hp": int(member.derived_stats.MaxHP), "status": HeroData.HeroStatus.ON_EXPEDITION}
	return result


static func valid(data: Variant) -> bool:
	return _valid(data, MEMBER_KEYS, true)


## The Milestone 4 (v3) snapshot has no frozen skill; used only during migration.
static func valid_legacy(data: Variant) -> bool:
	return _valid(data, LEGACY_MEMBER_KEYS, false)


static func _valid(data: Variant, member_keys: Array, require_skill: bool) -> bool:
	if not data is Dictionary or not HeroCatalog.has_exact_keys(data, PartyData.SLOT_NAMES):
		return false
	var ids := {}
	for member in data.values():
		if member == null:
			continue
		if not member is Dictionary or not HeroCatalog.has_exact_keys(member, member_keys):
			return false
		for key in ["hero_id", "hero_name", "class_id", "class_name"]:
			if not ExpeditionCatalog.text(member[key]):
				return false
		if ids.has(member.hero_id) or HeroCatalog.class_by_id(member.class_id) == null:
			return false
		ids[member.hero_id] = true
		if not ExpeditionCatalog.integer(member.level, 1, HeroCatalog.MAX_LEVEL) or member.basic_attack_target_rule not in ["FrontRowFirst", "AnySlot"]:
			return false
		if require_skill and not _valid_skill(member.skill):
			return false
		if not member.attributes is Dictionary or not HeroCatalog.has_exact_keys(member.attributes, HeroCatalog.ATTRIBUTES):
			return false
		for value in member.attributes.values():
			if not ExpeditionCatalog.integer(value):
				return false
		if not member.derived_stats is Dictionary or not HeroCatalog.has_exact_keys(member.derived_stats, HeroCatalog.STATS):
			return false
		for key in HeroCatalog.STATS:
			var value: Variant = member.derived_stats[key]
			if key in ["Evasion", "CritChance"]:
				if value is String:
					if value.length() != 16:
						return false
					for character in value:
						if character not in "0123456789abcdef":
							return false
					value = value.hex_decode().decode_double(0)
				if not ExpeditionCatalog.weight(value) or value > 1:
					return false
			elif not ExpeditionCatalog.integer(value, 1 if key == "MaxHP" else 0):
				return false
	return not ids.is_empty()


## Structural validation only: a frozen record survives later combat tuning and a
## legacy noncombat run may carry null. No lookup against today's skill registry.
static func _valid_skill(skill: Variant) -> bool:
	if skill == null:
		return true
	if not skill is Dictionary or not HeroCatalog.has_exact_keys(skill, SKILL_KEYS):
		return false
	for key in ["skill_id", "display_name", "multiplier_id"]:
		if not ExpeditionCatalog.text(skill[key]):
			return false
	if skill.kind not in SkillResource.KINDS or skill.target_rule not in SkillResource.TARGET_RULES:
		return false
	return ExpeditionCatalog.integer(skill.cooldown, 0, CombatCatalog.MAX_COOLDOWN)
