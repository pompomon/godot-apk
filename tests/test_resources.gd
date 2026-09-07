extends GutTest


func test_exported_resource_contracts() -> void:
	var contracts := [
		[HeroClassResource.new(), {
			"class_id": TYPE_STRING_NAME, "display_name": TYPE_STRING,
			"basic_attack_target_rule": TYPE_STRING,
			"active_skill": TYPE_OBJECT,
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
		[SkillResource.new(), {
			"skill_id": TYPE_STRING_NAME, "display_name": TYPE_STRING,
			"effect": TYPE_STRING, "target_rule": TYPE_STRING, "cooldown_turns": TYPE_INT,
		}],
		[EnemyGroupResource.new(), {
			"group_id": TYPE_STRING_NAME, "display_name": TYPE_STRING, "enemies": TYPE_ARRAY,
		}],
		[EncounterEntryResource.new(), {
			"kind": TYPE_STRING, "content_id": TYPE_STRING_NAME, "weight": TYPE_FLOAT,
		}],
		[LootResource.new(), {
			"loot_id": TYPE_STRING_NAME, "min_gold": TYPE_INT, "max_gold": TYPE_INT,
			"display_name": TYPE_STRING, "journal_text": TYPE_STRING,
			"item_pool": TYPE_DICTIONARY, "item_drop_chance": TYPE_FLOAT,
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
			"base_recovery_seconds": TYPE_INT, "max_offline_delta_seconds": TYPE_INT,
			"recovery_hp_percent": TYPE_INT,
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
	assert_eq(EnemyGroupResource.new().enemies.get_typed_builtin(), TYPE_DICTIONARY)
	assert_eq(HeroTraitResource.new().flags.get_typed_builtin(), TYPE_STRING_NAME)
	assert_eq(RegionResource.new().duration_options_seconds.get_typed_builtin(), TYPE_INT)
	assert_eq(RegionResource.new().encounter_pool.get_typed_script(), EncounterEntryResource)
	assert_eq(EventResource.new().outcomes.get_typed_script(), EventOutcomeResource)


func test_inspector_hints_and_positive_defaults() -> void:
	_assert_hint(SkillResource.new(), "effect", PROPERTY_HINT_ENUM, "Physical,Magic,Heal,Guard")
	_assert_hint(SkillResource.new(), "target_rule", PROPERTY_HINT_ENUM, "FrontRowFirst,AnySlot,LowestHPAlly,Self")
	assert_eq(SkillResource.new().cooldown_turns, 2)
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
	assert_eq(balancing.skill_damage_multipliers, {
		"aimed_shot": 1.5, "firebolt": 1.5, "guard": 0.5, "mend": 1.0,
	})
	assert_eq(balancing.encounter_kind_weight_multipliers, {
		"Loot": 1.0, "Event": 1.0, "Combat": 1.0,
	})
	assert_eq(balancing.max_offline_delta_seconds, 86400)
	assert_eq(balancing.base_recovery_seconds, 60)
	assert_eq(balancing.recovery_hp_percent, 25)
	assert_eq(balancing.xp_award_coefficients, {
		"recommended_party_power": 0.25, "duration_seconds": 1.0,
	})
	assert_eq(balancing.xp_threshold_curve, {"base": 100, "growth_factor": 1.25})
	assert_eq(Leveling.validation_error(balancing), "")


func test_authored_combat_catalog_and_class_skills() -> void:
	var balancing: BalancingConfig = load("res://data/balancing/default_balancing.tres")
	assert_true(CombatCatalog.validate_catalog(CombatCatalog.skills(), CombatCatalog.enemy_groups(), balancing))
	assert_eq(CombatCatalog.skills().size(), 4)
	assert_eq(CombatCatalog.enemy_groups().size(), 2)
	assert_null(CombatCatalog.skill_by_id("../skills/unknown"))
	assert_null(CombatCatalog.enemy_group_by_id("missing"))
	assert_false(CombatCatalog.validate_enemy_group(null))
	var expected: Dictionary = {
		"knight": ["guard", "Guard", "Self", "FrontRowFirst"],
		"ranger": ["aimed_shot", "Physical", "AnySlot", "AnySlot"],
		"wizard": ["firebolt", "Magic", "AnySlot", "AnySlot"],
		"cleric": ["mend", "Heal", "LowestHPAlly", "AnySlot"],
	}
	for hero_class in HeroCatalog.classes():
		var values: Array = expected[String(hero_class.class_id)]
		var skill: SkillResource = hero_class.active_skill
		assert_not_null(skill)
		assert_eq(skill, CombatCatalog.skill_by_id(values[0]))
		assert_eq(skill.effect, values[1])
		assert_eq(skill.target_rule, values[2])
		assert_eq(hero_class.basic_attack_target_rule, values[3])
		assert_eq(skill.cooldown_turns, 2)
		assert_true(CombatCatalog.validate_skill_snapshot(skill.snapshot()))
	for group in CombatCatalog.enemy_groups():
		assert_eq(CombatCatalog.enemy_group_by_id(String(group.group_id)), group)
		assert_true(CombatCatalog.validate_enemy_group(group))
	var groups: Array[EnemyGroupResource] = CombatCatalog.enemy_groups()
	groups.clear()
	assert_eq(CombatCatalog.enemy_groups().size(), 2)
	var region := ExpeditionCatalog.GREEN_HOLLOW
	assert_true(ExpeditionCatalog.validate_region(region, balancing))
	assert_eq(region.duration_options_seconds, [60])
	assert_eq(region.travel_step_count, 5)
	assert_false(region.retreat_ends_expedition)
	var pool: Array = []
	for entry in region.encounter_pool:
		pool.append([entry.kind, String(entry.content_id), entry.weight])
		assert_gt(entry.weight, 0.0)
		if entry.kind == "Combat":
			var group := CombatCatalog.enemy_group_by_id(String(entry.content_id))
			assert_not_null(group)
			assert_true(CombatCatalog.validate_enemy_group(group))
			if group != null:
				assert_gt(group.enemies.size(), 0)
	assert_eq(pool, [
		["Loot", "green_hollow_loot", 2.0],
		["Event", "green_hollow_bridge", 1.0],
		["Event", "green_hollow_spring", 1.0],
		["Event", "green_hollow_caravan", 1.0],
		["Event", "green_hollow_fireflies", 1.0],
		["Event", "green_hollow_ruins", 1.0],
		["Combat", "forest_wolves", 2.0],
		["Combat", "bandit_skirmishers", 1.0],
	])


func test_live_green_hollow_is_deterministic_and_starter_party_beats_wolves() -> void:
	var balancing: BalancingConfig = load("res://data/balancing/default_balancing.tres")
	var region := ExpeditionCatalog.GREEN_HOLLOW
	var party := PartyData.new()
	var classes := HeroCatalog.classes()
	for index in range(classes.size()):
		var single_class: Array[HeroClassResource] = [classes[index]]
		var hero := HeroGenerator.generate_hero("hero-%d" % (index + 1),
			RecruitmentService.seed_at(12345, index), single_class, HeroCatalog.traits())
		assert_not_null(hero)
		assert_true(party.place_hero(index, hero))
	var snapshot := ExpeditionPartySnapshot.capture(party, true)
	assert_not_null(snapshot)
	if snapshot == null:
		return
	var selected_groups := {}
	for seed_value in [0, 1, 2, 42, 12345]:
		var result := CombatEngine.resolve_combat(snapshot, snapshot.hero_states(),
			CombatCatalog.FOREST_WOLVES, seed_value, balancing)
		assert_false(result.has("error"))
		assert_eq(result.get("outcome"), "VICTORY", "Starter Party versus Forest Wolves, seed %d" % seed_value)
		var run := ExpeditionGenerator.generate(region, party, seed_value, 60, 1000, balancing)
		var repeated := ExpeditionGenerator.generate(region, party, seed_value, 60, 1000, balancing)
		assert_not_null(run)
		assert_not_null(repeated)
		if run == null or repeated == null:
			continue
		assert_true(ExpeditionData.valid(run.serialize()))
		var encoded := JSON.stringify(run.serialize(), "", true, true)
		assert_eq(JSON.stringify(repeated.serialize(), "", true, true), encoded)
		assert_true(ExpeditionData.valid(JSON.parse_string(encoded)))
		assert_eq(run.planned_step_count, 10)
		assert_eq(run.step_duration_seconds, 6)
		assert_false(run.retreat_ends_expedition)
		for step in run.steps:
			if step.kind != ExpeditionStep.StepKind.COMBAT:
				continue
			assert_true(step.content_id in ["forest_wolves", "bandit_skirmishers"])
			selected_groups[step.content_id] = true
			var group := CombatCatalog.enemy_group_by_id(step.content_id)
			var expected_enemy_ids: Array = []
			for enemy in group.enemies:
				expected_enemy_ids.append(enemy.combatant_id)
			assert_eq(step.result.enemy_states.keys(), expected_enemy_ids)
			assert_false(step.result.rounds.is_empty())
			assert_lte(step.result.rounds.size(), balancing.max_combat_rounds)
	assert_eq(selected_groups.size(), 2, "Fixed live-pool seeds exercise both authored Combat groups.")


func _assert_hint(resource: Resource, field: String, hint: int, hint_string: String) -> void:
	for property in resource.get_property_list():
		if property.name == field:
			assert_eq(property.hint, hint, field)
			assert_eq(property.hint_string, hint_string, field)
			return
	fail_test("Missing exported field: %s" % field)
