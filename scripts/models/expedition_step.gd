class_name ExpeditionStep
extends RefCounted
## Detached, resolved journal entry. Reserved combat payloads are not accepted yet.

enum StepKind { TRAVEL, LOOT, EVENT, COMBAT }

var _data: Dictionary
var kind: StepKind:
	get:
		return int(_data.kind) as StepKind
var content_id: String:
	get:
		return _data.content_id
var title: String:
	get:
		return _data.title
var journal_text: String:
	get:
		return _data.journal_text
var result: Dictionary:
	get:
		return _data.result.duplicate(true)


func _init(data: Dictionary = {}) -> void:
	_data = data.duplicate(true)


func serialize() -> Dictionary:
	return _data.duplicate(true)


static func valid(data: Variant, index: int) -> bool:
	if not data is Dictionary or not HeroCatalog.has_exact_keys(
			data, ["kind", "content_id", "title", "journal_text", "outcome_id", "result"]):
		return false
	if not ExpeditionCatalog.integer(data.kind, 0, StepKind.EVENT) or not data.content_id is String or not data.outcome_id is String:
		return false
	if not ExpeditionCatalog.text(data.title) or not ExpeditionCatalog.text(data.journal_text, 4096) or not ExpeditionCatalog.gold_payload(data.result):
		return false
	if index % 2 == 0:
		return int(data.kind) == StepKind.TRAVEL and data.content_id == "" and data.outcome_id == "" and data.result.gold == 0
	match int(data.kind):
		StepKind.LOOT:
			return ExpeditionCatalog.loot_by_id(data.content_id) != null and data.outcome_id == ""
		StepKind.EVENT:
			# Outcome text and rewards survive tuning/removal of an outcome table row.
			return ExpeditionCatalog.event_by_id(data.content_id) != null and ExpeditionCatalog.text(data.outcome_id)
	return false
