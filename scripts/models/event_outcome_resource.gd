class_name EventOutcomeResource
extends Resource
## An automatically selected event outcome and its plain-data reward payload.

@export var outcome_id: StringName
@export_multiline var journal_text: String
@export_range(0.001, 1000000.0) var weight: float = 1.0
## { "gold": int }; nonnegative gold only. Other payloads are not supported yet.
@export var result: Dictionary = {}
