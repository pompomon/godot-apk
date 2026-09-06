extends GutTest


func test_empty_draft_and_four_named_slots() -> void:
	var party := PartyData.new()
	assert_eq(party.slots.keys(), PartyData.SLOT_ORDER)
	assert_eq(party.slots.values(), [null, null, null, null])
	assert_eq(party.heroes(), [])
	assert_false(party.has_front_row_hero())
	assert_eq(party.validation_error(), "")
	assert_false(party.validation_error(true).is_empty())


func test_order_does_not_depend_on_insertion_order_and_capacity_is_four() -> void:
	var party := PartyData.new()
	for slot in [3, 1, 2, 0]:
		assert_true(party.place_hero(slot, HeroData.new("member-%d" % slot)))
	for slot in PartyData.SLOT_ORDER:
		assert_eq(party.heroes()[slot].hero_id, "member-%d" % slot)
	assert_eq(party.heroes().get_typed_script(), HeroData)
	assert_true(party.has_front_row_hero())
	assert_eq(party.validation_error(true), "")
	assert_false(party.place_hero(4, HeroData.new("fifth")))
	assert_eq(party.heroes().size(), 4)


func test_invalid_placement_duplicates_and_occupied_slots_do_not_mutate() -> void:
	var party := PartyData.new()
	var first := HeroData.new("one")
	assert_true(party.place_hero(0, first))
	var before := party.slots.duplicate()
	for slot in [-1, 4, 99]:
		assert_false(party.place_hero(slot, HeroData.new("other")))
	assert_false(party.place_hero(1, first))
	assert_false(party.place_hero(1, HeroData.new("one")))
	assert_false(party.place_hero(0, HeroData.new("other")))
	assert_false(party.place_hero(1, null))
	assert_false(party.place_hero(1, HeroData.new("")))
	assert_false(party.place_hero(1, HeroData.new("   ")))
	assert_eq(party.slots, before)


func test_validated_move_and_remove_do_not_overwrite() -> void:
	var party := PartyData.new()
	var first := HeroData.new("one")
	var second := HeroData.new("two")
	party.place_hero(0, first)
	party.place_hero(1, second)
	for endpoints in [[0, 0], [0, 1], [2, 3], [-1, 0], [0, 4]]:
		var before := party.slots.duplicate()
		assert_false(party.move_hero(endpoints[0], endpoints[1]))
		assert_eq(party.slots, before)
	assert_true(party.move_hero(0, 2))
	assert_null(party.slots[0])
	assert_same(party.slots[2], first)
	assert_true(party.remove_hero(1))
	assert_false(party.has_front_row_hero())
	assert_eq(party.heroes(), [first])
	assert_false(party.remove_hero(-1))
	assert_false(party.remove_hero(1))
	assert_true(party.remove_hero(2))
	assert_eq(party.validation_error(), "")


func test_copy_keeps_hero_identity_and_independent_slot_mapping() -> void:
	var party := PartyData.new()
	var hero := HeroData.new("one")
	hero.status = HeroData.HeroStatus.ASSIGNED
	party.place_hero(0, hero)
	var draft := party.copy()
	assert_same(draft.slots[0], hero)
	assert_true(draft.move_hero(0, 3))
	assert_same(party.slots[0], hero)
	assert_null(party.slots[3])
	var returned := draft.heroes()
	returned.clear()
	assert_eq(draft.heroes(), [hero])
	assert_eq(hero.status, HeroData.HeroStatus.ASSIGNED)


func test_malformed_mappings_have_explicit_validation_feedback() -> void:
	var hero := HeroData.new("one")
	var cases := [
		{}, {0: hero}, {0: hero, 1: null, 2: null, 3: null, 4: null},
		{"0": hero, 1: null, 2: null, 3: null},
		{0.0: hero, 1: null, 2: null, 3: null},
		{0: hero, 1: hero, 2: null, 3: null},
		{0: hero, 1: HeroData.new("one"), 2: null, 3: null},
		{0: "not a Hero", 1: null, 2: null, 3: null},
		{0: HeroData.new(), 1: null, 2: null, 3: null},
	]
	for slots in cases:
		var party := PartyData.new()
		party.slots = slots
		assert_false(party.validation_error().is_empty(), str(slots))
		assert_false(party.place_hero(3, HeroData.new("other")))
		assert_false(party.remove_hero(0))
		assert_false(party.move_hero(0, 3))
		assert_eq(party.slots, slots)
