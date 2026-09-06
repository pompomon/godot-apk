extends GutTest

const BALANCING: BalancingConfig = preload("res://data/balancing/default_balancing.tres")


func _party() -> PartyData:
	var party := PartyData.new()
	party.place_hero(3, HeroGenerator.generate_hero("hero-1", 42, HeroCatalog.classes(), HeroCatalog.traits()))
	return party


func test_authored_content_is_ordered_allowlisted_and_noncombat() -> void:
	assert_true(ExpeditionCatalog.validate_catalog(
		ExpeditionCatalog.regions(), ExpeditionCatalog.events(), ExpeditionCatalog.loot(), BALANCING))
	assert_eq(ExpeditionCatalog.events().size(), 5)
	assert_eq(ExpeditionCatalog.loot().size(), 1)
	var region := ExpeditionCatalog.GREEN_HOLLOW
	assert_eq(region.duration_options_seconds, [60])
	assert_eq(region.travel_step_count, 5)
	assert_eq(region.unlock_condition, {"kind": "always"})
	assert_null(ExpeditionCatalog.region_by_id("res://data/regions/green_hollow.tres"))
	assert_null(ExpeditionCatalog.event_by_id("missing"))
	assert_null(ExpeditionCatalog.loot_by_id("missing"))
	var duplicates: Array = ExpeditionCatalog.events()
	duplicates.append(duplicates[0])
	assert_false(ExpeditionCatalog.validate_catalog(ExpeditionCatalog.regions(), duplicates, ExpeditionCatalog.loot(), BALANCING))
	assert_false(ExpeditionCatalog.validate_catalog([], ExpeditionCatalog.events(), ExpeditionCatalog.loot(), BALANCING))


func test_invalid_region_counts_durations_pool_payloads_and_configuration() -> void:
	var changes := [
		["travel_step_count", 0], ["travel_step_count", -1], ["travel_step_count", 513],
		["recommended_party_power", -1], ["display_name", ""], ["travel_title", ""],
		["travel_text", ""], ["unlock_condition", {}], ["unlock_condition", {"kind": "gold", "value": 1}],
		["retreat_ends_expedition", true],
	]
	for change in changes:
		var region: RegionResource = ExpeditionCatalog.GREEN_HOLLOW.duplicate(true)
		region.set(change[0], change[1])
		assert_false(ExpeditionCatalog.validate_region(region, BALANCING), str(change))
	for values in [[], [0], [-10], [5], [61], [60, 60], [HeroCatalog.MAX_SAFE_INT + 1]]:
		var region: RegionResource = ExpeditionCatalog.GREEN_HOLLOW.duplicate(true)
		region.duration_options_seconds.assign(values)
		assert_false(ExpeditionCatalog.validate_region(region, BALANCING), str(values))
	for value in [NAN, INF, -INF, -1.0]:
		var region: RegionResource = ExpeditionCatalog.GREEN_HOLLOW.duplicate(true)
		region.encounter_pool[0].weight = value
		assert_false(ExpeditionCatalog.validate_region(region, BALANCING), str(value))
	for kind in ["Combat", "Travel", "", "unknown"]:
		var region: RegionResource = ExpeditionCatalog.GREEN_HOLLOW.duplicate(true)
		region.encounter_pool[0].kind = kind
		assert_false(ExpeditionCatalog.validate_region(region, BALANCING))
	for id in ["", "missing", "res://data/encounters/green_hollow_loot.tres"]:
		var region: RegionResource = ExpeditionCatalog.GREEN_HOLLOW.duplicate(true)
		region.encounter_pool[0].content_id = StringName(id)
		assert_false(ExpeditionCatalog.validate_region(region, BALANCING))
	var empty: RegionResource = ExpeditionCatalog.GREEN_HOLLOW.duplicate(true)
	empty.encounter_pool.clear()
	assert_false(ExpeditionCatalog.validate_region(empty, BALANCING))
	empty.encounter_pool.append(null)
	assert_false(ExpeditionCatalog.validate_region(empty, BALANCING))
	for multiplier in [null, true, "1", -1, NAN, INF]:
		var config: BalancingConfig = BALANCING.duplicate(true)
		config.encounter_kind_weight_multipliers.Loot = multiplier
		assert_false(ExpeditionCatalog.validate_region(ExpeditionCatalog.GREEN_HOLLOW, config))
	var config: BalancingConfig = BALANCING.duplicate(true)
	config.encounter_kind_weight_multipliers.erase("Loot")
	assert_false(ExpeditionCatalog.validate_region(ExpeditionCatalog.GREEN_HOLLOW, config))
	config.encounter_kind_weight_multipliers = {"Loot": 0.0, "Event": 0.0}
	assert_false(ExpeditionCatalog.validate_region(ExpeditionCatalog.GREEN_HOLLOW, config))
	for cap in [0, -1, HeroCatalog.MAX_SAFE_INT + 1]:
		config = BALANCING.duplicate(true)
		config.max_offline_delta_seconds = cap
		assert_false(ExpeditionCatalog.validate_region(ExpeditionCatalog.GREEN_HOLLOW, config))
	assert_null(ExpeditionGenerator.generate(ExpeditionCatalog.GREEN_HOLLOW, _party(), -1, 60, 1000, BALANCING))
	assert_null(ExpeditionGenerator.generate(ExpeditionCatalog.GREEN_HOLLOW, _party(), 1, 61, 1000, BALANCING))
	assert_null(ExpeditionGenerator.generate(ExpeditionCatalog.GREEN_HOLLOW, _party(), 1, 60, HeroCatalog.MAX_SAFE_INT, BALANCING))
	assert_null(ExpeditionGenerator.generate(ExpeditionCatalog.GREEN_HOLLOW, null, 1, 60, 1000, BALANCING))


func test_event_and_loot_validation_rejects_unsupported_and_nonfinite_data() -> void:
	assert_false(ExpeditionCatalog.validate_event(null))
	assert_false(ExpeditionCatalog.validate_loot(null))
	for value in [{}, {"gold": -1}, {"gold": 1.5}, {"gold": true}, {"gold": INF},
			{"gold": NAN}, {"gold": HeroCatalog.MAX_SAFE_INT + 1}, {"gold": 0, "item_ids": []},
			{"xp": 1}, {"gold": Resource.new()}, {"injury": true}]:
		var event: EventResource = ExpeditionCatalog.events()[0].duplicate(true)
		event.outcomes[0].result = value
		assert_false(ExpeditionCatalog.validate_event(event), str(value))
	for value in [-1.0, INF, NAN]:
		var event: EventResource = ExpeditionCatalog.events()[0].duplicate(true)
		event.outcomes[0].weight = value
		assert_false(ExpeditionCatalog.validate_event(event))
	var event: EventResource = ExpeditionCatalog.events()[0].duplicate(true)
	event.outcomes[1].outcome_id = event.outcomes[0].outcome_id
	assert_false(ExpeditionCatalog.validate_event(event))
	event.outcomes.clear()
	assert_false(ExpeditionCatalog.validate_event(event))
	event.outcomes.append(null)
	assert_false(ExpeditionCatalog.validate_event(event))
	event = ExpeditionCatalog.events()[0].duplicate(true)
	for outcome in event.outcomes:
		outcome.weight = 0
	assert_false(ExpeditionCatalog.validate_event(event))
	event = ExpeditionCatalog.events()[0].duplicate(true)
	event.description = "d".repeat(3000)
	event.outcomes[0].journal_text = "j".repeat(2000)
	assert_false(ExpeditionCatalog.validate_event(event), "Combined resolved journal text must fit the saved step boundary.")
	for limits in [[-1, 1], [4, 3], [0, ExpeditionCatalog.MAX_LOOT_GOLD + 1]]:
		var loot: LootResource = ExpeditionCatalog.LOOT.duplicate(true)
		loot.min_gold = limits[0]
		loot.max_gold = limits[1]
		assert_false(ExpeditionCatalog.validate_loot(loot))


func test_loot_only_two_pairs_have_ten_second_slices_and_inclusive_rolls() -> void:
	var region: RegionResource = ExpeditionCatalog.GREEN_HOLLOW.duplicate(true)
	region.travel_step_count = 2
	region.duration_options_seconds.assign([40, 80])
	region.encounter_pool = [region.encounter_pool[0]]
	var minimum_seen := false
	var maximum_seen := false
	for seed_value in range(32):
		var run := ExpeditionGenerator.generate(region, _party(), seed_value, 40, 1000, BALANCING)
		assert_not_null(run)
		assert_eq(run.step_duration_seconds, 10)
		assert_eq(run.steps.size(), 4)
		for index in range(4):
			assert_eq(int(run.steps[index].kind), index % 2)
			if index % 2 == 1:
				var gold := int(run.steps[index].result.gold)
				assert_between(gold, ExpeditionCatalog.LOOT.min_gold, ExpeditionCatalog.LOOT.max_gold)
				minimum_seen = minimum_seen or gold == ExpeditionCatalog.LOOT.min_gold
				maximum_seen = maximum_seen or gold == ExpeditionCatalog.LOOT.max_gold
	assert_true(minimum_seen)
	assert_true(maximum_seen)
	var longer := ExpeditionGenerator.generate(region, _party(), 1, 80, 1000, BALANCING)
	assert_eq(longer.step_duration_seconds, 20)
	assert_eq(longer.steps.size(), 4)
	for entry in region.encounter_pool:
		entry.weight = 0
	assert_null(ExpeditionGenerator.generate(region, _party(), 1, 40, 1000, BALANCING))


func test_effective_kind_multipliers_zero_weights_and_nonfinite_totals() -> void:
	var region: RegionResource = ExpeditionCatalog.GREEN_HOLLOW.duplicate(true)
	var config: BalancingConfig = BALANCING.duplicate(true)
	config.encounter_kind_weight_multipliers = {"Loot": 2.0, "Event": 0.0}
	var run := ExpeditionGenerator.generate(region, _party(), 77, 60, 1000, config)
	assert_not_null(run)
	for index in [1, 3, 5, 7, 9]:
		assert_eq(run.steps[index].kind, ExpeditionStep.StepKind.LOOT)
	region.encounter_pool[0].weight = 0
	assert_false(ExpeditionCatalog.validate_region(region, config))
	config.encounter_kind_weight_multipliers.Event = 1.0
	run = ExpeditionGenerator.generate(region, _party(), 77, 60, 1000, config)
	assert_not_null(run)
	for index in [1, 3, 5, 7, 9]:
		assert_eq(run.steps[index].kind, ExpeditionStep.StepKind.EVENT)
	region.encounter_pool[0].weight = 1.0e308
	config.encounter_kind_weight_multipliers.Loot = 1.0e308
	assert_false(ExpeditionCatalog.validate_region(region, config))
	var event: EventResource = ExpeditionCatalog.events()[0].duplicate(true)
	for outcome in event.outcomes:
		outcome.weight = 1.0e308
	assert_false(ExpeditionCatalog.validate_event(event))
	config = BALANCING.duplicate(true)
	var events := ExpeditionCatalog.events()
	events[0] = event
	assert_false(ExpeditionCatalog.validate_catalog(ExpeditionCatalog.regions(), events, ExpeditionCatalog.loot(), config))


func test_exact_seeded_selection_precedes_all_outcome_rolls_and_is_byte_identical() -> void:
	var party := _party()
	var first := ExpeditionGenerator.generate(ExpeditionCatalog.GREEN_HOLLOW, party, 12345, 60, 1000, BALANCING)
	assert_not_null(first)
	var signature: Array = []
	for index in [1, 3, 5, 7, 9]:
		var step := first.steps[index].serialize()
		signature.append([step.content_id, step.outcome_id, step.result.gold])
	var expected := [
		["green_hollow_loot", "", 4],
		["green_hollow_caravan", "news", 0],
		["green_hollow_loot", "", 3],
		["green_hollow_fireflies", "lights", 0],
		["green_hollow_ruins", "carvings", 0],
	]
	# Five selection draws are consumed before the first inclusive Loot roll.
	var reference := RandomNumberGenerator.new()
	reference.seed = 12345
	var selected: Array = []
	for pair in range(5):
		var roll := reference.randf() * 7.0
		selected.append(0 if roll < 2.0 else floori(roll) - 1)
	assert_eq(selected, [0, 3, 0, 4, 5])
	assert_eq(reference.randi_range(2, 6), 4)
	for index in range(expected.size()):
		assert_eq(signature[index], expected[index], "Pair %d" % index)
	seed(786)
	var next_global := randi()
	seed(786)
	var second := ExpeditionGenerator.generate(ExpeditionCatalog.GREEN_HOLLOW, party, 12345, 60, 1000, BALANCING)
	assert_eq(randi(), next_global, "Generation never advances global randomness.")
	assert_eq(JSON.stringify(first.serialize(), "", true, true), JSON.stringify(second.serialize(), "", true, true))
	assert_eq(first.last_revealed_index, -1)
	assert_eq(first.terminal_step_index, -1)
	assert_eq(first.effective_end_timestamp, 1060)
	assert_eq(first.step_duration_seconds, 6)
	assert_eq(first.credited_elapsed_seconds, 0)


func test_snapshot_and_resolved_content_are_detached_from_roster_and_resources() -> void:
	var party := _party()
	var hero := party.heroes()[0]
	hero.hero_class = hero.hero_class.duplicate(true)
	for index in range(hero.traits.size()):
		hero.traits[index] = hero.traits[index].duplicate(true)
	var region: RegionResource = ExpeditionCatalog.GREEN_HOLLOW.duplicate(true)
	var run := ExpeditionGenerator.generate(region, party, 17, 60, 1000, BALANCING)
	var original := run.serialize()
	var member: Dictionary = run.party_snapshot.slots.BACK_RIGHT
	assert_eq(member.derived_stats, HeroStats.compute_derived_stats(hero))
	assert_eq(member.attributes, HeroStats.effective_attributes(hero))
	assert_eq(member.basic_attack_target_rule, hero.hero_class.basic_attack_target_rule)
	assert_eq(run.party_snapshot.hero_states()[hero.hero_id].hp, member.derived_stats.MaxHP)
	hero.hero_name = "Changed"
	hero.attributes.MIG = 100
	hero.hero_class.display_name = "Changed class"
	hero.hero_class.basic_attack_target_rule = "AnySlot"
	hero.hero_class.derived_stat_bases.MaxHP = 900
	party.remove_hero(3)
	region.display_name = "Changed Region"
	region.travel_text = "Changed travel"
	run.steps[0].result.gold = 123
	member.derived_stats.MaxHP = 999
	var slots := run.party_snapshot.slots
	slots.BACK_RIGHT = null
	assert_eq(run.serialize(), original)
	assert_eq(run.party_snapshot.slots.BACK_RIGHT.hero_name, original.party_snapshot.BACK_RIGHT.hero_name)
