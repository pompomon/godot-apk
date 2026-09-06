class_name EnemyGroupResource
extends Resource
## Authored opponent formation for a Combat encounter, referenced by group_id.

@export var group_id: StringName
@export var display_name: String
@export var enemies: Array[EnemyStatBlockResource] = []
