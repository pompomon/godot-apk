extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
const STAGES := ["before_temp_write", "after_temp_validation", "after_backup_preparation",
	"after_backup_replace", "before_primary_replace", "after_primary_replace"]
var _isolation: RefCounted


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success)
	_stock()


func after_each() -> void:
	_isolation.finish()


func _stock() -> void:
	GameState.inventory.assign([ItemCatalog.SHORT_SWORD, ItemCatalog.SHORT_SWORD,
		ItemCatalog.HUNTING_BOW, ItemCatalog.LEATHER_ARMOR])
	SaveManager.save()
	assert_true(SaveManager.last_committed, SaveManager.last_error)


func test_preview_is_detached_and_does_not_mutate_hero_inventory_or_resources() -> void:
	var hero := GameState.roster[0]
	var before := SaveManager.capture_state()
	var original := HeroStats.compute_derived_stats(hero)
	var modifiers := ItemCatalog.SHORT_SWORD.stat_modifiers.duplicate()
	var draft := EquipmentService.new(hero)
	draft.weapon = ItemCatalog.SHORT_SWORD
	draft.armor = ItemCatalog.LEATHER_ARMOR
	var expected := original.duplicate()
	for item in [draft.weapon, draft.armor]:
		for stat in item.stat_modifiers:
			expected[stat] += int(item.stat_modifiers[stat])
	assert_eq(draft.preview_stats(), expected)
	assert_eq(SaveManager.capture_state(), before)
	assert_eq(ItemCatalog.SHORT_SWORD.stat_modifiers, modifiers)
	assert_null(hero.equipped_weapon)


func test_equip_swap_unequip_and_duplicate_copies_survive_reload() -> void:
	var hero := GameState.roster[0]
	var draft := EquipmentService.new(hero)
	draft.weapon = ItemCatalog.SHORT_SWORD
	draft.armor = ItemCatalog.LEATHER_ARMOR
	assert_true(draft.confirm(), draft.last_error)
	assert_same(hero.equipped_weapon, ItemCatalog.SHORT_SWORD)
	assert_same(hero.equipped_armor, ItemCatalog.LEATHER_ARMOR)
	assert_eq(GameState.inventory.count(ItemCatalog.SHORT_SWORD), 1)
	assert_eq(GameState.inventory.size(), 2)
	draft.weapon = ItemCatalog.HUNTING_BOW
	assert_true(draft.confirm(), draft.last_error)
	assert_eq(GameState.inventory.count(ItemCatalog.SHORT_SWORD), 2)
	assert_false(GameState.inventory.has(ItemCatalog.HUNTING_BOW))
	var saved := SaveManager.capture_state()
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), saved)
	hero = GameState.roster[0]
	assert_same(hero.equipped_weapon, ItemCatalog.HUNTING_BOW)
	assert_same(hero.equipped_armor, ItemCatalog.LEATHER_ARMOR)
	assert_same(GameState.inventory[0], ItemCatalog.SHORT_SWORD)
	draft = EquipmentService.new(hero)
	draft.weapon = null
	draft.armor = null
	assert_true(draft.confirm(), draft.last_error)
	assert_null(hero.equipped_weapon)
	assert_null(hero.equipped_armor)
	assert_eq(GameState.inventory.size(), 4)
	assert_eq(GameState.inventory.count(ItemCatalog.SHORT_SWORD), 2)


func test_duplicate_copies_can_equip_two_heroes_but_not_a_third() -> void:
	for index in [0, 1]:
		var draft := EquipmentService.new(GameState.roster[index])
		draft.weapon = ItemCatalog.SHORT_SWORD
		assert_true(draft.confirm(), draft.last_error)
	var third := EquipmentService.new(GameState.roster[2])
	third.weapon = ItemCatalog.SHORT_SWORD
	var saved := SaveManager.capture_state()
	assert_false(third.confirm())
	assert_string_contains(third.last_error, "inventory")
	assert_eq(SaveManager.capture_state(), saved)
	var unchanged := EquipmentService.new(GameState.roster[0])
	assert_true(unchanged.confirm())
	assert_eq(SaveManager.capture_state(), saved)


func test_new_rewards_while_drafting_are_preserved_and_missing_items_rejected() -> void:
	var draft := EquipmentService.new(GameState.roster[0])
	draft.weapon = ItemCatalog.HUNTING_BOW
	GameState.inventory.append(ItemCatalog.ROBES)
	assert_true(draft.confirm(), draft.last_error)
	assert_true(GameState.inventory.has(ItemCatalog.ROBES))
	var second := EquipmentService.new(GameState.roster[1])
	second.armor = ItemCatalog.ROBES
	GameState.inventory.erase(ItemCatalog.ROBES)
	var before := SaveManager.capture_state()
	assert_false(second.confirm())
	assert_eq(SaveManager.capture_state(), before)


func test_invalid_slots_unowned_items_and_forged_resources_are_rejected() -> void:
	var draft := EquipmentService.new(GameState.roster[0])
	var before := SaveManager.capture_state()
	for item in [ItemCatalog.LEATHER_ARMOR, ItemCatalog.APPRENTICE_STAFF,
			ItemCatalog.SHORT_SWORD.duplicate(true), ItemResource.new()]:
		draft.weapon = item
		assert_false(draft.confirm())
		assert_false(draft.last_error.is_empty())
		assert_eq(draft.preview_stats(), {})
		assert_eq(SaveManager.capture_state(), before)
	draft.weapon = null
	draft.armor = ItemCatalog.SHORT_SWORD
	assert_false(draft.confirm())


func test_eligibility_rejects_stale_heroes_offers_and_departed_heroes() -> void:
	assert_false(EquipmentService.new().confirm())
	assert_false(EquipmentService.new(GameState.recruitment_offers[0]).confirm())
	var hero := GameState.roster[0]
	var draft := EquipmentService.new(hero)
	for status in HeroData.HeroStatus.values():
		hero.status = status as HeroData.HeroStatus
		assert_eq(draft.validation_error().is_empty(), status in [
			HeroData.HeroStatus.IDLE, HeroData.HeroStatus.ASSIGNED, HeroData.HeroStatus.RESTING])
	hero.status = HeroData.HeroStatus.IDLE
	SaveManager.load_or_create()
	assert_false(draft.confirm(), "Reload replaces the canonical Hero even with the same stable ID.")
	draft = EquipmentService.new(GameState.roster[0])
	GameState.roster[0].equipped_weapon = ItemCatalog.HUNTING_BOW
	assert_false(draft.confirm(), "A stale screen cannot overwrite a different equipped item.")


func test_equipment_updates_confirmed_party_power_and_only_new_snapshots() -> void:
	var hero := GameState.roster[0]
	var party := PartyData.new()
	party.place_hero(0, hero)
	assert_true(PartyFormationService.confirm(party, ExpeditionManager.balancing))
	var canonical_party := GameState.current_party
	var frozen := ExpeditionPartySnapshot.capture(canonical_party, true)
	var old_snapshot := frozen.serialize()
	var old_power := PartyEvaluator.compute_party_power(canonical_party, ExpeditionManager.balancing)
	var draft := EquipmentService.new(hero)
	draft.weapon = ItemCatalog.SHORT_SWORD
	draft.armor = ItemCatalog.LEATHER_ARMOR
	assert_true(draft.confirm(), draft.last_error)
	assert_same(GameState.current_party, canonical_party)
	assert_same(canonical_party.heroes()[0], hero)
	assert_eq(hero.status, HeroData.HeroStatus.ASSIGNED)
	assert_gt(PartyEvaluator.compute_party_power(canonical_party, ExpeditionManager.balancing), old_power)
	var updated := ExpeditionPartySnapshot.capture(canonical_party, true)
	assert_eq(updated.slots.FRONT_LEFT.derived_stats, HeroStats.compute_derived_stats(hero))
	assert_gt(updated.slots.FRONT_LEFT.derived_stats.Attack, frozen.slots.FRONT_LEFT.derived_stats.Attack)
	assert_eq(frozen.serialize(), old_snapshot)
	var result := CombatEngine.resolve_combat(updated, updated.hero_states(),
		CombatCatalog.FOREST_WOLVES, 123, ExpeditionManager.balancing)
	assert_false(result.has("error"), str(result.get("error")))


func test_every_save_fault_rolls_back_or_keeps_committed_transfer_and_can_retry() -> void:
	for stage in STAGES:
		SaveManager.fault_injector = Callable()
		assert_true(RecruitmentService.initialize_new_game(12345))
		_stock()
		var hero := GameState.roster[0]
		var original := SaveManager.capture_state()
		var draft := EquipmentService.new(hero)
		draft.weapon = ItemCatalog.SHORT_SWORD
		draft.armor = ItemCatalog.LEATHER_ARMOR
		SaveManager.fault_injector = func(boundary: String) -> bool: return boundary == stage
		var committed: bool = stage == "after_primary_replace"
		assert_eq(draft.confirm(), committed, stage)
		assert_same(GameState.roster[0], hero, stage)
		if committed:
			assert_same(hero.equipped_weapon, ItemCatalog.SHORT_SWORD)
			assert_same(hero.equipped_armor, ItemCatalog.LEATHER_ARMOR)
			assert_false(SaveManager.last_warning.is_empty())
		else:
			assert_eq(SaveManager.capture_state(), original, stage)
			assert_same(draft.weapon, ItemCatalog.SHORT_SWORD, "Keep failed selection for retry.")
			SaveManager.fault_injector = Callable()
			assert_true(draft.confirm(), draft.last_error)
		SaveManager.fault_injector = Callable()
		var saved := SaveManager.capture_state()
		SaveManager.load_or_create()
		assert_eq(SaveManager.capture_state(), saved, stage)
