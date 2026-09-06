extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
var _isolation: RefCounted
var _balancing: BalancingConfig


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	_balancing = load("res://data/balancing/default_balancing.tres").duplicate()


func after_each() -> void:
	_isolation.finish()


func _boot() -> void:
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success, SaveManager.last_error)


func _offers(heroes: Array[HeroData]) -> Array:
	var result := []
	for hero in heroes:
		var traits := []
		for hero_trait in hero.traits:
			traits.append(hero_trait.trait_id)
		result.append([hero.hero_id, hero.hero_name, hero.hero_class.class_id,
			hero.attributes.duplicate(), traits])
	return result


func test_pure_offers_are_reproducible_and_do_not_allocate_or_mutate() -> void:
	var before := GameState.checkpoint()
	var ids: Array[String] = ["reserved-1", "reserved-2", "reserved-3"]
	var first := RecruitmentService.generate_offers(
		HeroCatalog.MAX_SAFE_INT, ids, HeroCatalog.classes(), HeroCatalog.traits())
	var second := RecruitmentService.generate_offers(
		HeroCatalog.MAX_SAFE_INT, ids, HeroCatalog.classes(), HeroCatalog.traits())
	assert_eq(_offers(first), _offers(second))
	assert_eq(first.size(), 3)
	assert_eq(first[0].hero_id, "reserved-1")
	assert_eq(GameState.checkpoint(), before)
	assert_eq(ids, ["reserved-1", "reserved-2", "reserved-3"])
	assert_eq(RecruitmentService.last_error, "")


func test_empty_and_invalid_offer_inputs_have_no_side_effects() -> void:
	var classes := HeroCatalog.classes()
	var traits := HeroCatalog.traits()
	var no_ids: Array[String] = []
	var id: Array[String] = ["one"]
	var duplicates: Array[String] = ["one", "one"]
	var invalid: Array[String] = ["one", ""]
	var no_classes: Array[HeroClassResource] = []
	var no_traits: Array[HeroTraitResource] = []
	assert_eq(RecruitmentService.generate_offers(1, no_ids, classes, traits), [])
	assert_eq(RecruitmentService.generate_offers(1, duplicates, classes, traits), [])
	assert_eq(RecruitmentService.generate_offers(1, invalid, classes, traits), [])
	assert_eq(RecruitmentService.generate_offers(-1, id, classes, traits), [])
	assert_eq(RecruitmentService.generate_offers(HeroCatalog.MAX_SAFE_INT + 1, id, classes, traits), [])
	assert_eq(RecruitmentService.generate_offers(1, id, no_classes, traits), [])
	assert_eq(RecruitmentService.generate_offers(1, id, classes, no_traits)[0].traits.size(), 0)
	assert_eq(GameState.next_hero_id, 1)


func test_seed_arithmetic_is_bounded_and_pinned() -> void:
	assert_eq(RecruitmentService.seed_at(12345, 0), 12345)
	assert_eq(RecruitmentService.seed_at(12345, 1), 60616)
	assert_eq(RecruitmentService.seed_at(HeroCatalog.MAX_SAFE_INT, 0), 4194303)
	assert_eq(RecruitmentService.seed_at(-1, 0), -1)
	assert_eq(RecruitmentService.seed_at(0, -1), -1)
	assert_eq(RecruitmentService.seed_at(HeroCatalog.MAX_SAFE_INT + 1, 0), -1)
	assert_eq(RecruitmentService.seed_at(0, HeroCatalog.MAX_SAFE_INT + 1), -1)
	for seed in [0, 1, HeroCatalog.MAX_SAFE_INT]:
		for sequence in [0, 12345, HeroCatalog.MAX_SAFE_INT]:
			assert_between(RecruitmentService.seed_at(seed, sequence), 0, 2147483646)


func test_bootstrap_failure_is_side_effect_free() -> void:
	var before := GameState.checkpoint()
	assert_false(RecruitmentService.initialize_new_game(-1))
	assert_eq(GameState.checkpoint(), before)
	assert_false(FileAccess.file_exists(SaveManager.get_save_path()))


func test_purchase_keeps_offer_identity_and_only_replaces_purchased_slot() -> void:
	_boot()
	var offer := GameState.recruitment_offers[1]
	var first := GameState.recruitment_offers[0]
	var third := GameState.recruitment_offers[2]
	var seed_before := GameState.recruitment_seed
	var old_seeds := GameState.offer_seeds.duplicate()
	assert_true(RecruitmentService.recruit(offer, _balancing), RecruitmentService.last_error)
	assert_eq(GameState.gold, 0)
	assert_eq(GameState.roster.size(), 5)
	assert_same(GameState.roster[4], offer)
	assert_eq(GameState.roster[4].hero_id, "hero-6")
	assert_same(GameState.recruitment_offers[0], first)
	assert_same(GameState.recruitment_offers[2], third)
	assert_eq(GameState.recruitment_offers[1].hero_id, "hero-8")
	assert_eq(GameState.next_hero_id, 9)
	assert_eq(GameState.recruitment_sequence, 8)
	assert_eq(GameState.recruitment_seed, seed_before)
	assert_eq(GameState.offer_seeds[0], old_seeds[0])
	assert_eq(GameState.offer_seeds[2], old_seeds[2])
	var expected := SaveManager.capture_state()
	GameState.reset()
	SaveManager.new_game_seed_override = 1
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), expected)


func test_no_reload_refresh_and_deterministic_continuation() -> void:
	_boot()
	GameState.gold = 1000
	SaveManager.save()
	var initial := GameState.checkpoint()
	var initial_json := SaveManager.capture_state()
	assert_true(RecruitmentService.recruit(GameState.recruitment_offers[2], _balancing))
	var first_result := SaveManager.capture_state()
	assert_true(RecruitmentService.recruit(GameState.recruitment_offers[0], _balancing))
	var second_result := SaveManager.capture_state()
	GameState.restore_checkpoint(initial)
	SaveManager.save()
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), initial_json)
	assert_true(RecruitmentService.recruit(GameState.recruitment_offers[2], _balancing))
	assert_eq(SaveManager.capture_state(), first_result)
	SaveManager.load_or_create()
	assert_true(RecruitmentService.recruit(GameState.recruitment_offers[0], _balancing))
	assert_eq(SaveManager.capture_state(), second_result)


func test_double_click_stale_missing_and_already_rostered_offers_are_rejected() -> void:
	_boot()
	var offer := GameState.recruitment_offers[0]
	assert_true(RecruitmentService.recruit(offer, _balancing))
	var after := SaveManager.capture_state()
	assert_false(RecruitmentService.recruit(offer, _balancing))
	assert_string_contains(RecruitmentService.last_error, "already")
	assert_false(RecruitmentService.recruit(HeroData.new("hero-999"), _balancing))
	assert_string_contains(RecruitmentService.last_error, "no longer")
	assert_false(RecruitmentService.recruit(null, _balancing))
	assert_eq(SaveManager.capture_state(), after)


func test_forged_hero_data_cannot_replace_actual_offer_data() -> void:
	_boot()
	var actual := GameState.recruitment_offers[0]
	var fake := HeroData.new(actual.hero_id)
	fake.hero_name = "Forged Hero"
	fake.level = 999
	assert_true(RecruitmentService.recruit(fake, _balancing))
	assert_same(GameState.roster[4], actual)
	assert_ne(GameState.roster[4].hero_name, fake.hero_name)
	assert_eq(GameState.roster[4].level, 1)


func test_custom_price_funds_and_capacity_checks_do_not_mutate_or_save() -> void:
	_boot()
	var offer := GameState.recruitment_offers[0]
	_balancing.recruitment_cost = 125
	var before := SaveManager.capture_state()
	var calls: Array[String] = []
	SaveManager.fault_injector = func(stage: String) -> bool:
		calls.append(stage)
		return false
	assert_false(RecruitmentService.recruit(offer, _balancing))
	assert_string_contains(RecruitmentService.last_error, "125")
	assert_eq(SaveManager.capture_state(), before)
	GameState.roster_capacity = 4
	_balancing.recruitment_cost = 25
	assert_false(RecruitmentService.recruit(offer, _balancing))
	assert_string_contains(RecruitmentService.last_error, "Roster full")
	assert_eq(calls, [])
	GameState.roster_capacity = 12
	assert_true(RecruitmentService.recruit(offer, _balancing))
	assert_eq(GameState.gold, 75)
	assert_eq(calls.count("before_temp_write"), 1)
	assert_eq(calls.count("before_primary_replace"), 1)


func test_invalid_prices_and_exhausted_allocators_reject_without_mutation() -> void:
	_boot()
	var offer := GameState.recruitment_offers[0]
	var before := SaveManager.capture_state()
	assert_false(RecruitmentService.recruit(offer, null))
	_balancing.recruitment_cost = -1
	assert_false(RecruitmentService.recruit(offer, _balancing))
	assert_eq(SaveManager.capture_state(), before)
	_balancing.recruitment_cost = 0
	GameState.next_hero_id = HeroCatalog.MAX_SAFE_INT
	assert_false(RecruitmentService.recruit(offer, _balancing))
	assert_string_contains(RecruitmentService.last_error, "exhausted")
	GameState.next_hero_id = 8
	GameState.recruitment_sequence = HeroCatalog.MAX_SAFE_INT
	assert_false(RecruitmentService.recruit(offer, _balancing))
	assert_eq(GameState.roster.size(), 4)


func test_every_precommit_failure_rolls_back_every_field_and_object_identity() -> void:
	_boot()
	var original := SaveManager.capture_state()
	var offer := GameState.recruitment_offers[1]
	for boundary in ["before_temp_write", "after_temp_validation", "after_backup_preparation",
			"after_backup_replace", "before_primary_replace"]:
		SaveManager.fault_injector = func(stage: String) -> bool: return stage == boundary
		assert_false(RecruitmentService.recruit(offer, _balancing), boundary)
		assert_eq(SaveManager.capture_state(), original, boundary)
		assert_same(GameState.recruitment_offers[1], offer)
		assert_string_contains(RecruitmentService.last_error, "no gold was spent")
		assert_false(SaveManager.last_committed)
	SaveManager.fault_injector = Callable()
	assert_true(RecruitmentService.recruit(offer, _balancing))
	assert_same(GameState.roster[4], offer)


func test_postcommit_warning_never_rolls_back_purchase() -> void:
	_boot()
	var offer := GameState.recruitment_offers[0]
	SaveManager.fault_injector = func(stage: String) -> bool: return stage == "after_primary_replace"
	assert_true(RecruitmentService.recruit(offer, _balancing))
	assert_same(GameState.roster[4], offer)
	assert_eq(GameState.gold, 0)
	assert_false(SaveManager.last_warning.is_empty())
	var expected := SaveManager.capture_state()
	SaveManager.fault_injector = Callable()
	SaveManager.load_or_create()
	assert_eq(SaveManager.capture_state(), expected)
