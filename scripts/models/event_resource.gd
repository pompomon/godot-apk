class_name EventResource
extends Resource
## Authored event text and weighted automatic outcomes.

@export var event_id: StringName
@export var display_name: String
@export_multiline var description: String
@export var outcomes: Array[EventOutcomeResource] = []
