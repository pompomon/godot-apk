class_name ExpeditionStep
extends RefCounted
## Detached, resolved journal entry with strict kind-specific frozen payloads.

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
	if ExpeditionCatalog.integer(_data.get("kind")):
		_data.kind = int(_data.kind)
	if _data.get("result") is Dictionary:
		_data.result = CombatResult.normalize_integers(_data.result)


func serialize() -> Dictionary:
	return _data.duplicate(true)


static func valid(data: Variant, index: int, snapshot: Variant = null, current_hero_states: Variant = null, legacy: bool = false) -> bool:
	if not data is Dictionary or not HeroCatalog.has_exact_keys(
			data, ["kind", "content_id", "title", "journal_text", "outcome_id", "result"]):
		return false
	if not ExpeditionCatalog.integer(data.kind, 0, StepKind.COMBAT) or not data.content_id is String or not data.outcome_id is String:
		return false
	if not ExpeditionCatalog.text(data.title) or not ExpeditionCatalog.text(data.journal_text, 4096):
		return false
	if int(data.kind) == StepKind.COMBAT:
		if index % 2 == 0 or not ExpeditionCatalog.text(data.content_id) or CombatCatalog.enemy_group_by_id(data.content_id) == null:
			return false
		return CombatResult.valid(data.result, snapshot, current_hero_states) and data.outcome_id == data.result.outcome
	if index % 2 == 0:
		return int(data.kind) == StepKind.TRAVEL and data.content_id == "" and data.outcome_id == "" and ExpeditionCatalog.gold_payload(data.result) and data.result.gold == 0
	if legacy:
		if not ExpeditionCatalog.gold_payload(data.result):
			return false
	elif not ExpeditionCatalog.reward_payload(data.result, 1 if int(data.kind) == StepKind.LOOT else ExpeditionCatalog.MAX_EVENT_ITEMS):
		return false
	match int(data.kind):
		StepKind.LOOT:
			return ExpeditionCatalog.loot_by_id(data.content_id) != null and data.outcome_id == ""
		StepKind.EVENT:
			# Outcome text and rewards survive tuning/removal of an outcome table row.
			return ExpeditionCatalog.event_by_id(data.content_id) != null and ExpeditionCatalog.text(data.outcome_id)
	return false
