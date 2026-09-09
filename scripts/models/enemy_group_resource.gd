class_name EnemyGroupResource
extends Resource
## Detached stat blocks with stable IDs, explicit rows, and physical basic attacks.

@export var group_id: StringName
@export var display_name: String
@export var enemies: Array[Dictionary] = []
## Optional combat-introduction candidates; falls back to a generic encounter line.
@export var journal_text_variants: Array[String] = []
