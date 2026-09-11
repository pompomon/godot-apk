class_name ExpeditionAutomationState
extends RefCounted
## Finite sequential-run configuration and compact committed history.

const MAX_REQUESTED_RUNS := 10
const KEYS := [
	"region_id", "duration_seconds", "party_hero_ids", "requested_runs",
	"completed_runs", "enabled", "cancelled", "stop_reason",
	"pending_offline_seconds", "cumulative_gold", "cumulative_item_count",
	"cumulative_xp_per_hero", "summaries",
]
const SUMMARY_KEYS := [
	"run_number", "region_name", "outcome", "gold", "item_count",
	"xp_per_hero", "resting_hero_count",
]
const OUTCOMES := ["COMPLETED", "RETREAT", "DEFEAT"]

var _data: Dictionary
var region_id: String:
	get: return _data.region_id
var duration_seconds: int:
	get: return int(_data.duration_seconds)
var party_hero_ids: Array:
	get: return _data.party_hero_ids.duplicate()
var requested_runs: int:
	get: return int(_data.requested_runs)
var completed_runs: int:
	get: return int(_data.completed_runs)
var enabled: bool:
	get: return _data.enabled
var cancelled: bool:
	get: return _data.cancelled
var stop_reason: String:
	get: return _data.stop_reason
var pending_offline_seconds: int:
	get: return int(_data.pending_offline_seconds)
var cumulative_gold: int:
	get: return int(_data.cumulative_gold)
var cumulative_item_count: int:
	get: return int(_data.cumulative_item_count)
var cumulative_xp_per_hero: int:
	get: return int(_data.cumulative_xp_per_hero)
var summaries: Array:
	get: return _data.summaries.duplicate(true)


func _init(data: Dictionary = {}) -> void:
	_data = data.duplicate(true)
	for key in [
			"duration_seconds", "requested_runs", "completed_runs",
			"pending_offline_seconds", "cumulative_gold", "cumulative_item_count",
			"cumulative_xp_per_hero",
	]:
		if _data.has(key):
			_data[key] = int(_data[key])
	if _data.get("summaries") is Array:
		for summary in _data.summaries:
			if summary is Dictionary:
				for key in [
						"run_number", "gold", "item_count", "xp_per_hero",
						"resting_hero_count",
				]:
					if summary.has(key):
						summary[key] = int(summary[key])


static func create(
		region: RegionResource, party: PartyData, duration: int, run_count: int
) -> ExpeditionAutomationState:
	if region == null or party == null:
		return null
	var ids: Array = []
	for slot in PartyData.SLOT_ORDER:
		var hero: Variant = party.slots.get(slot)
		ids.append(hero.hero_id if hero is HeroData else null)
	var result := ExpeditionAutomationState.new({
		"region_id": String(region.region_id),
		"duration_seconds": duration,
		"party_hero_ids": ids,
		"requested_runs": run_count,
		"completed_runs": 0,
		"enabled": true,
		"cancelled": false,
		"stop_reason": "",
		"pending_offline_seconds": 0,
		"cumulative_gold": 0,
		"cumulative_item_count": 0,
		"cumulative_xp_per_hero": 0,
		"summaries": [],
	})
	return result if valid(result.serialize()) else null


func serialize() -> Dictionary:
	return _data.duplicate(true)


func set_pending_seconds(value: int) -> void:
	_data.pending_offline_seconds = value


func append_summary(summary: Dictionary) -> bool:
	var next := _data.duplicate(true)
	next.summaries.append(summary.duplicate(true))
	next.completed_runs += 1
	next.cumulative_gold += int(summary.get("gold", 0))
	next.cumulative_item_count += int(summary.get("item_count", 0))
	next.cumulative_xp_per_hero += int(summary.get("xp_per_hero", 0))
	if next.completed_runs >= next.requested_runs and next.enabled:
		next.enabled = false
		next.stop_reason = "Completed all requested Expeditions."
	if not valid(next):
		return false
	_data = next
	return true


func cancel_after_current() -> void:
	_data.enabled = false
	_data.cancelled = true
	_data.stop_reason = "Stopping after the current Expedition."


func stop(reason: String) -> void:
	_data.enabled = false
	_data.stop_reason = reason.strip_edges().left(256)


static func valid(data: Variant) -> bool:
	if not data is Dictionary or not HeroCatalog.has_exact_keys(data, KEYS):
		return false
	if not ExpeditionCatalog.text(data.region_id):
		return false
	if not ExpeditionCatalog.integer(data.duration_seconds, 1):
		return false
	if not ExpeditionCatalog.integer(data.requested_runs, 2, MAX_REQUESTED_RUNS):
		return false
	if not ExpeditionCatalog.integer(data.completed_runs, 0, int(data.requested_runs)):
		return false
	if not data.enabled is bool or not data.cancelled is bool:
		return false
	if data.cancelled and data.enabled:
		return false
	if not data.stop_reason is String or data.stop_reason.length() > 256:
		return false
	if data.stop_reason != data.stop_reason.strip_edges():
		return false
	if data.enabled and (not data.stop_reason.is_empty()
			or int(data.completed_runs) >= int(data.requested_runs)):
		return false
	if not data.enabled and data.stop_reason.is_empty():
		return false
	if not ExpeditionCatalog.integer(
			data.pending_offline_seconds, 0,
			int(data.duration_seconds) * int(data.requested_runs)):
		return false
	for key in ["cumulative_gold", "cumulative_item_count", "cumulative_xp_per_hero"]:
		if not ExpeditionCatalog.integer(data[key]):
			return false
	if not data.party_hero_ids is Array or data.party_hero_ids.size() != PartyData.SLOT_ORDER.size():
		return false
	var ids := {}
	for id in data.party_hero_ids:
		if id == null:
			continue
		if not ExpeditionCatalog.text(id) or ids.has(id):
			return false
		ids[id] = true
	if ids.is_empty():
		return false
	if not data.summaries is Array or data.summaries.size() != int(data.completed_runs):
		return false
	var total_gold := 0
	var total_items := 0
	var total_xp := 0
	for index in range(data.summaries.size()):
		var summary: Variant = data.summaries[index]
		if not summary is Dictionary or not HeroCatalog.has_exact_keys(summary, SUMMARY_KEYS):
			return false
		if not ExpeditionCatalog.integer(summary.run_number, index + 1, index + 1):
			return false
		if not ExpeditionCatalog.text(summary.region_name) or summary.outcome not in OUTCOMES:
			return false
		for key in ["gold", "item_count", "xp_per_hero", "resting_hero_count"]:
			if not ExpeditionCatalog.integer(summary[key]):
				return false
		for pair in [
				[total_gold, int(summary.gold)],
				[total_items, int(summary.item_count)],
				[total_xp, int(summary.xp_per_hero)],
		]:
			if pair[1] > HeroCatalog.MAX_SAFE_INT - pair[0]:
				return false
		total_gold += int(summary.gold)
		total_items += int(summary.item_count)
		total_xp += int(summary.xp_per_hero)
	return (total_gold == int(data.cumulative_gold)
		and total_items == int(data.cumulative_item_count)
		and total_xp == int(data.cumulative_xp_per_hero))
