class_name BalancingConfig
extends Resource
## Shared gameplay coefficients, authored in the default balancing resource.
## Unconfigured fields are placeholders until their owning gameplay milestone.

@export var party_power_level_weight: float
## { derived_stat_name: float }
@export var party_power_stat_weights: Dictionary = {}
@export var missing_front_row_factor: float
@export var party_size_divisor: float
@export var base_hit_chance: float
@export var min_hit_chance: float
@export var max_hit_chance: float
@export var max_crit_chance: float
@export var basic_attack_damage_multiplier: float
## { skill_id: float }
@export var skill_damage_multipliers: Dictionary = {}
@export var critical_damage_multiplier: float
@export var max_combat_rounds: int
## { "recommended_party_power": float, "duration_seconds": float }
@export var xp_award_coefficients: Dictionary = {}
## { "base": int, "growth_factor": float }
@export var xp_threshold_curve: Dictionary = {}
## { "Loot": float, "Event": float, "Combat": float }
@export var encounter_kind_weight_multipliers: Dictionary = {}
@export var base_recovery_seconds: int
## Frozen into an Expedition at start; a Wounded Hero recovers to Idle after this
## many seconds. A placeholder until the full Wounded/Resting flow in Milestone 6.
@export var combat_recovery_seconds: int
@export var max_offline_delta_seconds: int
@export var recruitment_cost: int
