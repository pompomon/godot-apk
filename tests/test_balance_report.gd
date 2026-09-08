extends GutTest


func test_seeded_parties_are_repeatable_and_use_authored_levels_and_equipment() -> void:
	var tuning: BalancingConfig = load("res://data/balancing/default_balancing.tres")
	for seed_value in [0, 1, 7001, 9999]:
		var first := BalanceReport.generate_party(seed_value)
		var repeated := BalanceReport.generate_party(seed_value)
		assert_not_null(first)
		assert_between(first.heroes().size(), 1, 4)
		assert_eq(ExpeditionPartySnapshot.capture(first, true).serialize(),
			ExpeditionPartySnapshot.capture(repeated, true).serialize())
		assert_gt(PartyEvaluator.compute_party_power(first, tuning), 0.0)
		for hero in first.heroes():
			assert_between(hero.level, 1, 12)
			assert_false(HeroStats.compute_derived_stats(hero).is_empty())


func test_seeded_valid_report_has_repeatable_accounted_rows() -> void:
	var tuning: BalancingConfig = load("res://data/balancing/default_balancing.tres")
	var regions: Array[RegionResource] = [ExpeditionCatalog.region_by_id("green_hollow")]
	var first := BalanceReport.run(regions, 2, 9001, tuning)
	var repeated := BalanceReport.run(regions, 2, 9001, tuning)
	assert_false(first.has("error"))
	assert_eq(first.rows, repeated.rows)
	for row in first.rows:
		assert_eq(row.trials, 2)
		assert_eq(row.distinct_parties, row.trials)
		assert_eq(row.outcomes.VICTORY + row.outcomes.RETREAT + row.outcomes.DEFEAT, row.trials)
		assert_eq(row.victory_rate_95_ci, BalanceReport.victory_interval(row.outcomes.VICTORY, row.trials))
		var group_trials := 0
		var group_victories := 0
		for group in row.enemy_groups.values():
			assert_eq(group.outcomes.VICTORY + group.outcomes.RETREAT + group.outcomes.DEFEAT, group.trials)
			assert_eq(group.victories, group.outcomes.VICTORY)
			group_trials += group.trials
			group_victories += group.victories
		assert_eq(group_trials, row.trials)
		assert_eq(group_victories, row.outcomes.VICTORY)
		assert_between(row.full_expedition_resting_heroes, 0, row.full_expedition_participating_heroes)
		assert_between(row.full_expedition_participating_heroes, row.trials, row.trials * 4)


func test_invalid_report_parameters_fail_without_touching_company() -> void:
	var before := GameState.checkpoint()
	var tuning: BalancingConfig = load("res://data/balancing/default_balancing.tres")
	for count in [0, -1, BalanceReport.MAX_TRIALS + 1]:
		assert_true(BalanceReport.run(ExpeditionCatalog.regions(), count, 7001, tuning).has("error"))
	assert_true(BalanceReport.run([], 1, 7001, tuning).has("error"))
	assert_true(BalanceReport.run(ExpeditionCatalog.regions(), 1, -1, tuning).has("error"))
	assert_eq(GameState.checkpoint(), before)


func test_insufficient_distinct_parties_are_rejected_instead_of_recycled() -> void:
	var tuning: BalancingConfig = load("res://data/balancing/default_balancing.tres")
	var regions: Array[RegionResource] = [ExpeditionCatalog.GREEN_HOLLOW]
	var result := BalanceReport.run(regions, BalanceReport.MAX_TRIALS, 7001, tuning)
	assert_true(result.has("error"))
	assert_string_contains(result.get("error", ""), "Insufficient distinct Parties")


func test_wilson_interval_has_known_values_and_handles_boundaries() -> void:
	var interval := BalanceReport.victory_interval(80, 100)
	assert_almost_eq(interval[0], 0.7111708344, 0.00000001)
	assert_almost_eq(interval[1], 0.8666330667, 0.00000001)
	assert_almost_eq(BalanceReport.victory_interval(0, 100)[0], 0.0, 0.00000001)
	assert_almost_eq(BalanceReport.victory_interval(100, 100)[1], 1.0, 0.00000001)
	assert_gt(BalanceReport.victory_interval(0, 100)[1], 0.0)
	assert_lt(BalanceReport.victory_interval(100, 100)[0], 1.0)
	assert_eq(BalanceReport.victory_interval(0, 0), [])
	assert_eq(BalanceReport.victory_interval(-1, 100), [])
	assert_eq(BalanceReport.victory_interval(101, 100), [])
