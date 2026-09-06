class_name LootResource
extends Resource
## Authored inclusive gold range, referenced by loot_id in the Loot registry.

@export var loot_id: StringName
@export var display_name: String
@export_multiline var journal_text: String
@export var min_gold: int
@export var max_gold: int
