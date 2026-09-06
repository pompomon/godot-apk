extends GutTest


func test_fixed_seed_golden_heroes() -> void:
	# Captured with Godot 4.7.2; changing draw order/content intentionally changes these.
	var cases := [
		[0, "Lina", "cleric", {"MIG": 4, "FOC": 4, "GRT": 5, "GUI": 2, "FTH": 13}, ["keen_eyed"]],
		[2, "Lina", "wizard", {"MIG": 1, "FOC": 12, "GRT": 4, "GUI": 5, "FTH": 4}, []],
		[3, "Galen", "knight", {"MIG": 9, "FOC": 1, "GRT": 12, "GUI": 2, "FTH": 4}, []],
		[42, "Elara", "ranger", {"MIG": 8, "FOC": 3, "GRT": 5, "GUI": 10, "FTH": 2}, ["keen_eyed"]],
		[123456, "Petra", "wizard", {"MIG": 1, "FOC": 14, "GRT": 5, "GUI": 5, "FTH": 5}, ["keen_eyed"]],
		[HeroCatalog.MAX_SAFE_INT, "Kael", "ranger",
			{"MIG": 11, "FOC": 2, "GRT": 4, "GUI": 9, "FTH": 2}, ["lightfooted"]],
	]
	for example in cases:
		var hero := HeroGenerator.generate_hero(
			"hero-7", example[0], HeroCatalog.classes(), HeroCatalog.traits())
		assert_not_null(hero)
		if hero == null:
			continue
		assert_eq(_snapshot(hero), {
			"id": "hero-7", "name": example[1], "class": example[2],
			"level": 1, "xp": 0, "attributes": example[3], "traits": example[4],
			"status": HeroData.HeroStatus.IDLE,
		}, "Golden seed %s" % example[0])
		assert_null(hero.equipped_weapon)
		assert_null(hero.equipped_armor)


func test_repeated_generation_and_identity_do_not_change_rolls() -> void:
	var first := HeroGenerator.generate_hero(
		"original", 42, HeroCatalog.classes(), HeroCatalog.traits(), 8)
	for index in range(8):
		var repeated := HeroGenerator.generate_hero(
			"original", 42, HeroCatalog.classes(), HeroCatalog.traits(), 8)
		assert_eq(_snapshot(repeated), _snapshot(first), "Repetition %s" % index)
		assert_false(is_same(repeated, first))
	var other_id := HeroGenerator.generate_hero(
		"another", 42, HeroCatalog.classes(), HeroCatalog.traits())
	assert_eq(other_id.hero_id, "another")
	assert_eq(other_id.hero_name, first.hero_name)
	assert_eq(other_id.hero_class, first.hero_class)
	assert_eq(other_id.attributes, first.attributes, "Level is not baked into original rolls")
	assert_eq(other_id.traits, first.traits)
	assert_eq(first.level, 8)


func test_generation_does_not_read_or_advance_global_rng() -> void:
	seed(91023)
	var expected_first := randi()
	var expected_second := randi()
	seed(91023)
	assert_eq(randi(), expected_first)
	var hero := HeroGenerator.generate_hero("global", 42, HeroCatalog.classes(), HeroCatalog.traits())
	assert_eq(randi(), expected_second, "Local generation must not consume global draws")
	seed(11111)
	for index in range(20):
		randi()
	var other := HeroGenerator.generate_hero("global", 42, HeroCatalog.classes(), HeroCatalog.traits())
	assert_eq(_snapshot(hero), _snapshot(other), "Global RNG state must not influence generation")


func test_draw_sequence_is_class_name_independent_attributes_then_trait() -> void:
	var class_pool := HeroCatalog.classes()
	var trait_pool := HeroCatalog.traits()
	for value in range(64):
		var rng := RandomNumberGenerator.new()
		rng.seed = value
		var expected_class := class_pool[rng.randi_range(0, class_pool.size() - 1)]
		var expected_name: String = HeroGenerator.NAMES[rng.randi_range(0, HeroGenerator.NAMES.size() - 1)]
		var expected_attributes := {}
		for attribute in ["MIG", "FOC", "GRT", "GUI", "FTH"]:
			var bounds: Vector2i = expected_class.base_attribute_ranges[attribute]
			expected_attributes[attribute] = rng.randi_range(bounds.x, bounds.y)
		var expected_traits: Array[HeroTraitResource] = []
		if rng.randi_range(0, 1) == 1:
			expected_traits.append(trait_pool[rng.randi_range(0, trait_pool.size() - 1)])
		var hero := HeroGenerator.generate_hero("draw-order", value, class_pool, trait_pool)
		assert_eq(hero.hero_class, expected_class)
		assert_eq(hero.hero_name, expected_name)
		assert_eq(hero.attributes, expected_attributes)
		assert_eq(hero.traits, expected_traits)


func test_all_class_rolls_reach_both_inclusive_endpoints() -> void:
	for hero_class in HeroCatalog.classes():
		var minima := {}
		var maxima := {}
		for attribute in HeroCatalog.ATTRIBUTES:
			minima[attribute] = HeroCatalog.MAX_ATTRIBUTE
			maxima[attribute] = -1
		for value in range(256):
			var hero := HeroGenerator.generate_hero("bounds", value, [hero_class], [])
			assert_eq(hero.hero_class, hero_class)
			assert_eq(hero.attributes.size(), 5)
			for attribute in HeroCatalog.ATTRIBUTES:
				var bounds: Vector2i = hero_class.base_attribute_ranges[attribute]
				var rolled: int = hero.attributes[attribute]
				assert_typeof(hero.attributes[attribute], TYPE_INT)
				assert_between(rolled, bounds.x, bounds.y, "%s %s" % [hero_class.class_id, attribute])
				minima[attribute] = mini(minima[attribute], rolled)
				maxima[attribute] = maxi(maxima[attribute], rolled)
		for attribute in HeroCatalog.ATTRIBUTES:
			var bounds: Vector2i = hero_class.base_attribute_ranges[attribute]
			assert_eq(minima[attribute], bounds.x, "Inclusive minimum %s" % attribute)
			assert_eq(maxima[attribute], bounds.y, "Inclusive maximum %s" % attribute)


func test_zero_and_single_value_ranges_and_empty_trait_pool() -> void:
	var hero_class: HeroClassResource = HeroCatalog.KNIGHT.duplicate(true)
	hero_class.base_attribute_ranges = {
		"MIG": Vector2i(0, 0), "FOC": Vector2i(1, 1), "GRT": Vector2i(2, 2),
		"GUI": Vector2i(3, 3), "FTH": Vector2i(HeroCatalog.MAX_ATTRIBUTE, HeroCatalog.MAX_ATTRIBUTE),
	}
	var hero := HeroGenerator.generate_hero("fixed", 0, [hero_class], [], HeroCatalog.MAX_LEVEL)
	assert_not_null(hero)
	assert_eq(hero.attributes, {"MIG": 0, "FOC": 1, "GRT": 2, "GUI": 3, "FTH": HeroCatalog.MAX_ATTRIBUTE})
	assert_eq(hero.level, HeroCatalog.MAX_LEVEL)
	assert_eq(hero.traits.size(), 0)


func test_zero_or_one_traits_and_every_trait_is_reachable() -> void:
	var seen := {}
	var saw_no_trait := false
	for value in range(128):
		var hero := HeroGenerator.generate_hero(
			"traits", value, HeroCatalog.classes(), HeroCatalog.traits())
		assert_between(hero.traits.size(), 0, 1)
		if hero.traits.is_empty():
			saw_no_trait = true
		else:
			assert_has(HeroCatalog.traits(), hero.traits[0])
			seen[hero.traits[0].trait_id] = true
	assert_true(saw_no_trait)
	assert_eq(seen.size(), HeroCatalog.traits().size())


func test_pool_resources_and_collections_are_unchanged() -> void:
	var class_pool := HeroCatalog.classes()
	var trait_pool := HeroCatalog.traits()
	var classes_before := class_pool.duplicate()
	var traits_before := trait_pool.duplicate()
	var content_before := _content_snapshot(class_pool, trait_pool)
	for value in range(32):
		HeroGenerator.generate_hero("pure", value, class_pool, trait_pool, 20)
	assert_eq(class_pool, classes_before)
	assert_eq(trait_pool, traits_before)
	assert_eq(_content_snapshot(class_pool, trait_pool), content_before)
	var hero := HeroGenerator.generate_hero("independent", 42, class_pool, trait_pool)
	var other := HeroGenerator.generate_hero("independent", 42, class_pool, trait_pool)
	hero.attributes["MIG"] = 999
	hero.traits.clear()
	assert_eq(other.attributes["MIG"], 8)
	assert_eq(other.traits.size(), 1)
	assert_eq(_content_snapshot(class_pool, trait_pool), content_before)


func test_attribute_dictionary_insertion_order_does_not_change_generation() -> void:
	var original: HeroClassResource = HeroCatalog.KNIGHT.duplicate(true)
	var reordered: HeroClassResource = original.duplicate(true)
	reordered.base_attribute_ranges = {}
	for attribute in ["FTH", "GUI", "GRT", "FOC", "MIG"]:
		reordered.base_attribute_ranges[attribute] = original.base_attribute_ranges[attribute]
	for value in range(16):
		var first := HeroGenerator.generate_hero("order", value, [original], HeroCatalog.traits())
		var second := HeroGenerator.generate_hero("order", value, [reordered], HeroCatalog.traits())
		assert_eq(_snapshot(first), _snapshot(second))


func test_invalid_generation_arguments_return_null_without_errors() -> void:
	var classes := HeroCatalog.classes()
	var traits := HeroCatalog.traits()
	assert_null(HeroGenerator.generate_hero("", 0, classes, traits))
	assert_null(HeroGenerator.generate_hero("invalid", -1, classes, traits))
	assert_null(HeroGenerator.generate_hero("invalid", HeroCatalog.MAX_SAFE_INT + 1, classes, traits))
	for invalid_level in [-1, 0, HeroCatalog.MAX_LEVEL + 1]:
		assert_null(HeroGenerator.generate_hero("invalid", 0, classes, traits, invalid_level))
	assert_null(HeroGenerator.generate_hero("invalid", 0, [], traits))
	assert_null(HeroGenerator.generate_hero("invalid", 0, [null], traits))
	assert_null(HeroGenerator.generate_hero("invalid", 0, classes, [null]))
	assert_null(HeroGenerator.generate_hero("invalid", 0, [HeroClassResource.new()], traits))
	assert_null(HeroGenerator.generate_hero("invalid", 0, classes, [HeroTraitResource.new()]))
	assert_null(HeroGenerator.generate_hero("invalid", 0, [classes[0], classes[0]], traits))
	assert_null(HeroGenerator.generate_hero("invalid", 0, classes, [traits[0], traits[0]]))
	var malformed_class: HeroClassResource = classes[0].duplicate(true)
	malformed_class.per_level_growth["MIG"] = NAN
	assert_null(HeroGenerator.generate_hero("invalid", 0, [classes[1], malformed_class], traits))
	var malformed_trait: HeroTraitResource = traits[0].duplicate(true)
	malformed_trait.stat_modifiers["Attack"] = INF
	assert_null(HeroGenerator.generate_hero("invalid", 0, classes, [traits[1], malformed_trait]))


func test_hero_model_identity_defaults_and_independent_collections() -> void:
	var hero := HeroData.new("stable")
	var other := HeroData.new()
	assert_true(hero is RefCounted)
	hero.hero_id = "replacement"
	hero.set("hero_id", "another replacement")
	hero.hero_name = "Renamed"
	hero.hero_class = HeroCatalog.CLERIC
	assert_eq(hero.hero_id, "stable")
	other.hero_id = "late allocation"
	assert_eq(other.hero_id, "", "Even an empty initial ID cannot be reassigned")
	assert_eq(other.hero_name, "")
	assert_null(other.hero_class)
	assert_eq(other.level, 1)
	assert_eq(other.xp, 0)
	assert_null(other.equipped_weapon)
	assert_null(other.equipped_armor)
	assert_eq(other.status, HeroData.HeroStatus.IDLE)
	assert_eq(other.traits.get_typed_script(), HeroTraitResource)
	hero.attributes["MIG"] = 10
	hero.traits.append(HeroCatalog.HEARTY)
	assert_eq(other.attributes, {})
	assert_eq(other.traits.size(), 0)
	var labels := ["Idle", "Assigned", "On Expedition", "Resting", "Wounded", "Dead"]
	for value in HeroData.HeroStatus.values():
		hero.status = value
		assert_eq(hero.status_label(), labels[value])


func _snapshot(hero: HeroData) -> Dictionary:
	var trait_ids := []
	for hero_trait in hero.traits:
		trait_ids.append(String(hero_trait.trait_id))
	return {
		"id": hero.hero_id, "name": hero.hero_name, "class": String(hero.hero_class.class_id),
		"level": hero.level, "xp": hero.xp, "attributes": hero.attributes.duplicate(true),
		"traits": trait_ids, "status": hero.status,
	}


func _content_snapshot(classes: Array[HeroClassResource], traits: Array[HeroTraitResource]) -> Array:
	var snapshot := []
	for hero_class in classes:
		snapshot.append([
			hero_class.class_id, hero_class.display_name, hero_class.basic_attack_target_rule,
			hero_class.base_attribute_ranges.duplicate(true), hero_class.per_level_growth.duplicate(true),
			hero_class.derived_stat_bases.duplicate(true), hero_class.derived_stat_attribute_weights.duplicate(true),
		])
	for hero_trait in traits:
		snapshot.append([
			hero_trait.trait_id, hero_trait.display_name, hero_trait.description,
			hero_trait.stat_modifiers.duplicate(true), hero_trait.flags.duplicate(),
		])
	return snapshot
