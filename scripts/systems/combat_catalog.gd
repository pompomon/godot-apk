class_name CombatCatalog
extends RefCounted
## Combat-only authoring validation. Frozen skills never resolve a live asset.

const MAX_ENEMIES: int = 4
const MAX_ROUNDS: int = 100
const MAX_ACTIONS_PER_ROUND: int = 8
const MAX_COOLDOWN: int = 100
const SKILL_KEYS: Array = ["skill_id", "display_name", "effect", "target_rule", "cooldown_turns"]
const ENEMY_KEYS: Array = ["combatant_id", "display_name", "row", "basic_attack_target_rule", "derived_stats"]
const GUARD: SkillResource = preload("res://data/skills/guard.tres")
const AIMED_SHOT: SkillResource = preload("res://data/skills/aimed_shot.tres")
const FIREBOLT: SkillResource = preload("res://data/skills/firebolt.tres")
const MEND: SkillResource = preload("res://data/skills/mend.tres")
const BANDIT_SKIRMISHERS: EnemyGroupResource = preload("res://data/encounters/bandit_skirmishers.tres")
const FOREST_WOLVES: EnemyGroupResource = preload("res://data/encounters/forest_wolves.tres")
const ASHEN_RAIDERS: EnemyGroupResource = preload("res://data/encounters/ashen_raiders.tres")
const ASHEN_JACKALS: EnemyGroupResource = preload("res://data/encounters/ashen_jackals.tres")
const FROSTBOUND_SENTINELS: EnemyGroupResource = preload("res://data/encounters/frostbound_sentinels.tres")
const FROSTBOUND_PROWLERS: EnemyGroupResource = preload("res://data/encounters/frostbound_prowlers.tres")


static func skills() -> Array[SkillResource]:
	return [GUARD, AIMED_SHOT, FIREBOLT, MEND]


static func enemy_groups() -> Array[EnemyGroupResource]:
	return [BANDIT_SKIRMISHERS, FOREST_WOLVES, ASHEN_RAIDERS, ASHEN_JACKALS,
		FROSTBOUND_SENTINELS, FROSTBOUND_PROWLERS]


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
	return skill != null and validate_skill_snapshot(skill.snapshot())


static func validate_skill_snapshot(value: Variant) -> bool:
	if not value is Dictionary or not HeroCatalog.has_exact_keys(value, SKILL_KEYS):
		return false
	if not ExpeditionCatalog.text(value.skill_id) or not ExpeditionCatalog.text(value.display_name):
		return false
	if not value.effect is String or not value.target_rule is String:
		return false
	if not ExpeditionCatalog.integer(value.cooldown_turns, 0, MAX_COOLDOWN):
		return false
	match value.effect:
		"Physical", "Magic":
			return value.target_rule in ["FrontRowFirst", "AnySlot"]
		"Heal":
			return value.target_rule == "LowestHPAlly"
		"Guard":
			return value.target_rule == "Self"
	return false


static func validate_stats(value: Variant) -> bool:
	if not value is Dictionary or not HeroCatalog.has_exact_keys(value, HeroCatalog.STATS):
		return false
	for key in HeroCatalog.STATS:
		if key in ["Evasion", "CritChance"]:
			if not HeroCatalog.is_bounded_number(value[key], 0.0, 1.0):
				return false
		elif not ExpeditionCatalog.integer(value[key], 1 if key == "MaxHP" else 0):
			return false
	return true


static func validate_enemy_group(group: EnemyGroupResource) -> bool:
	if group == null or not ExpeditionCatalog.text(String(group.group_id)) or not ExpeditionCatalog.text(group.display_name):
		return false
	if not ExpeditionCatalog.text_variants_valid(group.journal_text_variants):
		return false
	if group.enemies.is_empty() or group.enemies.size() > MAX_ENEMIES:
		return false
	var ids: Dictionary = {}
	for enemy in group.enemies:
		if not HeroCatalog.has_exact_keys(enemy, ENEMY_KEYS):
			return false
		if not ExpeditionCatalog.text(enemy.combatant_id) or ids.has(enemy.combatant_id):
			return false
		if not ExpeditionCatalog.text(enemy.display_name) or not enemy.row is String or enemy.row not in ["Front", "Back"]:
			return false
		if not enemy.basic_attack_target_rule is String or enemy.basic_attack_target_rule not in ["FrontRowFirst", "AnySlot"] or not validate_stats(enemy.derived_stats):
			return false
		ids[enemy.combatant_id] = true
	return true


static func validate_balancing(balancing: BalancingConfig, used_skills: Array = []) -> bool:
	if balancing == null or not ExpeditionCatalog.integer(balancing.max_combat_rounds, 1, MAX_ROUNDS):
		return false
	if used_skills.size() > MAX_ACTIONS_PER_ROUND:
		return false
	for probability in [balancing.base_hit_chance, balancing.min_hit_chance,
			balancing.max_hit_chance, balancing.max_crit_chance]:
		if not HeroCatalog.is_bounded_number(probability, 0.0, 1.0):
			return false
	if balancing.min_hit_chance > balancing.max_hit_chance:
		return false
	if not _multiplier(balancing.basic_attack_damage_multiplier) or not _multiplier(balancing.critical_damage_multiplier):
		return false
	if balancing.skill_damage_multipliers.size() > CombatCatalog.MAX_ACTIONS_PER_ROUND:
		return false
	for id in balancing.skill_damage_multipliers:
		if not ExpeditionCatalog.text(id) or not _multiplier(balancing.skill_damage_multipliers[id]):
			return false
	for skill in used_skills:
		if not validate_skill_snapshot(skill) or not balancing.skill_damage_multipliers.has(skill.skill_id):
			return false
	return true


static func validate_catalog(skill_list: Array, group_list: Array, balancing: BalancingConfig) -> bool:
	if skill_list.is_empty() or skill_list.size() > MAX_ACTIONS_PER_ROUND or group_list.is_empty() or group_list.size() > MAX_ROUNDS:
		return false
	var ids: Dictionary = {}
	var snapshots: Array = []
	for skill in skill_list:
		if not skill is SkillResource or not validate_skill(skill) or ids.has(String(skill.skill_id)):
			return false
		ids[String(skill.skill_id)] = true
		snapshots.append(skill.snapshot())
	if not validate_balancing(balancing, snapshots):
		return false
	ids.clear()
	for group in group_list:
		if not group is EnemyGroupResource or not validate_enemy_group(group) or ids.has(String(group.group_id)):
			return false
		ids[String(group.group_id)] = true
	return true


static func _multiplier(value: Variant) -> bool:
	return HeroCatalog.is_bounded_number(value, 0.0, float(HeroCatalog.MAX_SAFE_INT))
