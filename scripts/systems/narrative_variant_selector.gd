class_name NarrativeVariantSelector
extends RefCounted
## Deterministic prose selection detached from the gameplay RNG stream.
##
## Selection never consumes RandomNumberGenerator, global rand*() calls, an
## implementation-dependent object hash, or clock/device state. Callers must
## not let this selector change the number or order of gameplay RNG calls.

const VERSION := "narrative-v1"


## Selects the resolved text for one narrative field. [fallback] is always the
## first candidate; [variants] are appended in authored order. The result is
## always one of these candidates (fallback when [variants] is empty).
static func select(
		fallback: String, variants: Array[String], expedition_seed: int, region_id: String,
		step_index: int, content_id: String, outcome_id: String, field_id: String) -> String:
	var candidates := candidate_list(fallback, variants)
	if candidates.size() <= 1:
		return fallback
	var index := _digest_index(
			expedition_seed, region_id, step_index, content_id, outcome_id, field_id, candidates.size())
	return candidates[index]


## Selects travel text while avoiding an immediate repeat of [previous_text]
## when more than one candidate exists.
static func select_travel(
		fallback: String, variants: Array[String], expedition_seed: int, region_id: String,
		step_index: int, previous_text: String) -> String:
	var candidates := candidate_list(fallback, variants)
	if candidates.size() <= 1:
		return fallback
	var index := _digest_index(expedition_seed, region_id, step_index, "", "", "travel", candidates.size())
	for offset in range(candidates.size()):
		var candidate_index := (index + offset) % candidates.size()
		if candidates[candidate_index] != previous_text:
			return candidates[candidate_index]
	return candidates[index]


## Returns the ordered candidate pool: the fallback followed by the variants.
## Does not mutate [variants].
static func candidate_list(fallback: String, variants: Array[String]) -> Array[String]:
	var candidates: Array[String] = [fallback]
	candidates.append_array(variants)
	return candidates


static func _digest_index(
		expedition_seed: int, region_id: String, step_index: int, content_id: String,
		outcome_id: String, field_id: String, candidate_count: int) -> int:
	var key := "%s|%d|%s|%d|%s|%s|%s" % [
		VERSION, expedition_seed, region_id, step_index, content_id, outcome_id, field_id]
	var digest := key.sha256_text()
	# First 8 hex chars as an unsigned magnitude; well within 64-bit range.
	return digest.substr(0, 8).hex_to_int() % candidate_count
