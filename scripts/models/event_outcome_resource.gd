class_name EventOutcomeResource
extends Resource
## An automatically selected event outcome and its plain-data reward payload.

@export var outcome_id: StringName
@export_multiline var journal_text: String
@export_range(0.001, 1000000.0) var weight: float = 1.0
## { "gold": int, "item_ids": Array[StringName] }; no objects or object keys.
## Persistence normalizes identifiers to JSON strings in later milestones.
@export var result: Dictionary = {}
