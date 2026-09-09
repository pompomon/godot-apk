class_name ExpeditionCatalog
extends RefCounted
## Ordered allowlists. Save validation checks identity, not today's outcome tuning.

const GREEN_HOLLOW: RegionResource = preload("res://data/regions/green_hollow.tres")
const ASHEN_REACH: RegionResource = preload("res://data/regions/ashen_reach.tres")
const FROSTBOUND_PASS: RegionResource = preload("res://data/regions/frostbound_pass.tres")
const LOOT: LootResource = preload("res://data/encounters/green_hollow_loot.tres")
const ASHEN_LOOT: LootResource = preload("res://data/encounters/ashen_loot.tres")
const FROSTBOUND_LOOT: LootResource = preload("res://data/encounters/frostbound_loot.tres")
const EVENTS: Array[EventResource] = [
	preload("res://data/encounters/green_hollow_bridge.tres"),
	preload("res://data/encounters/green_hollow_spring.tres"),
	preload("res://data/encounters/green_hollow_caravan.tres"),
	preload("res://data/encounters/green_hollow_fireflies.tres"),
	preload("res://data/encounters/green_hollow_ruins.tres"),
	preload("res://data/encounters/ashen_cistern.tres"),
	preload("res://data/encounters/ashen_kiln.tres"),
	preload("res://data/encounters/ashen_obelisk.tres"),
	preload("res://data/encounters/ashen_glass.tres"),
	preload("res://data/encounters/ashen_pilgrims.tres"),
	preload("res://data/encounters/frostbound_bells.tres"),
	preload("res://data/encounters/frostbound_crevasse.tres"),
	preload("res://data/encounters/frostbound_shelter.tres"),
	preload("res://data/encounters/frostbound_aurora.tres"),
	preload("res://data/encounters/frostbound_sled.tres"),
]
const MAX_STEPS := 1024
const MAX_LOOT_GOLD := 2147483647 # RandomNumberGenerator.randi_range's signed range.
const MAX_EVENT_ITEMS := 16


static func regions() -> Array[RegionResource]:
	return [GREEN_HOLLOW, ASHEN_REACH, FROSTBOUND_PASS]


static func events() -> Array[EventResource]:
	return EVENTS.duplicate()


static func loot() -> Array[LootResource]:
	return [LOOT, ASHEN_LOOT, FROSTBOUND_LOOT]


static func region_by_id(id: String) -> RegionResource:
	for region in regions():
		if String(region.region_id) == id:
			return region
	return null


static func event_by_id(id: String) -> EventResource:
	for event in events():
		if String(event.event_id) == id:
			return event
	return null


static func loot_by_id(id: String) -> LootResource:
	for entry in loot():
		if String(entry.loot_id) == id:
			return entry
	return null


static func integer(value: Variant, minimum: int = 0, maximum: int = HeroCatalog.MAX_SAFE_INT) -> bool:
	if value is int:
		return value >= minimum and value <= maximum
	return value is float and is_finite(value) and value >= minimum and value <= maximum and value == floor(value)


static func text(value: Variant, maximum: int = 128) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= maximum


## Validates an optional narrative-variant pool: an Array of nonempty,
## length-bounded, unique strings.
static func text_variants_valid(
		variants: Variant, maximum_entries: int = 16, maximum_length: int = 4096) -> bool:
	if not variants is Array or variants.size() > maximum_entries:
		return false
	var seen := {}
	for entry in variants:
		if not text(entry, maximum_length) or seen.has(entry):
			return false
		seen[entry] = true
	return true


static func weight(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0


static func gold_payload(value: Variant) -> bool:
	return value is Dictionary and HeroCatalog.has_exact_keys(value, ["gold"]) and integer(value.gold)


static func reward_payload(value: Variant, maximum_items: int = MAX_EVENT_ITEMS) -> bool:
	if gold_payload(value):
		return true
	if not value is Dictionary or not HeroCatalog.has_exact_keys(value, ["gold", "item_ids"]):
		return false
	if not integer(value.gold) or not value.item_ids is Array or value.item_ids.size() > maximum_items:
		return false
	for id in value.item_ids:
		if not text(id) or ItemCatalog.item_by_id(id) == null:
			return false
	return true


static func validate_loot(entry: LootResource) -> bool:
	if entry == null or not text(String(entry.loot_id)) or not text(entry.display_name) or not text(entry.journal_text, 4096):
		return false
	if not text_variants_valid(entry.journal_text_variants):
		return false
	if not integer(entry.min_gold, 0, MAX_LOOT_GOLD) or not integer(entry.max_gold, entry.min_gold, MAX_LOOT_GOLD):
		return false
	if not is_finite(entry.item_drop_chance) or entry.item_drop_chance < 0.0 or entry.item_drop_chance > 1.0:
		return false
	var total := 0.0
	for id in entry.item_pool:
		if not (id is String or id is StringName) or ItemCatalog.item_by_id(String(id)) == null or not weight(entry.item_pool[id]):
			return false
		total += float(entry.item_pool[id])
	return is_finite(total) and (entry.item_pool.is_empty() or entry.item_drop_chance == 0.0 or total > 0.0)


static func validate_event(event: EventResource) -> bool:
	if event == null or not text(String(event.event_id)) or not text(event.display_name) or not text(event.description, 4096):
		return false
	if not text_variants_valid(event.description_variants):
		return false
	if event.outcomes.is_empty() or event.outcomes.size() > MAX_STEPS:
		return false
	var descriptions := NarrativeVariantSelector.candidate_list(event.description, event.description_variants)
	var ids := {}
	var total := 0.0
	for outcome in event.outcomes:
		if outcome == null or not text(String(outcome.outcome_id)) or ids.has(outcome.outcome_id):
			return false
		if not text(outcome.journal_text, 4096) or not weight(outcome.weight) or not reward_payload(outcome.result):
			return false
		if not text_variants_valid(outcome.journal_text_variants):
			return false
		var outcome_texts := NarrativeVariantSelector.candidate_list(outcome.journal_text, outcome.journal_text_variants)
		for description in descriptions:
			for outcome_text in outcome_texts:
				if not text(description + "\n" + outcome_text, 4096):
					return false
		ids[outcome.outcome_id] = true
		total += outcome.weight
	return is_finite(total) and total > 0.0


static func clock_config_valid(balancing: BalancingConfig) -> bool:
	return balancing != null and integer(balancing.max_offline_delta_seconds, 1)


static func unlock_condition_valid(condition: Dictionary) -> bool:
	if not condition.get("kind") is String:
		return false
	match condition.kind:
		"always":
			return HeroCatalog.has_exact_keys(condition, ["kind"])
		"gold":
			return HeroCatalog.has_exact_keys(condition, ["kind", "value"]) \
				and condition.value is int and integer(condition.value, 1)
	return false


static func validate_region(region: RegionResource, balancing: BalancingConfig) -> bool:
	if region == null or not clock_config_valid(balancing):
		return false
	if not text(String(region.region_id)) or not text(region.display_name) or not integer(region.recommended_party_power):
		return false
	if not text(region.travel_title) or not text(region.travel_text, 4096):
		return false
	if not text_variants_valid(region.travel_text_variants):
		return false
	if not unlock_condition_valid(region.unlock_condition):
		return false
	if not integer(region.travel_step_count, 1, MAX_STEPS / 2) or region.duration_options_seconds.is_empty():
		return false
	var count := region.travel_step_count * 2
	var durations := {}
	for duration in region.duration_options_seconds:
		if not integer(duration, count) or duration % count != 0 or durations.has(duration):
			return false
		durations[duration] = true
	if region.encounter_pool.is_empty() or region.encounter_pool.size() > MAX_STEPS:
		return false
	var total := 0.0
	for entry in region.encounter_pool:
		if entry == null or entry.kind not in ["Loot", "Event", "Combat"] or not weight(entry.weight):
			return false
		if not text(String(entry.content_id)):
			return false
		var multiplier: Variant = balancing.encounter_kind_weight_multipliers.get(entry.kind)
		if not weight(multiplier):
			return false
		if entry.kind == "Loot" and not validate_loot(loot_by_id(String(entry.content_id))):
			return false
		if entry.kind == "Event" and not validate_event(event_by_id(String(entry.content_id))):
			return false
		if entry.kind == "Combat" and not CombatCatalog.validate_enemy_group(CombatCatalog.enemy_group_by_id(String(entry.content_id))):
			return false
		total += entry.weight * float(multiplier)
	return is_finite(total) and total > 0.0


static func validate_catalog(
		region_list: Array, event_list: Array, loot_list: Array, balancing: BalancingConfig) -> bool:
	var ids := {}
	var groups := [region_list, event_list, loot_list]
	for index in range(groups.size()):
		var group: Array = groups[index]
		if group.is_empty():
			return false
		for entry in group:
			var id := ""
			if index == 0 and entry is RegionResource and validate_region(entry, balancing):
				id = String(entry.region_id)
			elif index == 1 and entry is EventResource and validate_event(entry):
				id = String(entry.event_id)
			elif index == 2 and entry is LootResource and validate_loot(entry):
				id = String(entry.loot_id)
			else:
				return false
			if ids.has(id):
				return false
			ids[id] = true
	return true
