extends GutTest

const BALANCING: BalancingConfig = preload("res://data/balancing/default_balancing.tres")


func _party(level: int = 3) -> PartyData:
	var party := PartyData.new()
	var classes := HeroCatalog.classes()
	for index in range(classes.size()):
		var hero := HeroGenerator.generate_hero(
			"hero-%d" % (index + 1), 100 + index, [classes[index]], HeroCatalog.traits(), level)
		party.place_hero(index, hero)
	return party


func _full_snapshot(run: ExpeditionData, party: PartyData) -> Dictionary:
	var roster: Array = []
	for hero in party.heroes():
		var entry := SaveManager._serialize_hero(hero)
		entry.status = "ON_EXPEDITION"
		roster.append(entry)
	for number in range(5, 21):
		roster.append(SaveManager._serialize_hero(HeroGenerator.generate_hero(
			"hero-%d" % number, number, HeroCatalog.classes(), HeroCatalog.traits())))
	var offers: Array = []
	for number in range(21, 24):
		offers.append(SaveManager._serialize_hero(HeroGenerator.generate_hero(
			"hero-%d" % number, number, HeroCatalog.classes(), HeroCatalog.traits())))
	var inventory: Array = []
	inventory.resize(SaveManager.MAX_INVENTORY_ITEMS)
	inventory.fill("apprentice_staff")
	return {
		"save_version": SaveManager.SAVE_VERSION,
		"roster": roster, "recruitment_offers": offers, "gold": 400,
		"inventory": inventory, "unlocked_regions": ["green_hollow", "ashen_reach", "frostbound_pass"],
		"roster_capacity": 20, "next_hero_id": 24,
		"recruitment_seed": 21, "recruitment_sequence": 0, "offer_seeds": [21, 22, 23],
		"current_party": null, "expedition_seed": 1, "expedition_sequence": 1,
		"expedition": run.serialize(),
	}


func test_expanded_catalogs_are_valid_and_preserve_original_order() -> void:
	assert_true(ExpeditionCatalog.validate_catalog(
		ExpeditionCatalog.regions(), ExpeditionCatalog.events(), ExpeditionCatalog.loot(), BALANCING))
	assert_true(CombatCatalog.validate_catalog(CombatCatalog.skills(), CombatCatalog.enemy_groups(), BALANCING))
	assert_true(HeroCatalog.validate_catalog(HeroCatalog.classes(), HeroCatalog.traits()))
	assert_eq(ExpeditionCatalog.regions(), [
		ExpeditionCatalog.GREEN_HOLLOW, ExpeditionCatalog.ASHEN_REACH, ExpeditionCatalog.FROSTBOUND_PASS])
	assert_eq(ExpeditionCatalog.events().size(), 15)
	assert_eq(ExpeditionCatalog.loot().size(), 3)
	assert_eq(CombatCatalog.enemy_groups().size(), 6)
	assert_eq(CombatCatalog.skills().size(), 4)
	assert_eq(HeroCatalog.traits().size(), 8)
	var original_events := ["green_hollow_bridge", "green_hollow_spring", "green_hollow_caravan",
		"green_hollow_fireflies", "green_hollow_ruins"]
	for index in range(original_events.size()):
		assert_eq(String(ExpeditionCatalog.EVENTS[index].event_id), original_events[index])
	assert_eq(HeroCatalog.traits().slice(0, 4), [
		HeroCatalog.HEARTY, HeroCatalog.KEEN_EYED, HeroCatalog.LIGHTFOOTED, HeroCatalog.STUDIOUS])
	for region in ExpeditionCatalog.regions():
		assert_eq(ExpeditionCatalog.region_by_id(String(region.region_id)), region)
	for event in ExpeditionCatalog.events():
		assert_eq(ExpeditionCatalog.event_by_id(String(event.event_id)), event)
	for loot in ExpeditionCatalog.loot():
		assert_eq(ExpeditionCatalog.loot_by_id(String(loot.loot_id)), loot)


func test_regions_have_distinct_positive_encounter_mixes_and_authored_events() -> void:
	var all_content_ids := {}
	var all_enemy_ids := {}
	var mixes: Array = []
	var event_titles := {}
	var event_descriptions := {}
	for region in ExpeditionCatalog.regions():
		var event_ids := {}
		var enemies := {}
		var loot_ids := {}
		var mix := {"Event": 0.0, "Combat": 0.0, "Loot": 0.0}
		for entry in region.encounter_pool:
			assert_gt(entry.weight, 0.0)
			assert_false(all_content_ids.has(entry.content_id), "Each Region owns its encounters.")
			all_content_ids[entry.content_id] = true
			mix[entry.kind] += entry.weight * float(BALANCING.encounter_kind_weight_multipliers[entry.kind])
			match entry.kind:
				"Event":
					var event := ExpeditionCatalog.event_by_id(String(entry.content_id))
					assert_not_null(event)
					if event == null:
						continue
					event_ids[entry.content_id] = true
					assert_false(event_titles.has(event.display_name))
					assert_false(event_descriptions.has(event.description))
					event_titles[event.display_name] = true
					event_descriptions[event.description] = true
				"Loot":
					loot_ids[entry.content_id] = true
				"Combat":
					var group := CombatCatalog.enemy_group_by_id(String(entry.content_id))
					assert_not_null(group)
					if group == null:
						continue
					enemies[entry.content_id] = true
					for enemy in group.enemies:
						assert_false(all_enemy_ids.has(enemy.combatant_id), "Combatant IDs must not collide.")
						all_enemy_ids[enemy.combatant_id] = true
		assert_gte(event_ids.size(), 5, region.display_name)
		assert_gte(enemies.size(), 1, region.display_name)
		assert_eq(loot_ids.size(), 1, region.display_name)
		var total: float = mix.Event + mix.Combat + mix.Loot
		var normalized := [mix.Event / total, mix.Combat / total, mix.Loot / total]
		assert_false(normalized in mixes, "Encounter-kind odds must distinguish each Region.")
		mixes.append(normalized)
	assert_eq(ExpeditionCatalog.ASHEN_REACH.duration_options_seconds, [120])
	assert_eq(ExpeditionCatalog.FROSTBOUND_PASS.duration_options_seconds, [180])
	for region in ExpeditionCatalog.regions():
		assert_eq(region.travel_step_count, 5)
	assert_eq(ExpeditionCatalog.GREEN_HOLLOW.unlock_condition, {"kind": "always"})
	assert_eq(ExpeditionCatalog.ASHEN_REACH.unlock_condition, {"kind": "gold", "value": 200})
	assert_eq(ExpeditionCatalog.FROSTBOUND_PASS.unlock_condition, {"kind": "gold", "value": 400})


func test_unlock_condition_validation_has_exact_keys_and_integer_bounds() -> void:
	for condition in [{"kind": "always"}, {"kind": "gold", "value": 1},
			{"kind": "gold", "value": HeroCatalog.MAX_SAFE_INT}]:
		assert_true(ExpeditionCatalog.unlock_condition_valid(condition), str(condition))
		var region: RegionResource = ExpeditionCatalog.ASHEN_REACH.duplicate(true)
		region.unlock_condition = condition
		assert_true(ExpeditionCatalog.validate_region(region, BALANCING))
	for condition in [{}, {"value": 200}, {"kind": null}, {"kind": true},
			{"kind": "always", "value": 1}, {"kind": "gold"},
			{"kind": "gold", "value": 200, "extra": true},
			{"kind": "gold", "value": 200, "region_id": "green_hollow"},
			{"kind": "region_cleared", "region_id": "green_hollow"},
			{"kind": "res://data/regions/ashen_reach.tres"}]:
		assert_false(ExpeditionCatalog.unlock_condition_valid(condition), str(condition))
		var region: RegionResource = ExpeditionCatalog.ASHEN_REACH.duplicate(true)
		region.unlock_condition = condition
		assert_false(ExpeditionCatalog.validate_region(region, BALANCING))
	for value in [null, true, "200", 200.0, 0, -1, 1.5, NAN, INF, -INF, HeroCatalog.MAX_SAFE_INT + 1]:
		assert_false(ExpeditionCatalog.unlock_condition_valid({"kind": "gold", "value": value}), str(value))


func test_all_traits_are_paired_and_new_modifiers_change_derived_stats() -> void:
	var modifier_sets: Array = []
	for hero_trait in HeroCatalog.traits():
		assert_true(HeroCatalog.validate_trait(hero_trait))
		assert_true(hero_trait.flags.is_empty())
		assert_eq(hero_trait.stat_modifiers.size(), 2)
		var bonus := false
		var penalty := false
		for amount in hero_trait.stat_modifiers.values():
			bonus = bonus or amount > 0
			penalty = penalty or amount < 0
		assert_true(bonus, String(hero_trait.trait_id))
		assert_true(penalty, String(hero_trait.trait_id))
		assert_false(hero_trait.stat_modifiers in modifier_sets)
		modifier_sets.append(hero_trait.stat_modifiers)
	for hero_class in HeroCatalog.classes():
		var hero := HeroGenerator.generate_hero("hero-1", 42, [hero_class], [])
		var before := HeroStats.compute_derived_stats(hero)
		for hero_trait in HeroCatalog.traits().slice(4):
			hero.traits.assign([hero_trait])
			var after := HeroStats.compute_derived_stats(hero)
			for stat in HeroCatalog.STATS:
				if hero_trait.stat_modifiers.has(stat):
					assert_eq(int(after[stat]) - int(before[stat]), int(hero_trait.stat_modifiers[stat]),
						"%s: %s changes %s" % [hero_class.class_id, hero_trait.trait_id, stat])
				else:
					assert_eq(after[stat], before[stat])
		hero.traits.clear()


func test_generated_journals_repeat_and_round_trip_without_live_content_mutation() -> void:
	for region in ExpeditionCatalog.regions():
		for seed_value in [3, 42, 12345]:
			var party := _party()
			var duration: int = region.duration_options_seconds[0]
			var step_duration: int = duration / 10
			var first := ExpeditionGenerator.generate(region, party, seed_value, duration, 1000, BALANCING)
			var repeated := ExpeditionGenerator.generate(region, party, seed_value, duration, 1000, BALANCING)
			assert_not_null(first, "%s seed %d" % [region.region_id, seed_value])
			assert_not_null(repeated)
			if first == null or repeated == null:
				continue
			var serialized := JSON.stringify(first.serialize(), "", true, true)
			assert_eq(serialized, JSON.stringify(repeated.serialize(), "", true, true))
			assert_true(ExpeditionData.valid(JSON.parse_string(serialized)))
			assert_eq(first.planned_step_count, 10)
			assert_eq(first.step_duration_seconds, step_duration)
			assert_eq(first.last_revealed_index, -1)
			for index in range(first.steps.size()):
				assert_eq(first.steps[index].kind == ExpeditionStep.StepKind.TRAVEL, index % 2 == 0)
			var local_hero := party.heroes()[0]
			local_hero.level += 1
			local_hero.hero_name = "Changed after dispatch"
			assert_eq(serialized, JSON.stringify(first.serialize(), "", true, true))


func test_full_saves_with_five_combat_pairs_fit_size_limit_without_storage_io() -> void:
	for authored_region in ExpeditionCatalog.regions():
		for encounter in authored_region.encounter_pool:
			if encounter.kind != "Combat":
				continue
			var region: RegionResource = authored_region.duplicate(true)
			region.encounter_pool.assign([encounter])
			for level in [1, 3, 6]:
				var party := _party(level)
				var run := ExpeditionGenerator.generate(
					region, party, 12345, region.duration_options_seconds[0], 1000, BALANCING)
				assert_not_null(run, "%s level %d" % [encounter.content_id, level])
				if run == null:
					continue
				var snapshot := _full_snapshot(run, party)
				assert_true(SaveManager.validate_snapshot(snapshot))
				var serialized := JSON.stringify(snapshot, "\t", true, true)
				assert_lte(serialized.to_utf8_buffer().size(), SaveManager.MAX_SAVE_BYTES,
					"%s level %d full company save" % [encounter.content_id, level])
				var parsed: Variant = JSON.parse_string(serialized)
				assert_true(SaveManager.validate_snapshot(parsed))
