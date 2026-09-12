extends RefCounted
## Presentation-only allowlist. No saved ID is ever interpreted as a resource path.

const UNKNOWN_PORTRAIT = preload("res://assets/art/portraits/unknown.png")
const UNKNOWN_ICON = preload("res://assets/art/icons/unknown.png")
const UNKNOWN_REGION = preload("res://assets/art/backdrops/unknown.png")
const UNKNOWN_ENCOUNTER = preload("res://assets/art/encounters/unknown.png")
const PORTRAITS := {
	"knight": [
		preload("res://assets/art/portraits/knight_00.png"),
		preload("res://assets/art/portraits/knight_01.png"),
		preload("res://assets/art/portraits/knight_02.png"),
		preload("res://assets/art/portraits/knight_03.png"),
		preload("res://assets/art/portraits/knight_04.png"),
		preload("res://assets/art/portraits/knight_05.png"),
		preload("res://assets/art/portraits/knight_06.png"),
		preload("res://assets/art/portraits/knight_07.png"),
	],
	"ranger": [
		preload("res://assets/art/portraits/ranger_00.png"),
		preload("res://assets/art/portraits/ranger_01.png"),
		preload("res://assets/art/portraits/ranger_02.png"),
		preload("res://assets/art/portraits/ranger_03.png"),
		preload("res://assets/art/portraits/ranger_04.png"),
		preload("res://assets/art/portraits/ranger_05.png"),
		preload("res://assets/art/portraits/ranger_06.png"),
		preload("res://assets/art/portraits/ranger_07.png"),
	],
	"wizard": [
		preload("res://assets/art/portraits/wizard_00.png"),
		preload("res://assets/art/portraits/wizard_01.png"),
		preload("res://assets/art/portraits/wizard_02.png"),
		preload("res://assets/art/portraits/wizard_03.png"),
		preload("res://assets/art/portraits/wizard_04.png"),
		preload("res://assets/art/portraits/wizard_05.png"),
		preload("res://assets/art/portraits/wizard_06.png"),
		preload("res://assets/art/portraits/wizard_07.png"),
	],
	"cleric": [
		preload("res://assets/art/portraits/cleric_00.png"),
		preload("res://assets/art/portraits/cleric_01.png"),
		preload("res://assets/art/portraits/cleric_02.png"),
		preload("res://assets/art/portraits/cleric_03.png"),
		preload("res://assets/art/portraits/cleric_04.png"),
		preload("res://assets/art/portraits/cleric_05.png"),
		preload("res://assets/art/portraits/cleric_06.png"),
		preload("res://assets/art/portraits/cleric_07.png"),
	],
}
const CLASSES := {
	"knight": preload("res://assets/art/icons/class_knight.png"),
	"ranger": preload("res://assets/art/icons/class_ranger.png"),
	"wizard": preload("res://assets/art/icons/class_wizard.png"),
	"cleric": preload("res://assets/art/icons/class_cleric.png"),
}
const STATUSES := {
	HeroData.HeroStatus.IDLE: preload("res://assets/art/icons/status_idle.png"),
	HeroData.HeroStatus.ASSIGNED: preload("res://assets/art/icons/status_assigned.png"),
	HeroData.HeroStatus.ON_EXPEDITION: preload("res://assets/art/icons/status_on_expedition.png"),
	HeroData.HeroStatus.RESTING: preload("res://assets/art/icons/status_resting.png"),
	HeroData.HeroStatus.WOUNDED: preload("res://assets/art/icons/status_wounded.png"),
	HeroData.HeroStatus.DEAD: preload("res://assets/art/icons/status_dead.png"),
}
const ITEMS := {
	"short_sword": preload("res://assets/art/icons/item_short_sword.png"),
	"hunting_bow": preload("res://assets/art/icons/item_hunting_bow.png"),
	"apprentice_staff": preload("res://assets/art/icons/item_apprentice_staff.png"),
	"leather_armor": preload("res://assets/art/icons/item_leather_armor.png"),
	"chainmail": preload("res://assets/art/icons/item_chainmail.png"),
	"robes": preload("res://assets/art/icons/item_robes.png"),
}
const SLOTS := {
	"Weapon": preload("res://assets/art/icons/slot_weapon.png"),
	"Armor": preload("res://assets/art/icons/slot_armor.png"),
}
const REGIONS := {
	"green_hollow": preload("res://assets/art/backdrops/green_hollow.png"),
	"ashen_reach": preload("res://assets/art/backdrops/ashen_reach.png"),
	"frostbound_pass": preload("res://assets/art/backdrops/frostbound_pass.png"),
}
const JOURNAL := {
	ExpeditionStep.StepKind.TRAVEL: preload("res://assets/art/icons/journal_travel.png"),
	ExpeditionStep.StepKind.LOOT: preload("res://assets/art/icons/journal_loot.png"),
	ExpeditionStep.StepKind.EVENT: preload("res://assets/art/icons/journal_event.png"),
	ExpeditionStep.StepKind.COMBAT: preload("res://assets/art/icons/journal_combat.png"),
}
const OUTCOMES := {
	"VICTORY": preload("res://assets/art/icons/outcome_victory.png"),
	"RETREAT": preload("res://assets/art/icons/outcome_retreat.png"),
	"DEFEAT": preload("res://assets/art/icons/outcome_defeat.png"),
}
const UTILITIES := {
	"gold": preload("res://assets/art/icons/utility_gold.png"),
	"xp": preload("res://assets/art/icons/utility_xp.png"),
	"locked": preload("res://assets/art/icons/utility_locked.png"),
}
const ENEMIES := {
	"bandit_skirmishers": preload("res://assets/art/encounters/enemy_bandit_skirmishers.png"),
	"forest_wolves": preload("res://assets/art/encounters/enemy_forest_wolves.png"),
	"ashen_raiders": preload("res://assets/art/encounters/enemy_ashen_raiders.png"),
	"ashen_jackals": preload("res://assets/art/encounters/enemy_ashen_jackals.png"),
	"frostbound_sentinels": preload("res://assets/art/encounters/enemy_frostbound_sentinels.png"),
	"frostbound_prowlers": preload("res://assets/art/encounters/enemy_frostbound_prowlers.png"),
}
const EVENTS := {
	"green_hollow_bridge": preload("res://assets/art/encounters/event_green_hollow_bridge.png"),
	"green_hollow_spring": preload("res://assets/art/encounters/event_green_hollow_spring.png"),
	"green_hollow_caravan": preload("res://assets/art/encounters/event_green_hollow_caravan.png"),
	"green_hollow_fireflies": preload("res://assets/art/encounters/event_green_hollow_fireflies.png"),
	"green_hollow_ruins": preload("res://assets/art/encounters/event_green_hollow_ruins.png"),
	"ashen_cistern": preload("res://assets/art/encounters/event_ashen_cistern.png"),
	"ashen_kiln": preload("res://assets/art/encounters/event_ashen_kiln.png"),
	"ashen_obelisk": preload("res://assets/art/encounters/event_ashen_obelisk.png"),
	"ashen_glass": preload("res://assets/art/encounters/event_ashen_glass.png"),
	"ashen_pilgrims": preload("res://assets/art/encounters/event_ashen_pilgrims.png"),
	"frostbound_bells": preload("res://assets/art/encounters/event_frostbound_bells.png"),
	"frostbound_crevasse": preload("res://assets/art/encounters/event_frostbound_crevasse.png"),
	"frostbound_shelter": preload("res://assets/art/encounters/event_frostbound_shelter.png"),
	"frostbound_aurora": preload("res://assets/art/encounters/event_frostbound_aurora.png"),
	"frostbound_sled": preload("res://assets/art/encounters/event_frostbound_sled.png"),
}
const DECORATIONS := {
	"home_crest": preload("res://assets/art/decorations/home_crest.png"),
	"section_divider": preload("res://assets/art/decorations/section_divider.png"),
	"formation_emblem": preload("res://assets/art/decorations/formation_emblem.png"),
}


static func portrait(hero_id: String, class_id: String) -> Texture2D:
	if hero_id.is_empty() or not PORTRAITS.has(class_id):
		return UNKNOWN_PORTRAIT
	# v1 identity is permanent: never use bank.size(), String.hash(), or gameplay RNG.
	var digest := ("portrait-v1|%s|%s" % [class_id, hero_id]).sha256_text()
	var variant := digest.substr(0, 2).hex_to_int() % 8
	return PORTRAITS[class_id][variant]


static func class_icon(class_id: String) -> Texture2D:
	return CLASSES.get(class_id, UNKNOWN_ICON)


static func status_icon(status: int) -> Texture2D:
	return STATUSES.get(status, UNKNOWN_ICON)


static func item_icon(item_id: String) -> Texture2D:
	return ITEMS.get(item_id, UNKNOWN_ICON)


static func equipment_icon(item: ItemResource, slot: String) -> Texture2D:
	return item_icon(String(item.item_id)) if item != null else SLOTS.get(slot, UNKNOWN_ICON)


static func region(region_id: String) -> Texture2D:
	return REGIONS.get(region_id, UNKNOWN_REGION)


static func journal_icon(kind: int) -> Texture2D:
	return JOURNAL.get(kind, UNKNOWN_ICON)


static func outcome_icon(outcome: String) -> Texture2D:
	return OUTCOMES.get(outcome, UNKNOWN_ICON)


static func utility_icon(kind: String) -> Texture2D:
	return UTILITIES.get(kind, UNKNOWN_ICON)


static func enemy(group_id: String) -> Texture2D:
	return ENEMIES.get(group_id, UNKNOWN_ENCOUNTER)


static func event(event_id: String) -> Texture2D:
	return EVENTS.get(event_id, UNKNOWN_ENCOUNTER)


static func decoration(decoration_id: String) -> Texture2D:
	return DECORATIONS.get(decoration_id, UNKNOWN_ICON)
