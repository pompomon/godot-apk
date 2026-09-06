extends GutTest
## Deterministic, pure auto-combat: hand-computed formulas, forced-outcome
## scenarios, and a hand-reviewed fixed-seed golden result. No scene tree,
## GameState, clock, or global RNG is touched by the simulation.

const DEFAULT: BalancingConfig = preload("res://data/balancing/default_balancing.tres")


# --- Construction helpers -----------------------------------------------------

func _stats(max_hp: int, attack: int, magic: int, defense: int,
		evasion: float, initiative: int, crit: float) -> Dictionary:
	return {
		"MaxHP": max_hp, "Attack": attack, "MagicPower": magic, "Defense": defense,
		"Evasion": evasion, "Initiative": initiative, "CritChance": crit,
	}


func _attrs() -> Dictionary:
	return {"MIG": 10, "FOC": 10, "GRT": 10, "GUI": 10, "FTH": 10}


func _skill(id: String, kind: String, rule: String, mult: String, cooldown: int) -> Dictionary:
	return {
		"skill_id": id, "display_name": id.capitalize(), "kind": kind,
		"target_rule": rule, "multiplier_id": mult, "cooldown": cooldown,
	}


func _member(id: String, class_id: String, rule: String, stats: Dictionary, skill: Variant) -> Dictionary:
	return {
		"hero_id": id, "hero_name": id.capitalize(), "class_id": class_id,
		"class_name": class_id.capitalize(), "level": 1, "attributes": _attrs(),
		"derived_stats": stats, "basic_attack_target_rule": rule, "skill": skill,
	}


func _snapshot(members: Dictionary) -> ExpeditionPartySnapshot:
	var slots := {"FRONT_LEFT": null, "FRONT_RIGHT": null, "BACK_LEFT": null, "BACK_RIGHT": null}
	for slot in members:
		slots[slot] = members[slot]
	return ExpeditionPartySnapshot.new(slots)


func _enemy(id: String, row: String, rule: String, stats: Dictionary) -> EnemyStatBlockResource:
	var block := EnemyStatBlockResource.new()
	block.enemy_id = StringName(id)
	block.display_name = id.capitalize()
	block.row = row
	block.basic_attack_target_rule = rule
	block.derived_stats = stats
	return block


func _group(id: String, enemies: Array) -> EnemyGroupResource:
	var group := EnemyGroupResource.new()
	group.group_id = StringName(id)
	group.display_name = id.capitalize()
	group.enemies.assign(enemies)
	return group


func _forced() -> BalancingConfig:
	# Always hit, never crit: isolates targeting, damage, and skill behaviour from
	# the RNG so every asserted amount is hand-computable.
	var config: BalancingConfig = DEFAULT.duplicate(true)
	config.base_hit_chance = 1.0
	config.min_hit_chance = 1.0
	config.max_hit_chance = 1.0
	config.max_crit_chance = 0.0
	return config


func _actions(result: Dictionary) -> Array:
	var flat: Array = []
	for round_entry in result.rounds:
		for action in round_entry.actions:
			flat.append(action)
	return flat


# --- Pure formula helpers (hand-computed) ------------------------------------

func test_hit_chance_subtracts_evasion_and_clamps() -> void:
	assert_almost_eq(CombatResolver.hit_chance(0.90, 0.05, 0.50, 0.99), 0.85, 0.00001)
	assert_almost_eq(CombatResolver.hit_chance(0.90, 0.60, 0.50, 0.99), 0.50, 0.00001)
	assert_almost_eq(CombatResolver.hit_chance(0.90, -0.50, 0.50, 0.99), 0.99, 0.00001)
	assert_almost_eq(CombatResolver.hit_chance(1.00, 0.00, 1.00, 1.00), 1.00, 0.00001)


func test_damage_floors_exactly_once_after_mitigation_crit_and_guard() -> void:
	# max(1, 20*1.6 - 6) = 26; floor(26) = 26.
	assert_eq(CombatResolver.damage_amount(20.0, 1.6, 6.0, false, 1.5, 0.0), 26)
	# Critical: floor(26 * 1.5) = floor(39.0) = 39.
	assert_eq(CombatResolver.damage_amount(20.0, 1.6, 6.0, true, 1.5, 0.0), 39)
	# Guard halves once, after mitigation: floor(26 * 0.5) = 13.
	assert_eq(CombatResolver.damage_amount(20.0, 1.6, 6.0, false, 1.5, 0.5), 13)
	# Crit then Guard, single floor: floor(26 * 1.5 * 0.5) = floor(19.5) = 19.
	assert_eq(CombatResolver.damage_amount(20.0, 1.6, 6.0, true, 1.5, 0.5), 19)
	# Mitigation floor of one, then damage floor of one.
	assert_eq(CombatResolver.damage_amount(5.0, 1.0, 100.0, false, 1.5, 0.0), 1)
	assert_eq(CombatResolver.damage_amount(5.0, 1.0, 100.0, false, 1.5, 0.9), 1)
	# Fractional mitigation floors down: floor(max(1, 10*0.5 - 1)) = floor(4.0) = 4.
	assert_eq(CombatResolver.damage_amount(10.0, 0.5, 1.0, false, 1.5, 0.0), 4)
	# floor(7.9) style: max(1, 9*1.0 - 1) = 8; crit floor(8*1.25)=10.
	assert_eq(CombatResolver.damage_amount(9.0, 1.0, 1.0, true, 1.25, 0.0), 10)


func test_heal_floors_and_never_negative() -> void:
	assert_eq(CombatResolver.heal_amount(18.0, 1.5), 27)
	assert_eq(CombatResolver.heal_amount(7.0, 1.5), 10) # floor(10.5)
	assert_eq(CombatResolver.heal_amount(0.0, 1.5), 0)


# --- Malformed input rejection -----------------------------------------------

func test_malformed_input_returns_empty_and_is_distinguishable() -> void:
	var group := _group("g", [_enemy("e", "Front", "FrontRowFirst", _stats(10, 5, 0, 0, 0.0, 1, 0.0))])
	var snapshot := _snapshot({"FRONT_LEFT": _member("hero-1", "knight", "AnySlot", _stats(30, 10, 0, 0, 0.0, 5, 0.0), null)})
	var states := snapshot.hero_states()
	assert_eq(CombatResolver.resolve(null, states, group, 1, DEFAULT), {})
	assert_eq(CombatResolver.resolve(snapshot, states, null, 1, DEFAULT), {})
	assert_eq(CombatResolver.resolve(snapshot, states, group, -1, DEFAULT), {})
	assert_eq(CombatResolver.resolve(snapshot, states, group, HeroCatalog.MAX_SAFE_INT + 1, DEFAULT), {})
	assert_eq(CombatResolver.resolve(snapshot, states, group, 1, null), {})
	var broken: BalancingConfig = DEFAULT.duplicate(true)
	broken.max_combat_rounds = 0
	assert_eq(CombatResolver.resolve(snapshot, states, group, 1, broken), {})
	# A missing or out-of-range Hero HP state is rejected, never guessed.
	assert_eq(CombatResolver.resolve(snapshot, {}, group, 1, DEFAULT), {})
	assert_eq(CombatResolver.resolve(snapshot, {"hero-1": {"hp": 31}}, group, 1, DEFAULT), {})
	assert_eq(CombatResolver.resolve(snapshot, {"hero-1": {"hp": -1}}, group, 1, DEFAULT), {})
	assert_eq(CombatResolver.resolve(snapshot, {"hero-1": {"status": 4}}, group, 1, DEFAULT), {})
	# A valid call succeeds so the rejections above are meaningful.
	assert_false(CombatResolver.resolve(snapshot, states, group, 1, DEFAULT).is_empty())


func test_state_map_must_describe_the_party_exactly() -> void:
	var group := _group("g", [_enemy("e", "Front", "FrontRowFirst", _stats(10, 5, 0, 0, 0.0, 1, 0.0))])
	var snapshot := _snapshot({"FRONT_LEFT": _member("hero-1", "knight", "AnySlot", _stats(30, 10, 0, 0, 0.0, 5, 0.0), null)})
	# Exactly {hp, status} is required: an unexpected key is rejected, never ignored.
	assert_eq(CombatResolver.resolve(snapshot, {"hero-1": {"hp": 30, "status": 2, "extra": 1}}, group, 1, DEFAULT), {})
	# A status is mandatory; it is never defaulted.
	assert_eq(CombatResolver.resolve(snapshot, {"hero-1": {"hp": 30}}, group, 1, DEFAULT), {})
	# HP above the Hero's MaxHP is out of range even with both keys present.
	assert_eq(CombatResolver.resolve(snapshot, {"hero-1": {"hp": 31, "status": 2}}, group, 1, DEFAULT), {})
	# A status outside the Hero-status enum is rejected.
	assert_eq(CombatResolver.resolve(snapshot, {"hero-1": {"hp": 30, "status": 6}}, group, 1, DEFAULT), {})
	# An unrelated extra ID (the party holds only hero-1) makes the map malformed.
	assert_eq(CombatResolver.resolve(snapshot, {"hero-1": {"hp": 30, "status": 2}, "ghost": {"hp": 5, "status": 2}}, group, 1, DEFAULT), {})
	# The exact, in-range map still resolves.
	assert_false(CombatResolver.resolve(snapshot, {"hero-1": {"hp": 30, "status": 2}}, group, 1, DEFAULT).is_empty())


func test_state_map_omitting_a_party_member_is_rejected() -> void:
	var group := _group("g", [_enemy("e", "Front", "FrontRowFirst", _stats(10, 1, 0, 0, 0.0, 1, 0.0))])
	var snapshot := _snapshot({
		"FRONT_LEFT": _member("hero-1", "knight", "AnySlot", _stats(30, 10, 0, 0, 0.0, 5, 0.0), null),
		"BACK_LEFT": _member("hero-2", "ranger", "AnySlot", _stats(40, 10, 0, 0, 0.0, 6, 0.0), null),
	})
	# Only one of two members is described; the missing Hero cannot be guessed.
	assert_eq(CombatResolver.resolve(snapshot, {"hero-1": {"hp": 30, "status": 2}}, group, 1, DEFAULT), {})


func test_frozen_skill_without_a_configured_multiplier_is_rejected() -> void:
	var group := _group("g", [_enemy("e", "Front", "FrontRowFirst", _stats(10, 1, 0, 0, 0.0, 1, 0.0))])
	# The frozen skill points at a multiplier id absent from the balancing config.
	var hero := _member("hero-1", "wizard", "AnySlot", _stats(40, 10, 12, 0, 0.0, 8, 0.0),
		_skill("mystery", "Physical", "AnySlot", "not_in_config", 2))
	var snapshot := _snapshot({"FRONT_LEFT": hero})
	assert_eq(CombatResolver.resolve(snapshot, snapshot.hero_states(), group, 1, DEFAULT), {},
		"A frozen skill with no configured multiplier is rejected before any RNG is drawn.")
	# The identical party with a configured multiplier resolves normally.
	var ok := _member("hero-1", "wizard", "AnySlot", _stats(40, 10, 12, 0, 0.0, 8, 0.0),
		_skill("firebolt", "Physical", "AnySlot", "firebolt", 2))
	var ok_snapshot := _snapshot({"FRONT_LEFT": ok})
	assert_false(CombatResolver.resolve(ok_snapshot, ok_snapshot.hero_states(), group, 1, DEFAULT).is_empty())


func test_frozen_guard_skill_with_out_of_range_multiplier_is_rejected() -> void:
	var group := _group("g", [_enemy("e", "Front", "FrontRowFirst", _stats(10, 1, 0, 0, 0.0, 1, 0.0))])
	# A Guard whose frozen multiplier resolves above 1.0 is not a valid mitigation.
	var hero := _member("hero-1", "knight", "AnySlot", _stats(40, 10, 0, 0, 0.0, 8, 0.0),
		_skill("guard", "Guard", "Self", "aimed_shot", 2))
	var snapshot := _snapshot({"FRONT_LEFT": hero})
	assert_eq(CombatResolver.resolve(snapshot, snapshot.hero_states(), group, 1, DEFAULT), {},
		"A Guard reduction above 1.0 is rejected before resolution.")


# --- Targeting ---------------------------------------------------------------

func test_targeting_prefers_front_row_then_lowest_hp_then_ascending_id() -> void:
	# One fast, hard-hitting Hero versus two full-HP enemies: a Back enemy with a
	# lower ID and two Front enemies. FrontRowFirst must ignore the Back enemy and
	# break the Front tie by ascending ID.
	var hero := _member("hero-1", "knight", "FrontRowFirst", _stats(200, 100, 0, 0, 0.0, 99, 0.0), null)
	var snapshot := _snapshot({"FRONT_LEFT": hero})
	var group := _group("g", [
		_enemy("aaa-back", "Back", "AnySlot", _stats(10, 1, 0, 0, 0.0, 1, 0.0)),
		_enemy("m-front", "Front", "AnySlot", _stats(10, 1, 0, 0, 0.0, 1, 0.0)),
		_enemy("z-front", "Front", "AnySlot", _stats(10, 1, 0, 0, 0.0, 1, 0.0)),
	])
	var result := CombatResolver.resolve(snapshot, snapshot.hero_states(), group, 7, _forced())
	var hero_actions: Array = []
	for action in _actions(result):
		if action.actor_id == "hero-1":
			hero_actions.append(action.target_id)
	# Front row cleared by ascending ID before the Back enemy is ever hit.
	assert_eq(hero_actions, ["m-front", "z-front", "aaa-back"])
	assert_eq(result.outcome, "VICTORY")


func test_enemy_anyslot_targeting_reaches_the_back_row() -> void:
	var front := _member("front", "knight", "AnySlot", _stats(40, 1, 0, 100, 0.0, 1, 0.0), null)
	var back := _member("back", "wizard", "AnySlot", _stats(12, 1, 0, 0, 0.0, 1, 0.0), null)
	var snapshot := _snapshot({"FRONT_LEFT": front, "BACK_LEFT": back})
	# A single AnySlot enemy that hits hard and moves last.
	var group := _group("g", [_enemy("striker", "Back", "AnySlot", _stats(999, 40, 0, 0, 0.0, 1, 0.0))])
	var result := CombatResolver.resolve(snapshot, snapshot.hero_states(), group, 3, _forced())
	var first_target := ""
	for action in _actions(result):
		if action.actor_id == "striker":
			# The tied full-HP rows break by ascending ID, so the AnySlot enemy
			# reaches the back-row Hero first instead of being stuck on the front.
			first_target = action.target_id
			break
	assert_eq(first_target, "back", "AnySlot enemy can strike the back row.")


# --- Guard -------------------------------------------------------------------

func test_guard_halves_incoming_damage_once_until_the_casters_next_turn() -> void:
	var guard := _skill("guard", "Guard", "Self", "guard_reduction", 2)
	# Knight guards first (Initiative 99), the enemy strikes second.
	var hero := _member("hero-1", "knight", "AnySlot", _stats(500, 1, 0, 0, 0.0, 99, 0.0), guard)
	var snapshot := _snapshot({"FRONT_LEFT": hero})
	var group := _group("g", [_enemy("brute", "Front", "AnySlot", _stats(500, 30, 0, 0, 0.0, 1, 0.0))])
	var result := CombatResolver.resolve(snapshot, snapshot.hero_states(), group, 5, _forced())
	var round_one: Array = result.rounds[0].actions
	assert_eq(round_one[0].actor_id, "hero-1")
	assert_eq(round_one[0].action_kind, "Guard")
	assert_eq(round_one[0].action_name, "Guard")
	# Enemy damage: floor(max(1, 30 - 0) * (1 - 0.5)) = floor(15.0) = 15.
	assert_eq(round_one[1].actor_id, "brute")
	assert_eq(round_one[1].amount, 15, "Guard halves the first incoming hit.")
	# Guard expires at the start of the Knight's next turn; the Knight is on
	# cooldown, so round two's incoming hit is unmitigated.
	var round_two: Array = result.rounds[1].actions
	for action in round_two:
		if action.actor_id == "brute":
			assert_eq(action.amount, 30, "Guard does not persist past the caster's next turn.")


# --- Mend --------------------------------------------------------------------

func test_mend_restores_the_lowest_ratio_injured_living_ally() -> void:
	var mend := _skill("mend", "Heal", "LowestHpAlly", "mend", 2)
	var cleric := _member("cleric", "cleric", "AnySlot", _stats(40, 1, 18, 0, 0.0, 99, 0.0), mend)
	var hurt := _member("hurt", "knight", "AnySlot", _stats(50, 1, 0, 0, 0.0, 50, 0.0), null)
	var snapshot := _snapshot({"FRONT_LEFT": cleric, "FRONT_RIGHT": hurt})
	var group := _group("g", [_enemy("dummy", "Front", "AnySlot", _stats(999, 1, 0, 100, 0.0, 1, 0.0))])
	var states := snapshot.hero_states()
	states["hurt"] = {"hp": 20, "status": HeroData.HeroStatus.ON_EXPEDITION}
	var result := CombatResolver.resolve(snapshot, states, group, 9, _forced())
	var first: Dictionary = result.rounds[0].actions[0]
	assert_eq(first.actor_id, "cleric")
	assert_eq(first.action_kind, "Heal")
	# Heal amount floor(18 * 1.5) = 27; 20 + 27 clamped to MaxHP 50 = 47.
	assert_eq(first.target_id, "hurt", "Injured 40% ally is healed before the full-HP caster.")
	assert_eq(first.amount, 27)
	assert_eq(first.result_hp, 47)


func test_mend_heals_the_caster_when_it_is_the_only_injured_ally() -> void:
	var mend := _skill("mend", "Heal", "LowestHpAlly", "mend", 2)
	var cleric := _member("cleric", "cleric", "AnySlot", _stats(40, 1, 10, 0, 0.0, 99, 0.0), mend)
	var snapshot := _snapshot({"FRONT_LEFT": cleric})
	var group := _group("g", [_enemy("dummy", "Front", "AnySlot", _stats(999, 1, 0, 100, 0.0, 1, 0.0))])
	var states := snapshot.hero_states()
	states["cleric"] = {"hp": 5, "status": HeroData.HeroStatus.ON_EXPEDITION}
	var result := CombatResolver.resolve(snapshot, states, group, 2, _forced())
	var first: Dictionary = result.rounds[0].actions[0]
	assert_eq(first.action_kind, "Heal")
	assert_eq(first.target_id, "cleric", "Mend may heal the caster.")
	assert_eq(first.result_hp, 20) # 5 + floor(10 * 1.5)


func test_mend_falls_back_to_a_basic_attack_when_no_ally_is_injured() -> void:
	var mend := _skill("mend", "Heal", "LowestHpAlly", "mend", 2)
	var cleric := _member("cleric", "cleric", "AnySlot", _stats(40, 12, 10, 0, 0.0, 99, 0.0), mend)
	var snapshot := _snapshot({"FRONT_LEFT": cleric})
	var group := _group("g", [_enemy("dummy", "Front", "AnySlot", _stats(999, 1, 0, 0, 0.0, 1, 0.0))])
	var result := CombatResolver.resolve(snapshot, snapshot.hero_states(), group, 4, _forced())
	var first: Dictionary = result.rounds[0].actions[0]
	assert_eq(first.action_kind, "Attack", "No injured ally means a basic attack, not a wasted heal.")
	assert_eq(first.target_id, "dummy")


func test_mend_never_targets_or_resurrects_a_downed_ally() -> void:
	var mend := _skill("mend", "Heal", "LowestHpAlly", "mend", 2)
	var cleric := _member("cleric", "cleric", "AnySlot", _stats(40, 1, 10, 0, 0.0, 99, 0.0), mend)
	var downed := _member("downed", "knight", "AnySlot", _stats(50, 1, 0, 0, 0.0, 50, 0.0), null)
	var snapshot := _snapshot({"FRONT_LEFT": cleric, "FRONT_RIGHT": downed})
	var group := _group("g", [_enemy("dummy", "Front", "AnySlot", _stats(999, 1, 0, 100, 0.0, 1, 0.0))])
	var states := snapshot.hero_states()
	states["cleric"] = {"hp": 30, "status": HeroData.HeroStatus.ON_EXPEDITION}
	states["downed"] = {"hp": 0, "status": HeroData.HeroStatus.WOUNDED}
	var result := CombatResolver.resolve(snapshot, states, group, 6, _forced())
	for action in _actions(result):
		assert_ne(action.target_id, "downed", "A downed ally is never a heal target.")
		if action.actor_id == "downed":
			fail_test("A downed Hero must not act.")
	# The downed Hero stays at zero HP: no resurrection.
	assert_eq(result.final_hero_states["downed"].hp, 0)
	assert_true(result.final_hero_states.has("cleric"))


# --- Cooldowns ---------------------------------------------------------------

func test_skill_cooldown_counts_personal_turns_between_uses() -> void:
	# Aimed Shot (cooldown 2) is ready on personal turns 0 and 3, basic on 1 and 2.
	var aimed := _skill("aimed_shot", "Physical", "AnySlot", "aimed_shot", 2)
	var ranger := _member("ranger", "ranger", "AnySlot", _stats(999, 10, 0, 0, 0.0, 99, 0.0), aimed)
	var snapshot := _snapshot({"FRONT_LEFT": ranger})
	# A near-invincible enemy so the fight runs long enough to observe cooldowns.
	var group := _group("g", [_enemy("wall", "Front", "AnySlot", _stats(100000, 1, 0, 0, 0.0, 1, 0.0))])
	var result := CombatResolver.resolve(snapshot, snapshot.hero_states(), group, 8, _forced())
	var kinds: Array = []
	for action in _actions(result):
		if action.actor_id == "ranger":
			kinds.append(action.action_kind)
	assert_eq(kinds.slice(0, 4), ["Skill", "Attack", "Attack", "Skill"])


# --- Round cap and elimination ----------------------------------------------

func test_round_cap_without_elimination_is_a_retreat() -> void:
	var config := _forced()
	config.max_combat_rounds = 1
	# One damage per hit against huge HP pools: nobody is eliminated in one round.
	var hero := _member("hero-1", "knight", "AnySlot", _stats(9999, 1, 0, 100, 0.0, 50, 0.0), null)
	var snapshot := _snapshot({"FRONT_LEFT": hero})
	var group := _group("g", [_enemy("foe", "Front", "AnySlot", _stats(9999, 1, 0, 100, 0.0, 1, 0.0))])
	var result := CombatResolver.resolve(snapshot, snapshot.hero_states(), group, 1, config)
	assert_eq(result.rounds.size(), 1)
	assert_eq(result.outcome, "RETREAT")
	assert_gt(result.final_hero_states["hero-1"].hp, 0)


func test_party_wipe_is_a_defeat_and_downed_actors_are_skipped() -> void:
	var hero := _member("hero-1", "knight", "AnySlot", _stats(10, 1, 0, 0, 0.0, 1, 0.0), null)
	var snapshot := _snapshot({"FRONT_LEFT": hero})
	# The enemy strikes first and hits hard enough to end the fight immediately.
	var group := _group("g", [_enemy("slayer", "Front", "AnySlot", _stats(999, 100, 0, 0, 0.0, 99, 0.0))])
	var result := CombatResolver.resolve(snapshot, snapshot.hero_states(), group, 1, _forced())
	assert_eq(result.outcome, "DEFEAT")
	assert_eq(result.final_hero_states["hero-1"].hp, 0)
	# After the wipe the downed Hero never acts again.
	for action in _actions(result):
		assert_ne(action.actor_id, "hero-1")


func test_downed_hero_ends_wounded_while_survivors_stay_on_expedition() -> void:
	# hero-1 is struck down before it can act; hero-2 then finishes the lone enemy.
	var down := _member("hero-1", "knight", "FrontRowFirst", _stats(10, 1, 0, 0, 0.0, 1, 0.0), null)
	var winner := _member("hero-2", "ranger", "AnySlot", _stats(80, 40, 0, 0, 0.0, 40, 0.0), null)
	var snapshot := _snapshot({"FRONT_LEFT": down, "BACK_LEFT": winner})
	var group := _group("g", [_enemy("slayer", "Front", "FrontRowFirst", _stats(15, 100, 0, 0, 0.0, 50, 0.0))])
	var result := CombatResolver.resolve(snapshot, snapshot.hero_states(), group, 1, _forced())
	assert_eq(result.outcome, "VICTORY")
	assert_eq(result.final_hero_states["hero-1"].hp, 0)
	assert_eq(result.final_hero_states["hero-1"].status, HeroData.HeroStatus.WOUNDED,
		"A Hero at 0 HP ends the fight Wounded, with no revival.")
	assert_gt(result.final_hero_states["hero-2"].hp, 0)
	assert_eq(result.final_hero_states["hero-2"].status, HeroData.HeroStatus.ON_EXPEDITION,
		"A survivor keeps the On Expedition status it entered combat with.")


# --- Determinism, isolation, and immutability --------------------------------

func test_identical_calls_are_byte_identical_and_ignore_global_randomness() -> void:
	var hero := _member("hero-1", "ranger", "AnySlot", _stats(60, 14, 0, 2, 0.05, 12, 0.1),
		_skill("aimed_shot", "Physical", "AnySlot", "aimed_shot", 2))
	var snapshot := _snapshot({"FRONT_LEFT": hero})
	var group := CombatCatalog.BANDIT_SKIRMISHERS
	var first := CombatResolver.resolve(snapshot, snapshot.hero_states(), group, 4242, DEFAULT)
	seed(99)
	var expected_global := randi()
	seed(99)
	var second := CombatResolver.resolve(snapshot, snapshot.hero_states(), group, 4242, DEFAULT)
	assert_eq(randi(), expected_global, "The simulation never advances the global RNG.")
	assert_eq(JSON.stringify(first), JSON.stringify(second), "Same seed and inputs are identical.")
	# Maximum seed remains in range and resolves.
	assert_false(CombatResolver.resolve(snapshot, snapshot.hero_states(), group, HeroCatalog.MAX_SAFE_INT, DEFAULT).is_empty())


func test_resolution_never_mutates_its_inputs() -> void:
	var hero := _member("hero-1", "cleric", "AnySlot", _stats(50, 8, 12, 3, 0.0, 20, 0.0),
		_skill("mend", "Heal", "LowestHpAlly", "mend", 2))
	var snapshot := _snapshot({"FRONT_LEFT": hero})
	var slots_before := JSON.stringify(snapshot.slots)
	var states := snapshot.hero_states()
	states["hero-1"] = {"hp": 25, "status": HeroData.HeroStatus.ON_EXPEDITION}
	var states_before := JSON.stringify(states)
	CombatResolver.resolve(snapshot, states, CombatCatalog.FOREST_WOLVES, 77, DEFAULT)
	assert_eq(JSON.stringify(snapshot.slots), slots_before, "The frozen party is untouched.")
	assert_eq(JSON.stringify(states), states_before, "The caller HP map is untouched.")


# --- Catalog validation ------------------------------------------------------

func test_authored_combat_catalog_is_valid() -> void:
	assert_true(CombatCatalog.validate_catalog(DEFAULT))
	for skill in CombatCatalog.skills():
		assert_true(CombatCatalog.validate_skill(skill), String(skill.skill_id))
	for group in CombatCatalog.enemy_groups():
		assert_true(CombatCatalog.validate_enemy_group(group), String(group.group_id))
	assert_null(CombatCatalog.skill_by_id("missing"))
	assert_null(CombatCatalog.enemy_group_by_id("missing"))


func test_skill_validation_enforces_kind_target_agreement_and_bounds() -> void:
	var base: SkillResource = CombatCatalog.FIREBOLT.duplicate(true)
	assert_true(CombatCatalog.validate_skill(base))
	for change in [["skill_id", &""], ["display_name", ""], ["class_id", &""], ["multiplier_id", &""],
			["kind", "Nope"], ["target_rule", "Everywhere"], ["cooldown", -1],
			["cooldown", CombatCatalog.MAX_COOLDOWN + 1]]:
		var skill: SkillResource = CombatCatalog.FIREBOLT.duplicate(true)
		skill.set(change[0], change[1])
		assert_false(CombatCatalog.validate_skill(skill), str(change))
	var guard: SkillResource = CombatCatalog.GUARD.duplicate(true)
	guard.target_rule = "AnySlot"
	assert_false(CombatCatalog.validate_skill(guard), "Guard must target Self.")
	var mend: SkillResource = CombatCatalog.MEND.duplicate(true)
	mend.target_rule = "FrontRowFirst"
	assert_false(CombatCatalog.validate_skill(mend), "Heal must target LowestHpAlly.")


func test_enemy_group_validation_bounds_ids_rows_and_finite_stats() -> void:
	var block := _enemy("e1", "Front", "FrontRowFirst", _stats(45, 14, 0, 6, 0.05, 5, 0.05))
	assert_true(CombatCatalog.validate_enemy_group(_group("g", [block])))
	assert_false(CombatCatalog.validate_enemy_group(_group("g", [])))
	assert_false(CombatCatalog.validate_enemy_group(_group("", [block])))
	var dup := _group("g", [block, _enemy("e1", "Back", "AnySlot", _stats(10, 1, 0, 0, 0.0, 1, 0.0))])
	assert_false(CombatCatalog.validate_enemy_group(dup), "Enemy IDs must be unique.")
	for stats in [
		_stats(0, 14, 0, 6, 0.05, 5, 0.05),
		_stats(45, -1, 0, 6, 0.05, 5, 0.05),
		{"MaxHP": 45, "Attack": 14, "MagicPower": 0, "Defense": 6, "Evasion": 1.5, "Initiative": 5, "CritChance": 0.05},
		{"MaxHP": 45, "Attack": 14, "MagicPower": 0, "Defense": 6, "Evasion": INF, "Initiative": 5, "CritChance": 0.05},
	]:
		assert_false(CombatCatalog.validate_enemy_group(_group("g", [_enemy("e", "Front", "AnySlot", stats)])), str(stats))
	var short := _enemy("e", "Front", "AnySlot", {"MaxHP": 10, "Attack": 1})
	assert_false(CombatCatalog.validate_enemy_group(_group("g", [short])), "All seven stat keys are required.")


func test_combat_balancing_validation_rejects_probabilities_and_missing_multipliers() -> void:
	assert_true(CombatCatalog.validate_combat_balancing(DEFAULT))
	for change in [["max_combat_rounds", 0], ["max_combat_rounds", CombatCatalog.MAX_COMBAT_ROUNDS + 1],
			["combat_recovery_seconds", -1], ["base_hit_chance", 1.5], ["min_hit_chance", -0.1],
			["max_crit_chance", 2.0], ["basic_attack_damage_multiplier", -1.0]]:
		var config: BalancingConfig = DEFAULT.duplicate(true)
		config.set(change[0], change[1])
		assert_false(CombatCatalog.validate_combat_balancing(config), str(change))
	var swapped: BalancingConfig = DEFAULT.duplicate(true)
	swapped.min_hit_chance = 0.9
	swapped.max_hit_chance = 0.5
	assert_false(CombatCatalog.validate_combat_balancing(swapped), "min may not exceed max.")
	var missing: BalancingConfig = DEFAULT.duplicate(true)
	missing.skill_damage_multipliers = {"aimed_shot": 1.6, "firebolt": 1.8, "guard_reduction": 0.5}
	assert_false(CombatCatalog.validate_combat_balancing(missing), "Every skill needs a multiplier.")
	var big_guard: BalancingConfig = DEFAULT.duplicate(true)
	big_guard.skill_damage_multipliers = missing.skill_damage_multipliers.duplicate()
	big_guard.skill_damage_multipliers.guard_reduction = 1.5
	big_guard.skill_damage_multipliers.mend = 1.5
	assert_false(CombatCatalog.validate_combat_balancing(big_guard), "Guard reduction is a fraction.")


func test_combat_result_structural_validation() -> void:
	var group := CombatCatalog.BANDIT_SKIRMISHERS
	var hero := _member("hero-1", "ranger", "AnySlot", _stats(60, 14, 0, 2, 0.05, 12, 0.1),
		_skill("aimed_shot", "Physical", "AnySlot", "aimed_shot", 2))
	var snapshot := _snapshot({"FRONT_LEFT": hero})
	var result := CombatResolver.resolve(snapshot, snapshot.hero_states(), group, 55, DEFAULT)
	# Round-trip through JSON to mimic a persisted, reloaded journal.
	var restored: Dictionary = JSON.parse_string(JSON.stringify(result))
	assert_true(CombatCatalog.validate_combat_result(restored))
	assert_false(CombatCatalog.validate_combat_result({}))
	for change in [["outcome", "WIN"], ["gold", 1], ["rounds", {}], ["final_hero_states", []]]:
		var bad: Dictionary = restored.duplicate(true)
		bad[change[0]] = change[1]
		assert_false(CombatCatalog.validate_combat_result(bad), str(change))
	var bad_action: Dictionary = restored.duplicate(true)
	bad_action.rounds = restored.rounds.duplicate(true)
	bad_action.rounds[0] = restored.rounds[0].duplicate(true)
	bad_action.rounds[0].actions = restored.rounds[0].actions.duplicate(true)
	bad_action.rounds[0].actions[0] = restored.rounds[0].actions[0].duplicate(true)
	bad_action.rounds[0].actions[0].action_kind = "Dance"
	assert_false(CombatCatalog.validate_combat_result(bad_action))


# --- Hand-reviewed golden result ---------------------------------------------

func test_fixed_seed_golden_result_is_exact() -> void:
	# A fully specified party and enemy group with the shipped default balancing.
	# The entire outcome dictionary is locked so any change to ordering, formulas,
	# or RNG usage is caught, not merely a run-to-run comparison.
	var knight := _member("hero-1", "knight", "FrontRowFirst", _stats(70, 18, 4, 8, 0.05, 11, 0.0),
		_skill("guard", "Guard", "Self", "guard_reduction", 2))
	var ranger := _member("hero-2", "ranger", "AnySlot", _stats(48, 16, 3, 4, 0.10, 14, 0.0),
		_skill("aimed_shot", "Physical", "AnySlot", "aimed_shot", 2))
	var snapshot := _snapshot({"FRONT_LEFT": knight, "BACK_LEFT": ranger})
	var group := _group("bandit_skirmishers", [
		_enemy("bandit_thug", "Front", "FrontRowFirst", _stats(30, 12, 0, 4, 0.05, 6, 0.0)),
		_enemy("bandit_archer", "Back", "AnySlot", _stats(22, 10, 0, 2, 0.08, 8, 0.0)),
	])
	var result := CombatResolver.resolve(snapshot, snapshot.hero_states(), group, 20240607, DEFAULT)
	assert_eq(JSON.stringify(result), GOLDEN)


const GOLDEN := """{"final_hero_states":{"hero-1":{"hp":64,"status":2},"hero-2":{"hp":48,"status":2}},"gold":0,"outcome":"VICTORY","rounds":[{"actions":[{"action_kind":"Skill","action_name":"Aimed Shot","actor_id":"hero-2","actor_name":"Hero 2","amount":23,"result_hp":0,"target_id":"bandit_archer","target_name":"Bandit Archer","was_crit":false,"was_miss":false},{"action_kind":"Guard","action_name":"Guard","actor_id":"hero-1","actor_name":"Hero 1","amount":0,"result_hp":70,"target_id":"hero-1","target_name":"Hero 1","was_crit":false,"was_miss":false},{"action_kind":"Attack","action_name":"Basic Attack","actor_id":"bandit_thug","actor_name":"Bandit Thug","amount":2,"result_hp":68,"target_id":"hero-1","target_name":"Hero 1","was_crit":false,"was_miss":false}],"round_number":1},{"actions":[{"action_kind":"Attack","action_name":"Basic Attack","actor_id":"hero-2","actor_name":"Hero 2","amount":12,"result_hp":18,"target_id":"bandit_thug","target_name":"Bandit Thug","was_crit":false,"was_miss":false},{"action_kind":"Attack","action_name":"Basic Attack","actor_id":"hero-1","actor_name":"Hero 1","amount":14,"result_hp":4,"target_id":"bandit_thug","target_name":"Bandit Thug","was_crit":false,"was_miss":false},{"action_kind":"Attack","action_name":"Basic Attack","actor_id":"bandit_thug","actor_name":"Bandit Thug","amount":4,"result_hp":64,"target_id":"hero-1","target_name":"Hero 1","was_crit":false,"was_miss":false}],"round_number":2},{"actions":[{"action_kind":"Attack","action_name":"Basic Attack","actor_id":"hero-2","actor_name":"Hero 2","amount":12,"result_hp":0,"target_id":"bandit_thug","target_name":"Bandit Thug","was_crit":false,"was_miss":false}],"round_number":3}]}"""

