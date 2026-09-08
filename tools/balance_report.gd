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
	for index in range(POPULATION_SIZE):
		var party := generate_party(population_rng.randi())
		var power := PartyEvaluator.compute_party_power(party, balancing)
		if not is_finite(power):
			return {"error": "Generated Party has invalid Power."}
		for region in regions:
			var ratio := power / float(region.recommended_party_power)
			for tier in TIERS:
				var bounds: Vector2 = TIERS[tier]
				var bucket: Array = samples[String(region.region_id)][tier]
				if ratio >= bounds.x and ratio < bounds.y and bucket.size() < trials:
					bucket.append({"party": party, "power": power})
	var simulator := Simulator.new()
	var rows: Array = []
	for region in regions:
		for tier in TIERS:
			var bucket: Array = samples[String(region.region_id)][tier]
			if bucket.size() < mini(trials, 16):
				simulator.free()
				return {"error": "Insufficient generated Parties for %s/%s: %d." % [region.region_id, tier, bucket.size()]}
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
	var max_journal_bytes := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for index in range(trials):
		var sample: Dictionary = samples[index % samples.size()]
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
			per_group[id] = {"trials": 0, "victories": 0}
		per_group[id].trials += 1
		per_group[id].victories += 1 if result.outcome == "VICTORY" else 0
		min_power = minf(min_power, sample.power)
		max_power = maxf(max_power, sample.power)
		min_members = mini(min_members, party.heroes().size())
		max_members = maxi(max_members, party.heroes().size())
		var expedition := ExpeditionGenerator.generate(region, party, rng.randi(),
			region.duration_options_seconds[0], 1000, balancing)
		if expedition == null:
			return {"error": "Full Expedition generation failed for %s." % region.region_id}
		completed += 1 if expedition.terminal_step_index == -1 else 0
		var bytes := JSON.stringify(expedition.serialize(), "\t", true, true).to_utf8_buffer().size()
		max_journal_bytes = maxi(max_journal_bytes, bytes)
	var rate := float(outcomes.VICTORY) / trials
	var in_band := rate < 0.5 if tier == "below" else rate >= 0.70 and rate <= 0.85
	return {"region": String(region.region_id), "tier": tier,
		"recommended_power": region.recommended_party_power,
		"power_min": min_power, "power_max": max_power,
		"members_min": min_members, "members_max": max_members,
		"distinct_parties": mini(samples.size(), trials), "trials": trials,
		"outcomes": outcomes, "victory_rate": rate, "target_met": in_band,
		"enemy_groups": per_group, "full_expedition_completion_rate": float(completed) / trials,
		"max_expedition_bytes": max_journal_bytes}
