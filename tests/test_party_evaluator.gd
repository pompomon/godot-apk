extends GutTest

var _balancing: BalancingConfig
var _heroes: Array[HeroData]


func before_each() -> void:
	_balancing = load("res://data/balancing/default_balancing.tres").duplicate(true)
	# Keep the original hand-computed formula fixture independent of authored tuning.
	_balancing.party_power_level_weight = 10.0
	_balancing.party_power_stat_weights.Defense = 0.5
	_heroes = [
		_hero("knight", HeroCatalog.KNIGHT, HeroCatalog.HEARTY,
			{"MIG": 10, "FOC": 2, "GRT": 11, "GUI": 3, "FTH": 3}),
		_hero("ranger", HeroCatalog.RANGER, HeroCatalog.KEEN_EYED,
			{"MIG": 10, "FOC": 3, "GRT": 5, "GUI": 11, "FTH": 2}),
		_hero("wizard", HeroCatalog.WIZARD, HeroCatalog.STUDIOUS,
			{"MIG": 2, "FOC": 13, "GRT": 4, "GUI": 5, "FTH": 4}),
		_hero("cleric", HeroCatalog.CLERIC, HeroCatalog.LIGHTFOOTED,
			{"MIG": 3, "FOC": 5, "GRT": 6, "GUI": 3, "FTH": 13}),
	]


func _hero(id: String, hero_class: HeroClassResource, hero_trait: HeroTraitResource, attributes: Dictionary) -> HeroData:
	var hero := HeroData.new(id)
	hero.hero_class = hero_class
	hero.attributes = attributes
	hero.traits = [hero_trait]
	return hero


func _party(count: int) -> PartyData:
	var party := PartyData.new()
	for slot in count:
		party.place_hero(slot, _heroes[slot])
	return party


func test_hand_computed_full_and_one_two_three_member_powers() -> void:
	# Hero scores: 103, 71.5, 74, 85. Multiply the sum by count / 4.
	for example in [[0, 0.0], [1, 25.75], [2, 87.25], [3, 186.375], [4, 333.5]]:
		var party := _party(example[0])
		assert_eq(PartyEvaluator.validation_error(party, _balancing), "")
		assert_almost_eq(PartyEvaluator.compute_party_power(party, _balancing), example[1], 0.00000001)


func test_missing_front_penalty_applies_after_size_scaling() -> void:
	var party := _party(2)
	assert_almost_eq(PartyEvaluator.compute_party_power(party, _balancing), 87.25, 0.00000001)
	party.move_hero(0, 2)
	assert_almost_eq(PartyEvaluator.compute_party_power(party, _balancing), 87.25, 0.00000001)
	party.move_hero(1, 3)
	assert_almost_eq(PartyEvaluator.compute_party_power(party, _balancing), 74.1625, 0.00000001)
	party.remove_hero(3)
	assert_almost_eq(PartyEvaluator.compute_party_power(party, _balancing), 21.8875, 0.00000001)


func test_all_seven_weights_including_normally_zero_weights_are_consumed() -> void:
	var expected := {"MaxHP": 117, "Attack": 23, "MagicPower": 1, "Defense": 21,
		"Evasion": 0.019, "Initiative": 4, "CritChance": 0.036}
	_balancing.party_power_level_weight = 0
	for stat in HeroCatalog.STATS:
		for key in HeroCatalog.STATS:
			_balancing.party_power_stat_weights[key] = 0.0
		_balancing.party_power_stat_weights[stat] = 1.0
		assert_almost_eq(PartyEvaluator.compute_party_power(_party(1), _balancing),
			expected[stat] / 4.0, 0.000000001, stat)
	for stat in HeroCatalog.STATS:
		_balancing.party_power_stat_weights[stat] = 0.0
	assert_eq(PartyEvaluator.compute_party_power(_party(4), _balancing), 0.0)
	_balancing.party_power_level_weight = 12.5
	assert_eq(PartyEvaluator.compute_party_power(_party(4), _balancing), 50.0)
	_balancing.party_size_divisor = 2.5
	assert_eq(PartyEvaluator.compute_party_power(_party(4), _balancing), 80.0)


func test_large_integer_stat_weight_uses_float_arithmetic_before_multiplication() -> void:
	var party := _party(1)
	_balancing.party_power_level_weight = 0.0
	for stat in HeroCatalog.STATS:
		_balancing.party_power_stat_weights[stat] = 0
	_balancing.party_power_stat_weights.MaxHP = 1 << 60
	var expected := 117.0 * float(1 << 60) / 4.0
	assert_eq(PartyEvaluator.validation_error(party, _balancing), "")
	var power := PartyEvaluator.compute_party_power(party, _balancing)
	assert_true(is_finite(power))
	assert_eq(power, expected)
	_balancing.party_size_divisor = 1.0e-308
	_assert_invalid(party)


func test_growth_and_levels_use_derived_stats_without_rounding_power() -> void:
	var hero := _heroes[0]
	hero.level = 2
	# Effective MIG=11,GRT=13: HP=128, Attack=25, Magic=1, Defense=24.
	assert_eq(HeroStats.compute_derived_stats(hero).MaxHP, 128)
	assert_almost_eq(PartyEvaluator.compute_party_power(_party(1), _balancing), 30.5, 0.00000001)
	_balancing.party_size_divisor = 3.0
	assert_almost_eq(PartyEvaluator.compute_party_power(_party(1), _balancing), 122.0 / 3.0, 0.000000001)


func test_evaluation_is_pure_for_models_resources_and_global_state() -> void:
	var party := _party(4)
	var slots := party.slots.duplicate()
	var original := GameState.checkpoint()
	var weights := _balancing.party_power_stat_weights.duplicate()
	var attributes := _heroes[0].attributes.duplicate()
	var growth := _heroes[0].hero_class.per_level_growth.duplicate()
	var modifiers := _heroes[0].traits[0].stat_modifiers.duplicate()
	_heroes[0].xp = 123
	_heroes[0].status = HeroData.HeroStatus.WOUNDED
	var weapon := ItemResource.new()
	weapon.stat_modifiers = {"Attack": 9000.0}
	_heroes[0].equipped_weapon = weapon
	assert_eq(PartyEvaluator.compute_party_power(party, _balancing), 333.5)
	assert_eq(PartyEvaluator.compute_party_power(party, _balancing), 333.5)
	assert_eq(GameState.checkpoint(), original)
	assert_eq(party.slots, slots)
	assert_eq(_balancing.party_power_stat_weights, weights)
	assert_eq(_heroes[0].attributes, attributes)
	assert_eq(_heroes[0].hero_class.per_level_growth, growth)
	assert_eq(_heroes[0].traits[0].stat_modifiers, modifiers)
	assert_eq(_heroes[0].xp, 123)
	assert_eq(_heroes[0].status, HeroData.HeroStatus.WOUNDED)
	assert_eq(weapon.stat_modifiers, {"Attack": 9000.0})


func test_invalid_config_keys_weights_and_nonfinite_values_return_nan_with_reason() -> void:
	var party := _party(1)
	assert_true(is_nan(PartyEvaluator.compute_party_power(party, null)))
	assert_false(PartyEvaluator.validation_error(party, null).is_empty())
	for key in HeroCatalog.STATS:
		var original := _balancing.party_power_stat_weights.duplicate()
		_balancing.party_power_stat_weights.erase(key)
		_assert_invalid(party)
		_balancing.party_power_stat_weights = original.duplicate()
		for value in [-0.1, NAN, INF, -INF, "0", true, null, [], {}]:
			_balancing.party_power_stat_weights[key] = value
			_assert_invalid(party)
		_balancing.party_power_stat_weights = original
	_balancing.party_power_stat_weights["Unknown"] = 0.0
	_assert_invalid(party)


func test_invalid_level_weight_divisor_and_formation_factor_are_not_zero_power() -> void:
	var party := _party(0)
	for field in ["party_power_level_weight", "party_size_divisor", "missing_front_row_factor"]:
		var original: float = _balancing.get(field)
		var values: Array = [-1.0, NAN, INF, -INF]
		if field != "party_power_level_weight":
			values.append(0.0)
		if field == "missing_front_row_factor":
			values.append(1.01)
		for value in values:
			_balancing.set(field, value)
			_assert_invalid(party)
		_balancing.set(field, original)


func test_invalid_party_heroes_and_numeric_overflow_have_feedback() -> void:
	_assert_invalid(null)
	var party := _party(1)
	party.slots[1] = _heroes[0]
	_assert_invalid(party)
	party.slots[1] = null
	_heroes[0].attributes.MIG = NAN
	_assert_invalid(party)
	_heroes[0].attributes.MIG = 10
	_heroes[0].level = 0
	_assert_invalid(party)
	_heroes[0].level = 1
	_heroes[0].traits = [null]
	_assert_invalid(party)
	_heroes[0].traits.clear()
	_balancing.party_power_stat_weights.MaxHP = 1.0e308
	_assert_invalid(party)
	_balancing.party_power_stat_weights.MaxHP = 0.5
	_balancing.party_size_divisor = 1.0e-308
	_assert_invalid(party)


func _assert_invalid(party: PartyData) -> void:
	assert_false(PartyEvaluator.validation_error(party, _balancing).is_empty())
	assert_true(is_nan(PartyEvaluator.compute_party_power(party, _balancing)))
