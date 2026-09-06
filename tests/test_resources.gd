extends GutTest


func test_exported_resource_contracts() -> void:
	var contracts := [
		[HeroClassResource.new(), {
			"class_id": TYPE_STRING_NAME, "display_name": TYPE_STRING,
			"basic_attack_target_rule": TYPE_STRING, "skill_id": TYPE_STRING_NAME,
			"base_attribute_ranges": TYPE_DICTIONARY, "per_level_growth": TYPE_DICTIONARY,
			"derived_stat_bases": TYPE_DICTIONARY,
			"derived_stat_attribute_weights": TYPE_DICTIONARY,
		}],
		[HeroTraitResource.new(), {
			"trait_id": TYPE_STRING_NAME, "display_name": TYPE_STRING,
			"description": TYPE_STRING, "stat_modifiers": TYPE_DICTIONARY,
			"flags": TYPE_ARRAY,
		}],
		[ItemResource.new(), {
			"item_id": TYPE_STRING_NAME, "display_name": TYPE_STRING,
			"slot": TYPE_STRING, "rarity": TYPE_STRING_NAME,
			"stat_modifiers": TYPE_DICTIONARY,
		}],
		[EncounterEntryResource.new(), {
			"kind": TYPE_STRING, "content_id": TYPE_STRING_NAME, "weight": TYPE_FLOAT,
		}],
		[LootResource.new(), {
			"loot_id": TYPE_STRING_NAME, "min_gold": TYPE_INT, "max_gold": TYPE_INT,
			"display_name": TYPE_STRING, "journal_text": TYPE_STRING,
		}],
		[EventOutcomeResource.new(), {
			"outcome_id": TYPE_STRING_NAME, "journal_text": TYPE_STRING,
			"weight": TYPE_FLOAT, "result": TYPE_DICTIONARY,
		}],
		[EventResource.new(), {
			"event_id": TYPE_STRING_NAME, "display_name": TYPE_STRING,
			"description": TYPE_STRING, "outcomes": TYPE_ARRAY,
		}],
		[RegionResource.new(), {
			"region_id": TYPE_STRING_NAME, "display_name": TYPE_STRING,
			"travel_title": TYPE_STRING, "travel_text": TYPE_STRING,
			"recommended_party_power": TYPE_INT, "duration_options_seconds": TYPE_ARRAY,
			"travel_step_count": TYPE_INT, "encounter_pool": TYPE_ARRAY,
			"unlock_condition": TYPE_DICTIONARY, "retreat_ends_expedition": TYPE_BOOL,
		}],
		[BalancingConfig.new(), {
			"party_power_level_weight": TYPE_FLOAT, "party_power_stat_weights": TYPE_DICTIONARY,
			"missing_front_row_factor": TYPE_FLOAT, "party_size_divisor": TYPE_FLOAT,
			"base_hit_chance": TYPE_FLOAT, "min_hit_chance": TYPE_FLOAT,
			"max_hit_chance": TYPE_FLOAT, "max_crit_chance": TYPE_FLOAT,
			"basic_attack_damage_multiplier": TYPE_FLOAT, "skill_damage_multipliers": TYPE_DICTIONARY,
			"critical_damage_multiplier": TYPE_FLOAT, "max_combat_rounds": TYPE_INT,
			"xp_award_coefficients": TYPE_DICTIONARY, "xp_threshold_curve": TYPE_DICTIONARY,
			"encounter_kind_weight_multipliers": TYPE_DICTIONARY,
			"base_recovery_seconds": TYPE_INT, "combat_recovery_seconds": TYPE_INT,
			"max_offline_delta_seconds": TYPE_INT,
			"recruitment_cost": TYPE_INT,
		}],
	]
	for contract in contracts:
		var resource: Resource = contract[0]
		var exported_fields := {}
		for property in resource.get_property_list():
			if (property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE
					and property.usage & PROPERTY_USAGE_EDITOR):
				exported_fields[String(property.name)] = property.type
		assert_eq(exported_fields, contract[1], resource.get_script().resource_path)


func test_nested_collections_are_typed() -> void:
	assert_eq(HeroTraitResource.new().flags.get_typed_builtin(), TYPE_STRING_NAME)
	assert_eq(RegionResource.new().duration_options_seconds.get_typed_builtin(), TYPE_INT)
	assert_eq(RegionResource.new().encounter_pool.get_typed_script(), EncounterEntryResource)
	assert_eq(EventResource.new().outcomes.get_typed_script(), EventOutcomeResource)


func test_inspector_hints_and_positive_defaults() -> void:
	_assert_hint(HeroClassResource.new(), "basic_attack_target_rule",
		PROPERTY_HINT_ENUM, "FrontRowFirst,AnySlot")
	_assert_hint(ItemResource.new(), "slot", PROPERTY_HINT_ENUM, "Weapon,Armor")
	_assert_hint(EncounterEntryResource.new(), "kind", PROPERTY_HINT_ENUM, "Loot,Event,Combat")
	_assert_hint(EncounterEntryResource.new(), "weight", PROPERTY_HINT_RANGE, "0.001,1000000.0")
	_assert_hint(EventOutcomeResource.new(), "weight", PROPERTY_HINT_RANGE, "0.001,1000000.0")
	for pair in [
		[HeroTraitResource.new(), "description"],
		[EventResource.new(), "description"],
		[EventOutcomeResource.new(), "journal_text"],
		[RegionResource.new(), "travel_text"],
		[LootResource.new(), "journal_text"],
	]:
		_assert_hint(pair[0], pair[1], PROPERTY_HINT_MULTILINE_TEXT, "")
	assert_gt(EncounterEntryResource.new().weight, 0.0)
	assert_gt(EventOutcomeResource.new().weight, 0.0)
	assert_gt(RegionResource.new().travel_step_count, 0)


func test_default_balancing_asset() -> void:
	var balancing := load("res://data/balancing/default_balancing.tres") as BalancingConfig
	assert_not_null(balancing)
	if balancing == null:
		return
	assert_eq(balancing.recruitment_cost, 100)
	assert_almost_eq(balancing.base_hit_chance, 0.90, 0.00001)
	assert_almost_eq(balancing.min_hit_chance, 0.50, 0.00001)
	assert_almost_eq(balancing.max_hit_chance, 0.99, 0.00001)
	assert_almost_eq(balancing.max_crit_chance, 0.50, 0.00001)
	assert_almost_eq(balancing.basic_attack_damage_multiplier, 1.0, 0.00001)
	assert_almost_eq(balancing.critical_damage_multiplier, 1.5, 0.00001)
	assert_eq(balancing.party_power_level_weight, 10.0)
	assert_eq(balancing.party_power_stat_weights, {
		"MaxHP": 0.5, "Attack": 1.0, "MagicPower": 1.0, "Defense": 0.5,
		"Evasion": 0.0, "Initiative": 0.0, "CritChance": 0.0,
	})
	assert_eq(balancing.missing_front_row_factor, 0.85)
	assert_eq(balancing.party_size_divisor, 4.0)
	assert_eq(balancing.max_combat_rounds, 20)
	assert_eq(balancing.encounter_kind_weight_multipliers, {
		"Loot": 1.0, "Event": 1.0, "Combat": 1.0,
	})
	assert_eq(balancing.max_offline_delta_seconds, 86400)


func _assert_hint(resource: Resource, field: String, hint: int, hint_string: String) -> void:
	for property in resource.get_property_list():
		if property.name == field:
			assert_eq(property.hint, hint, field)
			assert_eq(property.hint_string, hint_string, field)
			return
	fail_test("Missing exported field: %s" % field)
