class_name PartyEvaluator
extends RefCounted
## Pure estimate, not combat strength. Invalid inputs are NAN, never a plausible zero.


static func validation_error(party: PartyData, balancing: BalancingConfig) -> String:
	if party == null:
		return "Missing formation."
	var error := party.validation_error()
	if not error.is_empty():
		return error
	if balancing == null:
		return "Missing Party Power configuration."
	if not HeroCatalog.has_exact_keys(balancing.party_power_stat_weights, HeroCatalog.STATS):
		return "Party Power requires exactly the seven derived-stat weights."
	if not _nonnegative(balancing.party_power_level_weight):
		return "Party Power level weight must be finite and nonnegative."
	for stat in HeroCatalog.STATS:
		if not _nonnegative(balancing.party_power_stat_weights[stat]):
			return "Party Power weight for %s must be finite and nonnegative." % stat
	if not is_finite(balancing.party_size_divisor) or balancing.party_size_divisor <= 0.0:
		return "Party size divisor must be finite and positive."
	if (not is_finite(balancing.missing_front_row_factor)
			or balancing.missing_front_row_factor <= 0.0 or balancing.missing_front_row_factor > 1.0):
		return "Missing-front-row factor must be in (0, 1]."
	for hero in party.heroes():
		var stats := HeroStats.compute_derived_stats(hero)
		if not HeroCatalog.has_exact_keys(stats, HeroCatalog.STATS):
			return "Invalid level, attributes, class or traits for Hero %s." % hero.hero_id
		for stat in HeroCatalog.STATS:
			if not _nonnegative(stats[stat]):
				return "Invalid derived stat %s for Hero %s." % [stat, hero.hero_id]
	if not is_finite(_compute(party, balancing)):
		return "Party Power exceeds the finite numeric range."
	return ""


static func compute_party_power(party: PartyData, balancing: BalancingConfig) -> float:
	if not validation_error(party, balancing).is_empty():
		return NAN
	return _compute(party, balancing)


static func _nonnegative(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0.0


static func _compute(party: PartyData, balancing: BalancingConfig) -> float:
	var total := 0.0
	var members := party.heroes()
	for hero in members:
		var stats := HeroStats.compute_derived_stats(hero)
		total += hero.level * balancing.party_power_level_weight
		for stat in HeroCatalog.STATS:
			total += float(stats[stat]) * float(balancing.party_power_stat_weights[stat])
	total *= members.size() / balancing.party_size_divisor
	if not party.has_front_row_hero():
		total *= balancing.missing_front_row_factor
	return total
