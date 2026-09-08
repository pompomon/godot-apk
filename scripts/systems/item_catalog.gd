class_name ItemCatalog
extends RefCounted
## Explicit equipment registry; shape validation also accepts detached fixtures.

const SHORT_SWORD = preload("res://data/items/short_sword.tres")
const HUNTING_BOW = preload("res://data/items/hunting_bow.tres")
const APPRENTICE_STAFF = preload("res://data/items/apprentice_staff.tres")
const LEATHER_ARMOR = preload("res://data/items/leather_armor.tres")
const CHAINMAIL = preload("res://data/items/chainmail.tres")
const ROBES = preload("res://data/items/robes.tres")


static func items() -> Array[ItemResource]:
	return [SHORT_SWORD, HUNTING_BOW, APPRENTICE_STAFF, LEATHER_ARMOR, CHAINMAIL, ROBES]


static func item_by_id(id: String) -> ItemResource:
	for item in items():
		if String(item.item_id) == id:
			return item
	return null


static func validate_item(item: ItemResource) -> bool:
	if item == null or String(item.item_id).strip_edges().is_empty():
		return false
	if item.display_name.strip_edges().is_empty() or item.slot not in ["Weapon", "Armor"]:
		return false
	if item.rarity not in [&"Common", &"Uncommon"]:
		return false
	for stat in item.stat_modifiers:
		if not HeroCatalog.is_content_key(stat, HeroCatalog.STATS):
			return false
		if not HeroCatalog.is_bounded_number(item.stat_modifiers[stat]):
			return false
	return true


static func validate_catalog() -> bool:
	var ids := {}
	for item in items():
		if not validate_item(item) or ids.has(item.item_id):
			return false
		ids[item.item_id] = true
	return not ids.is_empty()
