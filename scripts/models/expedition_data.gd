class_name ExpeditionData
extends RefCounted
## Resolved fields are defensive copies; only clock, cursor and finalization mutate.

enum Status { RUNNING, COMPLETED }
const LEGACY_RESOLVED_KEYS := ["region_id", "region_name", "party_snapshot", "seed", "start_timestamp",
	"duration_seconds", "step_duration_seconds", "steps", "terminal_step_index", "effective_end_timestamp"]
const RESOLVED_KEYS := LEGACY_RESOLVED_KEYS + ["planned_step_count", "retreat_ends_expedition"]
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
var planned_step_count: int:
	get: return int(_resolved.planned_step_count)
var retreat_ends_expedition: bool:
	get: return _resolved.retreat_ends_expedition
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
	# Older callers still supply a complete, untruncated candidate list.
	if not _resolved.has("planned_step_count"):
		_resolved.planned_step_count = data.get("steps", []).size()
	if not _resolved.has("retreat_ends_expedition"):
		_resolved.retreat_ends_expedition = false
	if _resolved.has("party_snapshot"):
		_resolved.party_snapshot = ExpeditionPartySnapshot.new(_resolved.party_snapshot).slots
	# Restore JSON's integer-valued floats without rounding safe integer IDs/rewards.
	for key in ["seed", "start_timestamp", "duration_seconds", "step_duration_seconds",
			"terminal_step_index", "effective_end_timestamp", "planned_step_count"]:
		if _resolved.has(key):
			_resolved[key] = int(_resolved[key])
	if _resolved.has("steps"):
		for index in range(_resolved.steps.size()):
			_resolved.steps[index] = ExpeditionStep.new(_resolved.steps[index]).serialize()
	for member in _resolved.get("party_snapshot", {}).values():
		if member == null:
			continue
		member.level = int(member.level)
		if member.has("active_skill"):
			member.active_skill.cooldown_turns = int(member.active_skill.cooldown_turns)
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


func final_hero_states() -> Dictionary:
	var states := party_snapshot.hero_states()
	for step in _resolved.steps:
		if int(step.kind) == ExpeditionStep.StepKind.COMBAT:
			states = step.result.final_hero_states.duplicate(true)
	return states


func display_step_count() -> int:
	return planned_step_count if status == Status.RUNNING else _resolved.steps.size()


func seconds_remaining() -> int:
	return maxi(0, duration_seconds - credited_elapsed_seconds) if status == Status.RUNNING else 0


static func valid(data: Variant) -> bool:
	return _valid(data, false)


static func valid_legacy(data: Variant) -> bool:
	return _valid(data, true)


static func _valid(data: Variant, legacy: bool) -> bool:
	var resolved_keys := LEGACY_RESOLVED_KEYS if legacy else RESOLVED_KEYS
	if not data is Dictionary or not HeroCatalog.has_exact_keys(data, resolved_keys + CLOCK_KEYS):
		return false
	if not ExpeditionCatalog.text(data.region_id) or ExpeditionCatalog.region_by_id(data.region_id) == null or not ExpeditionCatalog.text(data.region_name):
		return false
	if not ExpeditionPartySnapshot.valid(data.party_snapshot):
		return false
	if legacy:
		for member in data.party_snapshot.values():
			if member != null and member.has("active_skill"):
				return false
	for key in ["seed", "start_timestamp", "last_observed_utc", "effective_end_timestamp", "credited_elapsed_seconds"]:
		if not ExpeditionCatalog.integer(data[key]):
			return false
	for key in ["duration_seconds", "step_duration_seconds"]:
		if not ExpeditionCatalog.integer(data[key], 1):
			return false
	if not data.steps is Array or data.steps.size() < 2 or data.steps.size() > ExpeditionCatalog.MAX_STEPS or data.steps.size() % 2 != 0:
		return false
	var planned: int = data.steps.size()
	var terminal_retreat := false
	if not legacy:
		if not ExpeditionCatalog.integer(data.planned_step_count, 2, ExpeditionCatalog.MAX_STEPS) or not data.retreat_ends_expedition is bool:
			return false
		planned = int(data.planned_step_count)
		terminal_retreat = data.retreat_ends_expedition
	if planned % 2 != 0 or data.steps.size() > planned:
		return false
	if not ExpeditionCatalog.integer(data.terminal_step_index, -1, data.steps.size() - 1) or not ExpeditionCatalog.integer(data.status, Status.RUNNING, Status.COMPLETED):
		return false
	if not ExpeditionCatalog.integer(data.last_revealed_index, -1, data.steps.size() - 1):
		return false
	var duration := int(data.duration_seconds)
	var slice := int(data.step_duration_seconds)
	if duration % planned != 0 or duration / planned != slice:
		return false
	var terminal := int(data.terminal_step_index)
	if terminal != -1 and (legacy or terminal != data.steps.size() - 1):
		return false
	if terminal == -1 and data.steps.size() != planned:
		return false
	var effective_duration := duration if terminal == -1 else (terminal + 1) * slice
	if int(data.start_timestamp) > HeroCatalog.MAX_SAFE_INT - duration or int(data.effective_end_timestamp) != int(data.start_timestamp) + effective_duration:
		return false
	var elapsed := int(data.credited_elapsed_seconds)
	if elapsed > effective_duration or int(data.last_revealed_index) != elapsed / slice - 1:
		return false
	if (int(data.status) == Status.COMPLETED) != (elapsed == effective_duration):
		return false
	var total := 0
	var snapshot := ExpeditionPartySnapshot.new(data.party_snapshot)
	var states := snapshot.hero_states()
	var expected_terminal := -1
	for index in range(data.steps.size()):
		var step: Variant = data.steps[index]
		if not ExpeditionStep.valid(step, index, snapshot, states):
			return false
		if int(step.kind) == ExpeditionStep.StepKind.COMBAT:
			if legacy:
				return false
			states = step.result.final_hero_states
			if step.result.outcome == "DEFEAT" or (step.result.outcome == "RETREAT" and terminal_retreat):
				if index != data.steps.size() - 1:
					return false
				expected_terminal = index
		var gold := int(step.result.gold)
		if gold > HeroCatalog.MAX_SAFE_INT - total:
			return false
		total += gold
	return terminal == expected_terminal
