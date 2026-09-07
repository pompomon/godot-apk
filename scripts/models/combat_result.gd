class_name CombatResult
extends RefCounted
## Checks frozen log provenance without rerolling combat or reading live balancing.

const RESULT_KEYS := ["gold", "outcome", "rounds", "final_hero_states", "enemy_states"]
const ACTION_KEYS := ["actor_name", "action_name", "target_name", "damage_or_heal",
	"was_crit", "actor_id", "target_id", "effect", "hit"]
const OUTCOMES := ["VICTORY", "DEFEAT", "RETREAT"]


static func valid(data: Variant, snapshot: Variant, current_hero_states: Variant = null) -> bool:
	if not _keys(data, RESULT_KEYS):
		return false
	if not ExpeditionCatalog.integer(data.gold, 0, 0) or not data.outcome is String or data.outcome not in OUTCOMES:
		return false
	var members: Variant = snapshot.slots if snapshot is ExpeditionPartySnapshot else snapshot
	if not ExpeditionPartySnapshot.valid(members):
		return false
	var heroes := {}
	for member in members.values():
		if member != null:
			if not member.has("active_skill"):
				return false
			heroes[member.hero_id] = member
	var states: Variant = current_hero_states
	if states == null:
		states = ExpeditionPartySnapshot.new(members).hero_states()
	if not _hero_states_valid(states, heroes, true) or not _hero_states_valid(data.final_hero_states, heroes):
		return false
	if not data.enemy_states is Dictionary or data.enemy_states.is_empty() or data.enemy_states.size() > CombatCatalog.MAX_ENEMIES:
		return false
	var combatants := {}
	for id in heroes:
		combatants[id] = {
			"name": heroes[id].hero_name, "hero": true, "hp": int(states[id].hp),
			"max_hp": int(heroes[id].derived_stats.MaxHP), "skill": heroes[id].active_skill,
		}
	for id in data.enemy_states:
		if not ExpeditionCatalog.text(id) or combatants.has(id):
			return false
		var enemy: Variant = data.enemy_states[id]
		if not _keys(enemy, ["name", "max_hp", "hp", "row"]):
			return false
		if not ExpeditionCatalog.text(enemy.name) or not enemy.row is String or enemy.row not in ["Front", "Back"]:
			return false
		if not ExpeditionCatalog.integer(enemy.max_hp, 1) or not ExpeditionCatalog.integer(enemy.hp, 0, int(enemy.max_hp)):
			return false
		combatants[id] = {
			"name": enemy.name, "hero": false, "hp": int(enemy.max_hp),
			"max_hp": int(enemy.max_hp), "skill": {},
		}
	if not data.rounds is Array or data.rounds.size() > CombatCatalog.MAX_ROUNDS:
		return false
	for index in range(data.rounds.size()):
		var round_data: Variant = data.rounds[index]
		if not _keys(round_data, ["round_number", "actions"]) or not _both_sides_alive(combatants):
			return false
		if not ExpeditionCatalog.integer(round_data.round_number, index + 1, index + 1):
			return false
		if not round_data.actions is Array or round_data.actions.is_empty() or round_data.actions.size() > CombatCatalog.MAX_ACTIONS_PER_ROUND:
			return false
		var acted := {}
		for action in round_data.actions:
			if not _action_valid(action, combatants, acted):
				return false
			acted[action.actor_id] = true
			var target: Dictionary = combatants[action.target_id]
			var amount := int(action.damage_or_heal)
			if action.effect == "Heal":
				target.hp += mini(amount, int(target.max_hp) - int(target.hp))
			elif action.effect != "Guard":
				target.hp = maxi(0, int(target.hp) - amount)
		if _both_sides_alive(combatants):
			for id in combatants:
				if combatants[id].hp > 0 and not acted.has(id):
					return false
	var heroes_alive := _side_alive(combatants, true)
	var enemies_alive := _side_alive(combatants, false)
	var outcome := "RETREAT" if heroes_alive and enemies_alive else ("VICTORY" if heroes_alive else "DEFEAT")
	if data.outcome != outcome or (data.rounds.is_empty() and heroes_alive):
		return false
	for id in heroes:
		var state: Dictionary = data.final_hero_states[id]
		var expected_status := HeroData.HeroStatus.WOUNDED if state.hp == 0 or outcome == "DEFEAT" else HeroData.HeroStatus.IDLE
		if int(state.hp) != int(combatants[id].hp) or int(state.status) != expected_status:
			return false
	for id in data.enemy_states:
		if int(data.enemy_states[id].hp) != int(combatants[id].hp):
			return false
	return true


static func _hero_states_valid(states: Variant, heroes: Dictionary, initial: bool = false) -> bool:
	if not _keys(states, heroes.keys()):
		return false
	for id in heroes:
		var state: Variant = states[id]
		if not _keys(state, ["hp", "status"]):
			return false
		if not ExpeditionCatalog.integer(state.hp, 0, int(heroes[id].derived_stats.MaxHP)):
			return false
		if not ExpeditionCatalog.integer(state.status) or int(state.status) not in [HeroData.HeroStatus.IDLE, HeroData.HeroStatus.WOUNDED]:
			return false
		if int(state.hp) == 0 and int(state.status) != HeroData.HeroStatus.WOUNDED:
			return false
		if initial and int(state.hp) > 0 and int(state.status) != HeroData.HeroStatus.IDLE:
			return false
	return true


static func _action_valid(action: Variant, combatants: Dictionary, acted: Dictionary) -> bool:
	if not _keys(action, ACTION_KEYS) or not _both_sides_alive(combatants):
		return false
	for key in ["actor_id", "target_id", "actor_name", "target_name", "action_name", "effect"]:
		if not ExpeditionCatalog.text(action[key]):
			return false
	if not combatants.has(action.actor_id) or not combatants.has(action.target_id) or acted.has(action.actor_id):
		return false
	if not action.hit is bool or not action.was_crit is bool or not ExpeditionCatalog.integer(action.damage_or_heal):
		return false
	var actor: Dictionary = combatants[action.actor_id]
	var target: Dictionary = combatants[action.target_id]
	if actor.hp == 0 or target.hp == 0 or action.actor_name != actor.name or action.target_name != target.name:
		return false
	var basic: bool = action.action_name == "Attack" and action.effect == "Physical"
	var skill: Dictionary = actor.skill
	if not basic and (skill.is_empty() or action.action_name != skill.display_name or action.effect != skill.effect):
		return false
	match action.effect:
		"Physical", "Magic":
			if actor.hero == target.hero:
				return false
			return action.damage_or_heal >= 1 if action.hit else action.damage_or_heal == 0 and not action.was_crit
		"Heal":
			return actor.hero == target.hero and target.hp < target.max_hp and action.hit and not action.was_crit
		"Guard":
			return action.actor_id == action.target_id and action.damage_or_heal == 0 and action.hit and not action.was_crit
	return false


static func _keys(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size():
		return false
	for key in value:
		if not key is String or key not in keys:
			return false
	return true


static func _side_alive(combatants: Dictionary, heroes: bool) -> bool:
	for actor in combatants.values():
		if actor.hero == heroes and actor.hp > 0:
			return true
	return false


static func _both_sides_alive(combatants: Dictionary) -> bool:
	return _side_alive(combatants, true) and _side_alive(combatants, false)


static func normalize_integers(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = normalize_integers(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry in value:
			result.append(normalize_integers(entry))
		return result
	if value is float and ExpeditionCatalog.integer(value):
		return int(value)
	return value
