class_name ItemResource
extends Resource
## Authored equipment definition, not a mutable inventory instance.

@export var item_id: StringName
@export var display_name: String
@export_enum("Weapon", "Armor") var slot: String = "Weapon"
@export var rarity: StringName
## { derived_stat_name: float }
@export var stat_modifiers: Dictionary = {}
