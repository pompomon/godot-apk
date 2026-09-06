class_name PartyFormationService
extends RefCounted
## The only formation commit boundary. Draft operations never mutate company state.

static var last_error: String = ""


static func editing_error() -> String:
	if not GameState.initialized:
		return "Company is not initialized. Return Home and retry."
	if ExpeditionManager.is_expedition_active():
		return "The Party cannot be edited during an active Expedition."
	return ""


static func _current_party_error() -> String:
	var party := GameState.current_party
	if party != null:
		var error := party.validation_error(true)
		if not error.is_empty():
			return error
		for hero in party.heroes():
			if GameState.find_hero(hero.hero_id) != hero or hero.status != HeroData.HeroStatus.ASSIGNED:
				return "The confirmed Party is stale or unavailable. Return Home and reload."
	for hero in GameState.roster:
		if hero == null:
			return "The roster contains an invalid Hero."
		if hero.status == HeroData.HeroStatus.ASSIGNED and (party == null or not party.contains_id(hero.hero_id)):
			return "An Assigned Hero is not in the confirmed Party."
	return ""


static func availability_error(hero: HeroData) -> String:
	var error := editing_error()
	if not error.is_empty():
		return error
	if hero == null or GameState.find_hero(hero.hero_id) != hero:
		return "This Hero is no longer in the roster. Choose a current roster Hero."
	if hero.status not in HeroData.HeroStatus.values():
		return "This Hero has an invalid status."
	if hero.status == HeroData.HeroStatus.IDLE:
		return ""
	if hero.status == HeroData.HeroStatus.ASSIGNED and GameState.current_party != null:
		for member in GameState.current_party.heroes():
			if member == hero:
				return ""
	return "This Hero is unavailable: %s." % hero.status_label()


static func validation_error(
		party: PartyData, balancing: BalancingConfig, require_members: bool = true) -> String:
	var error := editing_error()
	if not error.is_empty():
		return error
	error = _current_party_error()
	if not error.is_empty():
		return error
	if party == null:
		return "Missing formation."
	error = party.validation_error(require_members)
	if not error.is_empty():
		return error
	for hero in party.heroes():
		error = availability_error(hero)
		if not error.is_empty():
			return error
	return PartyEvaluator.validation_error(party, balancing)


static func confirm(party: PartyData, balancing: BalancingConfig) -> bool:
	last_error = validation_error(party, balancing)
	if not last_error.is_empty():
		return false
	if GameState.current_party != null and GameState.current_party.slots == party.slots:
		return true
	var checkpoint := GameState.checkpoint()
	if GameState.current_party != null:
		for hero in GameState.current_party.heroes():
			hero.status = HeroData.HeroStatus.IDLE
	GameState.current_party = party.copy()
	for hero in GameState.current_party.heroes():
		hero.status = HeroData.HeroStatus.ASSIGNED
	return _save_or_restore(checkpoint, "Confirmation")


static func disband() -> bool:
	last_error = editing_error()
	if last_error.is_empty():
		last_error = _current_party_error()
	if not last_error.is_empty():
		return false
	if GameState.current_party == null:
		return true
	var checkpoint := GameState.checkpoint()
	for hero in GameState.current_party.heroes():
		hero.status = HeroData.HeroStatus.IDLE
	GameState.current_party = null
	return _save_or_restore(checkpoint, "Disband")


static func _save_or_restore(checkpoint: Dictionary, action: String) -> bool:
	SaveManager.save()
	if not SaveManager.last_committed:
		GameState.restore_checkpoint(checkpoint)
		last_error = "%s was not saved; the confirmed Party is unchanged. %s" % [action, SaveManager.last_error]
		return false
	return true
