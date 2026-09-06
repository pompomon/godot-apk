class_name HeroTraitResource
extends Resource
## Authored trait modifiers and flags; applying them belongs to gameplay systems.

@export var trait_id: StringName
@export var display_name: String
@export_multiline var description: String
## { derived_stat_name: float }
@export var stat_modifiers: Dictionary = {}
@export var flags: Array[StringName] = []
