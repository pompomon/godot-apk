class_name RegionResource
extends Resource
## Authored destination and encounter rules; no expedition runtime state.

@export var region_id: StringName
@export var display_name: String
@export var travel_title: String
@export_multiline var travel_text: String
## Optional additional candidates; [travel_text] + these form the selection pool.
@export_multiline var travel_text_variants: Array[String] = []
@export var recommended_party_power: int
@export var duration_options_seconds: Array[int] = []
## Positive; each Travel step is followed by exactly one encounter.
@export var travel_step_count: int = 1
@export var encounter_pool: Array[EncounterEntryResource] = []
## Exactly { "kind": "always" } or { "kind": "gold", "value": positive int }.
@export var unlock_condition: Dictionary = {}
@export var retreat_ends_expedition: bool
