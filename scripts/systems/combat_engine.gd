class_name CombatEngine
extends RefCounted
## Pure encounter resolution. Only a local seeded RNG and detached working data change.


static func resolve_combat(
		party: ExpeditionPartySnapshot, current_hero_states: Dictionary,
		enemy_group: EnemyGroupResource, seed: int, balancing: BalancingConfig) -> Dictionary:
	if not ExpeditionCatalog.integer(seed):
		return {"error": "Invalid combat seed."}
	var error: String = _validation_error(party, current_hero_states, enemy_group, balancing)
	if not error.is_empty():
		return {"error": error}
	var combatants: Dictionary = _combatants(party.slots, current_hero_states, enemy_group)
	if not _safe_amounts(combatants, balancing):
		return {"error": "Combat amounts exceed the safe integer limit."}
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed
	var rounds: Array = []
	for round_number in range(1, balancing.max_combat_rounds + 1):
		if not _both_sides_alive(combatants):
			break
		var actions: Array = []
		for actor in _turn_order(combatants, rng):
			if not _both_sides_alive(combatants):
				break
			if actor.hp == 0:
				continue
			actor.guard = 1.0
			actions.append(_act(actor, combatants, rng, balancing))
		rounds.append({"round_number": round_number, "actions": actions})
	var outcome: String = "RETREAT"
	if not _side_alive(combatants, false):
		outcome = "VICTORY"
	elif not _side_alive(combatants, true):
		outcome = "DEFEAT"
	var final_hero_states: Dictionary = {}
	var enemy_states: Dictionary = {}
	var ids: Array = combatants.keys()
	ids.sort()
	for id in ids:
		var actor: Dictionary = combatants[id]
		if actor.hero:
			final_hero_states[id] = {
				"hp": int(actor.hp),
				"status": HeroData.HeroStatus.WOUNDED if actor.hp == 0 or outcome == "DEFEAT" else HeroData.HeroStatus.IDLE,
			}
		else:
			enemy_states[id] = {
				"name": actor.name, "max_hp": int(actor.stats.MaxHP),
				"hp": int(actor.hp), "row": actor.row,
			}
	return {
		"gold": 0, "outcome": outcome, "rounds": rounds,
		"final_hero_states": final_hero_states, "enemy_states": enemy_states,
	}


static func _validation_error(
		party: ExpeditionPartySnapshot, states: Dictionary,
		group: EnemyGroupResource, balancing: BalancingConfig) -> String:
	if party == null or not ExpeditionPartySnapshot.valid(party.slots):
		return "Invalid Party snapshot."
	if not CombatCatalog.validate_enemy_group(group):
		return "Invalid enemy group."
	var members: Dictionary = party.slots
	var ids: Array = []
	var skills: Array = []
	for member in members.values():
		if member == null:
			continue
		if not member.has("active_skill"):
			return "Combat requires a frozen active skill for every Hero."
		if not CombatCatalog.validate_stats(member.derived_stats):
			return "Invalid Hero combat stats."
		ids.append(member.hero_id)
		skills.append(member.active_skill)
	if not HeroCatalog.has_exact_keys(states, ids):
		return "Current Hero states must cover exactly the Party."
	for member in members.values():
		if member == null:
			continue
		var state: Variant = states[member.hero_id]
		if not state is Dictionary or not HeroCatalog.has_exact_keys(state, ["hp", "status"]):
			return "Invalid current Hero state."
		if not ExpeditionCatalog.integer(state.hp, 0, int(member.derived_stats.MaxHP)):
			return "Current Hero HP is outside its bounds."
		if not ExpeditionCatalog.integer(state.status) or state.status not in [HeroData.HeroStatus.IDLE, HeroData.HeroStatus.WOUNDED]:
			return "Invalid simulation Hero status."
		if state.hp == 0 and state.status != HeroData.HeroStatus.WOUNDED:
			return "Zero-HP Heroes must be Wounded."
	for enemy in group.enemies:
		if enemy.combatant_id in ids:
			return "Hero and enemy IDs must not collide."
	if not CombatCatalog.validate_balancing(balancing, skills):
		return "Invalid combat balancing or missing skill multiplier."
	return ""


static func _combatants(members: Dictionary, states: Dictionary, group: EnemyGroupResource) -> Dictionary:
	var result: Dictionary = {}
	for index in range(PartyData.SLOT_NAMES.size()):
		var member: Variant = members[PartyData.SLOT_NAMES[index]]
		if member == null:
			continue
		result[member.hero_id] = {
			"id": member.hero_id, "name": member.hero_name, "hero": true,
			"row": "Front" if index < 2 else "Back", "stats": member.derived_stats,
			"hp": int(states[member.hero_id].hp),
			"basic_attack_target_rule": member.basic_attack_target_rule,
			"skill": member.active_skill, "cooldown": 0, "guard": 1.0,
		}
	for enemy in group.enemies:
		result[enemy.combatant_id] = {
			"id": enemy.combatant_id, "name": enemy.display_name, "hero": false,
			"row": enemy.row, "stats": enemy.derived_stats.duplicate(true),
			"hp": int(enemy.derived_stats.MaxHP),
			"basic_attack_target_rule": enemy.basic_attack_target_rule,
			"skill": {}, "cooldown": 0, "guard": 1.0,
		}
	return result


static func _safe_amounts(combatants: Dictionary, balancing: BalancingConfig) -> bool:
	var maximum_guard: float = 1.0
	for actor in combatants.values():
		if not actor.skill.is_empty() and actor.skill.effect == "Guard":
			maximum_guard = maxf(maximum_guard, float(balancing.skill_damage_multipliers[actor.skill.skill_id]))
	var maximum_crit: float = maxf(1.0, balancing.critical_damage_multiplier)
	for actor in combatants.values():
		var basic: float = float(actor.stats.Attack) * balancing.basic_attack_damage_multiplier
		if not _safe_damage(basic, maximum_crit, maximum_guard):
			return false
		if actor.skill.is_empty() or actor.skill.effect == "Guard":
			continue
		var power: float = float(actor.stats.Attack if actor.skill.effect == "Physical" else actor.stats.MagicPower)
		var amount: float = power * float(balancing.skill_damage_multipliers[actor.skill.skill_id])
		if actor.skill.effect == "Heal":
			if not _safe_number(amount):
				return false
		elif not _safe_damage(amount, maximum_crit, maximum_guard):
			return false
	return true


static func _safe_damage(base: float, crit: float, guard: float) -> bool:
	var critical: float = maxf(1.0, base) * crit
	return _safe_number(base) and _safe_number(critical) and _safe_number(critical * guard)


static func _safe_number(value: float) -> bool:
	return is_finite(value) and value >= 0.0 and value <= float(HeroCatalog.MAX_SAFE_INT)


static func _turn_order(combatants: Dictionary, rng: RandomNumberGenerator) -> Array:
	var ids: Array = combatants.keys()
	ids.sort()
	var order: Array = []
	for id in ids:
		var actor: Dictionary = combatants[id]
		if actor.hp > 0:
			actor.tiebreak = rng.randi()
			order.append(actor)
	order.sort_custom(_turn_before)
	return order


static func _turn_before(left: Dictionary, right: Dictionary) -> bool:
	if left.stats.Initiative != right.stats.Initiative:
		return left.stats.Initiative > right.stats.Initiative
	if left.tiebreak != right.tiebreak:
		return left.tiebreak < right.tiebreak
	return left.id < right.id


static func _act(actor: Dictionary, combatants: Dictionary, rng: RandomNumberGenerator, balancing: BalancingConfig) -> Dictionary:
	var skill: Dictionary = actor.skill
	var target: Dictionary = {}
	var use_skill: bool = false
	if actor.cooldown > 0:
		actor.cooldown -= 1
	elif not skill.is_empty():
		target = _target(actor, combatants, skill.target_rule)
		use_skill = not target.is_empty()
	var effect: String = "Physical"
	var action_name: String = "Attack"
	var multiplier: float = balancing.basic_attack_damage_multiplier
	if use_skill:
		effect = skill.effect
		action_name = skill.display_name
		multiplier = float(balancing.skill_damage_multipliers[skill.skill_id])
		actor.cooldown = int(skill.cooldown_turns)
	else:
		target = _target(actor, combatants, actor.basic_attack_target_rule)
	var amount: int = 0
	var hit: bool = true
	var was_crit: bool = false
	if effect == "Guard":
		actor.guard = multiplier
	elif effect == "Heal":
		amount = maxi(0, int(floor(float(actor.stats.MagicPower) * multiplier)))
		target.hp += mini(amount, int(target.stats.MaxHP) - int(target.hp))
	else:
		var hit_chance: float = clampf(balancing.base_hit_chance - float(target.stats.Evasion),
			balancing.min_hit_chance, balancing.max_hit_chance)
		hit = _roll(rng, hit_chance)
		if hit:
			var crit_chance: float = clampf(float(actor.stats.CritChance), 0.0, balancing.max_crit_chance)
			was_crit = _roll(rng, crit_chance)
			var power: float = float(actor.stats.MagicPower if effect == "Magic" else actor.stats.Attack)
			var mitigated: float = maxf(1.0, power * multiplier - float(target.stats.Defense))
			var critical: float = balancing.critical_damage_multiplier if was_crit else 1.0
			amount = maxi(1, int(floor(mitigated * critical * float(target.guard))))
			target.hp = maxi(0, int(target.hp) - amount)
	return {
		"actor_name": actor.name, "action_name": action_name, "target_name": target.name,
		"damage_or_heal": amount, "was_crit": was_crit,
		"actor_id": actor.id, "target_id": target.id, "effect": effect, "hit": hit,
	}


static func _roll(rng: RandomNumberGenerator, chance: float) -> bool:
	var roll: float = rng.randf()
	return chance >= 1.0 or roll < chance


static func _target(actor: Dictionary, combatants: Dictionary, rule: String) -> Dictionary:
	if rule == "Self":
		return actor
	var candidates: Array = []
	var has_front: bool = false
	for other in combatants.values():
		if other.hp == 0:
			continue
		if rule == "LowestHPAlly":
			if other.hero != actor.hero or other.hp == other.stats.MaxHP:
				continue
		elif other.hero == actor.hero:
			continue
		candidates.append(other)
		has_front = has_front or other.row == "Front"
	var best: Dictionary = {}
	for candidate in candidates:
		if rule == "FrontRowFirst" and has_front and candidate.row != "Front":
			continue
		if best.is_empty():
			best = candidate
			continue
		var comparison: int = _compare_fractions(int(candidate.hp), int(candidate.stats.MaxHP), int(best.hp), int(best.stats.MaxHP))
		if comparison < 0 or (comparison == 0 and candidate.id < best.id):
			best = candidate
	return best


static func _compare_fractions(left: int, left_max: int, right: int, right_max: int) -> int:
	# Continued fractions compare exact HP ratios without overflowing cross-products.
	var direction: int = 1
	while true:
		@warning_ignore("integer_division")
		var left_whole: int = left / left_max
		@warning_ignore("integer_division")
		var right_whole: int = right / right_max
		if left_whole != right_whole:
			return direction * (-1 if left_whole < right_whole else 1)
		var left_remainder: int = left % left_max
		var right_remainder: int = right % right_max
		if left_remainder == 0 or right_remainder == 0:
			if left_remainder == right_remainder:
				return 0
			return direction * (-1 if left_remainder == 0 else 1)
		left = left_max
		left_max = left_remainder
		right = right_max
		right_max = right_remainder
		direction = -direction
	return 0


static func _side_alive(combatants: Dictionary, heroes: bool) -> bool:
	for actor in combatants.values():
		if actor.hero == heroes and actor.hp > 0:
			return true
	return false


static func _both_sides_alive(combatants: Dictionary) -> bool:
	return _side_alive(combatants, true) and _side_alive(combatants, false)
