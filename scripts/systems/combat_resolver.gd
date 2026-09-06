class_name CombatResolver
extends RefCounted
## Pure, stateless auto-combat simulation. No scene tree, GameState, clock, or
## global RNG access: everything is derived from the seeded local RNG and the
## frozen inputs, so an identical call always yields an identical result.

const OUTCOMES := ["VICTORY", "DEFEAT", "RETREAT"]
const HERO_SIDE := "HERO"
const ENEMY_SIDE := "ENEMY"


## Returns a JSON-safe outcome dictionary, or {} for malformed input/config so a
## caller can distinguish and reject it. Never mutates its arguments.
static func resolve(
		party: ExpeditionPartySnapshot, current_hero_states: Dictionary,
		enemy_group: EnemyGroupResource, seed: int, balancing: BalancingConfig) -> Dictionary:
	if party == null or not ExpeditionPartySnapshot.valid(party.slots):
		return {}
	if not ExpeditionCatalog.integer(seed) or not CombatCatalog.validate_combat_balancing(balancing):
		return {}
	if not CombatCatalog.validate_enemy_group(enemy_group):
		return {}
	if not current_hero_states is Dictionary:
		return {}
	var combatants := _build_combatants(party, current_hero_states, enemy_group)
	if combatants.is_empty():
		return {}
	# Combat runs on the Party's frozen skills, so every skill actually used must
	# resolve a configured multiplier. A missing key is an error, never a silent
	# zero-damage skill, and it is rejected before any RNG is drawn.
	if not _frozen_skills_configured(combatants, balancing):
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rounds: Array = []
	var round_number := 1
	while round_number <= balancing.max_combat_rounds and _living(combatants, HERO_SIDE) and _living(combatants, ENEMY_SIDE):
		var actions: Array = []
		for actor in _turn_order(combatants, rng):
			if int(actor.hp) == 0:
				continue
			if not _living(combatants, HERO_SIDE) or not _living(combatants, ENEMY_SIDE):
				break
			actions.append(_resolve_action(actor, combatants, rng, balancing))
		rounds.append({"round_number": round_number, "actions": actions})
		round_number += 1
	var outcome := "RETREAT"
	if not _living(combatants, HERO_SIDE):
		outcome = "DEFEAT"
	elif not _living(combatants, ENEMY_SIDE):
		outcome = "VICTORY"
	var final_states := {}
	for combatant in combatants:
		if combatant.side == HERO_SIDE:
			# A Hero reduced to 0 HP is Wounded for the rest of the run; a survivor
			# keeps the On Expedition status it entered with. There is no revival.
			var status := int(combatant.status)
			if int(combatant.hp) == 0:
				status = HeroData.HeroStatus.WOUNDED
			final_states[combatant.id] = {"hp": int(combatant.hp), "status": status}
	return {"outcome": outcome, "rounds": rounds, "final_hero_states": final_states, "gold": 0}


static func _build_combatants(
		party: ExpeditionPartySnapshot, current_hero_states: Dictionary,
		enemy_group: EnemyGroupResource) -> Array:
	var combatants: Array = []
	var slots := party.slots
	var front := [PartyData.SLOT_NAMES[PartyData.FormationSlot.FRONT_LEFT], PartyData.SLOT_NAMES[PartyData.FormationSlot.FRONT_RIGHT]]
	var canonical := 0
	var member_count := 0
	for slot in PartyData.SLOT_NAMES:
		var member: Variant = slots[slot]
		if member == null:
			continue
		member_count += 1
		# The current-state entry must carry exactly an integer HP and status for
		# this Hero; a missing status or an unexpected key is rejected, never guessed.
		var state: Variant = current_hero_states.get(member.hero_id)
		if not state is Dictionary or not HeroCatalog.has_exact_keys(state, ["hp", "status"]):
			return []
		var max_hp := int(member.derived_stats.MaxHP)
		if not ExpeditionCatalog.integer(state.hp, 0, max_hp):
			return []
		if not ExpeditionCatalog.integer(state.status, 0, HeroData.HeroStatus.DEAD):
			return []
		combatants.append(_combatant(
			member.hero_id, member.hero_name, HERO_SIDE, "Front" if slot in front else "Back",
			member.basic_attack_target_rule, member.derived_stats, int(state.hp), max_hp, member.skill, int(state.status), canonical))
		canonical += 1
	# The map must describe every Party Hero and nothing else: an extra, unrelated
	# ID (or a duplicate/missing entry) is a malformed input.
	if current_hero_states.size() != member_count:
		return []
	for enemy in enemy_group.enemies:
		var max_hp := int(enemy.derived_stats.MaxHP)
		combatants.append(_combatant(
			String(enemy.enemy_id), enemy.display_name, ENEMY_SIDE, enemy.row,
			enemy.basic_attack_target_rule, enemy.derived_stats, max_hp, max_hp, null,
			HeroData.HeroStatus.ON_EXPEDITION, canonical))
		canonical += 1
	return combatants


static func _combatant(
		id: String, name: String, side: String, row: String, target_rule: String,
		stats: Dictionary, hp: int, max_hp: int, skill: Variant, status: int, canonical: int) -> Dictionary:
	return {
		"id": id, "name": name, "side": side, "row": row, "target_rule": target_rule,
		"stats": stats, "hp": hp, "max_hp": max_hp,
		"skill": skill if skill is Dictionary else null, "status": status,
		"canonical": canonical, "guard_reduction": 0.0, "own_turns": 0, "skill_ready_at": 0,
	}


static func _living(combatants: Array, side: String) -> bool:
	for combatant in combatants:
		if combatant.side == side and int(combatant.hp) > 0:
			return true
	return false


## Every frozen combatant skill must resolve a finite, nonnegative multiplier from
## the balancing config; Guard's fraction is additionally bounded to [0, 1]. The
## resolver reads the Party's frozen skills, which the catalog-level balancing check
## cannot see, so this guard prevents an invalid index during resolution.
static func _frozen_skills_configured(combatants: Array, balancing: BalancingConfig) -> bool:
	for combatant in combatants:
		var skill: Variant = combatant.skill
		if skill == null:
			continue
		var multiplier: Variant = balancing.skill_damage_multipliers.get(String(skill.multiplier_id))
		if not ExpeditionCatalog.weight(multiplier):
			return false
		if String(skill.kind) == "Guard" and float(multiplier) > 1.0:
			return false
	return true


## Canonical ordering is fixed before the seeded tiebreak rolls so identical
## Initiative resolves deterministically across platforms. One roll is drawn per
## combatant each round in canonical order.
static func _turn_order(combatants: Array, rng: RandomNumberGenerator) -> Array:
	var entries: Array = []
	for combatant in combatants:
		entries.append({"combatant": combatant, "tiebreak": rng.randf()})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ia := int(a.combatant.stats.Initiative)
		var ib := int(b.combatant.stats.Initiative)
		if ia != ib:
			return ia > ib
		if a.tiebreak != b.tiebreak:
			return a.tiebreak < b.tiebreak
		return int(a.combatant.canonical) < int(b.combatant.canonical))
	var order: Array = []
	for entry in entries:
		order.append(entry.combatant)
	return order


static func _resolve_action(
		actor: Dictionary, combatants: Array, rng: RandomNumberGenerator, balancing: BalancingConfig) -> Dictionary:
	# A Guard from the actor's previous turn expires at the start of this turn.
	actor.guard_reduction = 0.0
	var turn := int(actor.own_turns)
	actor.own_turns = turn + 1
	var skill: Variant = actor.skill
	var use_skill := skill != null and turn >= int(actor.skill_ready_at)
	if use_skill:
		match skill.kind:
			"Guard":
				actor.skill_ready_at = turn + 1 + int(skill.cooldown)
				var reduction: float = float(balancing.skill_damage_multipliers[String(skill.multiplier_id)])
				actor.guard_reduction = reduction
				return _record(actor, actor, "Guard", skill.display_name, false, false, 0, int(actor.hp))
			"Heal":
				var ally: Variant = _choose_target(actor, combatants, "LowestHpAlly")
				if ally != null:
					actor.skill_ready_at = turn + 1 + int(skill.cooldown)
					return _resolve_heal(actor, ally, float(balancing.skill_damage_multipliers[String(skill.multiplier_id)]), skill.display_name)
			_:
				var target: Variant = _choose_target(actor, combatants, skill.target_rule)
				if target != null:
					actor.skill_ready_at = turn + 1 + int(skill.cooldown)
					var multiplier: float = float(balancing.skill_damage_multipliers[String(skill.multiplier_id)])
					return _resolve_attack(actor, target, multiplier, skill.kind, "Skill", skill.display_name, rng, balancing)
	var basic_target: Variant = _choose_target(actor, combatants, actor.target_rule)
	if basic_target == null:
		return _record(actor, actor, "Attack", "Basic Attack", true, false, 0, int(actor.hp))
	return _resolve_attack(actor, basic_target, balancing.basic_attack_damage_multiplier, "Physical", "Attack", "Basic Attack", rng, balancing)


static func _choose_target(actor: Dictionary, combatants: Array, rule: String) -> Variant:
	if rule == "Self":
		return actor
	var candidates: Array = []
	if rule == "LowestHpAlly":
		for combatant in combatants:
			if combatant.side == actor.side and int(combatant.hp) > 0 and int(combatant.hp) < int(combatant.max_hp):
				candidates.append(combatant)
	else:
		var opponents: Array = []
		for combatant in combatants:
			if combatant.side != actor.side and int(combatant.hp) > 0:
				opponents.append(combatant)
		if rule == "FrontRowFirst":
			var front: Array = []
			for opponent in opponents:
				if opponent.row == "Front":
					front.append(opponent)
			candidates = front if not front.is_empty() else opponents
		else:
			candidates = opponents
	var best: Variant = null
	var best_ratio := 2.0
	for candidate in candidates:
		var ratio := float(candidate.hp) / float(candidate.max_hp)
		if best == null or ratio < best_ratio or (ratio == best_ratio and String(candidate.id) < String(best.id)):
			best = candidate
			best_ratio = ratio
	return best


static func hit_chance(base_hit: float, evasion: float, min_hit: float, max_hit: float) -> float:
	return clampf(base_hit - evasion, min_hit, max_hit)


## FinalDamage = max(1, floor(max(1, Attack*mult - Defense) * crit * (1 - guard))).
## Floors exactly once, after mitigation, crit, and Guard reduction.
static func damage_amount(
		attack_stat: float, multiplier: float, defense: float, is_crit: bool,
		critical_multiplier: float, guard_reduction: float) -> int:
	var mitigated := maxf(1.0, attack_stat * multiplier - defense)
	var scaled := mitigated * (critical_multiplier if is_crit else 1.0)
	scaled *= (1.0 - guard_reduction)
	return maxi(1, floori(scaled))


static func heal_amount(magic_power: float, multiplier: float) -> int:
	return maxi(0, floori(magic_power * multiplier))


static func _resolve_attack(
		actor: Dictionary, target: Dictionary, multiplier: float, kind: String,
		action_kind: String, action_name: String, rng: RandomNumberGenerator, balancing: BalancingConfig) -> Dictionary:
	var chance := hit_chance(balancing.base_hit_chance, float(target.stats.Evasion), balancing.min_hit_chance, balancing.max_hit_chance)
	if rng.randf() >= chance:
		return _record(actor, target, action_kind, action_name, true, false, 0, int(target.hp))
	var crit_chance := clampf(float(actor.stats.CritChance), 0.0, balancing.max_crit_chance)
	var is_crit := rng.randf() < crit_chance
	var attack_stat := float(actor.stats.MagicPower) if kind == "Magic" else float(actor.stats.Attack)
	var amount := damage_amount(
		attack_stat, multiplier, float(target.stats.Defense), is_crit,
		balancing.critical_damage_multiplier, float(target.guard_reduction))
	target.hp = maxi(0, int(target.hp) - amount)
	return _record(actor, target, action_kind, action_name, false, is_crit, amount, int(target.hp))


static func _resolve_heal(actor: Dictionary, target: Dictionary, multiplier: float, action_name: String) -> Dictionary:
	var amount := heal_amount(float(actor.stats.MagicPower), multiplier)
	target.hp = mini(int(target.max_hp), int(target.hp) + amount)
	return _record(actor, target, "Heal", action_name, false, false, amount, int(target.hp))


static func _record(
		actor: Dictionary, target: Dictionary, action_kind: String, action_name: String,
		was_miss: bool, was_crit: bool, amount: int, result_hp: int) -> Dictionary:
	return {
		"actor_id": actor.id, "actor_name": actor.name,
		"action_kind": action_kind, "action_name": action_name,
		"target_id": target.id, "target_name": target.name,
		"was_miss": was_miss, "was_crit": was_crit, "amount": amount, "result_hp": result_hp,
	}
