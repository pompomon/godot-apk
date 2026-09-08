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
		assert_eq(row.outcomes.VICTORY + row.outcomes.RETREAT + row.outcomes.DEFEAT, row.trials)


func test_invalid_report_parameters_fail_without_touching_company() -> void:
	var before := GameState.checkpoint()
	var tuning: BalancingConfig = load("res://data/balancing/default_balancing.tres")
	for count in [0, -1, BalanceReport.MAX_TRIALS + 1]:
		assert_true(BalanceReport.run(ExpeditionCatalog.regions(), count, 7001, tuning).has("error"))
	assert_true(BalanceReport.run([], 1, 7001, tuning).has("error"))
	assert_true(BalanceReport.run(ExpeditionCatalog.regions(), 1, -1, tuning).has("error"))
	assert_eq(GameState.checkpoint(), before)
