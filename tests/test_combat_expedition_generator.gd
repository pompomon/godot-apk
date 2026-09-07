extends GutTest

const BALANCING: BalancingConfig = preload("res://data/balancing/default_balancing.tres")
var _original_groups: Array = []
var _original_items: Dictionary
var _original_chance: float


func before_each() -> void:
	var loot := ExpeditionCatalog.LOOT
	_original_items = loot.item_pool.duplicate()
	_original_chance = loot.item_drop_chance
	loot.item_pool = {}
	loot.item_drop_chance = 0.0
	_original_groups.clear()
	for group in CombatCatalog.enemy_groups():
		_original_groups.append({"name": group.display_name, "enemies": group.enemies.duplicate(true)})


func after_each() -> void:
	var loot := ExpeditionCatalog.LOOT
	loot.item_pool = _original_items
	loot.item_drop_chance = _original_chance
	var groups := CombatCatalog.enemy_groups()
	for index in range(groups.size()):
		groups[index].display_name = _original_groups[index].name
		groups[index].enemies.assign(_original_groups[index].enemies)


func _stats(overrides: Dictionary = {}) -> Dictionary:
	var stats := {"MaxHP": 100, "Attack": 10, "MagicPower": 0, "Defense": 0,
		"Evasion": 0.0, "Initiative": 10, "CritChance": 0.0}
	stats.merge(overrides, true)
	return stats


func _hero(id: String = "hero", overrides: Dictionary = {}) -> HeroData:
	var hero := HeroData.new(id)
	hero.hero_name = id
	hero.hero_class = HeroCatalog.class_by_id("ranger").duplicate(true)
	hero.hero_class.active_skill = CombatCatalog.AIMED_SHOT.duplicate(true)
	hero.hero_class.derived_stat_bases = _stats(overrides)
	for attribute in HeroCatalog.ATTRIBUTES:
		hero.attributes[attribute] = 0
		for stat in HeroCatalog.STATS:
			hero.hero_class.derived_stat_attribute_weights[stat][attribute] = 0.0
	return hero


func _party(hero: HeroData = null) -> PartyData:
	var party := PartyData.new()
	party.place_hero(0, _hero() if hero == null else hero)
	return party


func _enemies(group: EnemyGroupResource, overrides: Dictionary = {}, id: String = "enemy") -> void:
	group.enemies.assign([{
		"combatant_id": id, "display_name": id, "row": "Front",
		"basic_attack_target_rule": "FrontRowFirst", "derived_stats": _stats(overrides),
	}])


func _balancing(rounds: int = 20) -> BalancingConfig:
	var config: BalancingConfig = BALANCING.duplicate(true)
	config.max_combat_rounds = rounds
	config.base_hit_chance = 1.0
	config.min_hit_chance = 1.0
	config.max_hit_chance = 1.0
	config.max_crit_chance = 0.0
	return config


func _entry(id: String, kind: String = "Combat", weight: float = 1.0) -> EncounterEntryResource:
	var entry := EncounterEntryResource.new()
	entry.kind = kind
	entry.content_id = StringName(id)
	entry.weight = weight
	return entry


func _region(pairs: int = 5, terminal_retreat: bool = false) -> RegionResource:
	var region: RegionResource = ExpeditionCatalog.GREEN_HOLLOW.duplicate(true)
	region.travel_step_count = pairs
	region.duration_options_seconds.assign([60])
	region.retreat_ends_expedition = terminal_retreat
	region.encounter_pool.assign([_entry("bandit_skirmishers")])
	return region


func _mixed_region() -> RegionResource:
	var region: RegionResource = ExpeditionCatalog.GREEN_HOLLOW.duplicate(true)
	region.encounter_pool.assign([
		_entry("green_hollow_loot", "Loot", 2.0),
		_entry("green_hollow_bridge", "Event"),
		_entry("green_hollow_spring", "Event"),
		_entry("bandit_skirmishers"),
		_entry("forest_wolves"),
		_entry("green_hollow_ruins", "Event"),
	])
	return region


func _gold(run: ExpeditionData) -> int:
	var total := 0
	for step in run.steps:
		total += int(step.result.gold)
	return total


func test_catalog_accepts_allowlisted_combat_and_both_retreat_rules() -> void:
	var production_region := ExpeditionCatalog.GREEN_HOLLOW
	var original_pool := production_region.encounter_pool.duplicate()
	for terminal_retreat in [false, true]:
		var region := _region(5, terminal_retreat)
		region.encounter_pool.append(_entry("forest_wolves"))
		assert_true(ExpeditionCatalog.validate_region(region, BALANCING))
		assert_true(ExpeditionCatalog.validate_catalog(
			[region], ExpeditionCatalog.events(), ExpeditionCatalog.loot(), BALANCING))
	assert_eq(production_region.encounter_pool, original_pool,
		"Controlled Combat fixtures must not change the production pool.")


func test_combat_catalog_preserves_id_enemy_weight_and_numeric_validation() -> void:
	for id in ["", "missing", "green_hollow_loot", "res://data/encounters/bandit_skirmishers.tres"]:
		var region := _region()
		region.encounter_pool[0].content_id = StringName(id)
		assert_false(ExpeditionCatalog.validate_region(region, BALANCING), id)
	for multiplier in [null, true, "1", -1, NAN, INF]:
		var config := _balancing()
		config.encounter_kind_weight_multipliers.Combat = multiplier
		assert_false(ExpeditionCatalog.validate_region(_region(), config), str(multiplier))
	var config := _balancing()
	config.encounter_kind_weight_multipliers.erase("Combat")
	assert_false(ExpeditionCatalog.validate_region(_region(), config))
	config.encounter_kind_weight_multipliers.Combat = 0.0
	assert_false(ExpeditionCatalog.validate_region(_region(), config))
	for value in [-1.0, NAN, INF, 0.0]:
		var region := _region()
		region.encounter_pool[0].weight = value
		assert_false(ExpeditionCatalog.validate_region(region, BALANCING), str(value))
	var overflow := _region()
	overflow.encounter_pool[0].weight = 1.0e308
	config.encounter_kind_weight_multipliers.Combat = 1.0e308
	assert_false(ExpeditionCatalog.validate_region(overflow, config))
	for hp in [0, -1, 1.5, true, INF, HeroCatalog.MAX_SAFE_INT + 1]:
		_enemies(CombatCatalog.BANDIT_SKIRMISHERS, {"MaxHP": hp})
		assert_false(ExpeditionCatalog.validate_region(_region(), BALANCING), str(hp))
		assert_null(ExpeditionGenerator.generate(_region(), _party(), 1, 60, 1000, BALANCING))
	var group := CombatCatalog.BANDIT_SKIRMISHERS
	_enemies(group)
	assert_true(ExpeditionCatalog.validate_region(_region(), BALANCING))
	group.enemies.clear()
	assert_false(ExpeditionCatalog.validate_region(_region(), BALANCING))
	assert_null(ExpeditionGenerator.generate(_region(), _party(), 1, 60, 1000, BALANCING))


func test_skills_and_combat_configuration_are_required_only_for_selected_combat() -> void:
	var hero := _hero()
	hero.hero_class.active_skill = null
	var party := _party(hero)
	var config := _balancing(0)
	var region := _mixed_region()
	region.travel_step_count = 1
	var run := ExpeditionGenerator.generate(region, party, 12345, 60, 1000, config)
	assert_not_null(run, "The one selected encounter is Loot despite positive Combat pool weights.")
	if run == null:
		return
	assert_eq(run.steps[1].kind, ExpeditionStep.StepKind.LOOT)
	assert_false(run.party_snapshot.slots.FRONT_LEFT.has("active_skill"))
	region.travel_step_count = 5
	config.encounter_kind_weight_multipliers.Combat = 0.0
	run = ExpeditionGenerator.generate(region, party, 12345, 60, 1000, config)
	assert_not_null(run, "Zero-weight Combat must not require skills or combat balancing.")
	if run != null:
		assert_false(run.party_snapshot.slots.FRONT_LEFT.has("active_skill"))
	config.encounter_kind_weight_multipliers.Combat = 1.0
	assert_null(ExpeditionGenerator.generate(region, party, 12345, 60, 1000, _balancing()))
	hero.hero_class.active_skill = CombatCatalog.AIMED_SHOT.duplicate(true)
	hero.hero_class.active_skill.target_rule = "Self"
	assert_null(ExpeditionGenerator.generate(region, party, 12345, 60, 1000, _balancing()))


func test_exact_mixed_selection_precedes_resolution_and_combat_uses_same_rng_stream() -> void:
	_enemies(CombatCatalog.BANDIT_SKIRMISHERS, {"MaxHP": 200, "Attack": 4}, "bandit")
	_enemies(CombatCatalog.FOREST_WOLVES, {"MaxHP": 200, "Attack": 3}, "wolf")
	var party := _party(_hero("hero", {"MaxHP": 1000, "Evasion": 0.13, "CritChance": 0.17}))
	var region := _mixed_region()
	var config := _balancing(2)
	config.base_hit_chance = 0.8
	config.min_hit_chance = 0.5
	config.max_hit_chance = 0.99
	config.max_crit_chance = 0.5
	var run := ExpeditionGenerator.generate(region, party, 12345, 60, 1000, config)
	assert_not_null(run)
	if run == null:
		return
	var reference := RandomNumberGenerator.new()
	reference.seed = 12345
	var selected: Array = []
	for pair in range(5):
		var roll := reference.randf() * 7.0
		selected.append(0 if roll < 2.0 else floori(roll) - 1)
	assert_eq(selected, [0, 3, 0, 4, 5])
	assert_eq(run.steps[1].result.gold, reference.randi_range(2, 6))
	var snapshot := ExpeditionPartySnapshot.capture(party, true)
	var expected_first := CombatEngine.resolve_combat(
		snapshot, snapshot.hero_states(), CombatCatalog.BANDIT_SKIRMISHERS, reference.randi(), config)
	assert_false(expected_first.has("error"))
	assert_eq(run.steps[3].result, expected_first)
	assert_eq(run.steps[5].result.gold, reference.randi_range(2, 6))
	var expected_second := CombatEngine.resolve_combat(
		snapshot, expected_first.final_hero_states, CombatCatalog.FOREST_WOLVES, reference.randi(), config)
	assert_eq(run.steps[7].result, expected_second)
	var ruins := ExpeditionCatalog.event_by_id("green_hollow_ruins")
	var total := 0.0
	for outcome in ruins.outcomes:
		total += outcome.weight
	var roll := reference.randf() * total
	var expected_outcome: EventOutcomeResource = null
	for outcome in ruins.outcomes:
		roll -= outcome.weight
		if roll < 0.0:
			expected_outcome = outcome
			break
	assert_eq(run.steps[9].serialize().outcome_id, String(expected_outcome.outcome_id))
	var expected_reward := expected_outcome.result.duplicate(true)
	expected_reward["item_ids"] = expected_reward.get("item_ids", [])
	assert_eq(run.steps[9].result, expected_reward)
	var ids: Array = []
	for index in [1, 3, 5, 7, 9]:
		ids.append(run.steps[index].content_id)
	assert_eq(ids, ["green_hollow_loot", "bandit_skirmishers", "green_hollow_loot", "forest_wolves", "green_hollow_ruins"])
	for index in [3, 7]:
		var step := run.steps[index]
		assert_eq(step.kind, ExpeditionStep.StepKind.COMBAT)
		assert_eq(step.serialize().outcome_id, step.result.outcome)
		assert_eq(step.result.gold, 0)
		assert_false(step.title.is_empty())
		assert_false(step.journal_text.is_empty())
	seed(786)
	var next_global := randi()
	seed(786)
	var repeated := ExpeditionGenerator.generate(region, party, 12345, 60, 1000, config)
	assert_eq(randi(), next_global, "Combat generation must not advance global randomness.")
	assert_eq(JSON.stringify(run.serialize(), "", true, true), JSON.stringify(repeated.serialize(), "", true, true))
	assert_eq(run.final_hero_states(), expected_second.final_hero_states)
	assert_eq(run.planned_step_count, 10)
	assert_eq(run.terminal_step_index, -1)
	assert_eq(run.effective_end_timestamp, 1060)


func test_sequential_combats_carry_complete_states_by_id_without_reviving_or_healing() -> void:
	_enemies(CombatCatalog.BANDIT_SKIRMISHERS, {"MaxHP": 10, "Attack": 12, "Initiative": 20})
	var party := _party(_hero("z-fallen", {"MaxHP": 10}))
	party.place_hero(3, _hero("a-survivor", {"MaxHP": 40}))
	var run := ExpeditionGenerator.generate(_region(3), party, 42, 60, 1000, _balancing())
	assert_not_null(run)
	if run == null:
		return
	assert_eq(run.steps.size(), 6)
	var survivor_hp := [40, 28, 16]
	for pair in range(3):
		var combat := run.steps[pair * 2 + 1].result
		assert_eq(combat.outcome, "VICTORY")
		assert_eq(combat.final_hero_states, {
			"z-fallen": {"hp": 0, "status": HeroData.HeroStatus.WOUNDED},
			"a-survivor": {"hp": survivor_hp[pair], "status": HeroData.HeroStatus.IDLE},
		})
		if pair > 0:
			for round_entry in combat.rounds:
				for action in round_entry.actions:
					assert_ne(action.actor_id, "z-fallen")
					assert_ne(action.target_id, "z-fallen")
	assert_eq(run.final_hero_states(), run.steps[5].result.final_hero_states)
	assert_true(ExpeditionData.valid(run.serialize()))
	assert_eq(run.party_snapshot.hero_states()["a-survivor"].hp, 40)
	assert_eq(party.heroes()[0].status, HeroData.HeroStatus.IDLE)


func _assert_terminal(run: ExpeditionData, outcome: String, terminal_retreat: bool) -> void:
	assert_not_null(run)
	if run == null:
		return
	assert_eq(run.steps.size(), 4, "Later selected encounters and rewards are removed.")
	assert_eq(run.steps[3].result.outcome, outcome)
	assert_eq(run.terminal_step_index, 3)
	assert_eq(run.planned_step_count, 10)
	assert_eq(run.retreat_ends_expedition, terminal_retreat)
	assert_eq(run.duration_seconds, 60)
	assert_eq(run.step_duration_seconds, 6)
	assert_eq(run.effective_end_timestamp, 1024)
	assert_eq(_gold(run), 4, "Only the Loot before the terminal Combat remains.")
	assert_eq(run.last_revealed_index, -1)
	assert_eq(run.display_step_count(), 10)
	assert_eq(run.seconds_remaining(), 60)
	var encoded := JSON.stringify(run.serialize(), "", true, true)
	var decoded: Dictionary = JSON.parse_string(encoded)
	assert_true(ExpeditionData.valid(decoded))
	var restored := ExpeditionData.new(decoded)
	assert_eq(JSON.stringify(restored.serialize(), "", true, true), encoded)
	assert_eq(restored.step_duration_seconds, 6)
	decoded.step_duration_seconds = 15
	assert_false(ExpeditionData.valid(decoded), "Truncation must not reslice the planned duration.")
	assert_eq(run.step_duration_seconds, 6)


func test_defeat_always_truncates_later_rewards_with_original_frozen_duration() -> void:
	_enemies(CombatCatalog.BANDIT_SKIRMISHERS, {"MaxHP": 1000, "Attack": 200, "Initiative": 100})
	for terminal_retreat in [false, true]:
		var region := _mixed_region()
		region.retreat_ends_expedition = terminal_retreat
		var run := ExpeditionGenerator.generate(region, _party(), 12345, 60, 1000, _balancing())
		_assert_terminal(run, "DEFEAT", terminal_retreat)
		if run == null:
			continue
		assert_eq(run.final_hero_states(), {"hero": {"hp": 0, "status": HeroData.HeroStatus.WOUNDED}})
		region.retreat_ends_expedition = not terminal_retreat
		region.travel_step_count = 2
		region.duration_options_seconds.assign([120])
		assert_eq(run.retreat_ends_expedition, terminal_retreat)
		assert_eq(run.planned_step_count, 10)
		assert_eq(run.step_duration_seconds, 6)
		assert_true(ExpeditionData.valid(run.serialize()))


func test_terminal_retreat_truncates_later_rewards_without_wounding_survivors() -> void:
	_enemies(CombatCatalog.BANDIT_SKIRMISHERS, {"MaxHP": 1000, "Attack": 3})
	var region := _mixed_region()
	region.retreat_ends_expedition = true
	var run := ExpeditionGenerator.generate(region, _party(), 12345, 60, 1000, _balancing(1))
	_assert_terminal(run, "RETREAT", true)
	if run != null:
		assert_eq(run.final_hero_states(), {"hero": {"hp": 97, "status": HeroData.HeroStatus.IDLE}})


func test_nonterminal_retreat_continues_to_later_rewards_and_carries_injured_hp() -> void:
	_enemies(CombatCatalog.BANDIT_SKIRMISHERS, {"MaxHP": 1000, "Attack": 3}, "bandit")
	_enemies(CombatCatalog.FOREST_WOLVES, {"MaxHP": 1000, "Attack": 3}, "wolf")
	var run := ExpeditionGenerator.generate(_mixed_region(), _party(), 12345, 60, 1000, _balancing(1))
	assert_not_null(run)
	if run == null:
		return
	assert_eq(run.steps.size(), 10)
	assert_eq(run.planned_step_count, 10)
	assert_eq(run.terminal_step_index, -1)
	assert_eq(run.effective_end_timestamp, 1060)
	assert_eq(run.step_duration_seconds, 6)
	assert_false(run.retreat_ends_expedition)
	assert_eq(run.steps[3].result.outcome, "RETREAT")
	assert_eq(run.steps[3].result.final_hero_states.hero.hp, 97)
	assert_eq(run.steps[7].result.outcome, "RETREAT")
	assert_eq(run.final_hero_states(), {"hero": {"hp": 94, "status": HeroData.HeroStatus.IDLE}})
	assert_gt(_gold(run), 4)
	assert_true(ExpeditionData.valid(run.serialize()))


func test_invalid_combat_configuration_aborts_instead_of_fabricating_an_outcome() -> void:
	var party := _party()
	for change in [
			["max_combat_rounds", 0], ["max_combat_rounds", 101],
			["base_hit_chance", NAN], ["min_hit_chance", 2.0],
			["basic_attack_damage_multiplier", -1.0],
			["skill_damage_multipliers", {}], ["skill_damage_multipliers", {"aimed_shot": true}],
			["skill_damage_multipliers", {"aimed_shot": HeroCatalog.MAX_SAFE_INT}]]:
		var config := _balancing()
		config.set(change[0], change[1])
		var snapshot := ExpeditionPartySnapshot.capture(party, true)
		var result := CombatEngine.resolve_combat(
			snapshot, snapshot.hero_states(), CombatCatalog.BANDIT_SKIRMISHERS, 1, config)
		assert_eq(result.keys(), ["error"], str(change))
		assert_null(ExpeditionGenerator.generate(_region(), party, 1, 60, 1000, config), str(change))


func test_invalid_simulator_input_aborts_the_whole_generated_journal() -> void:
	_enemies(CombatCatalog.BANDIT_SKIRMISHERS, {}, "hero")
	assert_true(ExpeditionCatalog.validate_region(_mixed_region(), BALANCING))
	var party := _party()
	var snapshot := ExpeditionPartySnapshot.capture(party, true)
	var result := CombatEngine.resolve_combat(
		snapshot, snapshot.hero_states(), CombatCatalog.BANDIT_SKIRMISHERS, 1, BALANCING)
	assert_eq(result.keys(), ["error"], "The catalog is valid but Hero/enemy IDs collide.")
	assert_null(ExpeditionGenerator.generate(_mixed_region(), party, 12345, 60, 1000, BALANCING))
	assert_eq(party.heroes()[0].status, HeroData.HeroStatus.IDLE)


func test_generation_never_mutates_inputs_and_freezes_json_safe_combat_values() -> void:
	_enemies(CombatCatalog.BANDIT_SKIRMISHERS, {"MaxHP": 1000, "Attack": 3})
	var hero := _hero("hero", {"Evasion": 0.13, "CritChance": 0.17})
	hero.status = HeroData.HeroStatus.ASSIGNED
	var party := _party(hero)
	var region := _region(3)
	var config := _balancing(1)
	var before := ExpeditionPartySnapshot.capture(party, true).serialize()
	var group := CombatCatalog.BANDIT_SKIRMISHERS
	var original_enemies := group.enemies.duplicate(true)
	var original_multipliers := config.skill_damage_multipliers.duplicate(true)
	var run := ExpeditionGenerator.generate(region, party, 27, 60, 1000, config)
	assert_not_null(run)
	if run == null:
		return
	assert_eq(ExpeditionPartySnapshot.capture(party, true).serialize(), before)
	assert_eq(hero.status, HeroData.HeroStatus.ASSIGNED)
	assert_same(party.slots[0], hero)
	assert_eq(group.enemies, original_enemies)
	assert_eq(config.skill_damage_multipliers, original_multipliers)
	assert_eq(config.max_combat_rounds, 1)
	var original := run.serialize()
	for key in ["Evasion", "CritChance"]:
		var encoded: String = original.party_snapshot.FRONT_LEFT.derived_stats[key]
		assert_eq(encoded.length(), 16)
		assert_eq(encoded.hex_decode().decode_double(0), before.FRONT_LEFT.derived_stats[key].hex_decode().decode_double(0))
	assert_eq(original.party_snapshot.FRONT_LEFT.active_skill, hero.hero_class.active_skill.snapshot())
	hero.hero_name = "Changed"
	hero.hero_class.derived_stat_bases.MaxHP = 1
	hero.hero_class.active_skill.display_name = "Changed skill"
	hero.attributes.MIG = 100
	party.remove_hero(0)
	region.travel_text = "Changed travel"
	region.retreat_ends_expedition = true
	config.max_combat_rounds = 99
	config.skill_damage_multipliers.aimed_shot = 999
	group.display_name = "Changed enemies"
	group.enemies.clear()
	var detached_states := run.final_hero_states()
	detached_states.hero.hp = 1
	var detached_step := run.steps[1].result
	detached_step.rounds.clear()
	assert_eq(run.serialize(), original)
	assert_true(ExpeditionData.valid(original), "Historical results do not reread enemy tuning.")
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(original, "", true, true))
	assert_true(ExpeditionData.valid(decoded))
	assert_eq(ExpeditionData.new(decoded).serialize(), original)
