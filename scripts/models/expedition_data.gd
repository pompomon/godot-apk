class_name ExpeditionData
extends RefCounted
## Resolved fields are defensive copies; only clock, cursor and finalization mutate.

enum Status { RUNNING, COMPLETED }
const RESOLVED_KEYS := ["region_id", "region_name", "party_snapshot", "seed", "start_timestamp",
	"duration_seconds", "step_duration_seconds", "steps", "terminal_step_index", "effective_end_timestamp"]
const CLOCK_KEYS := ["last_observed_utc", "credited_elapsed_seconds", "last_revealed_index", "status"]
var _resolved: Dictionary
var last_observed_utc: int
var credited_elapsed_seconds: int = 0
var last_revealed_index: int = -1
var status: Status = Status.RUNNING
var region_id: String:
	get: return _resolved.region_id
var region_name: String:
	get: return _resolved.region_name
var party_snapshot: ExpeditionPartySnapshot:
	get: return ExpeditionPartySnapshot.new(_resolved.party_snapshot)
var seed: int:
	get: return int(_resolved.seed)
var start_timestamp: int:
	get: return int(_resolved.start_timestamp)
var duration_seconds: int:
	get: return int(_resolved.duration_seconds)
var step_duration_seconds: int:
	get: return int(_resolved.step_duration_seconds)
var terminal_step_index: int:
	get: return int(_resolved.terminal_step_index)
var effective_end_timestamp: int:
	get: return int(_resolved.effective_end_timestamp)
var steps: Array[ExpeditionStep]:
	get:
		var result: Array[ExpeditionStep] = []
		for step in _resolved.steps:
			result.append(ExpeditionStep.new(step))
		return result


func _init(data: Dictionary = {}) -> void:
	_resolved = {}
	for key in RESOLVED_KEYS:
		if data.has(key):
			_resolved[key] = data[key]
	_resolved = _resolved.duplicate(true)
	if _resolved.has("party_snapshot"):
		_resolved.party_snapshot = ExpeditionPartySnapshot.new(_resolved.party_snapshot).slots
	# Restore JSON's integer-valued floats without rounding safe integer IDs/rewards.
	for key in ["seed", "start_timestamp", "duration_seconds", "step_duration_seconds",
			"terminal_step_index", "effective_end_timestamp"]:
		if _resolved.has(key):
			_resolved[key] = int(_resolved[key])
	for step in _resolved.get("steps", []):
		step.kind = int(step.kind)
		step.result.gold = int(step.result.gold)
	for member in _resolved.get("party_snapshot", {}).values():
		if member == null:
			continue
		member.level = int(member.level)
		for key in member.attributes:
			member.attributes[key] = int(member.attributes[key])
		for key in member.derived_stats:
			if key not in ["Evasion", "CritChance"]:
				member.derived_stats[key] = int(member.derived_stats[key])
	last_observed_utc = int(data.get("last_observed_utc", data.get("start_timestamp", 0)))
	credited_elapsed_seconds = int(data.get("credited_elapsed_seconds", 0))
	last_revealed_index = int(data.get("last_revealed_index", -1))
	status = int(data.get("status", Status.RUNNING)) as Status


func serialize() -> Dictionary:
	var data := _resolved.duplicate(true)
	if data.has("party_snapshot"):
		data.party_snapshot = ExpeditionPartySnapshot.new(data.party_snapshot).serialize()
	data.merge(clock_checkpoint())
	return data


func clock_checkpoint() -> Dictionary:
	return {"last_observed_utc": last_observed_utc, "credited_elapsed_seconds": credited_elapsed_seconds,
		"last_revealed_index": last_revealed_index, "status": status}


func restore_clock(data: Dictionary) -> void:
	last_observed_utc = int(data.last_observed_utc)
	credited_elapsed_seconds = int(data.credited_elapsed_seconds)
	last_revealed_index = int(data.last_revealed_index)
	status = int(data.status) as Status


func credited_gold() -> int:
	var total := 0
	for index in range(last_revealed_index + 1):
		total += int(_resolved.steps[index].result.gold)
	return total


static func valid(data: Variant) -> bool:
	if not data is Dictionary or not HeroCatalog.has_exact_keys(data, RESOLVED_KEYS + CLOCK_KEYS):
		return false
	if not ExpeditionCatalog.text(data.region_id) or ExpeditionCatalog.region_by_id(data.region_id) == null or not ExpeditionCatalog.text(data.region_name):
		return false
	if not ExpeditionPartySnapshot.valid(data.party_snapshot):
		return false
	for key in ["seed", "start_timestamp", "last_observed_utc", "effective_end_timestamp", "credited_elapsed_seconds"]:
		if not ExpeditionCatalog.integer(data[key]):
			return false
	for key in ["duration_seconds", "step_duration_seconds"]:
		if not ExpeditionCatalog.integer(data[key], 1):
			return false
	if not data.steps is Array or data.steps.size() < 2 or data.steps.size() > ExpeditionCatalog.MAX_STEPS or data.steps.size() % 2 != 0:
		return false
	if not ExpeditionCatalog.integer(data.terminal_step_index, -1, -1) or not ExpeditionCatalog.integer(data.status, Status.RUNNING, Status.COMPLETED):
		return false
	if not ExpeditionCatalog.integer(data.last_revealed_index, -1, data.steps.size() - 1):
		return false
	var duration := int(data.duration_seconds)
	var slice := int(data.step_duration_seconds)
	if duration % data.steps.size() != 0 or duration / data.steps.size() != slice:
		return false
	if int(data.start_timestamp) > HeroCatalog.MAX_SAFE_INT - duration or int(data.effective_end_timestamp) != int(data.start_timestamp) + duration:
		return false
	var elapsed := int(data.credited_elapsed_seconds)
	if elapsed > duration or int(data.last_revealed_index) != elapsed / slice - 1:
		return false
	if (int(data.status) == Status.COMPLETED) != (elapsed == duration):
		return false
	var total := 0
	for index in range(data.steps.size()):
		if not ExpeditionStep.valid(data.steps[index], index):
			return false
		var gold := int(data.steps[index].result.gold)
		if gold > HeroCatalog.MAX_SAFE_INT - total:
			return false
		total += gold
	return true
