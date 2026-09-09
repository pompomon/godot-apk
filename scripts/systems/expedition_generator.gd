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
	var xp_award := Leveling.award(region.recommended_party_power, duration_seconds, balancing)
	if xp_award < 0:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var weights: Array[float] = []
	for entry in region.encounter_pool:
		weights.append(entry.weight * float(balancing.encounter_kind_weight_multipliers[entry.kind]))
	var selected: Array[EncounterEntryResource] = []
	var includes_combat := false
	for index in range(region.travel_step_count):
		var entry := region.encounter_pool[_weighted_index(weights, rng)]
		selected.append(entry)
		includes_combat = includes_combat or entry.kind == "Combat"
	var snapshot := ExpeditionPartySnapshot.capture(party, includes_combat)
	if snapshot == null:
		return null
	var hero_states := snapshot.hero_states()
	var candidate_count := 2 * selected.size()
	var step_duration_seconds: int = duration_seconds / candidate_count
	var terminal_step_index := -1
	var steps: Array = []
	var region_id := String(region.region_id)
	var previous_travel_text := ""
	for loop_index in range(selected.size()):
		var entry: EncounterEntryResource = selected[loop_index]
		var travel_text := NarrativeVariantSelector.select_travel(
				region.travel_text, region.travel_text_variants, seed, region_id, loop_index, previous_travel_text)
		previous_travel_text = travel_text
		steps.append({"kind": ExpeditionStep.StepKind.TRAVEL, "content_id": "", "outcome_id": "",
			"title": region.travel_title, "journal_text": travel_text, "result": {"gold": 0}})
		var step := {"kind": ExpeditionStep.StepKind.LOOT, "content_id": String(entry.content_id),
			"outcome_id": "", "title": "", "journal_text": "", "result": {}}
		if entry.kind == "Loot":
			var loot := ExpeditionCatalog.loot_by_id(String(entry.content_id))
			step.title = loot.display_name
			step.journal_text = NarrativeVariantSelector.select(
					loot.journal_text, loot.journal_text_variants, seed, region_id, loop_index,
					String(entry.content_id), "", "loot")
			step.result = {"gold": rng.randi_range(loot.min_gold, loot.max_gold), "item_ids": []}
			if not loot.item_pool.is_empty() and loot.item_drop_chance > 0.0:
				if rng.randf() < loot.item_drop_chance:
					var item_weights: Array[float] = []
					for weight in loot.item_pool.values():
						item_weights.append(float(weight))
					step.result.item_ids.append(String(loot.item_pool.keys()[_weighted_index(item_weights, rng)]))
		elif entry.kind == "Event":
			var event := ExpeditionCatalog.event_by_id(String(entry.content_id))
			var outcome_weights: Array[float] = []
			for outcome in event.outcomes:
				outcome_weights.append(outcome.weight)
			var outcome := event.outcomes[_weighted_index(outcome_weights, rng)]
			step.kind = ExpeditionStep.StepKind.EVENT
			step.title = event.display_name
			var description := NarrativeVariantSelector.select(
					event.description, event.description_variants, seed, region_id, loop_index,
					String(entry.content_id), "", "event_description")
			var outcome_text := NarrativeVariantSelector.select(
					outcome.journal_text, outcome.journal_text_variants, seed, region_id, loop_index,
					String(entry.content_id), String(outcome.outcome_id), "event_outcome")
			step.journal_text = description + "\n" + outcome_text
			step.outcome_id = String(outcome.outcome_id)
			step.result = outcome.result.duplicate(true)
			if not step.result.has("item_ids"):
				step.result.item_ids = []
		else:
			var enemies := CombatCatalog.enemy_group_by_id(String(entry.content_id))
			var combat := CombatEngine.resolve_combat(snapshot, hero_states, enemies, rng.randi(), balancing)
			if combat.has("error"):
				return null
			step.kind = ExpeditionStep.StepKind.COMBAT
			step.title = enemies.display_name
			step.journal_text = NarrativeVariantSelector.select(
					"The Party encounters %s." % enemies.display_name, enemies.journal_text_variants,
					seed, region_id, loop_index, String(entry.content_id), "", "combat_intro")
			step.outcome_id = combat.outcome
			step.result = combat
			hero_states = combat.final_hero_states.duplicate(true)
		steps.append(step)
		if entry.kind == "Combat" and (step.result.outcome == "DEFEAT" or (
				step.result.outcome == "RETREAT" and region.retreat_ends_expedition)):
			terminal_step_index = steps.size() - 1
			break
	var effective_duration := duration_seconds if terminal_step_index == -1 else (terminal_step_index + 1) * step_duration_seconds
	var result := ExpeditionData.new({
		"region_id": String(region.region_id), "region_name": region.display_name, "party_snapshot": snapshot.slots,
		"seed": seed, "start_timestamp": start_timestamp, "duration_seconds": duration_seconds,
		"step_duration_seconds": step_duration_seconds, "steps": steps, "terminal_step_index": terminal_step_index,
		"planned_step_count": candidate_count, "retreat_ends_expedition": region.retreat_ends_expedition,
		"xp_award": xp_award, "recovery_seconds": balancing.base_recovery_seconds,
		"rest_hp_percent": balancing.recovery_hp_percent,
		"effective_end_timestamp": start_timestamp + effective_duration,
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
