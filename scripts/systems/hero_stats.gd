class_name HeroStats
extends RefCounted
## Pure roster statistics, including slot-compatible equipment.


static func effective_attributes(hero: HeroData) -> Dictionary:
	if hero == null or not HeroCatalog.validate_class(hero.hero_class):
		return {}
	if hero.level < 1 or hero.level > HeroCatalog.MAX_LEVEL:
		return {}
	if not HeroCatalog.has_exact_keys(hero.attributes, HeroCatalog.ATTRIBUTES):
		return {}
	var result := {}
	for attribute in HeroCatalog.ATTRIBUTES:
		var original: Variant = hero.attributes[attribute]
		if not original is int or not HeroCatalog.is_bounded_number(
				original, 0.0, HeroCatalog.MAX_ATTRIBUTE):
			return {}
		var growth: float = hero.hero_class.per_level_growth[attribute]
		result[attribute] = original + floori((hero.level - 1) * growth)
	return result


static func compute_derived_stats(hero: HeroData) -> Dictionary:
	var attributes := effective_attributes(hero)
	if attributes.is_empty():
		return {}
	var trait_ids := {}
	for hero_trait in hero.traits:
		if not HeroCatalog.validate_trait(hero_trait) or trait_ids.has(hero_trait.trait_id):
			return {}
		trait_ids[hero_trait.trait_id] = true
	var equipment: Array[ItemResource] = []
	if ItemCatalog.validate_item(hero.equipped_weapon) and hero.equipped_weapon.slot == "Weapon":
		equipment.append(hero.equipped_weapon)
	if ItemCatalog.validate_item(hero.equipped_armor) and hero.equipped_armor.slot == "Armor":
		equipment.append(hero.equipped_armor)
	var result := {}
	for stat in HeroCatalog.STATS:
		var value: float = hero.hero_class.derived_stat_bases[stat]
		for attribute in HeroCatalog.ATTRIBUTES:
			value += attributes[attribute] * hero.hero_class.derived_stat_attribute_weights[stat][attribute]
		for hero_trait in hero.traits:
			value += hero_trait.stat_modifiers.get(stat, 0.0)
		for item in equipment:
			value += item.stat_modifiers.get(stat, 0.0)
		if not is_finite(value):
			return {}
		if stat in ["Evasion", "CritChance"]:
			result[stat] = clampf(value, 0.0, 1.0)
		else:
			result[stat] = maxi(1 if stat == "MaxHP" else 0, floori(value))
	return result
