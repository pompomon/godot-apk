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
	# Pass one: every encounter pair is selected up front so a later early
	# termination cannot change which pairs were drawn.
	var weights: Array[float] = []
	for entry in region.encounter_pool:
		weights.append(entry.weight * float(balancing.encounter_kind_weight_multipliers[entry.kind]))
	var selected: Array[EncounterEntryResource] = []
	for index in range(region.travel_step_count):
		selected.append(region.encounter_pool[_weighted_index(weights, rng)])
	var candidate_count := 2 * selected.size()
	var step_duration_seconds: int = duration_seconds / candidate_count
	# Pass two: draw outcomes in order, carrying HP across combats, and stop at the
	# first terminal combat (a defeat, or a retreat when the region ends there).
	var current_states := snapshot.hero_states()
	var steps: Array = []
	var terminal_index := -1
	for entry in selected:
		steps.append({"kind": ExpeditionStep.StepKind.TRAVEL, "content_id": "", "outcome_id": "",
			"title": region.travel_title, "journal_text": region.travel_text, "result": {"gold": 0}})
		var step := _resolve_encounter(entry, rng, snapshot, current_states, balancing)
		if step.is_empty():
			return null
		steps.append(step)
		if int(step.kind) == ExpeditionStep.StepKind.COMBAT:
			var outcome: String = step.result.outcome
			if outcome == "DEFEAT" or (outcome == "RETREAT" and region.retreat_ends_expedition):
				terminal_index = steps.size() - 1
				break
	var effective_end := start_timestamp + steps.size() * step_duration_seconds
	var result := ExpeditionData.new({
		"region_id": String(region.region_id), "region_name": region.display_name, "party_snapshot": snapshot.slots,
		"seed": seed, "start_timestamp": start_timestamp, "duration_seconds": duration_seconds,
		"step_duration_seconds": step_duration_seconds, "candidate_step_count": candidate_count,
		"retreat_is_terminal": region.retreat_ends_expedition, "recovery_seconds": balancing.combat_recovery_seconds,
		"steps": steps, "terminal_step_index": terminal_index, "effective_end_timestamp": effective_end,
	})
	return result if ExpeditionData.valid(result.serialize()) else null


static func _resolve_encounter(
		entry: EncounterEntryResource, rng: RandomNumberGenerator, snapshot: ExpeditionPartySnapshot,
		current_states: Dictionary, balancing: BalancingConfig) -> Dictionary:
	var step := {"kind": ExpeditionStep.StepKind.LOOT, "content_id": String(entry.content_id),
		"outcome_id": "", "title": "", "journal_text": "", "result": {}}
	match entry.kind:
		"Loot":
			var loot := ExpeditionCatalog.loot_by_id(String(entry.content_id))
			step.title = loot.display_name
			step.journal_text = loot.journal_text
			step.result = {"gold": rng.randi_range(loot.min_gold, loot.max_gold)}
		"Event":
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
		"Combat":
			var group := CombatCatalog.enemy_group_by_id(String(entry.content_id))
			# The per-combat seed is drawn from the shared expedition RNG so the whole
			# run stays deterministic, but the simulation itself runs on its own seed.
			var combat_seed := rng.randi_range(0, ExpeditionCatalog.MAX_LOOT_GOLD - 1)
			var combat := CombatResolver.resolve(snapshot, current_states, group, combat_seed, balancing)
			if not combat is Dictionary or combat.is_empty():
				return {}
			for hero_id in combat.final_hero_states:
				var state: Dictionary = combat.final_hero_states[hero_id]
				current_states[hero_id] = {"hp": int(state.hp), "status": int(state.status)}
			step.kind = ExpeditionStep.StepKind.COMBAT
			step.title = group.display_name
			step.journal_text = "The Party clashes with the %s." % group.display_name
			step.result = combat
		_:
			return {}
	return step


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
