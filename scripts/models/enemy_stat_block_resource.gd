class_name EnemyStatBlockResource
extends Resource
## One authored enemy combatant: derived stats, formation row, and targeting.
## Enemies skip the Hero trait/generation system but must supply the same
## combat-relevant derived-stat keys before simulation.

@export var enemy_id: StringName
@export var display_name: String
@export_enum("Front", "Back") var row: String = "Front"
@export_enum("FrontRowFirst", "AnySlot") var basic_attack_target_rule: String = "FrontRowFirst"
## { "MaxHP": int, "Attack": int, "MagicPower": int, "Defense": int,
##   "Evasion": float, "Initiative": int, "CritChance": float }
@export var derived_stats: Dictionary = {}
