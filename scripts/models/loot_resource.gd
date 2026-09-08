class_name LootResource
extends Resource
## Ordered item weights are resolved after the inclusive gold roll.

@export var loot_id: StringName
@export var display_name: String
@export_multiline var journal_text: String
@export var min_gold: int
@export var max_gold: int
@export var item_pool: Dictionary = {}
@export_range(0.0, 1.0) var item_drop_chance: float = 0.0
