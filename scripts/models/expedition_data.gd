class_name ExpeditionData
extends RefCounted
## Resolved fields are defensive copies; only clock, cursor and finalization mutate.

enum Status { RUNNING, COMPLETED }
const LEGACY_RESOLVED_KEYS := ["region_id", "region_name", "party_snapshot", "seed", "start_timestamp",
	"duration_seconds", "step_duration_seconds", "steps", "terminal_step_index", "effective_end_timestamp"]
## v4 freezes the original candidate count, the retreat policy, and the recovery
## duration so a truncated schedule and Wounded timers resist later balance tuning.
const RESOLVED_KEYS := LEGACY_RESOLVED_KEYS + ["candidate_step_count", "retreat_is_terminal", "recovery_seconds"]
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
var candidate_step_count: int:
	get: return int(_resolved.candidate_step_count)
var retreat_is_terminal: bool:
	get: return bool(_resolved.retreat_is_terminal)
var recovery_seconds: int:
	get: return int(_resolved.recovery_seconds)
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
			"candidate_step_count", "recovery_seconds", "terminal_step_index", "effective_end_timestamp"]:
		if _resolved.has(key):
			_resolved[key] = int(_resolved[key])
	for step in _resolved.get("steps", []):
		step.kind = int(step.kind)
		if int(step.kind) == ExpeditionStep.StepKind.COMBAT:
			_restore_combat_result(step.result)
		else:
			step.result.gold = int(step.result.gold)
	for member in _resolved.get("party_snapshot", {}).values():
		if member == null:
			continue
		member.level = int(member.level)
		if member.get("skill") is Dictionary:
			member.skill.cooldown = int(member.skill.cooldown)
		for key in member.attributes:
			member.attributes[key] = int(member.attributes[key])
		for key in member.derived_stats:
			if key not in ["Evasion", "CritChance"]:
				member.derived_stats[key] = int(member.derived_stats[key])
	last_observed_utc = int(data.get("last_observed_utc", data.get("start_timestamp", 0)))
	credited_elapsed_seconds = int(data.get("credited_elapsed_seconds", 0))
	last_revealed_index = int(data.get("last_revealed_index", -1))
	status = int(data.get("status", Status.RUNNING)) as Status


static func _restore_combat_result(result: Dictionary) -> void:
	result.gold = int(result.gold)
	for round_entry in result.rounds:
		round_entry.round_number = int(round_entry.round_number)
		for action in round_entry.actions:
			action.amount = int(action.amount)
			action.result_hp = int(action.result_hp)
	for state in result.final_hero_states.values():
		state.hp = int(state.hp)
		state.status = int(state.status)


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


## Actual (possibly truncated) run length. The clock, cursor and completion cap on
## this, while duration_seconds/candidate_step_count preserve the original plan so
## the UI cannot infer an early ending from a shortened schedule.
func effective_seconds() -> int:
	return effective_end_timestamp - start_timestamp


## Merged final combat HP/status per Hero ID; a later combat overlays an earlier one.
func fold_final_states() -> Dictionary:
	var merged := {}
	for step in _resolved.steps:
		if int(step.kind) == ExpeditionStep.StepKind.COMBAT:
			for hero_id in step.result.final_hero_states:
				var state: Dictionary = step.result.final_hero_states[hero_id]
				merged[hero_id] = {"hp": int(state.hp), "status": int(state.status)}
	return merged


func party_defeated() -> bool:
	var terminal := int(_resolved.terminal_step_index)
	if terminal < 0:
		return false
	var step: Dictionary = _resolved.steps[terminal]
	return int(step.kind) == ExpeditionStep.StepKind.COMBAT and step.result.outcome == "DEFEAT"


static func valid(data: Variant) -> bool:
	return _valid(data, false)


## Original Milestone 4 (v3) schema: no frozen v4 fields, no combat, retreat never
## terminal. Used to validate a save before migrating it forward to v4.
static func valid_v3(data: Variant) -> bool:
	return _valid(data, true)


static func _valid(data: Variant, legacy: bool) -> bool:
	var resolved_keys := LEGACY_RESOLVED_KEYS if legacy else RESOLVED_KEYS
	if not data is Dictionary or not HeroCatalog.has_exact_keys(data, resolved_keys + CLOCK_KEYS):
		return false
	if not ExpeditionCatalog.text(data.region_id) or ExpeditionCatalog.region_by_id(data.region_id) == null or not ExpeditionCatalog.text(data.region_name):
		return false
	if legacy:
		if not ExpeditionPartySnapshot.valid_legacy(data.party_snapshot):
			return false
	elif not ExpeditionPartySnapshot.valid(data.party_snapshot):
		return false
	for key in ["seed", "start_timestamp", "last_observed_utc", "effective_end_timestamp", "credited_elapsed_seconds"]:
		if not ExpeditionCatalog.integer(data[key]):
			return false
	for key in ["duration_seconds", "step_duration_seconds"]:
		if not ExpeditionCatalog.integer(data[key], 1):
			return false
	if not data.steps is Array or data.steps.size() < 2 or data.steps.size() > ExpeditionCatalog.MAX_STEPS or data.steps.size() % 2 != 0:
		return false
	if not ExpeditionCatalog.integer(data.status, Status.RUNNING, Status.COMPLETED):
		return false
	if not ExpeditionCatalog.integer(data.last_revealed_index, -1, data.steps.size() - 1):
		return false
	# Validate the terminal index and frozen v4 fields as integers/bools *before*
	# any int() coercion so a malformed value cannot be silently rounded through.
	if not ExpeditionCatalog.integer(data.terminal_step_index, -1, data.steps.size() - 1):
		return false
	var candidate: int = data.steps.size()
	if not legacy:
		if not ExpeditionCatalog.integer(data.candidate_step_count, 2, ExpeditionCatalog.MAX_STEPS):
			return false
		candidate = int(data.candidate_step_count)
		if candidate % 2 != 0 or data.steps.size() > candidate:
			return false
		if not ExpeditionCatalog.integer(data.recovery_seconds) or not data.retreat_is_terminal is bool:
			return false
	var duration := int(data.duration_seconds)
	var slice := int(data.step_duration_seconds)
	if duration % candidate != 0 or duration / candidate != slice:
		return false
	# The effective end reflects the possibly truncated schedule; the original plan
	# still bounds arithmetic against overflow.
	if int(data.start_timestamp) > HeroCatalog.MAX_SAFE_INT - duration:
		return false
	var effective_seconds: int = data.steps.size() * slice
	if int(data.effective_end_timestamp) != int(data.start_timestamp) + effective_seconds:
		return false
	var elapsed := int(data.credited_elapsed_seconds)
	if elapsed > effective_seconds or int(data.last_revealed_index) != elapsed / slice - 1:
		return false
	if (int(data.status) == Status.COMPLETED) != (elapsed == effective_seconds):
		return false
	# Structurally validate every step (and cross-step combat consistency) before
	# indexing into the schedule by terminal index below, so a malformed step entry
	# can never be dereferenced.
	var terminal := int(data.terminal_step_index)
	if not _valid_steps(data, legacy, terminal):
		return false
	if legacy:
		return terminal == -1
	if terminal == -1:
		return data.steps.size() == candidate
	return terminal == data.steps.size() - 1 and int(data.steps[terminal].kind) == ExpeditionStep.StepKind.COMBAT


static func _valid_steps(data: Dictionary, legacy: bool, terminal: int) -> bool:
	var party_hp := {}
	for member in data.party_snapshot.values():
		if member != null:
			party_hp[member.hero_id] = int(member.derived_stats.MaxHP)
	var retreat_terminal := not legacy and bool(data.retreat_is_terminal)
	var total := 0
	for index in range(data.steps.size()):
		var step: Variant = data.steps[index]
		if not ExpeditionStep.valid(step, index):
			return false
		if legacy and int(step.kind) == ExpeditionStep.StepKind.COMBAT:
			return false
		if int(step.kind) == ExpeditionStep.StepKind.COMBAT:
			if not _valid_combat_consistency(step, party_hp, index == terminal, retreat_terminal):
				return false
		var gold := int(step.result.gold)
		if gold > HeroCatalog.MAX_SAFE_INT - total:
			return false
		total += gold
	return true


## Cross-step consistency that structural step validation cannot see: every final
## Hero ID belongs to the frozen party, HP never exceeds that Hero's MaxHP, and the
## VICTORY/DEFEAT/RETREAT outcome matches whether this step is the terminal one.
static func _valid_combat_consistency(step: Dictionary, party_hp: Dictionary, is_terminal: bool, retreat_terminal: bool) -> bool:
	# Every frozen Party Hero must appear exactly once: the loop rejects unknown IDs,
	# and this size check rejects an incomplete map that omits a living Hero.
	if step.result.final_hero_states.size() != party_hp.size():
		return false
	for hero_id in step.result.final_hero_states:
		if not party_hp.has(hero_id) or int(step.result.final_hero_states[hero_id].hp) > int(party_hp[hero_id]):
			return false
	var outcome: String = step.result.outcome
	var ends_run := outcome == "DEFEAT" or (outcome == "RETREAT" and retreat_terminal)
	return ends_run == is_terminal
