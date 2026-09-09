class_name EventOutcomeResource
extends Resource
## An automatically selected event outcome and its plain-data reward payload.

@export var outcome_id: StringName
@export_multiline var journal_text: String
## Optional additional candidates; [journal_text] + these form the selection pool.
@export_multiline var journal_text_variants: Array[String] = []
@export_range(0.001, 1000000.0) var weight: float = 1.0
## Exact { "gold": int } or { "gold": int, "item_ids": Array[String] }.
@export var result: Dictionary = {}
