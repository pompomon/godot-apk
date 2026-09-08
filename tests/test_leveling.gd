extends GutTest


func test_default_awards_and_ceiling_rounded_cumulative_thresholds() -> void:
	assert_eq(Leveling.award(101, 60), 85)
	assert_eq(Leveling.threshold(1), 0)
	assert_eq(Leveling.threshold(2), 100)
	assert_eq(Leveling.threshold(3), 225)
	assert_eq(Leveling.threshold(4), 382)
	assert_eq(Leveling.threshold(5), 578)
	assert_eq(Leveling.threshold(6), 823)
	for invalid in [0, -1, HeroCatalog.MAX_LEVEL + 1]:
		assert_eq(Leveling.threshold(invalid), -1)


func test_explicit_null_balancing_uses_authored_defaults() -> void:
	assert_eq(Leveling.validation_error(null), "")
	assert_eq(Leveling.award(101, 60, null), 85)
	assert_eq(Leveling.threshold(1, null), 0)
	assert_eq(Leveling.threshold(4, null), 382)
	assert_eq(Leveling.threshold(HeroCatalog.MAX_LEVEL, null), -1)
	assert_eq(Leveling.threshold(HeroCatalog.MAX_LEVEL + 1, null), -1)
	var hero := HeroData.new("defaults")
	assert_eq(Leveling.preview(hero, 382, null), {"xp": 382, "level": 4})
	assert_eq(hero.xp, 0)
	assert_eq(hero.level, 1)
	assert_true(Leveling.grant_xp(hero, 382, null))
	assert_eq(hero.xp, 382)
	assert_eq(hero.level, 4)
	assert_false(Leveling.grant_xp(hero, -1, null))
	assert_eq(hero.xp, 382)
	assert_eq(hero.level, 4)


func test_preview_is_pure_and_grant_processes_multiple_levels_without_rerolling() -> void:
	var hero := HeroGenerator.generate_hero("leveling", 42, HeroCatalog.classes(), HeroCatalog.traits())
	var attributes := hero.attributes.duplicate(true)
	var traits := hero.traits.duplicate()
	var stats := HeroStats.compute_derived_stats(hero)
	var growth := hero.hero_class.per_level_growth.duplicate(true)
	assert_eq(Leveling.preview(hero, 381), {"xp": 381, "level": 3})
	assert_eq(hero.level, 1)
	assert_eq(hero.xp, 0)
	assert_true(Leveling.grant_xp(hero, 382))
	assert_eq(hero.xp, 382)
	assert_eq(hero.level, 4)
	assert_eq(hero.attributes, attributes)
	assert_eq(hero.traits, traits)
	assert_eq(hero.hero_class.per_level_growth, growth)
	assert_ne(HeroStats.compute_derived_stats(hero), stats)
	assert_true(Leveling.grant_xp(hero, 0))
	assert_eq(hero.level, 4)
	assert_true(Leveling.grant_xp(hero, 196))
	assert_eq(hero.level, 5)
	assert_eq(hero.xp, 578)


func test_legacy_levels_are_not_downgraded_and_max_level_keeps_xp() -> void:
	var hero := HeroData.new("legacy")
	hero.level = 100
	assert_eq(Leveling.preview(hero, 1), {"xp": 1, "level": 100})
	hero.level = HeroCatalog.MAX_LEVEL
	assert_true(Leveling.grant_xp(hero, HeroCatalog.MAX_SAFE_INT))
	assert_eq(hero.level, HeroCatalog.MAX_LEVEL)
	assert_eq(hero.xp, HeroCatalog.MAX_SAFE_INT)
	assert_false(Leveling.grant_xp(hero, 1))
	assert_eq(hero.xp, HeroCatalog.MAX_SAFE_INT)


func test_invalid_awards_previews_and_grants_do_not_mutate() -> void:
	var hero := HeroData.new("invalid")
	for amount in [-1, HeroCatalog.MAX_SAFE_INT + 1]:
		assert_true(Leveling.preview(hero, amount).has("error"))
		assert_false(Leveling.grant_xp(hero, amount))
		assert_eq(hero.level, 1)
		assert_eq(hero.xp, 0)
	assert_true(Leveling.preview(null, 1).has("error"))
	assert_false(Leveling.grant_xp(null, 1))
	for level in [0, HeroCatalog.MAX_LEVEL + 1]:
		hero.level = level
		assert_false(Leveling.grant_xp(hero, 1))
		assert_eq(hero.level, level)
	hero.level = 1
	for xp in [-1, HeroCatalog.MAX_SAFE_INT + 1]:
		hero.xp = xp
		assert_false(Leveling.grant_xp(hero, 0))
		assert_eq(hero.xp, xp)
	assert_eq(Leveling.award(-1, 60), -1)
	assert_eq(Leveling.award(1, 0), -1)
	assert_eq(Leveling.award(1, -1), -1)
	assert_eq(Leveling.award(HeroCatalog.MAX_SAFE_INT + 1, 1), -1)
	assert_eq(Leveling.award(HeroCatalog.MAX_SAFE_INT, HeroCatalog.MAX_SAFE_INT), -1)


func test_balancing_rejects_bad_keys_values_and_recovery_bounds() -> void:
	assert_eq(Leveling.validation_error(null), "")
	assert_ne(Leveling.validation_error(BalancingConfig.new()), "")
	for field in ["xp_award_coefficients", "xp_threshold_curve"]:
		var tuning := _tuning()
		tuning.set(field, {})
		_assert_invalid_tuning(tuning, field == "xp_threshold_curve")
		tuning = _tuning()
		tuning.get(field)["extra"] = 1
		_assert_invalid_tuning(tuning, field == "xp_threshold_curve")
		for key in _tuning().get(field):
			for invalid in [NAN, INF, -INF, -1, "1", true, null, [], {}]:
				tuning = _tuning()
				tuning.get(field)[key] = invalid
				_assert_invalid_tuning(tuning, field == "xp_threshold_curve")
	for key in ["base", "growth_factor"]:
		var tuning := _tuning()
		tuning.xp_threshold_curve[key] = 0
		_assert_invalid_tuning(tuning, true)
	for seconds in [0, -1, HeroCatalog.MAX_SAFE_INT + 1]:
		var tuning := _tuning()
		tuning.base_recovery_seconds = seconds
		_assert_invalid_tuning(tuning)
	for percent in [-1, 101]:
		var tuning := _tuning()
		tuning.recovery_hp_percent = percent
		_assert_invalid_tuning(tuning)
	var zero := _tuning()
	zero.xp_award_coefficients = {"recommended_party_power": 0.0, "duration_seconds": 0.0}
	assert_eq(Leveling.award(100, 60, zero), 0)


func test_frozen_xp_preview_and_threshold_ignore_live_award_and_recovery_settings() -> void:
	var tuning := _tuning()
	tuning.xp_award_coefficients = {"unrelated_invalid_setting": NAN}
	tuning.base_recovery_seconds = -1
	tuning.recovery_hp_percent = 101
	assert_ne(Leveling.validation_error(tuning), "")
	assert_eq(Leveling.award(100, 60, tuning), -1)
	assert_eq(Leveling.threshold(1, tuning), 0)
	assert_eq(Leveling.threshold(4, tuning), 382)
	assert_eq(Leveling.threshold(HeroCatalog.MAX_LEVEL, tuning), -1)
	var hero := HeroData.new("frozen-award")
	assert_eq(Leveling.preview(hero, 382, tuning), {"xp": 382, "level": 4})
	assert_eq(hero.xp, 0)
	assert_eq(hero.level, 1)
	assert_true(Leveling.preview(hero, -1, tuning).has("error"))
	assert_true(Leveling.grant_xp(hero, 382, tuning))
	assert_eq(hero.xp, 382)
	assert_eq(hero.level, 4)
	tuning.xp_threshold_curve["growth_factor"] = NAN
	assert_eq(Leveling.threshold(4, tuning), -1)
	assert_true(Leveling.preview(hero, 1, tuning).has("error"))
	assert_false(Leveling.grant_xp(hero, 1, tuning))
	assert_eq(hero.xp, 382)
	assert_eq(hero.level, 4)


func test_constant_and_decreasing_curves_reach_max_level_without_underflow_or_long_scans() -> void:
	var tuning := _tuning()
	tuning.xp_threshold_curve = {"base": 1.1, "growth_factor": 1.0}
	assert_eq(Leveling.threshold(HeroCatalog.MAX_LEVEL, tuning), 1999998)
	var hero := HeroData.new()
	assert_eq(Leveling.preview(hero, 1999998, tuning), {"xp": 1999998, "level": HeroCatalog.MAX_LEVEL})
	tuning.xp_threshold_curve = {"base": 4, "growth_factor": 0.5}
	assert_eq(Leveling.threshold(5, tuning), 8)
	assert_eq(Leveling.threshold(HeroCatalog.MAX_LEVEL, tuning), 1000003)
	assert_eq(Leveling.preview(hero, 1000003, tuning)["level"], HeroCatalog.MAX_LEVEL)
	tuning.xp_threshold_curve = {"base": 0.5, "growth_factor": 0.00001}
	assert_eq(Leveling.threshold(HeroCatalog.MAX_LEVEL, tuning), 999999)
	tuning.xp_threshold_curve = {"base": 100, "growth_factor": 0.999999999999}
	assert_eq(Leveling.threshold(HeroCatalog.MAX_LEVEL, tuning), 99999900)


func test_unreachable_thresholds_stop_advancement_without_overflow() -> void:
	var tuning := _tuning()
	tuning.xp_threshold_curve = {"base": HeroCatalog.MAX_SAFE_INT, "growth_factor": 1.0}
	assert_eq(Leveling.threshold(2, tuning), HeroCatalog.MAX_SAFE_INT)
	assert_eq(Leveling.threshold(3, tuning), -1)
	assert_eq(Leveling.preview(HeroData.new(), HeroCatalog.MAX_SAFE_INT, tuning),
		{"xp": HeroCatalog.MAX_SAFE_INT, "level": 2})
	tuning.xp_threshold_curve = {"base": 100, "growth_factor": HeroCatalog.MAX_SAFE_INT}
	assert_eq(Leveling.threshold(HeroCatalog.MAX_LEVEL, tuning), -1)
	assert_eq(Leveling.threshold(2, tuning), 100)
	assert_eq(Leveling.preview(HeroData.new(), HeroCatalog.MAX_SAFE_INT, tuning)["level"], 2)
	assert_eq(Leveling.threshold(HeroCatalog.MAX_LEVEL), -1)
	var result := Leveling.preview(HeroData.new(), HeroCatalog.MAX_SAFE_INT)
	assert_gt(result["level"], 100)
	assert_lt(result["level"], 200)
	assert_eq(Leveling.threshold(result["level"] + 1), -1)


func test_cached_thresholds_match_direct_sums_and_refresh_after_tuning_mutation() -> void:
	var tuning := _tuning()
	for curve in [
		{"base": 2.25, "growth_factor": 1.01},
		{"base": 11, "growth_factor": 0.97},
		{"base": 3.5, "growth_factor": 1.0},
		{"base": 0.1, "growth_factor": 1.2},
	]:
		tuning.xp_threshold_curve = curve
		var total := 0
		for level in range(1, 101):
			assert_eq(Leveling.threshold(level, tuning), total)
			total += maxi(1, ceili(float(curve["base"]) * pow(float(curve["growth_factor"]), level - 1)))
		assert_eq(Leveling.threshold(2, tuning), ceili(float(curve["base"])))
	tuning.xp_threshold_curve["base"] = 999
	assert_eq(Leveling.threshold(2, tuning), 999)
	assert_eq(Leveling.threshold(2), 100)


func _tuning() -> BalancingConfig:
	return Leveling.DEFAULT_BALANCING.duplicate(true)


func _assert_invalid_tuning(tuning: BalancingConfig, invalid_curve: bool = false) -> void:
	assert_ne(Leveling.validation_error(tuning), "")
	assert_eq(Leveling.award(100, 60, tuning), -1)
	if invalid_curve:
		assert_eq(Leveling.threshold(2, tuning), -1)
		assert_true(Leveling.preview(HeroData.new(), 100, tuning).has("error"))
	else:
		assert_eq(Leveling.threshold(2, tuning), 100)
		assert_eq(Leveling.preview(HeroData.new(), 100, tuning), {"xp": 100, "level": 2})
