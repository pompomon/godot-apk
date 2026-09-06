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
		if step.kind == ExpeditionStep.StepKind.TRAVEL:
			continue
		var kind := "Loot" if step.kind == ExpeditionStep.StepKind.LOOT else "Event"
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
	if _expedition == null or not is_expedition_active():
		return
	if not _progress_config_valid():
		_fail("Expedition progress configuration is invalid. Correct it and retry.")
		return
	var now: Variant = _now()
	if not ExpeditionCatalog.integer(now):
		_fail("The current UTC timestamp is invalid. Check the clock and retry.")
		return
	if int(now) == _expedition.last_observed_utc:
		return
	last_committed = false
	last_error = ""
	if not SaveManager.validate_snapshot(SaveManager.capture_state()):
		_fail("Expedition state is invalid. Reload before retrying progress.")
		return
	var delta := clampi(int(now) - _expedition.last_observed_utc, 0, balancing.max_offline_delta_seconds)
	var elapsed := _expedition.credited_elapsed_seconds + mini(delta, _expedition.duration_seconds - _expedition.credited_elapsed_seconds)
	var cursor: int = elapsed / _expedition.step_duration_seconds - 1
	cursor = clampi(cursor, -1, _expedition.steps.size() - 1)
	var gold := GameState.gold
	var steps := _expedition.steps
	for index in range(_expedition.last_revealed_index + 1, cursor + 1):
		var reward := int(steps[index].result.gold)
		if reward > HeroCatalog.MAX_SAFE_INT - gold:
			_fail("Gold capacity would be exceeded. Spend gold, then retry progress.")
			return
		gold += reward
	var company_before := GameState.checkpoint()
	var own_before := checkpoint()
	GameState.gold = gold
	_expedition.last_observed_utc = int(now)
	_expedition.credited_elapsed_seconds = elapsed
	_expedition.last_revealed_index = cursor
	var finishing := cursor == steps.size() - 1
	if finishing:
		_expedition.status = ExpeditionData.Status.COMPLETED
		for member in _expedition.party_snapshot.slots.values():
			if member != null:
				GameState.find_hero(member.hero_id).status = HeroData.HeroStatus.IDLE
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
