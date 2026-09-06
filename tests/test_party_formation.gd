extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
const BALANCING: BalancingConfig = preload("res://data/balancing/default_balancing.tres")
var _isolation: RefCounted
var _expedition_script: Script

class ActiveExpedition:
	extends "res://autoload/ExpeditionManager.gd"

	func is_expedition_active() -> bool:
		return true

	func get_active_expedition() -> Variant:
		return {"sentinel": "unchanged"}


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	_expedition_script = ExpeditionManager.get_script()
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success, SaveManager.last_error)


func after_each() -> void:
	ExpeditionManager.set_script(_expedition_script)
	_isolation.finish()


func _party() -> PartyData:
	var party := PartyData.new()
	party.place_hero(0, GameState.roster[0])
	party.place_hero(3, GameState.roster[1])
	return party


func test_draft_changes_are_state_and_io_free() -> void:
	var before := SaveManager.capture_state()
	var calls: Array[String] = []
	SaveManager.fault_injector = func(stage: String) -> bool:
		calls.append(stage)
		return false
	var party := _party()
	party.move_hero(0, 1)
	party.remove_hero(3)
	assert_eq(PartyFormationService.validation_error(party, BALANCING), "")
	assert_eq(SaveManager.capture_state(), before)
	assert_eq(calls, [])


func test_confirm_assigns_canonical_heroes_copies_mapping_and_saves_once() -> void:
	var draft := _party()
	var calls: Array[String] = []
	SaveManager.fault_injector = func(stage: String) -> bool:
		calls.append(stage)
		return false
	assert_true(PartyFormationService.confirm(draft, BALANCING), PartyFormationService.last_error)
	assert_same(GameState.current_party.slots[0], GameState.roster[0])
	assert_same(GameState.current_party.slots[3], GameState.roster[1])
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.ASSIGNED)
	assert_eq(GameState.roster[1].status, HeroData.HeroStatus.ASSIGNED)
	assert_eq(GameState.roster[2].status, HeroData.HeroStatus.IDLE)
	assert_eq(calls.count("before_temp_write"), 1)
	assert_eq(calls.count("before_primary_replace"), 1)
	draft.remove_hero(0)
	assert_same(GameState.current_party.slots[0], GameState.roster[0])
	var expected := SaveManager.capture_state()
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), expected)


func test_edit_retains_moves_replaces_and_releases_members_only_at_confirm() -> void:
	assert_true(PartyFormationService.confirm(_party(), BALANCING))
	var removed := GameState.roster[0]
	var retained := GameState.roster[1]
	var addition := GameState.roster[2]
	var draft := GameState.current_party.copy()
	assert_true(draft.remove_hero(0))
	assert_true(draft.move_hero(3, 2))
	assert_true(draft.place_hero(1, addition))
	assert_eq(removed.status, HeroData.HeroStatus.ASSIGNED)
	assert_eq(addition.status, HeroData.HeroStatus.IDLE)
	assert_eq(PartyFormationService.availability_error(removed), "")
	assert_true(PartyFormationService.confirm(draft, BALANCING), PartyFormationService.last_error)
	assert_eq(removed.status, HeroData.HeroStatus.IDLE)
	assert_eq(retained.status, HeroData.HeroStatus.ASSIGNED)
	assert_eq(addition.status, HeroData.HeroStatus.ASSIGNED)
	assert_same(GameState.current_party.slots[2], retained)
	assert_null(GameState.current_party.slots[3])


func test_repeated_confirm_and_disband_are_safe_noops_without_additional_writes() -> void:
	var draft := _party()
	assert_true(PartyFormationService.confirm(draft, BALANCING))
	var expected := SaveManager.capture_state()
	var calls: Array[String] = []
	SaveManager.fault_injector = func(stage: String) -> bool:
		calls.append(stage)
		return false
	assert_true(PartyFormationService.confirm(draft, BALANCING))
	assert_eq(calls, [])
	assert_eq(SaveManager.capture_state(), expected)
	assert_eq(PartyFormationService.last_error, "")
	assert_true(PartyFormationService.disband())
	assert_null(GameState.current_party)
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.IDLE)
	assert_eq(GameState.roster[1].status, HeroData.HeroStatus.IDLE)
	assert_eq(calls.count("before_temp_write"), 1)
	calls.clear()
	assert_true(PartyFormationService.disband())
	assert_eq(calls, [])
	SaveManager.load_or_create()
	assert_null(GameState.current_party)


func test_reject_empty_missing_offer_forged_and_duplicate_members_without_saving() -> void:
	var before := SaveManager.capture_state()
	var cases: Array[PartyData] = [null, PartyData.new()]
	for hero in [HeroData.new("missing"), HeroData.new(GameState.roster[0].hero_id),
			GameState.recruitment_offers[0]]:
		var draft := PartyData.new()
		draft.place_hero(0, hero)
		cases.append(draft)
	var duplicate := _party()
	duplicate.slots[2] = duplicate.slots[0]
	cases.append(duplicate)
	var calls: Array[String] = []
	SaveManager.fault_injector = func(stage: String) -> bool:
		calls.append(stage)
		return false
	for draft in cases:
		assert_false(PartyFormationService.confirm(draft, BALANCING))
		assert_false(PartyFormationService.last_error.is_empty())
		assert_eq(SaveManager.capture_state(), before)
	assert_eq(calls, [])


func test_all_unavailable_statuses_and_orphan_assigned_are_rejected() -> void:
	var hero := GameState.roster[0]
	for status in [HeroData.HeroStatus.ASSIGNED, HeroData.HeroStatus.ON_EXPEDITION,
			HeroData.HeroStatus.RESTING, HeroData.HeroStatus.WOUNDED, HeroData.HeroStatus.DEAD]:
		hero.status = status
		var before := GameState.checkpoint()
		assert_false(PartyFormationService.availability_error(hero).is_empty())
		assert_false(PartyFormationService.confirm(_party(), BALANCING))
		assert_eq(GameState.checkpoint(), before)
	assert_null(GameState.current_party)


func test_stale_canonical_identity_and_changed_status_are_revalidated_at_confirm() -> void:
	var draft := _party()
	SaveManager.load_or_create()
	var before := SaveManager.capture_state()
	assert_false(PartyFormationService.confirm(draft, BALANCING))
	assert_string_contains(PartyFormationService.last_error, "no longer")
	assert_eq(SaveManager.capture_state(), before)
	draft = _party()
	GameState.roster[0].status = HeroData.HeroStatus.WOUNDED
	assert_false(PartyFormationService.confirm(draft, BALANCING))
	assert_null(GameState.current_party)
	GameState.roster[0].status = HeroData.HeroStatus.IDLE
	GameState.roster.remove_at(0)
	assert_false(PartyFormationService.confirm(draft, BALANCING))


func test_checkpoint_restores_mutable_statuses_independent_slots_and_canonical_identity() -> void:
	assert_true(PartyFormationService.confirm(_party(), BALANCING))
	var hero := GameState.roster[0]
	var offer := GameState.recruitment_offers[0]
	var checkpoint := GameState.checkpoint()
	hero.status = HeroData.HeroStatus.DEAD
	offer.status = HeroData.HeroStatus.RESTING
	GameState.current_party.slots[0] = null
	GameState.roster.clear()
	GameState.restore_checkpoint(checkpoint)
	assert_same(GameState.roster[0], hero)
	assert_same(GameState.current_party.slots[0], hero)
	assert_same(GameState.recruitment_offers[0], offer)
	assert_eq(hero.status, HeroData.HeroStatus.ASSIGNED)
	assert_eq(offer.status, HeroData.HeroStatus.IDLE)
	GameState.current_party.remove_hero(0)
	GameState.restore_checkpoint(checkpoint)
	assert_same(GameState.current_party.slots[0], hero)
	GameState.reset()
	assert_null(GameState.current_party)
	GameState.restore_checkpoint(checkpoint)
	assert_same(GameState.current_party.slots[0], hero)


func test_every_precommit_confirm_failure_restores_statuses_and_slots_then_retry_works() -> void:
	assert_true(PartyFormationService.confirm(_party(), BALANCING))
	var draft := GameState.current_party.copy()
	draft.remove_hero(0)
	draft.place_hero(1, GameState.roster[2])
	var original := SaveManager.capture_state()
	var removed := GameState.roster[0]
	var added := GameState.roster[2]
	for boundary in ["before_temp_write", "after_temp_validation", "after_backup_preparation",
			"after_backup_replace", "before_primary_replace"]:
		SaveManager.fault_injector = func(stage: String) -> bool: return stage == boundary
		assert_false(PartyFormationService.confirm(draft, BALANCING), boundary)
		assert_false(SaveManager.last_committed)
		assert_string_contains(PartyFormationService.last_error, "not saved")
		assert_eq(SaveManager.capture_state(), original)
		assert_same(GameState.current_party.slots[0], removed)
		assert_same(GameState.roster[2], added)
		assert_eq(added.status, HeroData.HeroStatus.IDLE)
		assert_same(draft.slots[1], added)
	SaveManager.fault_injector = Callable()
	assert_true(PartyFormationService.confirm(draft, BALANCING))
	assert_eq(removed.status, HeroData.HeroStatus.IDLE)
	assert_eq(added.status, HeroData.HeroStatus.ASSIGNED)


func test_every_precommit_disband_failure_restores_confirmed_party_then_retry_works() -> void:
	assert_true(PartyFormationService.confirm(_party(), BALANCING))
	var original := SaveManager.capture_state()
	var hero := GameState.roster[0]
	for boundary in ["before_temp_write", "after_temp_validation", "after_backup_preparation",
			"after_backup_replace", "before_primary_replace"]:
		SaveManager.fault_injector = func(stage: String) -> bool: return stage == boundary
		assert_false(PartyFormationService.disband(), boundary)
		assert_eq(SaveManager.capture_state(), original)
		assert_same(GameState.current_party.slots[0], hero)
		assert_eq(hero.status, HeroData.HeroStatus.ASSIGNED)
	SaveManager.fault_injector = Callable()
	assert_true(PartyFormationService.disband())
	assert_null(GameState.current_party)
	assert_eq(hero.status, HeroData.HeroStatus.IDLE)


func test_postcommit_warnings_never_roll_back_confirm_or_disband() -> void:
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "after_primary_replace"
	assert_true(PartyFormationService.confirm(_party(), BALANCING))
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.ASSIGNED)
	assert_false(SaveManager.last_warning.is_empty())
	var expected := SaveManager.capture_state()
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), expected)
	assert_true(PartyFormationService.disband())
	assert_false(SaveManager.last_warning.is_empty())
	SaveManager.load_or_create()
	assert_null(GameState.current_party)
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.IDLE)


func test_active_expedition_blocks_edit_confirm_and_disband_without_mutation() -> void:
	assert_true(PartyFormationService.confirm(_party(), BALANCING))
	var draft := GameState.current_party.copy()
	draft.move_hero(0, 1)
	var before := SaveManager.capture_state()
	ExpeditionManager.set_script(ActiveExpedition)
	assert_true(ExpeditionManager.is_expedition_active())
	assert_string_contains(PartyFormationService.editing_error(), "active Expedition")
	assert_false(PartyFormationService.confirm(draft, BALANCING))
	assert_false(PartyFormationService.disband())
	assert_eq(SaveManager.capture_state(), before)
	assert_eq(ExpeditionManager.get_active_expedition(), {"sentinel": "unchanged"})


func test_invalid_balance_and_invalid_company_save_leave_party_and_statuses_unchanged() -> void:
	var draft := _party()
	var before := SaveManager.capture_state()
	assert_false(PartyFormationService.confirm(draft, null))
	assert_eq(SaveManager.capture_state(), before)
	GameState.gold = -1
	assert_false(PartyFormationService.confirm(draft, BALANCING))
	assert_null(GameState.current_party)
	assert_eq(GameState.roster[0].status, HeroData.HeroStatus.IDLE)
	GameState.reset()
	assert_false(PartyFormationService.confirm(draft, BALANCING))
	assert_false(PartyFormationService.disband())
