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


func test_target_bands_and_margins_keep_existing_boundaries() -> void:
	assert_true(BalanceReport.target_met("below", 0.4999))
	assert_false(BalanceReport.target_met("below", 0.5))
	for tier in ["at", "above"]:
		assert_true(BalanceReport.target_met(tier, 0.70))
		assert_true(BalanceReport.target_met(tier, 0.85))
		assert_false(BalanceReport.target_met(tier, 0.6999))
		assert_false(BalanceReport.target_met(tier, 0.8501))
	assert_almost_eq(BalanceReport.band_margin("below", 0.47), 0.03, 0.0000001)
	assert_almost_eq(BalanceReport.band_margin("at", 0.75), 0.05, 0.0000001)
	assert_almost_eq(BalanceReport.band_margin("above", 0.862), -0.012, 0.0000001)


func test_aggregate_sums_raw_seed_counts_without_averaging_rates() -> void:
	var first := _report(1, [[3, 1, 0], [2, 0, 2]], 0.5, 120)
	var second := _report(2, [[1, 0, 3], [4, 0, 0]], 0.25, 150)
	var combined := BalanceReport.aggregate([first, second])
	assert_false(combined.has("error"), str(combined.get("error")))
	assert_eq(combined.seeds, [1, 2])
	assert_eq(combined.trials_per_tier, 4)
	var row: Dictionary = combined.rows[0]
	assert_eq([row.region, row.tier, row.trials], ["green_hollow", "at", 8])
	assert_eq(row.outcomes, {"VICTORY": 4, "RETREAT": 1, "DEFEAT": 3})
	assert_eq(row.seed_outcomes, [{"VICTORY": 3, "RETREAT": 1, "DEFEAT": 0},
		{"VICTORY": 1, "RETREAT": 0, "DEFEAT": 3}])
	assert_almost_eq(row.victory_rate, 0.5, 0.0000001)
	assert_false(row.target_met)
	assert_almost_eq(row.band_margin, -0.2, 0.0000001)
	assert_eq(row.victory_rate_95_ci, BalanceReport.victory_interval(4, 8))
	assert_eq(row.enemy_groups.forest_wolves.outcomes, row.outcomes)
	assert_eq(row.enemy_groups.forest_wolves.trials, 8)
	assert_eq(row.enemy_groups.forest_wolves.victories, 4)
	assert_almost_eq(row.full_expedition_completion_rate, 0.375, 0.0000001)
	assert_eq([row.full_expedition_resting_heroes, row.full_expedition_participating_heroes], [4, 16])
	assert_eq(row.max_expedition_bytes, 150)
	assert_eq([row.power_min, row.power_max, row.members_min, row.members_max], [310.0, 360.0, 1, 4])
	var below: Dictionary = combined.rows[1]
	assert_eq(below.outcomes, {"VICTORY": 6, "RETREAT": 0, "DEFEAT": 2})
	assert_false(below.target_met)


func test_aggregate_rejects_duplicate_seeds_and_mismatched_rows() -> void:
	var first := _report(1, [[3, 1, 0], [2, 0, 2]], 0.5, 120)
	assert_true(BalanceReport.aggregate([]).has("error"))
	assert_true(BalanceReport.aggregate([first, first.duplicate(true)]).has("error"))
	assert_true(BalanceReport.aggregate([first, {"error": "failed"}]).has("error"))
	var other_trials := _report(2, [[3, 1, 0], [2, 0, 2]], 0.5, 120)
	other_trials.trials_per_tier = 5
	assert_true(BalanceReport.aggregate([first, other_trials]).has("error"))
	var other_power := _report(3, [[3, 1, 0], [2, 0, 2]], 0.5, 120)
	other_power.rows[0].recommended_power = 331
	assert_true(BalanceReport.aggregate([first, other_power]).has("error"))
	var missing_row := _report(4, [[3, 1, 0], [2, 0, 2]], 0.5, 120)
	missing_row.rows.pop_back()
	assert_true(BalanceReport.aggregate([first, missing_row]).has("error"))
	var short_row := _report(5, [[3, 1, 0], [2, 0, 2]], 0.5, 120)
	short_row.rows[1].trials = 3
	assert_true(BalanceReport.aggregate([first, short_row]).has("error"))


func test_aggregate_of_one_real_report_preserves_its_counts() -> void:
	var tuning: BalancingConfig = load("res://data/balancing/default_balancing.tres")
	var regions: Array[RegionResource] = [ExpeditionCatalog.GREEN_HOLLOW]
	var report := BalanceReport.run(regions, 2, 9001, tuning)
	var combined := BalanceReport.aggregate([report])
	assert_false(combined.has("error"), str(combined.get("error")))
	assert_eq(combined.rows.size(), report.rows.size())
	for index in range(report.rows.size()):
		var row: Dictionary = report.rows[index]
		var total: Dictionary = combined.rows[index]
		assert_eq([total.region, total.tier, total.trials], [row.region, row.tier, row.trials])
		assert_eq(total.outcomes, row.outcomes)
		assert_eq(total.victory_rate, row.victory_rate)
		assert_eq(total.target_met, row.target_met)
		assert_eq(total.victory_rate_95_ci, row.victory_rate_95_ci)
		assert_eq(total.full_expedition_completion_rate, row.full_expedition_completion_rate)
		assert_eq(total.max_expedition_bytes, row.max_expedition_bytes)


func _report(seed_value: int, counts: Array, completion: float, bytes: int) -> Dictionary:
	var rows: Array = []
	var tiers := ["at", "below"]
	for index in range(counts.size()):
		var outcome := {"VICTORY": counts[index][0], "RETREAT": counts[index][1],
			"DEFEAT": counts[index][2]}
		rows.append({"region": "green_hollow", "tier": tiers[index], "recommended_power": 330,
			"power_min": 300.0 + seed_value * 10, "power_max": 340.0 + seed_value * 10,
			"members_min": seed_value, "members_max": 2 + seed_value, "trials": 4,
			"outcomes": outcome, "enemy_groups": {"forest_wolves": {"trials": 4,
				"victories": outcome.VICTORY, "outcomes": outcome.duplicate()}},
			"full_expedition_completion_rate": completion, "full_expedition_resting_heroes": 2,
			"full_expedition_participating_heroes": 8, "max_expedition_bytes": bytes})
	return {"seed": seed_value, "trials_per_tier": 4, "rows": rows}
