class_name EquipmentService
extends RefCounted
## A scene-local equipment draft; only confirmation mutates company ownership.

var hero: HeroData
var weapon: ItemResource
var armor: ItemResource
var last_error: String = ""
var _original_weapon: ItemResource
var _original_armor: ItemResource


func _init(selected: HeroData = null) -> void:
	hero = selected
	if hero != null:
		weapon = hero.equipped_weapon
		armor = hero.equipped_armor
		_original_weapon = weapon
		_original_armor = armor


func validation_error() -> String:
	if not GameState.initialized or hero == null or GameState.find_hero(hero.hero_id) != hero:
		return "This Hero is no longer available. Return to the roster."
	if hero.status not in [HeroData.HeroStatus.IDLE, HeroData.HeroStatus.ASSIGNED, HeroData.HeroStatus.RESTING]:
		return "Equipment cannot be changed while this Hero is %s." % hero.status_label()
	if hero.equipped_weapon != _original_weapon or hero.equipped_armor != _original_armor:
		return "Equipment changed since this screen opened. Return to Hero Detail and retry."
	for pair in [[weapon, "Weapon"], [armor, "Armor"]]:
		var item: ItemResource = pair[0]
		if item != null and (not ItemCatalog.validate_item(item) or item.slot != pair[1]
				or ItemCatalog.item_by_id(String(item.item_id)) != item):
			return "Choose a valid item for this equipment slot."
		if item != null and not available_items(pair[1]).has(item):
			return "The selected item is no longer in inventory. Choose another item."
	return ""


func available_items(slot: String) -> Array[ItemResource]:
	var result: Array[ItemResource] = []
	for item in GameState.inventory:
		if item is ItemResource and item.slot == slot:
			result.append(item)
	for item in [_original_weapon, _original_armor]:
		if item != null and item.slot == slot:
			result.append(item)
	return result


func preview_stats() -> Dictionary:
	if not validation_error().is_empty():
		return {}
	var detached := HeroData.new(hero.hero_id)
	detached.hero_class = hero.hero_class
	detached.level = hero.level
	detached.xp = hero.xp
	detached.attributes = hero.attributes.duplicate()
	detached.traits.assign(hero.traits)
	detached.equipped_weapon = weapon
	detached.equipped_armor = armor
	return HeroStats.compute_derived_stats(detached)


func confirm() -> bool:
	last_error = validation_error()
	if not last_error.is_empty():
		return false
	if not SaveManager.validate_snapshot(SaveManager.capture_state()) or preview_stats().is_empty():
		last_error = "Company data is invalid. Reload before changing equipment."
		return false
	if weapon == _original_weapon and armor == _original_armor:
		return true
	var inventory: Array[ItemResource] = []
	inventory.assign(GameState.inventory)
	for item in [_original_weapon, _original_armor]:
		if item != null:
			inventory.append(item)
	for item in [weapon, armor]:
		if item != null:
			var index := inventory.find(item)
			if index < 0:
				last_error = "An item is no longer available. Choose again."
				return false
			inventory.remove_at(index)
	var before := GameState.checkpoint()
	GameState.inventory.assign(inventory)
	hero.equipped_weapon = weapon
	hero.equipped_armor = armor
	SaveManager.save()
	if not SaveManager.last_committed:
		GameState.restore_checkpoint(before)
		last_error = "Equipment was not saved; inventory and equipped items are unchanged. Retry. " + SaveManager.last_error
		return false
	_original_weapon = weapon
	_original_armor = armor
	return true
