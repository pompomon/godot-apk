class_name BalanceReport
extends RefCounted
## Reproducible, detached trials; sample selection never consults combat outcomes.

const TIERS := {
	"below": Vector2(0.60, 0.80),
	"at": Vector2(0.95, 1.05),
	"above": Vector2(1.05, 1.15),
}
const MAX_TRIALS := 2000
const POPULATION_SIZE := 16000
const Simulator = preload("res://autoload/CombatSimulator.gd")


static func generate_party(seed_value: int) -> PartyData:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var classes := HeroCatalog.classes()
	for index in range(classes.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var swap := classes[index]
		classes[index] = classes[other]
		classes[other] = swap
	var party := PartyData.new()
	var members := rng.randi_range(1, 4)
	var level := rng.randi_range(1, 12)
	for index in range(members):
		var pool: Array[HeroClassResource] = [classes[index]]
		var hero := HeroGenerator.generate_hero(
			"hero-%d" % (index + 1), rng.randi(), pool, HeroCatalog.traits(), level)
		if hero == null:
			return null
		if rng.randi_range(0, 1) == 1:
			var weapons := [ItemCatalog.SHORT_SWORD, ItemCatalog.HUNTING_BOW, ItemCatalog.APPRENTICE_STAFF]
			hero.equipped_weapon = weapons[rng.randi_range(0, weapons.size() - 1)]
		if rng.randi_range(0, 1) == 1:
			var armors := [ItemCatalog.LEATHER_ARMOR, ItemCatalog.CHAINMAIL, ItemCatalog.ROBES]
			hero.equipped_armor = armors[rng.randi_range(0, armors.size() - 1)]
		party.place_hero(index, hero)
	return party


static func run(regions: Array[RegionResource], trials: int, seed_value: int,
		balancing: BalancingConfig) -> Dictionary:
	if trials < 1 or trials > MAX_TRIALS or not ExpeditionCatalog.integer(seed_value):
		return {"error": "Trials must be 1–%d and the seed a JSON-safe nonnegative integer." % MAX_TRIALS}
	if regions.is_empty() or not ExpeditionCatalog.validate_catalog(
			regions, ExpeditionCatalog.events(), ExpeditionCatalog.loot(), balancing):
		return {"error": "Invalid Region catalog or balancing."}
	var samples := {}
	for region in regions:
		if region.recommended_party_power <= 0:
			return {"error": "A balance report requires positive recommended Power."}
		samples[String(region.region_id)] = {"below": [], "at": [], "above": []}
	var population_rng := RandomNumberGenerator.new()
	population_rng.seed = seed_value
	var seen_parties := {}
	for index in range(POPULATION_SIZE):
		var party := generate_party(population_rng.randi())
		var power := PartyEvaluator.compute_party_power(party, balancing)
		if not is_finite(power):
			return {"error": "Generated Party has invalid Power."}
		var identity := ""
		for region in regions:
			var ratio := power / float(region.recommended_party_power)
			for tier in TIERS:
				var bounds: Vector2 = TIERS[tier]
				var bucket: Array = samples[String(region.region_id)][tier]
				if ratio >= bounds.x and ratio < bounds.y and bucket.size() < trials:
					if identity.is_empty():
						var snapshot := ExpeditionPartySnapshot.capture(party, true)
						if snapshot == null:
							return {"error": "Could not detach generated Party."}
						identity = JSON.stringify(snapshot.serialize(), "", true, true).sha256_text()
					var bucket_id := "%s/%s" % [region.region_id, tier]
					if not seen_parties.has(bucket_id):
						seen_parties[bucket_id] = {}
					if seen_parties[bucket_id].has(identity):
						continue
					seen_parties[bucket_id][identity] = true
					bucket.append({"party": party, "power": power})
	for region in regions:
		for tier in TIERS:
			var bucket: Array = samples[String(region.region_id)][tier]
			if bucket.size() < trials:
				return {"error": "Insufficient distinct Parties for %s/%s: %d of %d required." % [
					region.region_id, tier, bucket.size(), trials]}
	var simulator := Simulator.new()
	var rows: Array = []
	for region in regions:
		for tier in TIERS:
			var bucket: Array = samples[String(region.region_id)][tier]
			var row := _trials(region, tier, bucket, trials, seed_value, balancing, simulator)
			if row.has("error"):
				simulator.free()
				return row
			rows.append(row)
	simulator.free()
	return {"seed": seed_value, "trials_per_tier": trials, "population": POPULATION_SIZE,
		"sampling": "1–4 distinct classes, levels 1–12, independently optional starter weapon/armor; front slots first",
		"rows": rows}


static func _trials(region: RegionResource, tier: String, samples: Array,
		trials: int, seed_value: int, balancing: BalancingConfig, simulator: Node) -> Dictionary:
	var groups: Array[EnemyGroupResource] = []
	var weights: Array[float] = []
	for entry in region.encounter_pool:
		if entry.kind == "Combat" and entry.weight > 0.0:
			groups.append(CombatCatalog.enemy_group_by_id(String(entry.content_id)))
			weights.append(entry.weight)
	if groups.is_empty():
		return {"error": "No positive-weight Combat encounters in %s." % region.region_id}
	var outcomes := {"VICTORY": 0, "RETREAT": 0, "DEFEAT": 0}
	var per_group := {}
	var min_power := INF
	var max_power := 0.0
	var min_members := 4
	var max_members := 0
	var completed := 0
	var resting_heroes := 0
	var participating_heroes := 0
	var max_journal_bytes := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for index in range(trials):
		var sample: Dictionary = samples[index]
		var party: PartyData = sample.party
		var snapshot := ExpeditionPartySnapshot.capture(party, true)
		if snapshot == null:
			return {"error": "Could not detach sampled Party."}
		var group := groups[ExpeditionGenerator._weighted_index(weights, rng)]
		var combat_seed := rng.randi()
		var result: Dictionary = simulator.resolve_combat(
			snapshot, snapshot.hero_states(), group, combat_seed, balancing)
		if result.has("error") or not outcomes.has(result.get("outcome", "")):
			return {"error": "Combat trial failed: %s" % result}
		outcomes[result.outcome] += 1
		var id := String(group.group_id)
		if not per_group.has(id):
			per_group[id] = {"trials": 0, "victories": 0,
				"outcomes": {"VICTORY": 0, "RETREAT": 0, "DEFEAT": 0}}
		per_group[id].trials += 1
		per_group[id].victories += 1 if result.outcome == "VICTORY" else 0
		per_group[id].outcomes[result.outcome] += 1
		min_power = minf(min_power, sample.power)
		max_power = maxf(max_power, sample.power)
		min_members = mini(min_members, party.heroes().size())
		max_members = maxi(max_members, party.heroes().size())
		var expedition := ExpeditionGenerator.generate(region, party, rng.randi(),
			region.duration_options_seconds[0], 1000, balancing)
		if expedition == null:
			return {"error": "Full Expedition generation failed for %s." % region.region_id}
		completed += 1 if expedition.terminal_step_index == -1 else 0
		var final_states := expedition.final_hero_states()
		for member in expedition.party_snapshot.slots.values():
			if member == null:
				continue
			participating_heroes += 1
			var state: Dictionary = final_states[member.hero_id]
			if state.status == HeroData.HeroStatus.WOUNDED or (
					state.hp * 100 <= member.derived_stats.MaxHP * expedition.rest_hp_percent):
				resting_heroes += 1
		var bytes := JSON.stringify(expedition.serialize(), "\t", true, true).to_utf8_buffer().size()
		max_journal_bytes = maxi(max_journal_bytes, bytes)
	var rate := float(outcomes.VICTORY) / trials
	return {"region": String(region.region_id), "tier": tier,
		"recommended_power": region.recommended_party_power,
		"power_min": min_power, "power_max": max_power,
		"members_min": min_members, "members_max": max_members,
		"distinct_parties": trials, "trials": trials,
		"outcomes": outcomes, "victory_rate": rate, "target_met": target_met(tier, rate),
		"victory_rate_95_ci": victory_interval(outcomes.VICTORY, trials),
		"enemy_groups": per_group, "full_expedition_completion_rate": float(completed) / trials,
		"full_expedition_resting_heroes": resting_heroes,
		"full_expedition_participating_heroes": participating_heroes,
		"max_expedition_bytes": max_journal_bytes}


static func target_met(tier: String, rate: float) -> bool:
	return rate < 0.5 if tier == "below" else rate >= 0.70 and rate <= 0.85


static func band_margin(tier: String, rate: float) -> float:
	# Diagnostic distance inside the target band; target_met remains the gate.
	return 0.5 - rate if tier == "below" else minf(rate - 0.70, 0.85 - rate)


static func aggregate(reports: Array) -> Dictionary:
	# Sums raw counts from distinct seeds; per-seed rates are never averaged.
	var seeds: Array = []
	var order: Array = []
	var totals := {}
	var trials_per_tier := 0
	for report in reports:
		if not report is Dictionary or report.has("error") or not report.get("rows") is Array \
				or not ExpeditionCatalog.integer(report.get("seed")) or seeds.has(report.seed) \
				or not ExpeditionCatalog.integer(report.get("trials_per_tier"), 1) \
				or (not seeds.is_empty() and report.trials_per_tier != trials_per_tier):
			return {"error": "Aggregation requires valid reports with distinct seeds and equal trials."}
		seeds.append(report.seed)
		trials_per_tier = report.trials_per_tier
		var keys: Array = []
		for row in report.rows:
			var key := "%s/%s" % [row.region, row.tier]
			keys.append(key)
			if seeds.size() == 1:
				order.append(key)
				totals[key] = {"region": row.region, "tier": row.tier,
					"recommended_power": row.recommended_power, "power_min": INF, "power_max": 0.0,
					"members_min": 4, "members_max": 0, "trials": 0, "completed": 0,
					"outcomes": {"VICTORY": 0, "RETREAT": 0, "DEFEAT": 0}, "seed_outcomes": [],
					"enemy_groups": {}, "full_expedition_resting_heroes": 0,
					"full_expedition_participating_heroes": 0, "max_expedition_bytes": 0}
			elif not totals.has(key) or totals[key].recommended_power != row.recommended_power:
				return {"error": "Aggregated reports must contain identical Region rows."}
			if row.trials != trials_per_tier:
				return {"error": "Every aggregated row must use the report's trials per tier."}
			var total: Dictionary = totals[key]
			var trials: int = row.trials
			total.power_min = minf(total.power_min, row.power_min)
			total.power_max = maxf(total.power_max, row.power_max)
			total.members_min = mini(total.members_min, row.members_min)
			total.members_max = maxi(total.members_max, row.members_max)
			total.trials += trials
			total.completed += roundi(float(row.full_expedition_completion_rate) * trials)
			for outcome in total.outcomes:
				total.outcomes[outcome] += int(row.outcomes[outcome])
			total.seed_outcomes.append(row.outcomes.duplicate())
			for id in row.enemy_groups:
				var group: Dictionary = row.enemy_groups[id]
				if not total.enemy_groups.has(id):
					total.enemy_groups[id] = {"trials": 0, "victories": 0,
						"outcomes": {"VICTORY": 0, "RETREAT": 0, "DEFEAT": 0}}
				total.enemy_groups[id].trials += int(group.trials)
				total.enemy_groups[id].victories += int(group.victories)
				for outcome in total.enemy_groups[id].outcomes:
					total.enemy_groups[id].outcomes[outcome] += int(group.outcomes[outcome])
			total.full_expedition_resting_heroes += int(row.full_expedition_resting_heroes)
			total.full_expedition_participating_heroes += int(row.full_expedition_participating_heroes)
			total.max_expedition_bytes = maxi(total.max_expedition_bytes, row.max_expedition_bytes)
		if keys != order:
			return {"error": "Aggregated reports must contain identical Region rows."}
	if order.is_empty():
		return {"error": "Aggregation requires at least one report with rows."}
	var rows: Array = []
	for key in order:
		var total: Dictionary = totals[key]
		var trials: int = total.trials
		var victories: int = total.outcomes.VICTORY
		var rate := float(victories) / trials
		for group in total.enemy_groups.values():
			group.victory_rate = float(group.victories) / group.trials
		rows.append({"region": total.region, "tier": total.tier,
			"recommended_power": total.recommended_power,
			"power_min": total.power_min, "power_max": total.power_max,
			"members_min": total.members_min, "members_max": total.members_max,
			"trials": trials, "outcomes": total.outcomes, "seed_outcomes": total.seed_outcomes,
			"victory_rate": rate, "target_met": target_met(total.tier, rate),
			"band_margin": band_margin(total.tier, rate),
			"victory_rate_95_ci": victory_interval(victories, trials),
			"enemy_groups": total.enemy_groups,
			"full_expedition_completion_rate": float(total.completed) / trials,
			"full_expedition_resting_heroes": total.full_expedition_resting_heroes,
			"full_expedition_participating_heroes": total.full_expedition_participating_heroes,
			"max_expedition_bytes": total.max_expedition_bytes})
	return {"seeds": seeds, "trials_per_tier": trials_per_tier, "population": POPULATION_SIZE,
		"rows": rows}


static func victory_interval(victories: int, trials: int) -> Array[float]:
	# Wilson 95% interval describes sampling uncertainty, not target acceptance.
	if trials <= 0 or victories < 0 or victories > trials:
		return []
	var rate := float(victories) / trials
	var z_squared := 1.959963984540054 * 1.959963984540054
	var denominator := 1.0 + z_squared / trials
	var center := (rate + z_squared / (2.0 * trials)) / denominator
	var margin := sqrt(z_squared * (rate * (1.0 - rate) / trials
		+ z_squared / (4.0 * trials * trials))) / denominator
	return [maxf(0.0, center - margin), minf(1.0, center + margin)]
