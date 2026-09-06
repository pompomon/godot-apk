class_name EncounterEntryResource
extends Resource
## Weighted reference into a kind-specific loot, event, or enemy-group registry.

@export_enum("Loot", "Event", "Combat") var kind: String = "Loot"
@export var content_id: StringName
@export_range(0.001, 1000000.0) var weight: float = 1.0
