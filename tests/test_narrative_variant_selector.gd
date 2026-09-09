extends GutTest
## NarrativeVariantSelector must be deterministic and never touch gameplay RNG.


func test_same_inputs_return_the_same_text() -> void:
	var variants: Array[String] = ["b", "c", "d"]
	var first := NarrativeVariantSelector.select("a", variants, 12345, "green_hollow", 3, "loot", "", "loot")
	var second := NarrativeVariantSelector.select("a", variants, 12345, "green_hollow", 3, "loot", "", "loot")
	assert_eq(first, second)


func test_different_step_indexes_can_select_different_candidates() -> void:
	var variants: Array[String] = ["b", "c", "d", "e", "f", "g"]
	var seen := {}
	for step_index in range(8):
		seen[NarrativeVariantSelector.select("a", variants, 999, "green_hollow", step_index, "loot", "", "loot")] = true
	assert_gt(seen.size(), 1)


func test_empty_variant_pool_returns_fallback() -> void:
	var empty: Array[String] = []
	assert_eq(NarrativeVariantSelector.select("fallback", empty, 1, "r", 0, "c", "", "field"), "fallback")


func test_selection_does_not_advance_global_randomness() -> void:
	seed(4242)
	var expected := randi()
	seed(4242)
	var variants: Array[String] = ["b", "c"]
	NarrativeVariantSelector.select("a", variants, 55, "region", 2, "content", "outcome", "field")
	assert_eq(randi(), expected)


func test_candidate_ordering_is_deterministic() -> void:
	var variants: Array[String] = ["b", "c"]
	assert_eq(NarrativeVariantSelector.candidate_list("a", variants), ["a", "b", "c"])
	assert_eq(NarrativeVariantSelector.candidate_list("a", variants), ["a", "b", "c"])


func test_selection_does_not_mutate_source_arrays() -> void:
	var variants: Array[String] = ["b", "c"]
	var original := variants.duplicate()
	NarrativeVariantSelector.select("a", variants, 1, "r", 0, "c", "", "field")
	NarrativeVariantSelector.candidate_list("a", variants)
	assert_eq(variants, original)


func test_utf8_text_remains_valid() -> void:
	var variants: Array[String] = ["Café", "北の道", "naïve"]
	var result := NarrativeVariantSelector.select("fallback", variants, 3, "r", 0, "c", "", "field")
	assert_true(result in NarrativeVariantSelector.candidate_list("fallback", variants))


func test_invalid_candidate_arrays_are_rejected_by_catalog_validation() -> void:
	assert_false(ExpeditionCatalog.text_variants_valid("fallback", "not an array"))
	assert_false(ExpeditionCatalog.text_variants_valid("fallback", [""]))
	assert_false(ExpeditionCatalog.text_variants_valid("fallback", ["dup", "dup"]))
	assert_false(ExpeditionCatalog.text_variants_valid("fallback", ["fallback"]))
	assert_false(ExpeditionCatalog.text_variants_valid("fallback", [" leading"]))
	assert_false(ExpeditionCatalog.text_variants_valid("fallback", ["trailing "]))
	assert_false(ExpeditionCatalog.text_variants_valid("fallback", ["x".repeat(4097)]))
	assert_false(ExpeditionCatalog.text_variants_valid("fallback", [1, "ok"]))
	assert_false(ExpeditionCatalog.text_variants_valid("fallback", [null]))
	var too_many: Array = []
	for i in range(17):
		too_many.append("v%d" % i)
	assert_false(ExpeditionCatalog.text_variants_valid("fallback", too_many))
	assert_true(ExpeditionCatalog.text_variants_valid("fallback", []))
	assert_true(ExpeditionCatalog.text_variants_valid("fallback", ["a", "b"]))


func test_catalog_validation_rejects_variants_that_duplicate_fallbacks() -> void:
	var region: RegionResource = ExpeditionCatalog.GREEN_HOLLOW.duplicate(true)
	region.travel_text_variants.assign([region.travel_text])
	var balancing: BalancingConfig = load("res://data/balancing/default_balancing.tres")
	assert_false(ExpeditionCatalog.validate_region(region, balancing))

	var group: EnemyGroupResource = CombatCatalog.enemy_groups()[0].duplicate(true)
	group.journal_text_variants.assign(["The Party encounters %s." % group.display_name])
	assert_false(CombatCatalog.validate_enemy_group(group))


func test_event_validation_rejects_combined_variants_over_step_text_limit() -> void:
	var event: EventResource = ExpeditionCatalog.events()[0].duplicate(true)
	event.description_variants.assign(["d".repeat(3000)])
	event.outcomes[0].journal_text_variants.assign(["j".repeat(1096)])
	assert_false(ExpeditionCatalog.validate_event(event))


func test_select_travel_avoids_immediate_repetition_when_possible() -> void:
	var variants: Array[String] = ["b", "c", "d"]
	var previous := NarrativeVariantSelector.select_travel("a", variants, 10, "region", 0, "")
	var next_text := NarrativeVariantSelector.select_travel("a", variants, 10, "region", 1, previous)
	assert_ne(next_text, previous)


func test_select_travel_skips_variants_that_duplicate_fallback() -> void:
	var variants: Array[String] = ["same", "different"]
	for step_index in range(8):
		assert_eq(NarrativeVariantSelector.select_travel(
				"same", variants, 10, "region", step_index, "same"), "different")


func test_select_travel_with_single_candidate_always_returns_fallback() -> void:
	var empty: Array[String] = []
	assert_eq(NarrativeVariantSelector.select_travel("only", empty, 10, "region", 0, "only"), "only")
