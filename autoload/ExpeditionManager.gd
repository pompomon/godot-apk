extends Node
## Sole run owner. Persist rewards, cursor, clock and Hero statuses before publishing.

signal changed
signal completed
signal operation_failed

const DEFAULT_BALANCING: BalancingConfig = preload("res://data/balancing/default_balancing.tres")
var balancing: BalancingConfig = DEFAULT_BALANCING
var clock: Callable
var last_error: String = ""
var last_committed: bool = false
var _expedition: ExpeditionData
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


func serialize() -> Variant:
	return _expedition.serialize() if _expedition != null else null


func replace_from_save(data: Variant) -> void:
	reset()
	if data != null:
		_expedition = ExpeditionData.new(data)


func reset() -> void:
	_expedition = null
	_completion_presented = false
	last_error = ""
	last_committed = false


func checkpoint() -> Dictionary:
	return {"expedition": _expedition,
		"clock_state": _expedition.clock_checkpoint() if _expedition != null else {},
		"completion_presented": _completion_presented}


func restore_checkpoint(data: Dictionary) -> void:
	_expedition = data.expedition
	if _expedition != null:
		_expedition.restore_clock(data.clock_state)
	_completion_presented = data.completion_presented


func take_completion_route() -> bool:
	if _expedition == null or is_expedition_active() or _completion_presented:
		return false
	_completion_presented = true
	return true


func mark_report_viewed() -> void:
	if _expedition != null and not is_expedition_active():
		_completion_presented = true


func start_error(region: RegionResource, party: PartyData, duration_seconds: int) -> String:
	if not GameState.initialized:
		return "Company is not initialized. Return Home and retry."
	if _expedition != null:
		return "Finish and acknowledge the existing Expedition report before dispatching again."
	if party == null or party != GameState.current_party:
		return "The confirmed Party changed. Return Home and choose it again."
	if not party.validation_error(true).is_empty():
		return "Confirm a valid Party before dispatching."
	for hero in party.heroes():
		if GameState.find_hero(hero.hero_id) != hero or hero.status != HeroData.HeroStatus.ASSIGNED:
			return "A Party member is stale or unavailable. Return Home and reload."
	if region == null or ExpeditionCatalog.region_by_id(String(region.region_id)) != region:
		return "Choose an available Region."
	if not ExpeditionCatalog.validate_catalog(ExpeditionCatalog.regions(), ExpeditionCatalog.events(), ExpeditionCatalog.loot(), balancing):
		return "Expedition content or balancing is invalid. Check the configuration and retry."
	if duration_seconds not in region.duration_options_seconds:
		return "Choose one of this Region's offered durations."
	if Leveling.award(region.recommended_party_power, duration_seconds, balancing) < 0:
		return "Progression configuration is invalid. Correct it and retry."
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


func start_expedition(region: RegionResource, party: PartyData, duration_seconds: int) -> void:
	last_committed = false
	last_error = start_error(region, party, duration_seconds)
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
	var company_before := GameState.checkpoint()
	var own_before := checkpoint()
	_expedition = resolved
	_completion_presented = false
	GameState.expedition_sequence = (GameState.expedition_sequence + 1) % (HeroCatalog.MAX_SAFE_INT + 1)
	for hero in party.heroes():
		hero.status = HeroData.HeroStatus.ON_EXPEDITION
	GameState.current_party = null
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
	var observe_run := active_run and int(now) != _expedition.last_observed_utc
	var recovering: Array[HeroData] = []
	for hero in GameState.roster:
		if hero != null and hero.status == HeroData.HeroStatus.RESTING and hero.recovery_ready_at > 0 and hero.recovery_ready_at <= int(now):
			recovering.append(hero)
	if not observe_run and recovering.is_empty():
		return
	last_committed = false
	last_error = ""
	if not SaveManager.validate_snapshot(SaveManager.capture_state()):
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
	var company_before := GameState.checkpoint()
	var own_before := checkpoint()
	for hero in recovering:
		hero.status = HeroData.HeroStatus.IDLE
		hero.recovery_ready_at = 0
	GameState.gold = gold
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


func acknowledge_report(expected: ExpeditionData) -> void:
	last_committed = false
	last_error = ""
	if expected == null or expected != _expedition or is_expedition_active():
		_fail("This completed report is no longer available. Return Home.")
		return
	var company_before := GameState.checkpoint()
	var own_before := checkpoint()
	_expedition = null
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
