class_name Leveling
extends RefCounted
## Cumulative XP calculations. Cached threshold runs depend only on curve values.

const DEFAULT_BALANCING = preload("res://data/balancing/default_balancing.tres")
const MAX_SAFE_INT = HeroCatalog.MAX_SAFE_INT
const MAX_LEVEL = HeroCatalog.MAX_LEVEL

static var _base: float = -1.0
static var _growth: float = -1.0
static var _ends := PackedInt64Array()
static var _totals := PackedInt64Array()
static var _costs := PackedInt64Array()
static var _unreachable: bool = false


static func validation_error(balancing: BalancingConfig = DEFAULT_BALANCING) -> String:
	if balancing == null:
		balancing = DEFAULT_BALANCING
	if not HeroCatalog.has_exact_keys(balancing.xp_award_coefficients,
			["recommended_party_power", "duration_seconds"]):
		return "Invalid XP award coefficients."
	for coefficient in balancing.xp_award_coefficients.values():
		if not HeroCatalog.is_bounded_number(coefficient, 0.0, MAX_SAFE_INT):
			return "Invalid XP award coefficient."
	var curve_error := _curve_validation_error(balancing)
	if not curve_error.is_empty():
		return curve_error
	if balancing.base_recovery_seconds <= 0 or balancing.base_recovery_seconds > MAX_SAFE_INT:
		return "Invalid recovery duration."
	if balancing.recovery_hp_percent < 0 or balancing.recovery_hp_percent > 100:
		return "Invalid recovery HP percentage."
	return ""


static func _curve_validation_error(balancing: BalancingConfig) -> String:
	if not HeroCatalog.has_exact_keys(balancing.xp_threshold_curve, ["base", "growth_factor"]):
		return "Invalid XP threshold curve."
	for value in balancing.xp_threshold_curve.values():
		if not HeroCatalog.is_bounded_number(value, 0.0, MAX_SAFE_INT) or float(value) <= 0.0:
			return "Invalid XP threshold value."
	return ""


static func award(recommended_power: int, duration_seconds: int,
		balancing: BalancingConfig = DEFAULT_BALANCING) -> int:
	if balancing == null:
		balancing = DEFAULT_BALANCING
	if not validation_error(balancing).is_empty():
		return -1
	if recommended_power < 0 or recommended_power > MAX_SAFE_INT:
		return -1
	if duration_seconds <= 0 or duration_seconds > MAX_SAFE_INT:
		return -1
	var coefficients := balancing.xp_award_coefficients
	var value: float = recommended_power * float(coefficients["recommended_party_power"]) \
		+ duration_seconds * float(coefficients["duration_seconds"])
	if not is_finite(value) or value > MAX_SAFE_INT:
		return -1
	return maxi(0, floori(value))


static func threshold(level: int, balancing: BalancingConfig = DEFAULT_BALANCING) -> int:
	if balancing == null:
		balancing = DEFAULT_BALANCING
	if level < 1 or level > MAX_LEVEL or not _curve_validation_error(balancing).is_empty():
		return -1
	_prepare_curve(balancing)
	return _threshold(level)


static func preview(hero: HeroData, amount: int,
		balancing: BalancingConfig = DEFAULT_BALANCING) -> Dictionary:
	if balancing == null:
		balancing = DEFAULT_BALANCING
	var error := _curve_validation_error(balancing)
	if not error.is_empty():
		return {"error": error}
	if hero == null or hero.level < 1 or hero.level > MAX_LEVEL:
		return {"error": "Invalid Hero level."}
	if hero.xp < 0 or hero.xp > MAX_SAFE_INT or amount < 0 or amount > MAX_SAFE_INT - hero.xp:
		return {"error": "Invalid or overflowing XP."}
	var xp := hero.xp + amount
	_prepare_curve(balancing)
	var low := hero.level
	var high := MAX_LEVEL
	while low < high:
		@warning_ignore("integer_division")
		var middle := low + (high - low + 1) / 2
		var required := _threshold(middle)
		if required >= 0 and required <= xp:
			low = middle
		else:
			high = middle - 1
	return {"xp": xp, "level": low}


static func grant_xp(hero: HeroData, amount: int,
		balancing: BalancingConfig = DEFAULT_BALANCING) -> bool:
	var result := preview(hero, amount, balancing)
	if result.has("error"):
		return false
	hero.xp = result["xp"]
	hero.level = result["level"]
	return true


static func _prepare_curve(balancing: BalancingConfig) -> void:
	var base: float = balancing.xp_threshold_curve["base"]
	var growth: float = balancing.xp_threshold_curve["growth_factor"]
	if base == _base and growth == _growth:
		return
	_base = base
	_growth = growth
	_ends.clear()
	_totals.clear()
	_costs.clear()
	_unreachable = false


static func _cost(exponent: int) -> int:
	var raw := _base * pow(_growth, exponent)
	if not is_finite(raw) or raw > MAX_SAFE_INT:
		return -1
	# Positive decreasing curves still cost one XP after floating-point underflow.
	return maxi(1, ceili(raw))


static func _threshold(level: int) -> int:
	var advances := level - 1
	if advances == 0:
		return 0
	var covered: int = 0 if _ends.is_empty() else _ends[-1]
	var total: int = 0 if _totals.is_empty() else _totals[-1]
	while covered < advances and not _unreachable:
		var cost := _cost(covered)
		if cost < 0:
			_unreachable = true
			break
		var end := covered + 1
		# Group equal rounded costs: constant/decaying curves never require a
		# million-step scan, and repeated UI previews reuse the numeric cache.
		if end < MAX_LEVEL - 1 and _cost(end) == cost:
			var low := end
			var high := MAX_LEVEL - 2
			while low < high:
				@warning_ignore("integer_division")
				var middle := low + (high - low + 1) / 2
				if _cost(middle) == cost:
					low = middle
				else:
					high = middle - 1
			end = low + 1
		@warning_ignore("integer_division")
		var affordable := (MAX_SAFE_INT - total) / cost
		if end - covered > affordable:
			end = covered + affordable
			_unreachable = true
		if end == covered:
			break
		total += (end - covered) * cost
		_ends.append(end)
		_totals.append(total)
		_costs.append(cost)
		covered = end
	if covered < advances:
		return -1
	var low := 0
	var high := _ends.size() - 1
	while low < high:
		@warning_ignore("integer_division")
		var middle := (low + high) / 2
		if _ends[middle] < advances:
			low = middle + 1
		else:
			high = middle
	return _totals[low] - (_ends[low] - advances) * _costs[low]
