extends GutTest


func test_hand_calculated_knight_with_hearty() -> void:
	var hero := _hero(HeroCatalog.KNIGHT, {"MIG": 10, "FOC": 2, "GRT": 11, "GUI": 3, "FTH": 3})
	hero.traits = [HeroCatalog.HEARTY]
	# HP = 40 + 10 + 5*11 + 12; Attack = floor(6 + 1.5*10 + .25*11).
	_assert_stats(hero, {
		"MaxHP": 117, "Attack": 23, "MagicPower": 1, "Defense": 21,
		"Evasion": 0.019, "Initiative": 4, "CritChance": 0.036,
	})


func test_hand_calculated_ranger_with_keen_eyed() -> void:
	var hero := _hero(HeroCatalog.RANGER, {"MIG": 10, "FOC": 3, "GRT": 5, "GUI": 11, "FTH": 2})
	hero.traits = [HeroCatalog.KEEN_EYED]
	# Attack = 8 + 1.75*10 + .5*11; Defense = floor(2 + .75*5 + .25*11 - 2).
	_assert_stats(hero, {
		"MaxHP": 53, "Attack": 31, "MagicPower": 1, "Defense": 6,
		"Evasion": 0.106, "Initiative": 23, "CritChance": 0.144,
	})


func test_hand_calculated_wizard_with_studious() -> void:
	var hero := _hero(HeroCatalog.WIZARD, {"MIG": 2, "FOC": 13, "GRT": 4, "GUI": 5, "FTH": 4})
	hero.traits = [HeroCatalog.STUDIOUS]
	# MagicPower = floor(10 + 2.25*13 + .25*4 + 3); Attack = floor(2 + .75*2 - 2).
	_assert_stats(hero, {
		"MaxHP": 34, "Attack": 1, "MagicPower": 43, "Defense": 6,
		"Evasion": 0.04, "Initiative": 13, "CritChance": 0.066,
	})


func test_hand_calculated_cleric_with_lightfooted() -> void:
	var hero := _hero(HeroCatalog.CLERIC, {"MIG": 3, "FOC": 5, "GRT": 6, "GUI": 3, "FTH": 13})
	hero.traits = [HeroCatalog.LIGHTFOOTED]
	# MagicPower = floor(8 + .5*5 + 2*13); Initiative = floor(4 + .75*3 + .25*13 - 2).
	_assert_stats(hero, {
		"MaxHP": 60, "Attack": 4, "MagicPower": 36, "Defense": 10,
		"Evasion": 0.087, "Initiative": 7, "CritChance": 0.029,
	})


func test_fractional_growth_is_floored_per_attribute_before_weighting() -> void:
	var hero := _fractional_hero()
	assert_eq(HeroStats.effective_attributes(hero), {"MIG": 2, "FOC": 2, "GRT": 5, "GUI": 7, "FTH": 5})
	assert_eq(hero.attributes, {"MIG": 1, "FOC": 2, "GRT": 3, "GUI": 4, "FTH": 5})
	hero.level = 1
	assert_eq(HeroStats.effective_attributes(hero), hero.attributes)


func test_every_weight_and_all_flat_modifiers_are_added_before_final_floor() -> void:
	var hero := _fractional_hero()
	# .25 base + .25*(2+2+5+7+5) + .3 + .3 = 6.1, floored only now.
	_assert_stats(hero, {
		"MaxHP": 6, "Attack": 6, "MagicPower": 6, "Defense": 6,
		"Evasion": 0.155, "Initiative": 6, "CritChance": 0.325,
	})


func test_negative_integral_stats_and_out_of_range_probabilities_are_clamped() -> void:
	var hero := _hero(HeroCatalog.KNIGHT.duplicate(true), _zero_attributes())
	for stat in HeroCatalog.STATS:
		hero.hero_class.derived_stat_bases[stat] = -2.25
	hero.traits = [_modifier("penalty", {"MaxHP": -20.0, "Attack": -4.0})]
	_assert_stats(hero, {
		"MaxHP": 1, "Attack": 0, "MagicPower": 0, "Defense": 0,
		"Evasion": 0.0, "Initiative": 0, "CritChance": 0.0,
	})
	hero.hero_class.derived_stat_bases["Evasion"] = 1.2
	hero.hero_class.derived_stat_bases["CritChance"] = 1.0
	hero.traits = [_modifier("probability", {"Evasion": 0.1, "CritChance": 0.5})]
	var stats := HeroStats.compute_derived_stats(hero)
	assert_eq(stats["Evasion"], 1.0)
	assert_eq(stats["CritChance"], 1.0)
	hero.hero_class.derived_stat_bases["Evasion"] = 1.2
	hero.hero_class.derived_stat_bases["CritChance"] = -0.1
	hero.traits = [_modifier("mixed", {"Evasion": -0.3, "CritChance": 0.2})]
	stats = HeroStats.compute_derived_stats(hero)
	assert_almost_eq(stats["Evasion"], 0.9, 0.0000001, "Clamp after modifiers, not before")
	assert_almost_eq(stats["CritChance"], 0.1, 0.0000001)


func test_custom_nonnegative_attributes_need_not_match_generation_ranges() -> void:
	var hero := _hero(HeroCatalog.KNIGHT, _zero_attributes())
	assert_eq(HeroStats.effective_attributes(hero), _zero_attributes())
	assert_eq(HeroStats.compute_derived_stats(hero)["MaxHP"], 40)
	for attribute in HeroCatalog.ATTRIBUTES:
		hero.attributes[attribute] = HeroCatalog.MAX_ATTRIBUTE
	hero.level = HeroCatalog.MAX_LEVEL
	var effective := HeroStats.effective_attributes(hero)
	assert_eq(effective["MIG"], 2499998)
	assert_eq(effective["GRT"], 2999998)
	assert_false(HeroStats.compute_derived_stats(hero).is_empty())


func test_stats_are_pure_and_equipment_status_xp_identity_do_not_affect_them() -> void:
	var hero := _fractional_hero()
	var attributes_before := hero.attributes.duplicate(true)
	var traits_before := hero.traits.duplicate()
	var growth_before := hero.hero_class.per_level_growth.duplicate(true)
	var bases_before := hero.hero_class.derived_stat_bases.duplicate(true)
	var weights_before := hero.hero_class.derived_stat_attribute_weights.duplicate(true)
	var modifiers_before := hero.traits[0].stat_modifiers.duplicate(true)
	var first := HeroStats.compute_derived_stats(hero)
	assert_eq(HeroStats.compute_derived_stats(hero), first)
	var returned_attributes := HeroStats.effective_attributes(hero)
	returned_attributes["MIG"] = 999
	var weapon := ItemResource.new()
	weapon.stat_modifiers = {"Attack": 5000.0}
	var armor := ItemResource.new()
	armor.slot = "Armor"
	armor.stat_modifiers = {"Defense": 5000.0}
	hero.equipped_weapon = weapon
	hero.equipped_armor = armor
	hero.xp = 250
	hero.hero_name = "Renamed"
	hero.status = HeroData.HeroStatus.WOUNDED
	assert_eq(HeroStats.compute_derived_stats(hero), first)
	first["MaxHP"] = -999
	assert_eq(HeroStats.compute_derived_stats(hero)["MaxHP"], 6)
	assert_eq(hero.attributes, attributes_before)
	assert_eq(hero.traits, traits_before)
	assert_eq(hero.hero_class.per_level_growth, growth_before)
	assert_eq(hero.hero_class.derived_stat_bases, bases_before)
	assert_eq(hero.hero_class.derived_stat_attribute_weights, weights_before)
	assert_eq(hero.traits[0].stat_modifiers, modifiers_before)
	assert_eq(hero.equipped_weapon, weapon)
	assert_eq(hero.equipped_armor, armor)
	assert_eq(weapon.stat_modifiers, {"Attack": 5000.0})
	assert_eq(armor.stat_modifiers, {"Defense": 5000.0})
	assert_eq(hero.hero_id, "stats")
	assert_eq(hero.level, 4)


func test_maximum_valid_growth_and_coefficients_remain_safe() -> void:
	var hero := _hero(HeroCatalog.KNIGHT.duplicate(true), _zero_attributes())
	hero.level = HeroCatalog.MAX_LEVEL
	for attribute in HeroCatalog.ATTRIBUTES:
		hero.attributes[attribute] = HeroCatalog.MAX_ATTRIBUTE
		hero.hero_class.per_level_growth[attribute] = HeroCatalog.MAX_ATTRIBUTE
	for stat in HeroCatalog.STATS:
		hero.hero_class.derived_stat_bases[stat] = HeroCatalog.MAX_ATTRIBUTE
		for attribute in HeroCatalog.ATTRIBUTES:
			hero.hero_class.derived_stat_attribute_weights[stat][attribute] = HeroCatalog.MAX_ATTRIBUTE
	var effective := HeroStats.effective_attributes(hero)
	assert_eq(effective["MIG"], 1000000000000)
	var stats := HeroStats.compute_derived_stats(hero)
	assert_eq(stats.size(), 7)
	assert_gt(stats["MaxHP"], HeroCatalog.MAX_SAFE_INT, "Derived stats are not JSON seed state")
	assert_typeof(stats["MaxHP"], TYPE_INT)
	assert_eq(stats["Evasion"], 1.0)
	assert_eq(stats["CritChance"], 1.0)
	for stat in HeroCatalog.STATS:
		for attribute in HeroCatalog.ATTRIBUTES:
			hero.hero_class.derived_stat_attribute_weights[stat][attribute] = -HeroCatalog.MAX_ATTRIBUTE
	_assert_stats(hero, {
		"MaxHP": 1, "Attack": 0, "MagicPower": 0, "Defense": 0,
		"Evasion": 0.0, "Initiative": 0, "CritChance": 0.0,
	})


func test_invalid_hero_class_level_and_attributes_return_empty_safely() -> void:
	assert_eq(HeroStats.effective_attributes(null), {})
	assert_eq(HeroStats.compute_derived_stats(null), {})
	_assert_invalid(HeroData.new())
	_assert_invalid(_hero(HeroClassResource.new(), _zero_attributes()))
	var hero := _hero(HeroCatalog.KNIGHT, _zero_attributes())
	for invalid_level in [-1, 0, HeroCatalog.MAX_LEVEL + 1]:
		hero.level = invalid_level
		_assert_invalid(hero)
	hero.level = 1
	for attribute in HeroCatalog.ATTRIBUTES:
		for invalid in [-1, 1.5, 2.0, HeroCatalog.MAX_ATTRIBUTE + 1, NAN, INF, -INF, "10", true, null, [], {}]:
			hero.attributes = _zero_attributes()
			hero.attributes[attribute] = invalid
			_assert_invalid(hero)
		hero.attributes = _zero_attributes()
		hero.attributes.erase(attribute)
		_assert_invalid(hero)
	hero.attributes = _zero_attributes()
	hero.attributes["unknown"] = 1
	_assert_invalid(hero)
	hero.attributes = _zero_attributes()
	hero.hero_class = HeroCatalog.KNIGHT.duplicate(true)
	hero.hero_class.derived_stat_attribute_weights["Attack"]["MIG"] = NAN
	_assert_invalid(hero)


func test_invalid_active_traits_return_empty_safely() -> void:
	var hero := _hero(HeroCatalog.KNIGHT, _zero_attributes())
	hero.traits = [null]
	assert_eq(HeroStats.compute_derived_stats(hero), {})
	hero.traits = [HeroTraitResource.new()]
	assert_eq(HeroStats.compute_derived_stats(hero), {})
	var invalid := _modifier("invalid", {"MaxHP": INF})
	hero.traits = [invalid]
	assert_eq(HeroStats.compute_derived_stats(hero), {})
	hero.traits = [HeroCatalog.HEARTY, HeroCatalog.HEARTY]
	assert_eq(HeroStats.compute_derived_stats(hero), {})


func _hero(hero_class: HeroClassResource, attributes: Dictionary) -> HeroData:
	var hero := HeroData.new("stats")
	hero.hero_class = hero_class
	hero.attributes = attributes
	return hero


func _zero_attributes() -> Dictionary:
	return {"MIG": 0, "FOC": 0, "GRT": 0, "GUI": 0, "FTH": 0}


func _modifier(id: String, modifiers: Dictionary) -> HeroTraitResource:
	var hero_trait := HeroTraitResource.new()
	hero_trait.trait_id = StringName(id)
	hero_trait.display_name = id
	hero_trait.description = "Synthetic flat modifiers for an arithmetic test."
	hero_trait.stat_modifiers = modifiers
	return hero_trait


func _fractional_hero() -> HeroData:
	var hero := _hero(HeroCatalog.KNIGHT.duplicate(true), {"MIG": 1, "FOC": 2, "GRT": 3, "GUI": 4, "FTH": 5})
	hero.level = 4
	hero.hero_class.per_level_growth = {"MIG": 0.5, "FOC": 0.25, "GRT": 0.75, "GUI": 1.25, "FTH": 0.0}
	var first := {}
	var second := {}
	for stat in HeroCatalog.STATS:
		hero.hero_class.derived_stat_bases[stat] = 0.25
		for attribute in HeroCatalog.ATTRIBUTES:
			hero.hero_class.derived_stat_attribute_weights[stat][attribute] = 0.25
		first[stat] = 0.3
		second[stat] = 0.3
	for stat in ["Evasion", "CritChance"]:
		for attribute in HeroCatalog.ATTRIBUTES:
			hero.hero_class.derived_stat_attribute_weights[stat][attribute] = 0.0
	hero.hero_class.derived_stat_bases["Evasion"] = 0.125
	hero.hero_class.derived_stat_bases["CritChance"] = 0.3
	first["Evasion"] = 0.01
	second["Evasion"] = 0.02
	first["CritChance"] = -0.015
	second["CritChance"] = 0.04
	hero.traits = [_modifier("first", first), _modifier("second", second)]
	return hero


func _assert_stats(hero: HeroData, expected: Dictionary) -> void:
	var actual := HeroStats.compute_derived_stats(hero)
	assert_eq(actual.size(), 7)
	for stat in expected:
		assert_has(actual, stat)
		if not actual.has(stat):
			continue
		if stat in ["Evasion", "CritChance"]:
			assert_typeof(actual[stat], TYPE_FLOAT)
			assert_almost_eq(actual[stat], expected[stat], 0.0000001, stat)
			assert_between(actual[stat], 0.0, 1.0, stat)
		else:
			assert_typeof(actual[stat], TYPE_INT)
			assert_eq(actual[stat], expected[stat], stat)


func _assert_invalid(hero: HeroData) -> void:
	assert_eq(HeroStats.effective_attributes(hero), {})
	assert_eq(HeroStats.compute_derived_stats(hero), {})
