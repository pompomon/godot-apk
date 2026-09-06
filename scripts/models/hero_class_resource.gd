class_name HeroClassResource
extends Resource
## Authored class attributes, growth, targeting, and derived-stat coefficients.

@export var class_id: StringName
@export var display_name: String
@export_enum("FrontRowFirst", "AnySlot") var basic_attack_target_rule: String = "FrontRowFirst"
## { "MIG": Vector2i(min, max), "FOC": Vector2i, "GRT": Vector2i,
##   "GUI": Vector2i, "FTH": Vector2i }; ranges are inclusive.
@export var base_attribute_ranges: Dictionary = {}
## { "MIG": float, "FOC": float, "GRT": float, "GUI": float, "FTH": float }
@export var per_level_growth: Dictionary = {}
## { "MaxHP": float, "Attack": float, "MagicPower": float, "Defense": float,
##   "Evasion": float, "Initiative": float, "CritChance": float }
@export var derived_stat_bases: Dictionary = {}
## { derived_stat_name: { "MIG": float, "FOC": float, "GRT": float,
##                        "GUI": float, "FTH": float } }; include zero weights.
@export var derived_stat_attribute_weights: Dictionary = {}
