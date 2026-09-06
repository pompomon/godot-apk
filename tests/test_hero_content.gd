extends GutTest


func test_catalog_has_four_ordered_classes_and_functional_tradeoff_traits() -> void:
	var classes := HeroCatalog.classes()
	var traits := HeroCatalog.traits()
	assert_eq(classes.size(), 4)
	assert_between(traits.size(), 3, 5)
	assert_true(HeroCatalog.validate_catalog(classes, traits))
	var ids := ["knight", "ranger", "wizard", "cleric"]
	var names := ["Knight", "Ranger", "Wizard", "Cleric"]
	for index in range(classes.size()):
		var hero_class := classes[index]
		assert_true(HeroCatalog.validate_class(hero_class))
		assert_eq(String(hero_class.class_id), ids[index])
		assert_eq(hero_class.display_name, names[index])
		assert_eq(hero_class.basic_attack_target_rule, "FrontRowFirst" if index == 0 else "AnySlot")
		assert_eq(hero_class.base_attribute_ranges.size(), 5)
		assert_eq(hero_class.per_level_growth.size(), 5)
		assert_eq(hero_class.derived_stat_bases.size(), 7)
		assert_eq(hero_class.derived_stat_attribute_weights.size(), 7)
		for stat in HeroCatalog.STATS:
			assert_eq(hero_class.derived_stat_attribute_weights[stat].size(), 5)
	var trait_ids := []
	for hero_trait in traits:
		assert_true(HeroCatalog.validate_trait(hero_trait))
		assert_eq(hero_trait.flags.size(), 0)
		var has_bonus := false
		var has_penalty := false
		for amount in hero_trait.stat_modifiers.values():
			has_bonus = has_bonus or amount > 0
			has_penalty = has_penalty or amount < 0
		assert_true(has_bonus, "%s bonus" % hero_trait.trait_id)
		assert_true(has_penalty, "%s tradeoff" % hero_trait.trait_id)
		trait_ids.append(String(hero_trait.trait_id))
	assert_eq(trait_ids, ["hearty", "keen_eyed", "lightfooted", "studious"])
	assert_eq(HeroCatalog.HEARTY.stat_modifiers, {"MaxHP": 12.0, "Initiative": -1.0})
	assert_eq(HeroCatalog.KEEN_EYED.stat_modifiers, {"CritChance": 0.04, "Defense": -2.0})
	assert_eq(HeroCatalog.LIGHTFOOTED.stat_modifiers, {"Evasion": 0.06, "Initiative": -2.0})
	assert_eq(HeroCatalog.STUDIOUS.stat_modifiers, {"MagicPower": 3.0, "Attack": -2.0})


func test_classes_have_distinct_role_appropriate_attributes_and_growth() -> void:
	var primaries := [["MIG", "GRT"], ["MIG", "GUI"], ["FOC"], ["FTH"]]
	var classes := HeroCatalog.classes()
	for index in range(classes.size()):
		var hero_class := classes[index]
		for primary in primaries[index]:
			for secondary in HeroCatalog.ATTRIBUTES:
				if secondary in primaries[index]:
					continue
				assert_gt(hero_class.base_attribute_ranges[primary].x,
					hero_class.base_attribute_ranges[secondary].y,
					"%s primary %s exceeds %s" % [hero_class.class_id, primary, secondary])
				assert_gt(hero_class.per_level_growth[primary], hero_class.per_level_growth[secondary])
		for other_index in range(index + 1, classes.size()):
			assert_ne(hero_class.base_attribute_ranges, classes[other_index].base_attribute_ranges)
			assert_ne(hero_class.per_level_growth, classes[other_index].per_level_growth)


func test_catalog_lookup_is_explicit_and_returns_fresh_pool_arrays() -> void:
	for hero_class in HeroCatalog.classes():
		assert_eq(HeroCatalog.class_by_id(String(hero_class.class_id)), hero_class)
	for hero_trait in HeroCatalog.traits():
		assert_eq(HeroCatalog.trait_by_id(String(hero_trait.trait_id)), hero_trait)
	for unknown in ["", "missing", "Knight", "../knight", "res://data/classes/knight.tres", "user://hero.tres"]:
		assert_null(HeroCatalog.class_by_id(unknown))
		assert_null(HeroCatalog.trait_by_id(unknown))
	assert_null(HeroCatalog.class_by_id("hearty"))
	assert_null(HeroCatalog.trait_by_id("knight"))
	var classes := HeroCatalog.classes()
	var traits := HeroCatalog.traits()
	classes.clear()
	traits.reverse()
	traits.pop_back()
	assert_eq(HeroCatalog.classes().size(), 4)
	assert_eq(HeroCatalog.classes()[0], HeroCatalog.KNIGHT)
	assert_eq(HeroCatalog.traits().size(), 4)
	assert_eq(HeroCatalog.traits()[0], HeroCatalog.HEARTY)


func test_class_rejects_missing_and_extra_keys_in_every_complete_map() -> void:
	for field in ["base_attribute_ranges", "per_level_growth", "derived_stat_bases", "derived_stat_attribute_weights"]:
		var valid: HeroClassResource = HeroCatalog.KNIGHT.duplicate(true)
		var values: Dictionary = valid.get(field)
		for key in values:
			var hero_class: HeroClassResource = valid.duplicate(true)
			var incomplete: Dictionary = hero_class.get(field)
			incomplete.erase(key)
			assert_false(HeroCatalog.validate_class(hero_class), "%s missing %s" % [field, key])
		var extra: HeroClassResource = valid.duplicate(true)
		extra.get(field)["unknown"] = 0.0
		assert_false(HeroCatalog.validate_class(extra), "%s extra key" % field)
		var mistyped: HeroClassResource = valid.duplicate(true)
		var malformed: Dictionary = mistyped.get(field)
		malformed.erase(malformed.keys()[0])
		malformed[123] = 0.0
		assert_false(HeroCatalog.validate_class(mistyped), "%s non-string key" % field)
	for stat in HeroCatalog.STATS:
		for attribute in HeroCatalog.ATTRIBUTES:
			var hero_class: HeroClassResource = HeroCatalog.KNIGHT.duplicate(true)
			hero_class.derived_stat_attribute_weights[stat].erase(attribute)
			assert_false(HeroCatalog.validate_class(hero_class), "%s missing %s" % [stat, attribute])
		var extra: HeroClassResource = HeroCatalog.KNIGHT.duplicate(true)
		extra.derived_stat_attribute_weights[stat]["unknown"] = 0.0
		assert_false(HeroCatalog.validate_class(extra), "%s extra weight" % stat)


func test_class_rejects_invalid_range_types_order_and_bounds() -> void:
	for attribute in HeroCatalog.ATTRIBUTES:
		for invalid in [
			null, true, 3, [1, 2], {"min": 1, "max": 2}, Vector2(1, 2),
			Vector2i(-1, 2), Vector2i(4, 3), Vector2i(0, HeroCatalog.MAX_ATTRIBUTE + 1),
		]:
			var hero_class: HeroClassResource = HeroCatalog.KNIGHT.duplicate(true)
			hero_class.base_attribute_ranges[attribute] = invalid
			assert_false(HeroCatalog.validate_class(hero_class), "%s invalid range %s" % [attribute, invalid])
	var boundary: HeroClassResource = HeroCatalog.KNIGHT.duplicate(true)
	boundary.base_attribute_ranges["MIG"] = Vector2i(0, 0)
	boundary.base_attribute_ranges["FOC"] = Vector2i(HeroCatalog.MAX_ATTRIBUTE, HeroCatalog.MAX_ATTRIBUTE)
	assert_true(HeroCatalog.validate_class(boundary))


func test_class_rejects_non_numeric_non_finite_and_oversized_coefficients() -> void:
	var invalid_numbers := [true, "1.0", null, [], {}, NAN, INF, -INF,
		HeroCatalog.MAX_ATTRIBUTE + 1, -HeroCatalog.MAX_ATTRIBUTE - 1]
	for invalid in invalid_numbers:
		for attribute in HeroCatalog.ATTRIBUTES:
			var hero_class: HeroClassResource = HeroCatalog.KNIGHT.duplicate(true)
			hero_class.per_level_growth[attribute] = invalid
			assert_false(HeroCatalog.validate_class(hero_class), "Invalid growth %s" % attribute)
		for stat in HeroCatalog.STATS:
			var hero_class: HeroClassResource = HeroCatalog.KNIGHT.duplicate(true)
			hero_class.derived_stat_bases[stat] = invalid
			assert_false(HeroCatalog.validate_class(hero_class), "Invalid base %s" % stat)
			for attribute in HeroCatalog.ATTRIBUTES:
				var bad_weight: HeroClassResource = HeroCatalog.KNIGHT.duplicate(true)
				bad_weight.derived_stat_attribute_weights[stat][attribute] = invalid
				assert_false(HeroCatalog.validate_class(bad_weight), "Invalid weight %s/%s" % [stat, attribute])
	for attribute in HeroCatalog.ATTRIBUTES:
		var negative_growth: HeroClassResource = HeroCatalog.KNIGHT.duplicate(true)
		negative_growth.per_level_growth[attribute] = -0.01
		assert_false(HeroCatalog.validate_class(negative_growth))
	for invalid_weights in [null, 1.0, [], "weights"]:
		var hero_class: HeroClassResource = HeroCatalog.KNIGHT.duplicate(true)
		hero_class.derived_stat_attribute_weights["Attack"] = invalid_weights
		assert_false(HeroCatalog.validate_class(hero_class))


func test_class_numeric_boundaries_allow_explicit_zero_and_signed_weights() -> void:
	var hero_class: HeroClassResource = HeroCatalog.KNIGHT.duplicate(true)
	hero_class.per_level_growth["MIG"] = HeroCatalog.MAX_ATTRIBUTE
	hero_class.per_level_growth["FOC"] = 0
	hero_class.derived_stat_bases["MaxHP"] = HeroCatalog.MAX_ATTRIBUTE
	hero_class.derived_stat_bases["Attack"] = -HeroCatalog.MAX_ATTRIBUTE
	hero_class.derived_stat_attribute_weights["Attack"]["MIG"] = -0.25
	hero_class.derived_stat_attribute_weights["MagicPower"]["FOC"] = 0
	assert_true(HeroCatalog.validate_class(hero_class))


func test_class_rejects_missing_identity_name_and_invalid_targeting() -> void:
	assert_false(HeroCatalog.validate_class(null))
	assert_false(HeroCatalog.validate_class(HeroClassResource.new()))
	for id in ["", " "]:
		var hero_class: HeroClassResource = HeroCatalog.KNIGHT.duplicate(true)
		hero_class.class_id = StringName(id)
		assert_false(HeroCatalog.validate_class(hero_class))
	var unnamed: HeroClassResource = HeroCatalog.KNIGHT.duplicate(true)
	unnamed.display_name = " "
	assert_false(HeroCatalog.validate_class(unnamed))
	for rule in ["", "Front", "Back", "anyslot", "res://other.tres"]:
		var hero_class: HeroClassResource = HeroCatalog.KNIGHT.duplicate(true)
		hero_class.basic_attack_target_rule = rule
		assert_false(HeroCatalog.validate_class(hero_class))


func test_trait_rejects_malformed_identity_modifiers_and_unsupported_flags() -> void:
	assert_false(HeroCatalog.validate_trait(null))
	assert_false(HeroCatalog.validate_trait(HeroTraitResource.new()))
	for field in ["trait_id", "display_name", "description"]:
		var hero_trait: HeroTraitResource = HeroCatalog.HEARTY.duplicate(true)
		hero_trait.set(field, &"" if field == "trait_id" else " ")
		assert_false(HeroCatalog.validate_trait(hero_trait), field)
	for invalid_key in [123, true, "Unknown", "MaxHp", "AttackMultiplier"]:
		var hero_trait: HeroTraitResource = HeroCatalog.HEARTY.duplicate(true)
		hero_trait.stat_modifiers[invalid_key] = 1.0
		assert_false(HeroCatalog.validate_trait(hero_trait))
	for invalid_value in [true, "12", null, [], {}, NAN, INF, -INF,
			HeroCatalog.MAX_ATTRIBUTE + 1, -HeroCatalog.MAX_ATTRIBUTE - 1]:
		var hero_trait: HeroTraitResource = HeroCatalog.HEARTY.duplicate(true)
		hero_trait.stat_modifiers["MaxHP"] = invalid_value
		assert_false(HeroCatalog.validate_trait(hero_trait))
	var flagged: HeroTraitResource = HeroCatalog.HEARTY.duplicate(true)
	flagged.flags = [&"conditional_damage"]
	assert_false(HeroCatalog.validate_trait(flagged), "Unimplemented conditional traits are not functional")
	var boundary: HeroTraitResource = HeroCatalog.HEARTY.duplicate(true)
	boundary.stat_modifiers = {"MaxHP": HeroCatalog.MAX_ATTRIBUTE, "Attack": -HeroCatalog.MAX_ATTRIBUTE, "Defense": 0}
	assert_true(HeroCatalog.validate_trait(boundary))


func test_catalog_rejects_empty_class_pool_nulls_and_duplicate_ids() -> void:
	assert_false(HeroCatalog.validate_catalog([], []))
	assert_false(HeroCatalog.validate_catalog([], HeroCatalog.traits()))
	assert_true(HeroCatalog.validate_catalog(HeroCatalog.classes(), []))
	assert_false(HeroCatalog.validate_catalog([null], []))
	assert_false(HeroCatalog.validate_catalog(HeroCatalog.classes(), [null]))
	assert_false(HeroCatalog.validate_catalog([HeroClassResource.new()], []))
	assert_false(HeroCatalog.validate_catalog(HeroCatalog.classes(), [HeroTraitResource.new()]))
	var duplicate_class: HeroClassResource = HeroCatalog.KNIGHT.duplicate(true)
	duplicate_class.display_name = "Different object, same ID"
	assert_false(HeroCatalog.validate_catalog([HeroCatalog.KNIGHT, duplicate_class], []))
	var duplicate_trait: HeroTraitResource = HeroCatalog.HEARTY.duplicate(true)
	duplicate_trait.display_name = "Different object, same ID"
	assert_false(HeroCatalog.validate_catalog(HeroCatalog.classes(), [HeroCatalog.HEARTY, duplicate_trait]))
	assert_false(HeroCatalog.validate_catalog([HeroCatalog.KNIGHT, HeroCatalog.KNIGHT], []))
	assert_false(HeroCatalog.validate_catalog(HeroCatalog.classes(), [HeroCatalog.HEARTY, HeroCatalog.HEARTY]))
