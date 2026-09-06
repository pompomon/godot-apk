class_name ExpeditionGenerator
extends RefCounted
## Pure two-pass generation; never uses the global RNG or live company state.


static func generate(
		region: RegionResource, party: PartyData, seed: int, duration_seconds: int,
		start_timestamp: int, balancing: BalancingConfig) -> ExpeditionData:
	if not ExpeditionCatalog.validate_region(region, balancing) or not ExpeditionCatalog.integer(seed):
		return null
	if duration_seconds not in region.duration_options_seconds or not ExpeditionCatalog.integer(start_timestamp):
		return null
	if start_timestamp > HeroCatalog.MAX_SAFE_INT - duration_seconds:
		return null
	var snapshot := ExpeditionPartySnapshot.capture(party)
	if snapshot == null:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var weights: Array[float] = []
	for entry in region.encounter_pool:
		weights.append(entry.weight * float(balancing.encounter_kind_weight_multipliers[entry.kind]))
	var selected: Array[EncounterEntryResource] = []
	for index in range(region.travel_step_count):
		selected.append(region.encounter_pool[_weighted_index(weights, rng)])
	var candidate_count := 2 * selected.size()
	var step_duration_seconds: int = duration_seconds / candidate_count
	var steps: Array = []
	for entry in selected:
		steps.append({"kind": ExpeditionStep.StepKind.TRAVEL, "content_id": "", "outcome_id": "",
			"title": region.travel_title, "journal_text": region.travel_text, "result": {"gold": 0}})
		var step := {"kind": ExpeditionStep.StepKind.LOOT, "content_id": String(entry.content_id),
			"outcome_id": "", "title": "", "journal_text": "", "result": {}}
		if entry.kind == "Loot":
			var loot := ExpeditionCatalog.loot_by_id(String(entry.content_id))
			step.title = loot.display_name
			step.journal_text = loot.journal_text
			step.result = {"gold": rng.randi_range(loot.min_gold, loot.max_gold)}
		else:
			var event := ExpeditionCatalog.event_by_id(String(entry.content_id))
			var outcome_weights: Array[float] = []
			for outcome in event.outcomes:
				outcome_weights.append(outcome.weight)
			var outcome := event.outcomes[_weighted_index(outcome_weights, rng)]
			step.kind = ExpeditionStep.StepKind.EVENT
			step.title = event.display_name
			step.journal_text = event.description + "\n" + outcome.journal_text
			step.outcome_id = String(outcome.outcome_id)
			step.result = outcome.result.duplicate(true)
		steps.append(step)
	var result := ExpeditionData.new({
		"region_id": String(region.region_id), "region_name": region.display_name, "party_snapshot": snapshot.slots,
		"seed": seed, "start_timestamp": start_timestamp, "duration_seconds": duration_seconds,
		"step_duration_seconds": step_duration_seconds, "steps": steps, "terminal_step_index": -1,
		"effective_end_timestamp": start_timestamp + duration_seconds,
	})
	return result if ExpeditionData.valid(result.serialize()) else null


static func _weighted_index(weights: Array[float], rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for value in weights:
		total += value
	var roll := rng.randf() * total
	var last_positive := -1
	for index in range(weights.size()):
		if weights[index] <= 0.0:
			continue
		last_positive = index
		roll -= weights[index]
		if roll < 0.0:
			return index
	return last_positive
