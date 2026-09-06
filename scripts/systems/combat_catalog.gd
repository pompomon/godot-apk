class_name CombatCatalog
extends RefCounted
## Ordered allowlist for combat content: authored skills and enemy groups.
## Like the other catalogs, IDs never resolve to caller-provided resource paths.

const GUARD: SkillResource = preload("res://data/skills/guard.tres")
const AIMED_SHOT: SkillResource = preload("res://data/skills/aimed_shot.tres")
const FIREBOLT: SkillResource = preload("res://data/skills/firebolt.tres")
const MEND: SkillResource = preload("res://data/skills/mend.tres")
const BANDIT_SKIRMISHERS: EnemyGroupResource = preload("res://data/encounters/bandit_skirmishers.tres")
const FOREST_WOLVES: EnemyGroupResource = preload("res://data/encounters/forest_wolves.tres")

const MAX_ENEMIES := 32
const MAX_COMBAT_ROUNDS := 1000
const MAX_COOLDOWN := 1000
const MAX_COMBATANTS := MAX_ENEMIES + 4 # four party formation slots
const OUTCOMES := ["VICTORY", "DEFEAT", "RETREAT"]
const ACTION_KINDS := ["Attack", "Skill", "Heal", "Guard"]


static func skills() -> Array[SkillResource]:
	return [GUARD, AIMED_SHOT, FIREBOLT, MEND]


static func enemy_groups() -> Array[EnemyGroupResource]:
	return [BANDIT_SKIRMISHERS, FOREST_WOLVES]


static func skill_by_id(id: String) -> SkillResource:
	for skill in skills():
		if String(skill.skill_id) == id:
			return skill
	return null


static func enemy_group_by_id(id: String) -> EnemyGroupResource:
	for group in enemy_groups():
		if String(group.group_id) == id:
			return group
	return null


static func validate_skill(skill: SkillResource) -> bool:
	if skill == null or not ExpeditionCatalog.text(String(skill.skill_id)) or not ExpeditionCatalog.text(skill.display_name):
		return false
	if not ExpeditionCatalog.text(String(skill.class_id)) or not ExpeditionCatalog.text(String(skill.multiplier_id)):
		return false
	if skill.kind not in SkillResource.KINDS or skill.target_rule not in SkillResource.TARGET_RULES:
		return false
	if not ExpeditionCatalog.integer(skill.cooldown, 0, MAX_COOLDOWN):
		return false
	# Kind and target rule must agree so authoring cannot produce a self-damaging
	# attack or an enemy-targeted heal.
	match skill.kind:
		"Guard":
			return skill.target_rule == "Self"
		"Heal":
			return skill.target_rule == "LowestHpAlly"
		_:
			return skill.target_rule in ["FrontRowFirst", "AnySlot"]


static func validate_enemy_stats(stats: Variant) -> bool:
	if not stats is Dictionary or not HeroCatalog.has_exact_keys(stats, HeroCatalog.STATS):
		return false
	for key in HeroCatalog.STATS:
		var value: Variant = stats[key]
		if key in ["Evasion", "CritChance"]:
			if not ExpeditionCatalog.weight(value) or float(value) > 1.0:
				return false
		elif not ExpeditionCatalog.integer(value, 1 if key == "MaxHP" else 0):
			return false
	return true


static func validate_enemy_group(group: EnemyGroupResource) -> bool:
	if group == null or not ExpeditionCatalog.text(String(group.group_id)) or not ExpeditionCatalog.text(group.display_name):
		return false
	if group.enemies.is_empty() or group.enemies.size() > MAX_ENEMIES:
		return false
	var ids := {}
	for enemy in group.enemies:
		if enemy == null or not ExpeditionCatalog.text(String(enemy.enemy_id)) or not ExpeditionCatalog.text(enemy.display_name):
			return false
		if ids.has(enemy.enemy_id) or enemy.row not in ["Front", "Back"]:
			return false
		if enemy.basic_attack_target_rule not in ["FrontRowFirst", "AnySlot"]:
			return false
		if not validate_enemy_stats(enemy.derived_stats):
			return false
		ids[enemy.enemy_id] = true
	return true


## Round bounds, ordered probability limits, and finite nonnegative multipliers
## for every authored skill. Missing skill configuration is an error, not a
## zero-damage skill. Guard's reduction fraction is additionally clamped to [0,1].
static func validate_combat_balancing(balancing: BalancingConfig) -> bool:
	if balancing == null or not ExpeditionCatalog.integer(balancing.max_combat_rounds, 1, MAX_COMBAT_ROUNDS):
		return false
	if not ExpeditionCatalog.integer(balancing.combat_recovery_seconds, 0):
		return false
	for value in [balancing.base_hit_chance, balancing.min_hit_chance, balancing.max_hit_chance, balancing.max_crit_chance]:
		if not ExpeditionCatalog.weight(value) or float(value) > 1.0:
			return false
	if balancing.min_hit_chance > balancing.max_hit_chance:
		return false
	if not ExpeditionCatalog.weight(balancing.basic_attack_damage_multiplier) or not ExpeditionCatalog.weight(balancing.critical_damage_multiplier):
		return false
	if not balancing.skill_damage_multipliers is Dictionary:
		return false
	for skill in skills():
		if not validate_skill(skill):
			return false
		var multiplier: Variant = balancing.skill_damage_multipliers.get(String(skill.multiplier_id))
		if not ExpeditionCatalog.weight(multiplier):
			return false
		if skill.kind == "Guard" and float(multiplier) > 1.0:
			return false
	return true


static func validate_catalog(balancing: BalancingConfig) -> bool:
	if not validate_combat_balancing(balancing):
		return false
	var skill_ids := {}
	for skill in skills():
		if skill_ids.has(skill.skill_id):
			return false
		skill_ids[skill.skill_id] = true
	var group_ids := {}
	for group in enemy_groups():
		if not validate_enemy_group(group) or group_ids.has(group.group_id):
			return false
		group_ids[group.group_id] = true
	# Every Hero class references exactly one authored skill belonging to it.
	for hero_class in HeroCatalog.classes():
		var skill := skill_by_id(String(hero_class.skill_id))
		if skill == null or String(skill.class_id) != String(hero_class.class_id):
			return false
	return true


## Structural, bounded validation of a persisted combat result. Never re-runs the
## simulation and never checks amounts against today's balancing so a saved
## journal remains valid after tuning changes. Cross-step Hero-ID/HP/outcome
## consistency is enforced separately in ExpeditionData.
static func validate_combat_result(result: Variant) -> bool:
	if not result is Dictionary or not HeroCatalog.has_exact_keys(result, ["outcome", "rounds", "final_hero_states", "gold"]):
		return false
	if result.outcome not in OUTCOMES or result.gold != 0:
		return false
	if not result.rounds is Array or result.rounds.size() > MAX_COMBAT_ROUNDS:
		return false
	for round_entry in result.rounds:
		if not round_entry is Dictionary or not HeroCatalog.has_exact_keys(round_entry, ["round_number", "actions"]):
			return false
		if not ExpeditionCatalog.integer(round_entry.round_number, 1, MAX_COMBAT_ROUNDS):
			return false
		if not round_entry.actions is Array or round_entry.actions.size() > MAX_COMBATANTS:
			return false
		for action in round_entry.actions:
			if not _valid_action(action):
				return false
	if not result.final_hero_states is Dictionary or result.final_hero_states.size() > PartyData.SLOT_ORDER.size():
		return false
	for hero_id in result.final_hero_states:
		if not ExpeditionCatalog.text(hero_id) or not _valid_hero_state(result.final_hero_states[hero_id]):
			return false
	return true


static func _valid_action(action: Variant) -> bool:
	if not action is Dictionary or not HeroCatalog.has_exact_keys(action, [
			"actor_id", "actor_name", "action_kind", "action_name",
			"target_id", "target_name", "was_miss", "was_crit", "amount", "result_hp"]):
		return false
	for key in ["actor_id", "actor_name", "action_name", "target_id", "target_name"]:
		if not ExpeditionCatalog.text(action[key]):
			return false
	if action.action_kind not in ACTION_KINDS:
		return false
	if not action.was_miss is bool or not action.was_crit is bool:
		return false
	return ExpeditionCatalog.integer(action.amount, 0) and ExpeditionCatalog.integer(action.result_hp, 0)


static func _valid_hero_state(state: Variant) -> bool:
	if not state is Dictionary or not HeroCatalog.has_exact_keys(state, ["hp", "status"]):
		return false
	return ExpeditionCatalog.integer(state.hp, 0) and ExpeditionCatalog.integer(state.status, 0, HeroData.HeroStatus.DEAD)
