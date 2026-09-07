extends GutTest


func test_six_registered_items_have_distinct_valid_modifiers_and_stable_ids() -> void:
	assert_true(ItemCatalog.validate_catalog())
	assert_eq(ItemCatalog.items().size(), 6)
	var ids := []
	var modifiers := []
	var slots := {"Weapon": 0, "Armor": 0}
	var rarities := {}
	for item in ItemCatalog.items():
		assert_true(ItemCatalog.validate_item(item))
		assert_eq(ItemCatalog.item_by_id(String(item.item_id)), item)
		assert_false(ids.has(item.item_id))
		assert_false(modifiers.has(item.stat_modifiers))
		ids.append(item.item_id)
		modifiers.append(item.stat_modifiers)
		slots[item.slot] += 1
		rarities[item.rarity] = true
	assert_eq(slots, {"Weapon": 3, "Armor": 3})
	assert_eq(rarities.size(), 2)
	var returned := ItemCatalog.items()
	returned.clear()
	assert_eq(ItemCatalog.items().size(), 6)
	for id in ["", "missing", "../items/short_sword", "res://data/items/short_sword.tres"]:
		assert_null(ItemCatalog.item_by_id(id))


func test_every_class_can_use_each_matching_item_and_unequip_restores_stats() -> void:
	for hero_class in HeroCatalog.classes():
		var classes: Array[HeroClassResource] = [hero_class]
		var hero := HeroGenerator.generate_hero("equipment", 42, classes, [])
		var original := HeroStats.compute_derived_stats(hero)
		for item in ItemCatalog.items():
			var before := item.stat_modifiers.duplicate(true)
			if item.slot == "Weapon":
				hero.equipped_weapon = item
			else:
				hero.equipped_armor = item
			var stats := HeroStats.compute_derived_stats(hero)
			for stat in HeroCatalog.STATS:
				assert_almost_eq(float(stats[stat]), float(original[stat]) + float(before.get(stat, 0)), 0.0000001)
			assert_eq(item.stat_modifiers, before)
			hero.equipped_weapon = null
			hero.equipped_armor = null
			assert_eq(HeroStats.compute_derived_stats(hero), original)


func test_both_slots_apply_before_final_floor_and_probability_clamp() -> void:
	var hero := HeroGenerator.generate_hero("fractional", 42, [HeroCatalog.KNIGHT], [])
	hero.hero_class = hero.hero_class.duplicate(true)
	for stat in HeroCatalog.STATS:
		hero.hero_class.derived_stat_bases[stat] = 0.25
		for attribute in HeroCatalog.ATTRIBUTES:
			hero.hero_class.derived_stat_attribute_weights[stat][attribute] = 0.0
	hero.equipped_weapon = _item("Weapon", {"Attack": 0.4, "MaxHP": -50, "Evasion": 1.0, "CritChance": -2})
	hero.equipped_armor = _item("Armor", {"Attack": 0.4, "Defense": -2, "Evasion": -0.5, "CritChance": 0.5})
	var attributes := hero.attributes.duplicate(true)
	var stats := HeroStats.compute_derived_stats(hero)
	assert_eq(stats["Attack"], 1)
	assert_eq(stats["MaxHP"], 1)
	assert_eq(stats["Defense"], 0)
	assert_almost_eq(stats["Evasion"], 0.75, 0.0000001)
	assert_eq(stats["CritChance"], 0.0)
	assert_eq(hero.attributes, attributes)
	assert_eq(hero.equipped_weapon.stat_modifiers["Attack"], 0.4)
	assert_eq(hero.equipped_armor.stat_modifiers["Attack"], 0.4)


func test_invalid_items_and_mismatched_slots_have_no_effect_or_mutation() -> void:
	assert_false(ItemCatalog.validate_item(null))
	assert_false(ItemCatalog.validate_item(ItemResource.new()))
	var hero := HeroGenerator.generate_hero("invalid", 42, HeroCatalog.classes(), [])
	var original := HeroStats.compute_derived_stats(hero)
	var item := _item("Weapon", {"Attack": 1})
	assert_true(ItemCatalog.validate_item(item), "Custom valid fixtures need not be registered.")
	assert_null(ItemCatalog.item_by_id(String(item.item_id)))
	for field in ["item_id", "display_name", "slot", "rarity"]:
		var invalid: ItemResource = item.duplicate(true)
		invalid.set(field, "")
		assert_false(ItemCatalog.validate_item(invalid))
	for modifier in [NAN, INF, -INF, true, null, "1", [], {}, HeroCatalog.MAX_ATTRIBUTE + 1]:
		var invalid: ItemResource = item.duplicate(true)
		invalid.stat_modifiers["Attack"] = modifier
		assert_false(ItemCatalog.validate_item(invalid))
		hero.equipped_weapon = invalid
		assert_eq(HeroStats.compute_derived_stats(hero), original)
	var unknown := _item("Weapon", {"Unknown": 1})
	assert_false(ItemCatalog.validate_item(unknown))
	hero.equipped_weapon = ItemCatalog.CHAINMAIL
	assert_eq(HeroStats.compute_derived_stats(hero), original)
	hero.equipped_weapon = null
	hero.equipped_armor = ItemCatalog.SHORT_SWORD
	assert_eq(HeroStats.compute_derived_stats(hero), original)
	hero.equipped_armor = null
	assert_eq(HeroStats.compute_derived_stats(hero), original)


func test_party_power_and_frozen_combat_snapshot_use_equipment_stats() -> void:
	var hero := HeroGenerator.generate_hero("combat", 42, [HeroCatalog.KNIGHT], [])
	var party := PartyData.new()
	assert_true(party.place_hero(0, hero))
	var original := ExpeditionPartySnapshot.capture(party, true)
	assert_not_null(original)
	var original_data := original.serialize()
	var balancing: BalancingConfig = load("res://data/balancing/default_balancing.tres")
	var original_power := PartyEvaluator.compute_party_power(party, balancing)
	hero.equipped_weapon = ItemCatalog.SHORT_SWORD
	hero.equipped_armor = ItemCatalog.CHAINMAIL
	var equipped := ExpeditionPartySnapshot.capture(party, true)
	assert_not_null(equipped)
	assert_ne(equipped.serialize(), original.serialize())
	assert_eq(original.serialize(), original_data, "Existing combat snapshots remain frozen.")
	assert_eq(equipped.slots[PartyData.SLOT_NAMES[0]]["derived_stats"], HeroStats.compute_derived_stats(hero))
	assert_gt(PartyEvaluator.compute_party_power(party, balancing), original_power)
	assert_eq(HeroStats.compute_derived_stats(hero)["Attack"],
		HeroStats.compute_derived_stats(_unequipped_copy(hero))["Attack"] + 4)


func _unequipped_copy(hero: HeroData) -> HeroData:
	var copy := HeroData.new(hero.hero_id)
	copy.hero_class = hero.hero_class
	copy.attributes = hero.attributes.duplicate(true)
	copy.level = hero.level
	copy.traits = hero.traits.duplicate()
	return copy


func _item(slot: String, modifiers: Dictionary) -> ItemResource:
	var item := ItemResource.new()
	item.item_id = &"fixture"
	item.display_name = "Fixture"
	item.rarity = &"Common"
	item.slot = slot
	item.stat_modifiers = modifiers
	return item
