extends GutTest

const BALANCING: BalancingConfig = preload("res://data/balancing/default_balancing.tres")


func test_thresholds_before_at_and_above_are_exact_and_ordered() -> void:
	for gold in [0, 199, 200, 201, 399, 400, 401, HeroCatalog.MAX_SAFE_INT]:
		var result := CompanyProgression.preview(gold, [], 12, BALANCING)
		assert_false(result.has("error"), str(gold))
		var expected: Array[StringName] = [&"green_hollow"]
		if gold >= 200:
			expected.append(&"ashen_reach")
		if gold >= 400:
			expected.append(&"frostbound_pass")
		assert_eq(result.unlocked_regions, expected, str(gold))
		assert_eq(result.roster_capacity, 20 if gold >= 400 else (16 if gold >= 200 else 12))
		assert_eq(result.unlocked_regions.get_typed_builtin(), TYPE_STRING_NAME)


func test_spending_and_lower_tuning_never_remove_achievements_or_capacity() -> void:
	var unlocked: Array[StringName] = [&"green_hollow", &"ashen_reach", &"frostbound_pass"]
	var config := BALANCING.duplicate(true)
	config.region_roster_capacities = {"green_hollow": 4, "ashen_reach": 8, "frostbound_pass": 12}
	for capacity in [20, 32, CompanyProgression.MAX_ROSTER_CAPACITY]:
		var result := CompanyProgression.preview(0, unlocked, capacity, config)
		assert_eq(result.unlocked_regions, unlocked)
		assert_eq(result.roster_capacity, capacity)
	var partial := CompanyProgression.preview(0, ["frostbound_pass"], 12, BALANCING)
	assert_eq(partial.unlocked_regions, [&"frostbound_pass", &"green_hollow"])
	assert_eq(partial.roster_capacity, 20)


func test_preview_does_not_mutate_inputs_or_alias_the_returned_list() -> void:
	var unlocked: Array[StringName] = [&"green_hollow"]
	var config := BALANCING.duplicate(true)
	var tuning: Dictionary = config.region_roster_capacities.duplicate(true)
	var result := CompanyProgression.preview(200, unlocked, 12, config)
	assert_eq(unlocked, [&"green_hollow"])
	assert_eq(config.region_roster_capacities, tuning)
	result.unlocked_regions.clear()
	assert_eq(unlocked, [&"green_hollow"])


func test_preview_rejects_bad_company_ranges_and_region_ids() -> void:
	for gold in [-1, HeroCatalog.MAX_SAFE_INT + 1]:
		assert_true(CompanyProgression.preview(gold, [], 12, BALANCING).has("error"))
	for capacity in [0, -1, CompanyProgression.MAX_ROSTER_CAPACITY + 1]:
		assert_true(CompanyProgression.preview(100, [], capacity, BALANCING).has("error"))
	for unlocked in [[true], [1], [null], [{}], [""], ["unknown"],
			["res://data/regions/green_hollow.tres"], ["green_hollow", &"green_hollow"]]:
		var result := CompanyProgression.preview(100, unlocked, 12, BALANCING)
		assert_true(HeroCatalog.has_exact_keys(result, ["error"]), str(unlocked))


func test_preview_validates_only_its_required_tuning_and_exact_capacity_map() -> void:
	assert_true(CompanyProgression.preview(100, [], 12, null).has("error"))
	for capacities in [{}, {"green_hollow": 12},
			{"green_hollow": 12, "ashen_reach": 16, "frostbound_pass": 20, "unknown": 24}]:
		var config := BALANCING.duplicate(true)
		config.region_roster_capacities = capacities
		assert_true(CompanyProgression.preview(400, [], 12, config).has("error"))
	for value in [null, true, "16", 0, -1, 1.5, INF, NAN, CompanyProgression.MAX_ROSTER_CAPACITY + 1]:
		var config := BALANCING.duplicate(true)
		config.region_roster_capacities.ashen_reach = value
		assert_true(CompanyProgression.preview(0, [], 12, config).has("error"), str(value))
	var config := BalancingConfig.new()
	config.region_roster_capacities = {"green_hollow": 12.0, "ashen_reach": 16.0, "frostbound_pass": 20.0}
	assert_false(CompanyProgression.preview(400, [], 12, config).has("error"),
		"Unrelated Combat, reward and clock fields are not part of Company eligibility.")


func test_eligibility_uses_saved_membership_and_requirement_text_is_safe() -> void:
	assert_true(CompanyProgression.is_unlocked(ExpeditionCatalog.GREEN_HOLLOW, []))
	assert_false(CompanyProgression.is_unlocked(ExpeditionCatalog.ASHEN_REACH, []))
	assert_true(CompanyProgression.is_unlocked(ExpeditionCatalog.ASHEN_REACH, ["ashen_reach"]))
	assert_false(CompanyProgression.is_unlocked(ExpeditionCatalog.FROSTBOUND_PASS, ["ashen_reach"]))
	assert_false(CompanyProgression.is_unlocked(null, ["green_hollow"]))
	var unknown := RegionResource.new()
	unknown.region_id = &"unknown"
	assert_false(CompanyProgression.is_unlocked(unknown, ["unknown"]))
	assert_string_contains(CompanyProgression.requirement_text(ExpeditionCatalog.GREEN_HOLLOW), "Always")
	assert_string_contains(CompanyProgression.requirement_text(ExpeditionCatalog.ASHEN_REACH), "200")
	assert_string_contains(CompanyProgression.requirement_text(ExpeditionCatalog.FROSTBOUND_PASS), "400")
	assert_false(CompanyProgression.requirement_text(null).is_empty())
	var malformed := ExpeditionCatalog.ASHEN_REACH.duplicate(true)
	malformed.unlock_condition = {"kind": "gold", "value": "200"}
	assert_string_contains(CompanyProgression.requirement_text(malformed), "invalid")
