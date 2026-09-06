class_name RegionResource
extends Resource
## Authored destination and encounter rules; no expedition runtime state.

@export var region_id: StringName
@export var display_name: String
@export var recommended_party_power: int
@export var duration_options_seconds: Array[int] = []
## Positive; each Travel step is followed by exactly one encounter.
@export var travel_step_count: int = 1
@export var encounter_pool: Array[EncounterEntryResource] = []
## { "kind": "always" | "gold" | "region_cleared",
##   "value": int, "region_id": StringName }
@export var unlock_condition: Dictionary = {}
@export var retreat_ends_expedition: bool
