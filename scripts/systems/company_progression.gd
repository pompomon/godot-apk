class_name CompanyProgression
extends RefCounted
## Permanent Company achievements; observations own persistence and publication.

const MAX_ROSTER_CAPACITY := 1024


static func preview(gold: int, unlocked: Array, capacity: int, balancing: BalancingConfig) -> Dictionary:
	if not ExpeditionCatalog.integer(gold) or not ExpeditionCatalog.integer(capacity, 1, MAX_ROSTER_CAPACITY):
		return {"error": "Company gold or roster capacity is outside the supported range."}
	if balancing == null:
		return {"error": "Company progression balancing is missing."}
	var known_ids: Array[StringName] = []
	for region in ExpeditionCatalog.regions():
		if region == null or not ExpeditionCatalog.unlock_condition_valid(region.unlock_condition):
			return {"error": "A Region unlock requirement is invalid."}
		if known_ids.has(region.region_id):
			return {"error": "Region IDs must be unique."}
		known_ids.append(region.region_id)
	if not HeroCatalog.has_exact_keys(balancing.region_roster_capacities, known_ids):
		return {"error": "Roster capacity tuning must name every known Region exactly once."}
	for id in known_ids:
		if not ExpeditionCatalog.integer(balancing.region_roster_capacities[id], 1, MAX_ROSTER_CAPACITY):
			return {"error": "A Region roster capacity is outside the supported range."}
	var result: Array[StringName] = []
	for id in unlocked:
		if not (id is String or id is StringName) or not known_ids.has(StringName(id)) or result.has(StringName(id)):
			return {"error": "Unlocked Regions must be unique known IDs."}
		result.append(StringName(id))
	for region in ExpeditionCatalog.regions():
		var condition := region.unlock_condition
		var achieved: bool = region.region_id == &"green_hollow" or condition.kind == "always" or (
			condition.kind == "gold" and gold >= int(condition.value))
		if achieved and not result.has(region.region_id):
			result.append(region.region_id)
	var next_capacity := capacity
	for id in result:
		next_capacity = maxi(next_capacity, int(balancing.region_roster_capacities[id]))
	return {"unlocked_regions": result, "roster_capacity": next_capacity}


static func is_unlocked(region: RegionResource, unlocked: Array) -> bool:
	if region == null or ExpeditionCatalog.region_by_id(String(region.region_id)) == null:
		return false
	return region.region_id == &"green_hollow" or unlocked.has(region.region_id)


static func requirement_text(region: RegionResource) -> String:
	if region == null or ExpeditionCatalog.region_by_id(String(region.region_id)) == null:
		return "Region unavailable."
	if region.region_id == &"green_hollow":
		return "Always available."
	if not ExpeditionCatalog.unlock_condition_valid(region.unlock_condition) or region.unlock_condition.kind != "gold":
		return "Region unlock requirement is invalid."
	return "Hold %d gold to unlock permanently." % int(region.unlock_condition.value)
