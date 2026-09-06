class_name PartyData
extends RefCounted
## Formation mapping only. Copies share canonical Heroes, not mutable slot dictionaries.

enum FormationSlot { FRONT_LEFT, FRONT_RIGHT, BACK_LEFT, BACK_RIGHT }

const SLOT_ORDER := [
	FormationSlot.FRONT_LEFT, FormationSlot.FRONT_RIGHT,
	FormationSlot.BACK_LEFT, FormationSlot.BACK_RIGHT,
]
const SLOT_NAMES := ["FRONT_LEFT", "FRONT_RIGHT", "BACK_LEFT", "BACK_RIGHT"]
const SLOT_LABELS := ["Front left", "Front right", "Back left", "Back right"]

var slots: Dictionary = {
	FormationSlot.FRONT_LEFT: null, FormationSlot.FRONT_RIGHT: null,
	FormationSlot.BACK_LEFT: null, FormationSlot.BACK_RIGHT: null,
}


func validation_error(require_members: bool = false) -> String:
	if slots.size() != SLOT_ORDER.size():
		return "A formation must have exactly four named slots."
	for slot in slots:
		if not slot is int or slot not in SLOT_ORDER:
			return "Unknown formation slot."
	var ids := {}
	for slot in SLOT_ORDER:
		var hero: Variant = slots[slot]
		if hero == null:
			continue
		if not hero is HeroData or hero.hero_id.strip_edges().is_empty():
			return "Every member must be a Hero with a stable ID."
		if ids.has(hero.hero_id):
			return "A Hero may occupy only one formation slot."
		ids[hero.hero_id] = true
	if require_members and ids.is_empty():
		return "Choose at least one Hero before confirming."
	return ""


func heroes() -> Array[HeroData]:
	var result: Array[HeroData] = []
	for slot in SLOT_ORDER:
		var hero: Variant = slots.get(slot)
		if hero is HeroData:
			result.append(hero)
	return result


func has_front_row_hero() -> bool:
	return (slots.get(FormationSlot.FRONT_LEFT) is HeroData
		or slots.get(FormationSlot.FRONT_RIGHT) is HeroData)


func contains_id(hero_id: String) -> bool:
	for hero in heroes():
		if hero.hero_id == hero_id:
			return true
	return false


func place_hero(slot: int, hero: HeroData) -> bool:
	if not validation_error().is_empty() or slot not in SLOT_ORDER:
		return false
	if hero == null or hero.hero_id.strip_edges().is_empty():
		return false
	if slots[slot] != null or contains_id(hero.hero_id):
		return false
	slots[slot] = hero
	return true


func remove_hero(slot: int) -> bool:
	if not validation_error().is_empty() or slot not in SLOT_ORDER or slots[slot] == null:
		return false
	slots[slot] = null
	return true


func move_hero(from_slot: int, to_slot: int) -> bool:
	if not validation_error().is_empty() or from_slot not in SLOT_ORDER or to_slot not in SLOT_ORDER:
		return false
	if slots[from_slot] == null or slots[to_slot] != null:
		return false
	slots[to_slot] = slots[from_slot]
	slots[from_slot] = null
	return true


func copy() -> PartyData:
	var result := PartyData.new()
	result.slots = slots.duplicate()
	return result
