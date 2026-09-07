extends GutTest


func test_exact_complete_victory_log_and_facade() -> void:
	var party: ExpeditionPartySnapshot = _party([_member("hero", {"MaxHP": 30, "Initiative": 20})])
	var enemies: EnemyGroupResource = _group([_enemy("enemy", {"MaxHP": 50, "Attack": 4, "Initiative": 1})])
	var balancing: BalancingConfig = _balancing(10)
	var expected: Dictionary = {
		"gold": 0, "outcome": "VICTORY",
		"rounds": [
			{"round_number": 1, "actions": [
				_action("hero", "Aimed Shot", "enemy", 15),
				_action("enemy", "Attack", "hero", 4),
			]},
			{"round_number": 2, "actions": [
				_action("hero", "Attack", "enemy", 10),
				_action("enemy", "Attack", "hero", 4),
			]},
			{"round_number": 3, "actions": [
				_action("hero", "Attack", "enemy", 10),
				_action("enemy", "Attack", "hero", 4),
			]},
			{"round_number": 4, "actions": [_action("hero", "Aimed Shot", "enemy", 15)]},
		],
		"final_hero_states": {"hero": {"hp": 18, "status": HeroData.HeroStatus.IDLE}},
		"enemy_states": {"enemy": {"name": "enemy", "max_hp": 50, "hp": 0, "row": "Front"}},
	}
	assert_eq(_resolve(party, enemies, balancing), expected)
	assert_eq(CombatSimulator.resolve_combat(party, party.hero_states(), enemies, 1234, balancing), expected)
	assert_eq(JSON.parse_string(JSON.stringify(expected)), _json_numbers(expected))


func test_overkill_logs_calculated_damage_not_hp_difference() -> void:
	var party: ExpeditionPartySnapshot = _party([_member("hero", {"Attack": 11, "Initiative": 20})])
	var result: Dictionary = _resolve(party, _group([_enemy("enemy", {"MaxHP": 1})]), _balancing())
	assert_eq(result.rounds[0].actions, [_action("hero", "Aimed Shot", "enemy", 16)])
	assert_eq(result.enemy_states.enemy.hp, 0)
	assert_eq(result.outcome, "VICTORY")


func test_exact_defeat_and_zero_hp_heroes_never_act() -> void:
	var party: ExpeditionPartySnapshot = _party([
		_member("fallen", {"MaxHP": 20}, "guard"), _member("living", {"MaxHP": 3}, "guard"),
	])
	var states: Dictionary = {"fallen": {"hp": 0, "status": 4}, "living": {"hp": 3, "status": 0}}
	var enemies: EnemyGroupResource = _group([_enemy("enemy", {"Attack": 7, "Initiative": 30})])
	assert_eq(_resolve(party, enemies, _balancing(5), states), {
		"gold": 0, "outcome": "DEFEAT",
		"rounds": [{"round_number": 1, "actions": [_action("enemy", "Attack", "living", 7)]}],
		"final_hero_states": {"fallen": {"hp": 0, "status": 4}, "living": {"hp": 0, "status": 4}},
		"enemy_states": {"enemy": {"name": "enemy", "max_hp": 100, "hp": 100, "row": "Front"}},
	})
	states.living = {"hp": 0, "status": 4}
	var result: Dictionary = _resolve(party, enemies, _balancing(), states)
	assert_eq(result.outcome, "DEFEAT")
	assert_eq(result.rounds, [])
	assert_eq(result.final_hero_states, states)


func test_zero_hp_stays_wounded_on_victory_and_retreat() -> void:
	var party: ExpeditionPartySnapshot = _party([
		_member("fallen"), _member("living", {"Initiative": 30}),
	])
	var states: Dictionary = party.hero_states()
	states.fallen = {"hp": 0, "status": 4}
	for hp in [1, 1000]:
		var result: Dictionary = _resolve(party, _group([_enemy("enemy", {"MaxHP": hp})]), _balancing(), states)
		assert_eq(result.outcome, "VICTORY" if hp == 1 else "RETREAT")
		assert_eq(result.final_hero_states.fallen, {"hp": 0, "status": 4})
		assert_eq(result.final_hero_states.living.status, 0)
		assert_eq(_actor_actions(result, "fallen"), [])


func test_seeded_order_is_canonical_and_independent_of_container_insertion_order() -> void:
	var party: ExpeditionPartySnapshot = _party([
		_member("z-hero", {}, "guard"), _member("a-hero", {}, "guard"),
	])
	var enemies: EnemyGroupResource = _group([_enemy("z-enemy"), _enemy("a-enemy")])
	var balancing: BalancingConfig = _balancing(4)
	balancing.base_hit_chance = 0.9
	balancing.min_hit_chance = 0.5
	balancing.max_hit_chance = 0.99
	balancing.max_crit_chance = 0.5
	var result: Dictionary = _resolve(party, enemies, balancing)
	var reordered: Dictionary = {}
	var names: Array = PartyData.SLOT_NAMES.duplicate()
	names.reverse()
	for name in names:
		reordered[name] = party.slots[name]
	enemies.enemies.reverse()
	assert_eq(_resolve(ExpeditionPartySnapshot.new(reordered), enemies, balancing), result)
	assert_eq(_resolve(party, enemies, balancing), result)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1234
	var ranked: Array = []
	for id in ["a-enemy", "a-hero", "z-enemy", "z-hero"]:
		ranked.append({"id": id, "roll": rng.randi()})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.roll < b.roll if a.roll != b.roll else a.id < b.id)
	var expected_ids: Array = []
	var actual_ids: Array = []
	for entry in ranked:
		expected_ids.append(entry.id)
	for action in result.rounds[0].actions:
		actual_ids.append(action.actor_id)
	assert_eq(actual_ids, expected_ids)
	var different_order_seen: bool = false
	for combat_seed in range(1, 9):
		var other: Dictionary = _resolve(party, enemies, balancing, {}, combat_seed)
		if other.rounds[0].actions[0].actor_id != actual_ids[0]:
			different_order_seen = true
	assert_true(different_order_seen, "Seeded ties are not fixed stable-ID ordering.")


func test_initiative_always_precedes_random_tiebreaks() -> void:
	var party: ExpeditionPartySnapshot = _party([
		_member("slow", {"Initiative": 1}, "guard"), _member("fast", {"Initiative": 40}, "guard"),
	])
	var enemies: EnemyGroupResource = _group([
		_enemy("middle", {"Initiative": 20}), _enemy("last", {"Initiative": 0}),
	])
	for combat_seed in [1, 2, 3, 456]:
		var result: Dictionary = _resolve(party, enemies, _balancing(), {}, combat_seed)
		var ids: Array = []
		for action in result.rounds[0].actions:
			ids.append(action.actor_id)
		assert_eq(ids, ["fast", "middle", "slow", "last"])


func test_both_hero_basic_target_rules_use_authored_rule_not_class_or_id() -> void:
	for rule in ["FrontRowFirst", "AnySlot"]:
		var party: ExpeditionPartySnapshot = _party([
			_member("opener", {"Initiative": 30}),
			_member("actor", {"Initiative": 20}, "mend", rule),
		])
		var enemies: EnemyGroupResource = _group([
			_enemy("a-back", {"Initiative": 1}, "Back"),
			_enemy("z-front", {"Initiative": 1}, "Front"),
		])
		var result: Dictionary = _resolve(party, enemies, _balancing())
		var action: Dictionary = _actor_actions(result, "actor")[0]
		assert_eq(action.action_name, "Attack")
		assert_eq(action.target_id, "z-front" if rule == "FrontRowFirst" else "a-back")


func test_both_enemy_basic_target_rules_use_authored_rule_not_id() -> void:
	var party: ExpeditionPartySnapshot = _party([
		_member("front", {}, "guard"), null, _member("back", {}, "guard"),
	])
	var states: Dictionary = party.hero_states()
	states.back.hp = 10
	for rule in ["FrontRowFirst", "AnySlot"]:
		var enemies: EnemyGroupResource = _group([_enemy("same-id", {"Initiative": 50}, "Back", rule)])
		var result: Dictionary = _resolve(party, enemies, _balancing(), states)
		var action: Dictionary = result.rounds[0].actions[0]
		assert_eq(action.target_id, "front" if rule == "FrontRowFirst" else "back")
		assert_eq(action.effect, "Physical")


func test_front_row_fallback_for_both_teams_and_no_dead_turns() -> void:
	var party: ExpeditionPartySnapshot = _party([_member("hero", {"Initiative": 20}, "guard", "FrontRowFirst")])
	var enemies: EnemyGroupResource = _group([
		_enemy("front", {"MaxHP": 1, "Attack": 0, "Initiative": 1}),
		_enemy("back", {"Attack": 0, "Initiative": 0}, "Back"),
	])
	var result: Dictionary = _resolve(party, enemies, _balancing(3))
	var actions: Array = _actor_actions(result, "hero")
	assert_eq(actions[1].target_id, "front")
	assert_eq(actions[2].target_id, "back")
	assert_eq(_actor_actions(result, "front").size(), 1, "Killed actors lose their pending turn.")
	party = _party([_member("front", {}, "guard"), null, _member("back", {}, "guard")])
	var states: Dictionary = party.hero_states()
	states.front = {"hp": 0, "status": 4}
	result = _resolve(party, _group([_enemy("enemy", {"Initiative": 30})]), _balancing(), states)
	assert_eq(result.rounds[0].actions[0].target_id, "back")


func test_target_percentage_ties_choose_stable_id_on_both_sides() -> void:
	var party: ExpeditionPartySnapshot = _party([
		_member("z-hero", {"MaxHP": 100}, "guard"),
		_member("a-hero", {"MaxHP": 200}, "guard"),
	])
	var states: Dictionary = {"z-hero": {"hp": 50, "status": 0}, "a-hero": {"hp": 100, "status": 0}}
	var result: Dictionary = _resolve(party, _group([_enemy("enemy", {"Initiative": 30})]), _balancing(), states)
	assert_eq(result.rounds[0].actions[0].target_id, "a-hero")
	party = _party([_member("hero", {"Initiative": 30}, "mend")])
	result = _resolve(party, _group([_enemy("z-enemy", {"MaxHP": 200}), _enemy("a-enemy")]), _balancing())
	assert_eq(result.rounds[0].actions[0].target_id, "a-enemy")


func test_target_ratios_are_exact_near_maximum_safe_hp() -> void:
	var maximum: int = HeroCatalog.MAX_SAFE_INT
	var party: ExpeditionPartySnapshot = _party([
		_member("a-higher", {"MaxHP": maximum, "Attack": 0, "MagicPower": 0}, "guard"),
		_member("z-lower", {"MaxHP": maximum - 1, "Attack": 0, "MagicPower": 0}, "guard"),
	])
	var states: Dictionary = {
		"a-higher": {"hp": maximum - 1, "status": 0},
		"z-lower": {"hp": maximum - 2, "status": 0},
	}
	var result: Dictionary = _resolve(party, _group([_enemy("enemy", {"Initiative": 30, "Attack": 1})]), _balancing(), states)
	assert_eq(result.rounds[0].actions[0].target_id, "z-lower")


func test_skill_target_rule_is_independent_of_basic_rule() -> void:
	var opener: Dictionary = _member("opener", {"Initiative": 30})
	var actor: Dictionary = _member("actor", {"Initiative": 20}, "aimed_shot", "FrontRowFirst")
	var enemies: EnemyGroupResource = _group([_enemy("a-back", {}, "Back"), _enemy("z-front")])
	var result: Dictionary = _resolve(_party([opener, actor]), enemies, _balancing())
	assert_eq(_actor_actions(result, "actor")[0].target_id, "a-back")
	actor.active_skill.target_rule = "FrontRowFirst"
	actor.basic_attack_target_rule = "AnySlot"
	result = _resolve(_party([opener, actor]), enemies, _balancing())
	assert_eq(_actor_actions(result, "actor")[0].target_id, "z-front")


func test_defender_evasion_changes_hit_without_touching_attributes() -> void:
	var party: ExpeditionPartySnapshot = _party([_member("hero", {"Initiative": 30})])
	var balancing: BalancingConfig = _balancing()
	balancing.min_hit_chance = 0.0
	var enemies: EnemyGroupResource = _group([_enemy("enemy", {"Evasion": 0.0})])
	var before: Dictionary = party.serialize()
	var hit_result: Dictionary = _resolve(party, enemies, balancing)
	enemies.enemies[0].derived_stats.Evasion = 1.0
	var miss_result: Dictionary = _resolve(party, enemies, balancing)
	assert_eq(hit_result.rounds[0].actions[0], _action("hero", "Aimed Shot", "enemy", 15))
	assert_eq(miss_result.rounds[0].actions[0], _action("hero", "Aimed Shot", "enemy", 0, "Physical", false))
	assert_eq(party.serialize(), before)


func test_hit_probability_minimum_and_maximum_are_applied() -> void:
	var party: ExpeditionPartySnapshot = _party([_member("hero", {"Initiative": 30})])
	var enemies: EnemyGroupResource = _group([_enemy("enemy", {"Evasion": 1.0})])
	var balancing: BalancingConfig = _balancing()
	assert_true(_resolve(party, enemies, balancing).rounds[0].actions[0].hit)
	balancing.min_hit_chance = 0.0
	balancing.max_hit_chance = 0.0
	enemies.enemies[0].derived_stats.Evasion = 0.0
	assert_false(_resolve(party, enemies, balancing).rounds[0].actions[0].hit)


func test_physical_damage_floors_once_after_fractional_multiplier_defense_and_crit() -> void:
	var party: ExpeditionPartySnapshot = _party([_member("hero", {"Attack": 3, "MagicPower": 90, "CritChance": 1.0, "Initiative": 30})])
	var balancing: BalancingConfig = _balancing()
	balancing.max_crit_chance = 1.0
	var result: Dictionary = _resolve(party, _group([_enemy("enemy", {"Defense": 1})]), balancing)
	# (3 * 1.5 - 1) * 1.5 = 5.25, with no intermediate floor.
	assert_eq(result.rounds[0].actions[0], _action("hero", "Aimed Shot", "enemy", 5, "Physical", true, true))
	balancing.max_crit_chance = 0.0
	result = _resolve(party, _group([_enemy("enemy", {"Defense": 1})]), balancing)
	assert_eq(result.rounds[0].actions[0].damage_or_heal, 3)
	assert_false(result.rounds[0].actions[0].was_crit)


func test_magic_uses_magic_power_and_enemy_basic_remains_physical() -> void:
	var party: ExpeditionPartySnapshot = _party([_member("wizard", {"Attack": 99, "MagicPower": 3, "CritChance": 1.0, "Initiative": 30}, "firebolt")])
	var enemies: EnemyGroupResource = _group([_enemy("enemy", {"Attack": 3, "MagicPower": 99, "Defense": 1})])
	var balancing: BalancingConfig = _balancing()
	balancing.max_crit_chance = 1.0
	var result: Dictionary = _resolve(party, enemies, balancing)
	assert_eq(result.rounds[0].actions[0], _action("wizard", "Firebolt", "enemy", 5, "Magic", true, true))
	assert_eq(result.rounds[0].actions[1], _action("enemy", "Attack", "wizard", 3))


func test_heal_floors_once_logs_unclamped_amount_and_never_misses_or_crits() -> void:
	var party: ExpeditionPartySnapshot = _party([_member("cleric", {"MagicPower": 3, "CritChance": 1.0, "Initiative": 30}, "mend")])
	var states: Dictionary = {"cleric": {"hp": 99, "status": 0}}
	var balancing: BalancingConfig = _balancing()
	balancing.skill_damage_multipliers.mend = 1.25
	balancing.max_crit_chance = 1.0
	balancing.min_hit_chance = 0.0
	balancing.max_hit_chance = 0.0
	var result: Dictionary = _resolve(party, _group(), balancing, states)
	assert_eq(result.rounds[0].actions[0], _action("cleric", "Mend", "cleric", 3, "Heal"))
	assert_eq(result.final_hero_states.cleric.hp, 100)


func test_mend_selects_living_injured_ally_and_does_not_resurrect() -> void:
	var party: ExpeditionPartySnapshot = _party([
		_member("cleric", {"MagicPower": 3, "Initiative": 30}, "mend"),
		_member("injured", {}, "guard"), _member("fallen", {}, "guard"),
	])
	var states: Dictionary = {"cleric": {"hp": 80, "status": 0}, "injured": {"hp": 10, "status": 0}, "fallen": {"hp": 0, "status": 4}}
	var balancing: BalancingConfig = _balancing()
	balancing.max_hit_chance = 0.0
	balancing.min_hit_chance = 0.0
	var result: Dictionary = _resolve(party, _group(), balancing, states)
	assert_eq(result.rounds[0].actions[0], _action("cleric", "Mend", "injured", 3, "Heal"))
	assert_eq(result.final_hero_states.injured.hp, 13)
	assert_eq(result.final_hero_states.fallen.hp, 0)


func test_mend_without_valid_target_attacks_without_consuming_cooldown() -> void:
	var party: ExpeditionPartySnapshot = _party([_member("cleric", {"Initiative": 30}, "mend")])
	var result: Dictionary = _resolve(party, _group([_enemy("enemy", {"MaxHP": 1000, "Attack": 4})]), _balancing(5))
	var names: Array = []
	for action in _actor_actions(result, "cleric"):
		names.append(action.action_name)
	assert_eq(names, ["Attack", "Mend", "Attack", "Attack", "Mend"])
	assert_eq(result.final_hero_states.cleric.hp, 92)


func test_guard_activation_expiry_and_two_intervening_actor_turns() -> void:
	var party: ExpeditionPartySnapshot = _party([_member("knight", {"MaxHP": 1000, "Initiative": 30}, "guard")])
	var result: Dictionary = _resolve(party, _group([_enemy("enemy", {"MaxHP": 1000, "Attack": 7})]), _balancing(4))
	var names: Array = []
	var damage: Array = []
	for action in _actor_actions(result, "knight"):
		names.append(action.action_name)
	for action in _actor_actions(result, "enemy"):
		damage.append(action.damage_or_heal)
	assert_eq(names, ["Guard", "Attack", "Attack", "Guard"])
	assert_eq(damage, [3, 7, 7, 3])
	assert_eq(result.final_hero_states.knight.hp, 980)
	assert_eq(result.rounds[0].actions[0], _action("knight", "Guard", "knight", 0, "Guard"))


func test_guard_lasts_until_next_actor_turn_not_round_boundary() -> void:
	var party: ExpeditionPartySnapshot = _party([_member("knight", {"Initiative": 1}, "guard")])
	var result: Dictionary = _resolve(party, _group([_enemy("enemy", {"MaxHP": 1000, "Attack": 7, "Initiative": 30})]), _balancing(3))
	var damage: Array = []
	for action in _actor_actions(result, "enemy"):
		damage.append(action.damage_or_heal)
	assert_eq(damage, [7, 3, 7])


func test_guard_multiplies_after_mitigation_and_crit_before_single_floor() -> void:
	var party: ExpeditionPartySnapshot = _party([_member("knight", {"Initiative": 30, "Defense": 1}, "guard")])
	var balancing: BalancingConfig = _balancing()
	balancing.basic_attack_damage_multiplier = 1.25
	balancing.max_crit_chance = 1.0
	var result: Dictionary = _resolve(party, _group([_enemy("enemy", {"Attack": 7, "CritChance": 1.0})]), balancing)
	# (7 * 1.25 - 1) * 1.5 * .5 = 5.8125.
	assert_eq(result.rounds[0].actions[1].damage_or_heal, 5)
	assert_true(result.rounds[0].actions[1].was_crit)
	balancing.skill_damage_multipliers.guard = 0.0
	result = _resolve(party, _group([_enemy("enemy", {"Attack": 0})]), balancing)
	assert_eq(result.rounds[0].actions[1].damage_or_heal, 1)


func test_guard_cannot_miss_or_crit_and_zero_multiplier_heal_still_logs() -> void:
	var balancing: BalancingConfig = _balancing()
	balancing.min_hit_chance = 0.0
	balancing.max_hit_chance = 0.0
	balancing.max_crit_chance = 1.0
	var party: ExpeditionPartySnapshot = _party([_member("hero", {"CritChance": 1.0, "Initiative": 30}, "guard")])
	var result: Dictionary = _resolve(party, _group(), balancing)
	assert_eq(result.rounds[0].actions[0], _action("hero", "Guard", "hero", 0, "Guard"))
	party = _party([_member("hero", {"CritChance": 1.0, "Initiative": 30}, "mend")])
	balancing.skill_damage_multipliers.mend = 0.0
	result = _resolve(party, _group(), balancing, {"hero": {"hp": 1, "status": 0}})
	assert_eq(result.rounds[0].actions[0], _action("hero", "Mend", "hero", 0, "Heal"))
	assert_eq(result.final_hero_states.hero.hp, 1)


func test_zero_cooldown_skills_are_ready_each_turn_and_reset_between_encounters() -> void:
	var member: Dictionary = _member("hero", {"Initiative": 30}, "guard")
	member.active_skill.cooldown_turns = 0
	var party: ExpeditionPartySnapshot = _party([member])
	var enemies: EnemyGroupResource = _group([_enemy("enemy", {"Attack": 10})])
	var result: Dictionary = _resolve(party, enemies, _balancing(2))
	assert_eq(_actor_actions(result, "hero").size(), 2)
	for action in _actor_actions(result, "hero"):
		assert_eq(action.action_name, "Guard")
	assert_eq(result.final_hero_states.hero.hp, 90)
	member.active_skill.cooldown_turns = 2
	party = _party([member])
	result = _resolve(party, enemies, _balancing())
	var next: Dictionary = _resolve(party, enemies, _balancing(), result.final_hero_states)
	assert_eq(next.rounds[0].actions[0].action_name, "Guard")
	assert_eq(next.final_hero_states.hero.hp, 90, "Current HP carries over without implicit healing.")


func test_maximum_rounds_combatants_and_actions_are_bounded() -> void:
	var members: Array = []
	var enemies: Array = []
	for index in range(4):
		members.append(_member("hero-%d" % index, {"MaxHP": 5000, "Attack": 0, "MagicPower": 0}, "guard"))
		enemies.append(_enemy("enemy-%d" % index, {"MaxHP": 5000, "Attack": 0}))
	var result: Dictionary = _resolve(_party(members), _group(enemies), _balancing(100))
	assert_eq(result.outcome, "RETREAT")
	assert_eq(result.rounds.size(), 100)
	assert_eq(result.enemy_states.size(), 4)
	assert_eq(result.final_hero_states.size(), 4)
	for index in range(100):
		assert_eq(result.rounds[index].round_number, index + 1)
		assert_eq(result.rounds[index].actions.size(), 8)
		for action in result.rounds[index].actions:
			assert_true(HeroCatalog.has_exact_keys(action, [
				"actor_name", "action_name", "target_name", "damage_or_heal", "was_crit",
				"actor_id", "target_id", "effect", "hit",
			]))


func test_resolution_is_nonmutating_repeatable_and_does_not_use_global_rng() -> void:
	var party: ExpeditionPartySnapshot = _party([_member("hero", {"Initiative": 30}, "guard")])
	var states: Dictionary = party.hero_states()
	var enemies: EnemyGroupResource = _group()
	var balancing: BalancingConfig = _balancing(4)
	var party_before: Dictionary = party.serialize()
	var states_before: Dictionary = states.duplicate(true)
	var enemies_before: Array = enemies.enemies.duplicate(true)
	var multipliers_before: Dictionary = balancing.skill_damage_multipliers.duplicate(true)
	seed(751)
	var expected_first: int = randi()
	var expected_second: int = randi()
	seed(751)
	assert_eq(randi(), expected_first)
	var result: Dictionary = _resolve(party, enemies, balancing, states)
	assert_eq(randi(), expected_second)
	assert_eq(_resolve(party, enemies, balancing, states), result)
	assert_eq(party.serialize(), party_before)
	assert_eq(states, states_before)
	assert_eq(enemies.enemies, enemies_before)
	assert_eq(balancing.skill_damage_multipliers, multipliers_before)
	assert_eq(balancing.max_combat_rounds, 4)
	result.final_hero_states.hero.hp = 0
	result.enemy_states.enemy.name = "Changed result"
	result.rounds[0].actions[0].actor_name = "Changed result"
	assert_eq(party.serialize(), party_before)
	assert_eq(states, states_before)
	assert_eq(enemies.enemies, enemies_before)


func test_optional_skill_capture_preserves_legacy_shape_and_exact_double_encoding() -> void:
	var formation: PartyData = PartyData.new()
	var hero: HeroData = HeroData.new("captured")
	hero.hero_name = "Captured Hero"
	hero.hero_class = HeroCatalog.RANGER.duplicate(true)
	hero.hero_class.active_skill = hero.hero_class.active_skill.duplicate(true)
	var authored_skill_before: Dictionary = CombatCatalog.AIMED_SHOT.snapshot()
	hero.attributes = {"MIG": 10, "FOC": 3, "GRT": 5, "GUI": 11, "FTH": 2}
	formation.slots[PartyData.FormationSlot.FRONT_LEFT] = hero
	var legacy: ExpeditionPartySnapshot = ExpeditionPartySnapshot.capture(formation)
	var combat: ExpeditionPartySnapshot = ExpeditionPartySnapshot.capture(formation, true)
	assert_true(HeroCatalog.has_exact_keys(legacy.slots.FRONT_LEFT, ExpeditionPartySnapshot.MEMBER_KEYS))
	assert_true(HeroCatalog.has_exact_keys(combat.slots.FRONT_LEFT, ExpeditionPartySnapshot.MEMBER_KEYS + ["active_skill"]))
	var stripped: Dictionary = combat.serialize()
	stripped.FRONT_LEFT.erase("active_skill")
	assert_eq(stripped, legacy.serialize())
	assert_eq(combat.hero_states(), {"captured": {"hp": combat.slots.FRONT_LEFT.derived_stats.MaxHP, "status": 0}})
	var saved: Dictionary = combat.serialize()
	for key in ["Evasion", "CritChance"]:
		assert_typeof(saved.FRONT_LEFT.derived_stats[key], TYPE_STRING)
		assert_eq(saved.FRONT_LEFT.derived_stats[key].length(), 16)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	assert_true(ExpeditionPartySnapshot.valid(parsed))
	assert_eq(_json_numbers(ExpeditionPartySnapshot.new(parsed).slots), _json_numbers(combat.slots))
	hero.hero_class.active_skill.display_name = "Retuned"
	hero.hero_class.active_skill.cooldown_turns = 99
	hero.hero_class.basic_attack_target_rule = "FrontRowFirst"
	assert_eq(combat.slots.FRONT_LEFT.active_skill, authored_skill_before)
	assert_eq(CombatCatalog.AIMED_SHOT.snapshot(), authored_skill_before)
	assert_eq(combat.slots.FRONT_LEFT.basic_attack_target_rule, "AnySlot")
	assert_eq(_json_numbers(ExpeditionPartySnapshot.new(parsed).serialize()), _json_numbers(saved))
	var returned: Dictionary = combat.slots
	returned.FRONT_LEFT.active_skill.effect = "Guard"
	assert_eq(combat.serialize(), saved)


func test_skill_validation_is_combat_only_and_capture_rejects_invalid_skill() -> void:
	var formation: PartyData = PartyData.new()
	var hero: HeroData = HeroData.new("hero")
	hero.hero_name = "Hero"
	hero.hero_class = HeroCatalog.KNIGHT.duplicate(true)
	hero.attributes = {"MIG": 1, "FOC": 1, "GRT": 1, "GUI": 1, "FTH": 1}
	hero.hero_class.active_skill = null
	formation.slots[0] = hero
	assert_true(HeroCatalog.validate_class(hero.hero_class))
	assert_not_null(ExpeditionPartySnapshot.capture(formation))
	assert_null(ExpeditionPartySnapshot.capture(formation, true))
	var legacy: ExpeditionPartySnapshot = ExpeditionPartySnapshot.capture(formation)
	_assert_error(_resolve(legacy, _group(), _balancing()))


func test_missing_partial_extra_and_malformed_current_states_are_errors() -> void:
	var party: ExpeditionPartySnapshot = _party([_member("hero")])
	for states in [
		{}, {"other": {"hp": 100, "status": 0}}, {"hero": {"hp": 100}},
		{"hero": {"hp": 100, "status": 0, "extra": 1}}, {"hero": null},
		{"hero": {"hp": -1, "status": 0}}, {"hero": {"hp": 101, "status": 0}},
		{"hero": {"hp": 1.5, "status": 0}}, {"hero": {"hp": NAN, "status": 0}},
		{"hero": {"hp": 100, "status": 1}}, {"hero": {"hp": 100, "status": true}},
		{"hero": {"hp": 0, "status": 0}}, {"hero": {"hp": 100, "status": HeroData.HeroStatus.WOUNDED}},
		{"hero": {"hp": 100, "status": 0}, "extra": {"hp": 1, "status": 0}},
	]:
		_assert_error(CombatEngine.resolve_combat(party, states, _group(), 1, _balancing()))


func test_seed_is_a_nonnegative_safe_integer() -> void:
	var party: ExpeditionPartySnapshot = _party([_member("hero")])
	var states: Dictionary = party.hero_states()
	var before: Dictionary = party.serialize()
	for combat_seed in [-1, HeroCatalog.MAX_SAFE_INT + 1]:
		_assert_error(CombatEngine.resolve_combat(party, states, _group(), combat_seed, _balancing()))
	for combat_seed in [0, HeroCatalog.MAX_SAFE_INT]:
		var result: Dictionary = CombatEngine.resolve_combat(party, states, _group(), combat_seed, _balancing())
		assert_false(result.has("error"))
	assert_eq(party.serialize(), before)
	assert_eq(states, party.hero_states())


func test_current_states_accept_json_integer_floats_but_not_invalid_status_types() -> void:
	var party: ExpeditionPartySnapshot = _party([_member("living"), _member("fallen")])
	var states: Dictionary = {"living": {"hp": 100, "status": 0}, "fallen": {"hp": 0, "status": 4}}
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(states))
	var before: Dictionary = parsed.duplicate(true)
	assert_typeof(parsed.living.status, TYPE_FLOAT)
	assert_typeof(parsed.fallen.status, TYPE_FLOAT)
	var enemies: EnemyGroupResource = _group()
	var balancing: BalancingConfig = _balancing()
	var expected: Dictionary = CombatEngine.resolve_combat(party, states, enemies, 1234, balancing)
	assert_false(expected.has("error"))
	assert_eq(CombatEngine.resolve_combat(party, parsed, enemies, 1234, balancing), expected)
	assert_eq(parsed, before)
	for invalid_status in [0.5, 4.5, true, false, "0", "4"]:
		var invalid: Dictionary = states.duplicate(true)
		invalid.living.status = invalid_status
		_assert_error(CombatEngine.resolve_combat(party, invalid, enemies, 1234, balancing))


func test_malformed_snapshot_and_skill_shapes_are_errors() -> void:
	_assert_error(CombatEngine.resolve_combat(null, {}, _group(), 1, _balancing()))
	_assert_error(CombatEngine.resolve_combat(ExpeditionPartySnapshot.new(), {}, _group(), 1, _balancing()))
	for changes in [
		{"active_skill": null}, {"active_skill": {}}, {"extra": 1},
		{"hero_name": "x".repeat(129)}, {"basic_attack_target_rule": "Self"},
		{"derived_stats": {"MaxHP": 100}},
	]:
		var member: Dictionary = _member("hero")
		member.merge(changes, true)
		var party: ExpeditionPartySnapshot = _party([member])
		assert_false(ExpeditionPartySnapshot.valid(party.slots))
		_assert_error(CombatEngine.resolve_combat(party, {"hero": {"hp": 100, "status": 0}}, _group(), 1, _balancing()))
	for changes in [
		{"skill_id": ""}, {"display_name": "x".repeat(129)}, {"effect": "Poison"},
		{"target_rule": "Self"}, {"cooldown_turns": -1}, {"cooldown_turns": 101},
		{"cooldown_turns": 0.5}, {"cooldown_turns": true}, {"extra": 0},
	]:
		var member: Dictionary = _member("hero")
		member.active_skill.merge(changes, true)
		assert_false(CombatCatalog.validate_skill_snapshot(member.active_skill))
		var party: ExpeditionPartySnapshot = _party([member])
		_assert_error(CombatEngine.resolve_combat(party, {"hero": {"hp": 100, "status": 0}}, _group(), 1, _balancing()))


func test_invalid_enemy_groups_stats_bounds_and_colliding_ids_are_errors() -> void:
	var party: ExpeditionPartySnapshot = _party([_member("hero")])
	_assert_error(_resolve(party, null, _balancing()))
	var empty: EnemyGroupResource = EnemyGroupResource.new()
	empty.group_id = &"empty"
	empty.display_name = "Empty"
	_assert_error(_resolve(party, empty, _balancing()))
	_assert_error(_resolve(party, _group([_enemy("same"), _enemy("same")]), _balancing()))
	_assert_error(_resolve(party, _group([_enemy("hero")]), _balancing()))
	var many: Array = []
	for index in range(5):
		many.append(_enemy("enemy-%d" % index))
	_assert_error(_resolve(party, _group(many), _balancing()))
	for changes in [
		{"combatant_id": ""}, {"display_name": "x".repeat(129)}, {"row": "Middle"},
		{"basic_attack_target_rule": "LowestHPAlly"}, {"extra": 1},
		{"derived_stats": {}},
	]:
		var enemy: Dictionary = _enemy("enemy")
		enemy.merge(changes, true)
		_assert_error(_resolve(party, _group([enemy]), _balancing()))
	for key in HeroCatalog.STATS:
		for value in [-1, INF, NAN, true, "12", {"nested": 1}]:
			var enemy: Dictionary = _enemy("enemy")
			enemy.derived_stats[key] = value
			_assert_error(_resolve(party, _group([enemy]), _balancing()))
	for changes in [{"MaxHP": 0}, {"Attack": 0.5}, {"Evasion": 1.01}, {"CritChance": 1.01}, {"MaxHP": HeroCatalog.MAX_SAFE_INT + 1}]:
		_assert_error(_resolve(party, _group([_enemy("enemy", changes)]), _balancing()))


func test_invalid_balancing_and_missing_skill_multipliers_are_errors() -> void:
	var party: ExpeditionPartySnapshot = _party([_member("hero")])
	_assert_error(_resolve(party, _group(), null))
	for rounds in [0, -1, 101]:
		_assert_error(_resolve(party, _group(), _balancing(rounds)))
	for property in ["base_hit_chance", "min_hit_chance", "max_hit_chance", "max_crit_chance"]:
		for value in [-0.1, 1.1, INF, NAN]:
			var balancing: BalancingConfig = _balancing()
			balancing.set(property, value)
			_assert_error(_resolve(party, _group(), balancing))
	for property in ["basic_attack_damage_multiplier", "critical_damage_multiplier"]:
		for value in [-0.1, INF, NAN]:
			var balancing: BalancingConfig = _balancing()
			balancing.set(property, value)
			_assert_error(_resolve(party, _group(), balancing))
	var reversed: BalancingConfig = _balancing()
	reversed.min_hit_chance = 0.8
	reversed.max_hit_chance = 0.2
	_assert_error(_resolve(party, _group(), reversed))
	for value in [null, -0.1, INF, NAN, true, "1.5"]:
		var balancing: BalancingConfig = _balancing()
		balancing.skill_damage_multipliers.aimed_shot = value
		_assert_error(_resolve(party, _group(), balancing))
	var missing: BalancingConfig = _balancing()
	missing.skill_damage_multipliers.erase("aimed_shot")
	_assert_error(_resolve(party, _group(), missing))


func test_safe_integer_amount_limits_reject_overflow_without_mutation() -> void:
	var member: Dictionary = _member("hero", {"Attack": HeroCatalog.MAX_SAFE_INT, "Initiative": 30})
	var party: ExpeditionPartySnapshot = _party([member])
	var states: Dictionary = party.hero_states()
	var before: Dictionary = party.serialize()
	_assert_error(_resolve(party, _group(), _balancing(), states))
	assert_eq(party.serialize(), before)
	assert_eq(states, party.hero_states())
	var balancing: BalancingConfig = _balancing()
	balancing.skill_damage_multipliers.aimed_shot = 1.0
	balancing.critical_damage_multiplier = 1.0
	var result: Dictionary = _resolve(party, _group(), balancing)
	assert_eq(result.rounds[0].actions[0].damage_or_heal, HeroCatalog.MAX_SAFE_INT)
	assert_eq(result.enemy_states.enemy.hp, 0)
	member = _member("healer", {"MagicPower": HeroCatalog.MAX_SAFE_INT}, "mend")
	balancing.skill_damage_multipliers.mend = 2.0
	_assert_error(_resolve(_party([member]), _group(), balancing))


func test_frozen_skill_definitions_need_not_match_retuned_catalog() -> void:
	var member: Dictionary = _member("hero", {"Initiative": 30})
	member.active_skill.display_name = "Historical Shot"
	member.active_skill.cooldown_turns = 1
	var party: ExpeditionPartySnapshot = _party([member])
	var result: Dictionary = _resolve(party, _group([_enemy("enemy", {"MaxHP": 1000})]), _balancing(3))
	var actions: Array = _actor_actions(result, "hero")
	assert_eq(actions[0].action_name, "Historical Shot")
	assert_eq(actions[1].action_name, "Attack")
	assert_eq(actions[2].action_name, "Historical Shot")


func test_name_boundaries_and_json_round_trip_of_full_result() -> void:
	var member: Dictionary = _member("hero", {"Initiative": 30})
	member.hero_name = "h".repeat(128)
	member.active_skill.display_name = "s".repeat(128)
	var enemy: Dictionary = _enemy("enemy")
	enemy.display_name = "e".repeat(128)
	var result: Dictionary = _resolve(_party([member]), _group([enemy]), _balancing())
	assert_false(result.has("error"))
	assert_eq(JSON.parse_string(JSON.stringify(result)), _json_numbers(result))
	assert_eq(result.rounds[0].actions[0].actor_name.length(), 128)
	assert_eq(result.rounds[0].actions[0].action_name.length(), 128)
	assert_eq(result.rounds[0].actions[0].target_name.length(), 128)


func _json_numbers(value: Variant) -> Variant:
	# JSON has one numeric type; Godot parses its numbers as floats.
	if value is int:
		return float(value)
	if value is Dictionary:
		var dictionary: Dictionary = {}
		for key in value:
			dictionary[key] = _json_numbers(value[key])
		return dictionary
	if value is Array:
		var array: Array = []
		for item in value:
			array.append(_json_numbers(item))
		return array
	return value


func _stats(overrides: Dictionary = {}) -> Dictionary:
	var stats: Dictionary = {
		"MaxHP": 100, "Attack": 10, "MagicPower": 8, "Defense": 0,
		"Evasion": 0.0, "Initiative": 10, "CritChance": 0.0,
	}
	stats.merge(overrides, true)
	return stats


func _member(id: String, overrides: Dictionary = {}, skill_id: String = "aimed_shot", rule: String = "AnySlot") -> Dictionary:
	return {
		"hero_id": id, "hero_name": id, "class_id": "ranger", "class_name": "Ranger", "level": 1,
		"attributes": {"MIG": 1, "FOC": 1, "GRT": 1, "GUI": 1, "FTH": 1},
		"derived_stats": _stats(overrides), "basic_attack_target_rule": rule,
		"active_skill": CombatCatalog.skill_by_id(skill_id).snapshot(),
	}


func _party(members: Array) -> ExpeditionPartySnapshot:
	var slots: Dictionary = {}
	for index in range(PartyData.SLOT_NAMES.size()):
		slots[PartyData.SLOT_NAMES[index]] = members[index] if index < members.size() else null
	return ExpeditionPartySnapshot.new(slots)


func _enemy(id: String, overrides: Dictionary = {}, row: String = "Front", rule: String = "FrontRowFirst") -> Dictionary:
	return {
		"combatant_id": id, "display_name": id, "row": row,
		"basic_attack_target_rule": rule, "derived_stats": _stats(overrides),
	}


func _group(enemies: Array = []) -> EnemyGroupResource:
	var group: EnemyGroupResource = EnemyGroupResource.new()
	group.group_id = &"fixture"
	group.display_name = "Fixture enemies"
	group.enemies.assign(enemies if not enemies.is_empty() else [_enemy("enemy")])
	return group


func _balancing(rounds: int = 1) -> BalancingConfig:
	var balancing: BalancingConfig = load("res://data/balancing/default_balancing.tres").duplicate(true)
	balancing.max_combat_rounds = rounds
	balancing.base_hit_chance = 1.0
	balancing.min_hit_chance = 1.0
	balancing.max_hit_chance = 1.0
	balancing.max_crit_chance = 0.0
	return balancing


func _resolve(party: ExpeditionPartySnapshot, enemies: EnemyGroupResource, balancing: BalancingConfig,
		states: Dictionary = {}, combat_seed: int = 1234) -> Dictionary:
	var current: Dictionary = party.hero_states() if states.is_empty() else states
	return CombatEngine.resolve_combat(party, current, enemies, combat_seed, balancing)


func _action(actor: String, name: String, target: String, amount: int,
		effect: String = "Physical", hit: bool = true, crit: bool = false) -> Dictionary:
	return {
		"actor_name": actor, "action_name": name, "target_name": target, "damage_or_heal": amount,
		"was_crit": crit, "actor_id": actor, "target_id": target, "effect": effect, "hit": hit,
	}


func _actor_actions(result: Dictionary, id: String) -> Array:
	var actions: Array = []
	for round_log in result.rounds:
		for action in round_log.actions:
			if action.actor_id == id:
				actions.append(action)
	return actions


func _assert_error(result: Dictionary) -> void:
	assert_true(HeroCatalog.has_exact_keys(result, ["error"]), str(result))
	if result.has("error"):
		assert_true(ExpeditionCatalog.text(result.error))
