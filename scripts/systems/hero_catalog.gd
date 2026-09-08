class_name HeroCatalog
extends RefCounted
## Explicit, ordered content allowlist; IDs never resolve to caller-provided paths.

const ATTRIBUTES = ["MIG", "FOC", "GRT", "GUI", "FTH"]
const STATS = ["MaxHP", "Attack", "MagicPower", "Defense", "Evasion", "Initiative", "CritChance"]
const MAX_SAFE_INT = 9007199254740991
const MAX_LEVEL = 1000000
const MAX_ATTRIBUTE = 1000000

const KNIGHT = preload("res://data/classes/knight.tres")
const RANGER = preload("res://data/classes/ranger.tres")
const WIZARD = preload("res://data/classes/wizard.tres")
const CLERIC = preload("res://data/classes/cleric.tres")
const HEARTY = preload("res://data/traits/hearty.tres")
const KEEN_EYED = preload("res://data/traits/keen_eyed.tres")
const LIGHTFOOTED = preload("res://data/traits/lightfooted.tres")
const STUDIOUS = preload("res://data/traits/studious.tres")
const IRONHIDE = preload("res://data/traits/ironhide.tres")
const FIERCE = preload("res://data/traits/fierce.tres")
const FOCUSED = preload("res://data/traits/focused.tres")
const ALERT = preload("res://data/traits/alert.tres")


static func classes() -> Array[HeroClassResource]:
	return [KNIGHT, RANGER, WIZARD, CLERIC]


static func traits() -> Array[HeroTraitResource]:
	return [HEARTY, KEEN_EYED, LIGHTFOOTED, STUDIOUS, IRONHIDE, FIERCE, FOCUSED, ALERT]


static func class_by_id(id: String) -> HeroClassResource:
	for resource in classes():
		if String(resource.class_id) == id:
			return resource
	return null


static func trait_by_id(id: String) -> HeroTraitResource:
	for resource in traits():
		if String(resource.trait_id) == id:
			return resource
	return null


static func validate_class(resource: HeroClassResource) -> bool:
	if resource == null or String(resource.class_id).strip_edges().is_empty():
		return false
	if resource.display_name.strip_edges().is_empty():
		return false
	if resource.basic_attack_target_rule not in ["FrontRowFirst", "AnySlot"]:
		return false
	if not has_exact_keys(resource.base_attribute_ranges, ATTRIBUTES):
		return false
	if not has_exact_keys(resource.per_level_growth, ATTRIBUTES):
		return false
	if not has_exact_keys(resource.derived_stat_bases, STATS):
		return false
	if not has_exact_keys(resource.derived_stat_attribute_weights, STATS):
		return false
	for attribute in ATTRIBUTES:
		var bounds: Variant = resource.base_attribute_ranges[attribute]
		if not bounds is Vector2i:
			return false
		if bounds.x < 0 or bounds.y < bounds.x or bounds.y > MAX_ATTRIBUTE:
			return false
		if not is_bounded_number(resource.per_level_growth[attribute], 0.0, MAX_ATTRIBUTE):
			return false
	for stat in STATS:
		if not is_bounded_number(resource.derived_stat_bases[stat]):
			return false
		var weights: Variant = resource.derived_stat_attribute_weights[stat]
		if not weights is Dictionary or not has_exact_keys(weights, ATTRIBUTES):
			return false
		for attribute in ATTRIBUTES:
			if not is_bounded_number(weights[attribute]):
				return false
	return true


static func validate_trait(resource: HeroTraitResource) -> bool:
	if resource == null or String(resource.trait_id).strip_edges().is_empty():
		return false
	if resource.display_name.strip_edges().is_empty() or resource.description.strip_edges().is_empty():
		return false
	for stat in resource.stat_modifiers:
		if not is_content_key(stat, STATS) or not is_bounded_number(resource.stat_modifiers[stat]):
			return false
	# No flag has gameplay semantics in the roster milestone.
	return resource.flags.is_empty()


static func validate_catalog(
		class_pool: Array[HeroClassResource], trait_pool: Array[HeroTraitResource]) -> bool:
	if class_pool.is_empty():
		return false
	var class_ids := {}
	for resource in class_pool:
		if not validate_class(resource) or class_ids.has(resource.class_id):
			return false
		class_ids[resource.class_id] = true
	var trait_ids := {}
	for resource in trait_pool:
		if not validate_trait(resource) or trait_ids.has(resource.trait_id):
			return false
		trait_ids[resource.trait_id] = true
	return true


static func has_exact_keys(values: Dictionary, keys: Array) -> bool:
	if values.size() != keys.size():
		return false
	for key in values:
		if not is_content_key(key, keys):
			return false
	return true


static func is_content_key(key: Variant, keys: Array) -> bool:
	return (key is String or key is StringName) and String(key) in keys


static func is_bounded_number(
		value: Variant, minimum: float = -MAX_ATTRIBUTE, maximum: float = MAX_ATTRIBUTE) -> bool:
	if not (value is int or value is float):
		return false
	var number := float(value)
	return is_finite(number) and number >= minimum and number <= maximum
