extends Node
## Sole run owner. Persist rewards, cursor, clock and Hero statuses before publishing.

signal changed
signal completed
signal operation_failed

const DEFAULT_BALANCING: BalancingConfig = preload("res://data/balancing/default_balancing.tres")
const MAX_AUTOMATED_COMPLETIONS_PER_OBSERVATION := 4
var balancing: BalancingConfig = DEFAULT_BALANCING
var clock: Callable
var last_error: String = ""
var last_committed: bool = false
var _expedition: ExpeditionData
var _automation: ExpeditionAutomationState
var _completion_presented: bool = false
var _timer: Timer
var _lifecycle_enabled: bool = false
var _foreground: bool = true


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(observe_foreground)
	add_child(_timer)


func enable_lifecycle() -> void:
	_lifecycle_enabled = true
	_timer.start()
	observe_foreground()


func observe_foreground() -> void:
	if _lifecycle_enabled and _foreground and GameState.initialized:
		reveal_progress()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		_foreground = false
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		_foreground = true
		observe_foreground()


func is_expedition_active() -> bool:
	return _expedition != null and _expedition.status == ExpeditionData.Status.RUNNING


func get_active_expedition() -> ExpeditionData:
	return _expedition


func get_automation_state() -> Dictionary:
	return _automation.serialize() if _automation != null else {}


func is_automation_enabled() -> bool:
	return _automation != null and _automation.enabled


func serialize() -> Variant:
	return _expedition.serialize() if _expedition != null else null


func serialize_automation() -> Variant:
	return _automation.serialize() if _automation != null else null


func replace_from_save(data: Variant, automation_data: Variant = null) -> void:
	reset()
	if data != null:
		_expedition = ExpeditionData.new(data)
	if automation_data != null:
		_automation = ExpeditionAutomationState.new(automation_data)


func reset() -> void:
	_expedition = null
	_automation = null
	_completion_presented = false
	last_error = ""
	last_committed = false


func checkpoint() -> Dictionary:
	return {"expedition": _expedition,
		"clock_state": _expedition.clock_checkpoint() if _expedition != null else {},
		"automation": _automation.serialize() if _automation != null else null,
		"completion_presented": _completion_presented}


func restore_checkpoint(data: Dictionary) -> void:
	_expedition = data.expedition
	if _expedition != null:
		_expedition.restore_clock(data.clock_state)
	_automation = ExpeditionAutomationState.new(data.automation) if data.get("automation") != null else null
	_completion_presented = data.completion_presented


func take_completion_route() -> bool:
	if _expedition == null or is_expedition_active() or _completion_presented:
		return false
	_completion_presented = true
	return true


func mark_report_viewed() -> void:
	if _expedition != null and not is_expedition_active():
		_completion_presented = true


func start_error(
		region: RegionResource, party: PartyData, duration_seconds: int, run_count: int = 1
) -> String:
	if not GameState.initialized:
		return "Company is not initialized. Return Home and retry."
	if _expedition != null:
		return "Finish and acknowledge the existing Expedition report before dispatching again."
	if run_count < 1 or run_count > ExpeditionAutomationState.MAX_REQUESTED_RUNS:
		return "Choose between 1 and %d Expeditions." % ExpeditionAutomationState.MAX_REQUESTED_RUNS
	if party == null or party != GameState.current_party:
		return "The confirmed Party changed. Return Home and choose it again."
	if not party.validation_error(true).is_empty():
		return "Confirm a valid Party before dispatching."
	for hero in party.heroes():
		if GameState.find_hero(hero.hero_id) != hero or hero.status != HeroData.HeroStatus.ASSIGNED:
			return "A Party member is stale or unavailable. Return Home and reload."
	if region == null or ExpeditionCatalog.region_by_id(String(region.region_id)) != region:
		return "Choose an available Region."
	if not CompanyProgression.is_unlocked(region, GameState.unlocked_regions):
		return "This Region is locked. " + CompanyProgression.requirement_text(region)
	if not ExpeditionCatalog.validate_catalog(ExpeditionCatalog.regions(), ExpeditionCatalog.events(), ExpeditionCatalog.loot(), balancing):
		return "Expedition content or balancing is invalid. Check the configuration and retry."
	if duration_seconds not in region.duration_options_seconds:
		return "Choose one of this Region's offered durations."
	var xp_award := Leveling.award(region.recommended_party_power, duration_seconds, balancing)
	if xp_award < 0:
		return "Progression configuration is invalid. Correct it and retry."
	if xp_award > 0:
		for hero in party.heroes():
			var preview := Leveling.preview(hero, xp_award, balancing)
			if preview.has("error"):
				return "Hero progression could not be applied. " + String(preview.error)
	if not ExpeditionCatalog.integer(GameState.expedition_seed) or not ExpeditionCatalog.integer(GameState.expedition_sequence):
		return "Expedition seed state is invalid."
	if not SaveManager.validate_snapshot(SaveManager.capture_state()):
		return "Company state is invalid. Reload before dispatching."
	return ""


## Addition modulo 2^53 keeps the independent sequence and generated seed JSON-safe.
func next_seed() -> int:
	return (GameState.expedition_seed + GameState.expedition_sequence) % (HeroCatalog.MAX_SAFE_INT + 1)


func _now() -> Variant:
	return clock.call() if clock.is_valid() else int(Time.get_unix_time_from_system())


func _fail(message: String) -> void:
	last_committed = false
	last_error = message
	operation_failed.emit()


func _progress_config_valid() -> bool:
	if not ExpeditionCatalog.clock_config_valid(balancing):
		return false
	for step in _expedition.steps:
		var kind: String
		match step.kind:
			ExpeditionStep.StepKind.TRAVEL, ExpeditionStep.StepKind.COMBAT:
				continue
			ExpeditionStep.StepKind.LOOT:
				kind = "Loot"
			ExpeditionStep.StepKind.EVENT:
				kind = "Event"
			_:
				return false
		if not ExpeditionCatalog.weight(balancing.encounter_kind_weight_multipliers.get(kind)):
			return false
	return true


func start_expedition(
		region: RegionResource, party: PartyData, duration_seconds: int, run_count: int = 1
) -> void:
	last_committed = false
	last_error = start_error(region, party, duration_seconds, run_count)
	if not last_error.is_empty():
		operation_failed.emit()
		return
	var now: Variant = _now()
	if not ExpeditionCatalog.integer(now):
		_fail("The current UTC timestamp is invalid. Check the clock and retry.")
		return
	var resolved := ExpeditionGenerator.generate(region, party, next_seed(), duration_seconds, int(now), balancing)
	if resolved == null:
		_fail("Could not resolve this Expedition. Check its content and retry.")
		return
	if resolved.effective_end_timestamp > HeroCatalog.MAX_SAFE_INT - resolved.recovery_seconds:
		_fail("The Hero recovery deadline exceeds the supported UTC range. Check the clock and retry.")
		return
	var reward_items := 0
	for step in resolved.steps:
		reward_items += step.result.get("item_ids", []).size()
	if reward_items > SaveManager.MAX_INVENTORY_ITEMS - GameState.inventory.size():
		_fail("Inventory capacity would be exceeded. Equip items, then retry.")
		return
	var automation := ExpeditionAutomationState.create(
		region, party, duration_seconds, run_count) if run_count > 1 else null
	if run_count > 1 and automation == null:
		_fail("Could not configure automated Expeditions. Check the selection and retry.")
		return
	var company_before := GameState.checkpoint()
	var own_before := checkpoint()
	_expedition = resolved
	_automation = automation
	_completion_presented = false
	GameState.expedition_sequence = (GameState.expedition_sequence + 1) % (HeroCatalog.MAX_SAFE_INT + 1)
	for hero in party.heroes():
		hero.status = HeroData.HeroStatus.ON_EXPEDITION
	GameState.current_party = null
	_persist(company_before, own_before)


func stop_automation_after_current() -> void:
	last_committed = false
	last_error = ""
	if _automation == null or not is_expedition_active() or not _automation.enabled:
		_fail("No active automated Expedition series can be stopped.")
		return
	var company_before := GameState.checkpoint()
	var own_before := checkpoint()
	_automation.cancel_after_current()
	_persist(company_before, own_before)


func reveal_progress() -> void:
	if not GameState.initialized:
		return
	var active_run := _expedition != null and is_expedition_active()
	if active_run and not _progress_config_valid():
		_fail("Expedition progress configuration is invalid. Correct it and retry.")
		return
	var now: Variant = _now()
	if not ExpeditionCatalog.integer(now):
		_fail("The current UTC timestamp is invalid. Check the clock and retry.")
		return
	if active_run and _automation != null:
		_reveal_automated_progress(int(now))
		return
	var observe_run := active_run and int(now) != _expedition.last_observed_utc
	var recovering: Array[HeroData] = []
	for hero in GameState.roster:
		if hero != null and hero.status == HeroData.HeroStatus.RESTING and hero.recovery_ready_at > 0 and hero.recovery_ready_at <= int(now):
			recovering.append(hero)
	if (observe_run or not recovering.is_empty()) and not SaveManager.validate_snapshot(SaveManager.capture_state()):
		_fail("Expedition state is invalid. Reload before retrying progress.")
		return
	var elapsed := 0
	var cursor := -1
	var gold := GameState.gold
	var inventory: Array[ItemResource] = GameState.inventory.duplicate()
	var finishing := false
	var final_states := {}
	var progression := {}
	var resting := {}
	var recovery_ready_at := 0
	if observe_run:
		var delta := clampi(int(now) - _expedition.last_observed_utc, 0, balancing.max_offline_delta_seconds)
		var effective_duration := _expedition.effective_end_timestamp - _expedition.start_timestamp
		elapsed = _expedition.credited_elapsed_seconds + mini(delta, effective_duration - _expedition.credited_elapsed_seconds)
		cursor = elapsed / _expedition.step_duration_seconds - 1
		var steps := _expedition.steps
		for index in range(_expedition.last_revealed_index + 1, cursor + 1):
			var reward := int(steps[index].result.gold)
			if reward > HeroCatalog.MAX_SAFE_INT - gold:
				_fail("Gold capacity would be exceeded. Spend gold, then retry progress.")
				return
			gold += reward
			for id in steps[index].result.get("item_ids", []):
				var item := ItemCatalog.item_by_id(id)
				if item == null:
					_fail("An item reward is unavailable. Restore its content and retry.")
					return
				inventory.append(item)
		finishing = cursor == steps.size() - 1
		if finishing:
			final_states = _expedition.final_hero_states()
			var dispatch_hp := {}
			for member in _expedition.party_snapshot.slots.values():
				if member != null:
					dispatch_hp[member.hero_id] = int(member.derived_stats.MaxHP)
			for id in final_states:
				var hero := GameState.find_hero(id)
				if _expedition.xp_award > 0:
					var preview := Leveling.preview(hero, _expedition.xp_award, balancing)
					if preview.has("error"):
						_fail("Hero progression could not be applied. " + String(preview.error))
						return
					progression[id] = preview
				var state: Dictionary = final_states[id]
				# Products fit signed int64 for JSON-safe HP and a percentage <= 100.
				if int(state.status) == HeroData.HeroStatus.WOUNDED or (
						int(state.hp) > 0 and int(state.hp) * 100 <= int(dispatch_hp[id]) * _expedition.rest_hp_percent):
					resting[id] = true
			if not resting.is_empty():
				if int(now) > HeroCatalog.MAX_SAFE_INT - _expedition.recovery_seconds:
					_fail("The Hero recovery deadline exceeds the supported UTC range. Check the clock and retry.")
					return
				recovery_ready_at = int(now) + _expedition.recovery_seconds
	var company_progression := CompanyProgression.preview(gold, GameState.unlocked_regions, GameState.roster_capacity, balancing)
	if company_progression.has("error"):
		_fail("Company progression could not be applied. " + String(company_progression.error))
		return
	var company_changed: bool = company_progression.unlocked_regions != GameState.unlocked_regions or company_progression.roster_capacity != GameState.roster_capacity
	if not observe_run and recovering.is_empty():
		if not company_changed:
			return
		if not SaveManager.validate_snapshot(SaveManager.capture_state()):
			_fail("Company state is invalid. Reload before retrying progression.")
			return
	last_committed = false
	last_error = ""
	var company_before := GameState.checkpoint()
	var own_before := checkpoint()
	for hero in recovering:
		hero.status = HeroData.HeroStatus.IDLE
		hero.recovery_ready_at = 0
	GameState.gold = gold
	GameState.unlocked_regions.assign(company_progression.unlocked_regions)
	GameState.roster_capacity = company_progression.roster_capacity
	GameState.inventory.assign(inventory)
	if observe_run:
		_expedition.last_observed_utc = int(now)
		_expedition.credited_elapsed_seconds = elapsed
		_expedition.last_revealed_index = cursor
	if finishing:
		_expedition.status = ExpeditionData.Status.COMPLETED
		for id in final_states:
			var hero := GameState.find_hero(id)
			hero.status = HeroData.HeroStatus.RESTING if resting.has(id) else int(final_states[id].status) as HeroData.HeroStatus
			hero.recovery_ready_at = recovery_ready_at if resting.has(id) else 0
			if progression.has(id):
				hero.xp = progression[id].xp
				hero.level = progression[id].level
	if _persist(company_before, own_before, true) and finishing:
		completed.emit()


func _reveal_automated_progress(now: int) -> void:
	var has_pending := _automation.pending_offline_seconds > 0
	var observe_run := now != _expedition.last_observed_utc or has_pending
	var recovering: Array[HeroData] = []
	for hero in GameState.roster:
		if (hero != null and hero.status == HeroData.HeroStatus.RESTING
				and hero.recovery_ready_at > 0 and hero.recovery_ready_at <= now):
			recovering.append(hero)
	if (observe_run or not recovering.is_empty()) \
			and not SaveManager.validate_snapshot(SaveManager.capture_state()):
		_fail("Expedition state is invalid. Reload before retrying progress.")
		return
	var company_before := GameState.checkpoint()
	var own_before := checkpoint()
	var available := _automation.pending_offline_seconds
	if now != _expedition.last_observed_utc:
		available += clampi(
			now - _expedition.last_observed_utc, 0, balancing.max_offline_delta_seconds)
	var current_remaining := (
		_expedition.effective_end_timestamp - _expedition.start_timestamp
		- _expedition.credited_elapsed_seconds)
	var future_runs := _automation.requested_runs - _automation.completed_runs - 1
	var maximum_remaining := current_remaining + maxi(0, future_runs) * _automation.duration_seconds
	available = mini(available, maximum_remaining)
	_automation.set_pending_seconds(0)
	var completed_count := 0
	var series_finished := false
	while is_expedition_active():
		var run := _expedition
		var effective_duration := run.effective_end_timestamp - run.start_timestamp
		var remaining := effective_duration - run.credited_elapsed_seconds
		var consumed := mini(available, remaining)
		var elapsed := run.credited_elapsed_seconds + consumed
		var cursor := elapsed / run.step_duration_seconds - 1
		var steps := run.steps
		for index in range(run.last_revealed_index + 1, cursor + 1):
			var reward := int(steps[index].result.gold)
			if reward > HeroCatalog.MAX_SAFE_INT - GameState.gold:
				_restore_and_fail(
					company_before, own_before,
					"Gold capacity would be exceeded. Spend gold, then retry progress.")
				return
			GameState.gold += reward
			for id in steps[index].result.get("item_ids", []):
				if GameState.inventory.size() >= SaveManager.MAX_INVENTORY_ITEMS:
					_restore_and_fail(
						company_before, own_before,
						"Inventory capacity would be exceeded. Equip items, then retry progress.")
					return
				var item := ItemCatalog.item_by_id(id)
				if item == null:
					_restore_and_fail(
						company_before, own_before,
						"An item reward is unavailable. Restore its content and retry.")
					return
				GameState.inventory.append(item)
		run.last_observed_utc = now
		run.credited_elapsed_seconds = elapsed
		run.last_revealed_index = cursor
		available -= consumed
		if elapsed < effective_duration:
			break
		run.status = ExpeditionData.Status.COMPLETED
		var finalization := _finalize_automated_run(run, now)
		if finalization.has("error"):
			_restore_and_fail(company_before, own_before, finalization.error)
			return
		var item_count := 0
		for step in run.steps:
			item_count += step.result.get("item_ids", []).size()
		var outcome := "COMPLETED"
		if run.terminal_step_index >= 0:
			outcome = String(run.steps[-1].result.get("outcome", "COMPLETED"))
		if not _automation.append_summary({
			"run_number": _automation.completed_runs + 1,
			"region_name": run.region_name,
			"outcome": outcome,
			"gold": run.credited_gold(),
			"item_count": item_count,
			"xp_per_hero": run.xp_award,
			"resting_hero_count": int(finalization.resting_count),
		}):
			_restore_and_fail(
				company_before, own_before,
				"Automated Expedition history is invalid. Reload before retrying progress.")
			return
		completed_count += 1
		if finalization.resting_count > 0:
			_automation.stop("Stopped because a participating Hero needs to rest.")
		elif not _automation.enabled:
			if _automation.cancelled and _automation.completed_runs < _automation.requested_runs:
				_automation.stop("Stopped by the player after the current Expedition.")
		if not _automation.enabled:
			available = 0
			_automation.set_pending_seconds(0)
			series_finished = true
			break
		var successor_start := maxi(0, now - available)
		var successor_error := _start_automated_successor(run, successor_start)
		if not successor_error.is_empty():
			_automation.stop(successor_error)
			available = 0
			_automation.set_pending_seconds(0)
			series_finished = true
			break
		if completed_count >= MAX_AUTOMATED_COMPLETIONS_PER_OBSERVATION:
			_expedition.last_observed_utc = now
			_automation.set_pending_seconds(available)
			break
	if is_expedition_active():
		_expedition.last_observed_utc = now
		if completed_count < MAX_AUTOMATED_COMPLETIONS_PER_OBSERVATION:
			_automation.set_pending_seconds(available)
	for hero in recovering:
		hero.status = HeroData.HeroStatus.IDLE
		hero.recovery_ready_at = 0
	var company_progression := CompanyProgression.preview(
		GameState.gold, GameState.unlocked_regions, GameState.roster_capacity, balancing)
	if company_progression.has("error"):
		_restore_and_fail(
			company_before, own_before,
			"Company progression could not be applied. " + String(company_progression.error))
		return
	var company_changed: bool = (
		company_progression.unlocked_regions != GameState.unlocked_regions
		or company_progression.roster_capacity != GameState.roster_capacity)
	GameState.unlocked_regions.assign(company_progression.unlocked_regions)
	GameState.roster_capacity = company_progression.roster_capacity
	if not observe_run and recovering.is_empty() and not company_changed:
		restore_checkpoint(own_before)
		return
	if _persist(company_before, own_before, true):
		if series_finished:
			completed.emit()
		elif (_automation != null and _automation.pending_offline_seconds > 0
				and _lifecycle_enabled):
			observe_foreground.call_deferred()


func _finalize_automated_run(run: ExpeditionData, now: int) -> Dictionary:
	var final_states := run.final_hero_states()
	var dispatch_hp := {}
	for member in run.party_snapshot.slots.values():
		if member != null:
			dispatch_hp[member.hero_id] = int(member.derived_stats.MaxHP)
	var resting := {}
	var progression := {}
	for id in final_states:
		var hero := GameState.find_hero(id)
		if hero == null:
			return {"error": "A participating Hero is missing. Automated Expeditions stopped."}
		if run.xp_award > 0:
			var preview := Leveling.preview(hero, run.xp_award, balancing)
			if preview.has("error"):
				return {"error": "Hero progression could not be applied. " + String(preview.error)}
			progression[id] = preview
		var state: Dictionary = final_states[id]
		if int(state.status) == HeroData.HeroStatus.WOUNDED or (
				int(state.hp) > 0
				and int(state.hp) * 100 <= int(dispatch_hp[id]) * run.rest_hp_percent):
			resting[id] = true
	if not resting.is_empty() and now > HeroCatalog.MAX_SAFE_INT - run.recovery_seconds:
		return {"error": "The Hero recovery deadline exceeds the supported UTC range."}
	var recovery_ready_at := now + run.recovery_seconds if not resting.is_empty() else 0
	for id in final_states:
		var hero := GameState.find_hero(id)
		hero.status = (
			HeroData.HeroStatus.RESTING
			if resting.has(id)
			else int(final_states[id].status) as HeroData.HeroStatus)
		hero.recovery_ready_at = recovery_ready_at if resting.has(id) else 0
		if progression.has(id):
			hero.xp = progression[id].xp
			hero.level = progression[id].level
	return {"resting_count": resting.size()}


func _automation_party() -> Dictionary:
	var region := ExpeditionCatalog.region_by_id(_automation.region_id)
	if region == null:
		return {"error": "Stopped because the selected Region is no longer available."}
	if _automation.duration_seconds not in region.duration_options_seconds:
		return {"error": "Stopped because the selected duration is no longer offered."}
	if not CompanyProgression.is_unlocked(region, GameState.unlocked_regions):
		return {"error": "Stopped because the selected Region is no longer unlocked."}
	if not ExpeditionCatalog.validate_catalog(
			ExpeditionCatalog.regions(), ExpeditionCatalog.events(),
			ExpeditionCatalog.loot(), balancing):
		return {"error": "Stopped because Expedition content or balancing is invalid."}
	var party := PartyData.new()
	for index in range(_automation.party_hero_ids.size()):
		var id: Variant = _automation.party_hero_ids[index]
		if id == null:
			continue
		var hero := GameState.find_hero(id)
		if hero == null:
			return {"error": "Stopped because a participating Hero is missing."}
		if hero.status != HeroData.HeroStatus.IDLE:
			return {"error": "Stopped because %s is %s." % [hero.hero_name, hero.status_label()]}
		party.slots[PartyData.SLOT_ORDER[index]] = hero
	if not party.validation_error(true).is_empty():
		return {"error": "Stopped because the automated Party is invalid."}
	var xp_award := Leveling.award(
		region.recommended_party_power, _automation.duration_seconds, balancing)
	if xp_award < 0:
		return {"error": "Stopped because progression configuration is invalid."}
	for hero in party.heroes():
		if xp_award > 0 and Leveling.preview(hero, xp_award, balancing).has("error"):
			return {"error": "Stopped because Hero progression cannot be applied."}
	return {"party": party, "region": region}


func _start_automated_successor(previous: ExpeditionData, start_timestamp: int) -> String:
	var input := _automation_party()
	if input.has("error"):
		return input.error
	var party: PartyData = input.party
	var region: RegionResource = input.region
	var resolved := ExpeditionGenerator.generate(
		region, party, next_seed(), _automation.duration_seconds, start_timestamp, balancing)
	if resolved == null:
		return "Stopped because the next Expedition could not be resolved."
	if resolved.effective_end_timestamp > HeroCatalog.MAX_SAFE_INT - resolved.recovery_seconds:
		return "Stopped because the next recovery deadline exceeds the supported UTC range."
	var reward_items := 0
	var reward_gold := 0
	for step in resolved.steps:
		reward_items += step.result.get("item_ids", []).size()
		var step_gold := int(step.result.gold)
		if step_gold > HeroCatalog.MAX_SAFE_INT - reward_gold:
			return "Stopped because the next Expedition's gold exceeds the supported range."
		reward_gold += step_gold
	if reward_items > SaveManager.MAX_INVENTORY_ITEMS - GameState.inventory.size():
		return "Stopped because inventory capacity would be exceeded."
	if reward_gold > HeroCatalog.MAX_SAFE_INT - GameState.gold:
		return "Stopped because gold capacity would be exceeded."
	var sequence_before := GameState.expedition_sequence
	var statuses := {}
	for hero in party.heroes():
		statuses[hero] = hero.status
		hero.status = HeroData.HeroStatus.ON_EXPEDITION
	GameState.expedition_sequence = (
		GameState.expedition_sequence + 1) % (HeroCatalog.MAX_SAFE_INT + 1)
	_expedition = resolved
	var snapshot := SaveManager.capture_state()
	var encoded_size := JSON.stringify(snapshot, "\t", true, true).to_utf8_buffer().size()
	if not SaveManager.validate_snapshot(snapshot) or encoded_size > SaveManager.MAX_SAVE_BYTES:
		_expedition = previous
		GameState.expedition_sequence = sequence_before
		for hero in statuses:
			hero.status = statuses[hero]
		return "Stopped because the next Expedition would exceed save limits."
	return ""


func _restore_and_fail(
		company_before: Dictionary, own_before: Dictionary, message: String
) -> void:
	GameState.restore_checkpoint(company_before)
	restore_checkpoint(own_before)
	_fail(message)


func acknowledge_report(expected: ExpeditionData) -> void:
	last_committed = false
	last_error = ""
	if expected == null or expected != _expedition or is_expedition_active():
		_fail("This completed report is no longer available. Return Home.")
		return
	var company_before := GameState.checkpoint()
	var own_before := checkpoint()
	_expedition = null
	_automation = null
	_completion_presented = false
	_persist(company_before, own_before)


func _persist(company_before: Dictionary, own_before: Dictionary, retain_feedback: bool = false) -> bool:
	var warning := SaveManager.last_warning
	SaveManager.save()
	if retain_feedback:
		SaveManager.retain_warning(warning)
	if not SaveManager.last_committed:
		GameState.restore_checkpoint(company_before)
		restore_checkpoint(own_before)
		_fail("Expedition changes were not saved; nothing was credited or consumed. Retry. " + SaveManager.last_error)
		return false
	last_committed = true
	last_error = ""
	changed.emit()
	return true
