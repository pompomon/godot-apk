extends RefCounted
## Canonical authoring inputs. IDs, seeds and variant ordering are release-stable.

const PALETTE := preload("res://tools/art/art_palette.gd")
const VERSION := "busts-waypoints-and-tales-2"
const CLASSES := ["knight", "ranger", "wizard", "cleric"]
const PORTRAIT_SEEDS := {
	"knight": 1100, "ranger": 1200, "wizard": 1300, "cleric": 1400,
}
const ICON_GROUPS := {
	"class": CLASSES,
	"status": ["idle", "assigned", "on_expedition", "resting", "wounded", "dead"],
	"item": ["short_sword", "hunting_bow", "apprentice_staff", "leather_armor", "chainmail", "robes"],
	"slot": ["weapon", "armor"],
	"journal": ["travel", "loot", "event", "combat"],
	"outcome": ["victory", "retreat", "defeat"],
	"utility": ["gold", "xp", "locked"],
}
const ICON_SEEDS := {
	"class_knight": 2100, "class_ranger": 2101, "class_wizard": 2102, "class_cleric": 2103,
	"status_idle": 2104, "status_assigned": 2105, "status_on_expedition": 2106,
	"status_resting": 2107, "status_wounded": 2108, "status_dead": 2109,
	"item_short_sword": 2110, "item_hunting_bow": 2111, "item_apprentice_staff": 2112,
	"item_leather_armor": 2113, "item_chainmail": 2114, "item_robes": 2115,
	"slot_weapon": 2116, "slot_armor": 2117,
	"journal_travel": 2118, "journal_loot": 2119, "journal_event": 2120, "journal_combat": 2121,
	"outcome_victory": 2122, "outcome_retreat": 2123, "outcome_defeat": 2124,
	"utility_gold": 2125, "utility_xp": 2126, "utility_locked": 2127,
}
const REGIONS := ["green_hollow", "ashen_reach", "frostbound_pass", "unknown"]
const BACKDROP_SEEDS := {
	"green_hollow": 3100, "ashen_reach": 3101, "frostbound_pass": 3102, "unknown": 3103,
}
const ENEMIES := [
	"bandit_skirmishers", "forest_wolves", "ashen_raiders", "ashen_jackals",
	"frostbound_sentinels", "frostbound_prowlers",
]
const EVENTS := [
	"green_hollow_bridge", "green_hollow_spring", "green_hollow_caravan",
	"green_hollow_fireflies", "green_hollow_ruins", "ashen_cistern", "ashen_kiln",
	"ashen_obelisk", "ashen_glass", "ashen_pilgrims", "frostbound_bells",
	"frostbound_crevasse", "frostbound_shelter", "frostbound_aurora", "frostbound_sled",
]
const ENCOUNTER_SEEDS := {
	"enemy_bandit_skirmishers": 4100, "enemy_forest_wolves": 4101,
	"enemy_ashen_raiders": 4102, "enemy_ashen_jackals": 4103,
	"enemy_frostbound_sentinels": 4104, "enemy_frostbound_prowlers": 4105,
	"event_green_hollow_bridge": 4200, "event_green_hollow_spring": 4201,
	"event_green_hollow_caravan": 4202, "event_green_hollow_fireflies": 4203,
	"event_green_hollow_ruins": 4204, "event_ashen_cistern": 4205,
	"event_ashen_kiln": 4206, "event_ashen_obelisk": 4207,
	"event_ashen_glass": 4208, "event_ashen_pilgrims": 4209,
	"event_frostbound_bells": 4210, "event_frostbound_crevasse": 4211,
	"event_frostbound_shelter": 4212, "event_frostbound_aurora": 4213,
	"event_frostbound_sled": 4214, "unknown": 4900,
}
const DECORATION_SEEDS := {
	"home_crest": 5100, "section_divider": 5101, "formation_emblem": 5102,
}
const FACES := [
	{"skin": 0, "hair": 0, "cut": "short", "beard": false, "wide": false},
	{"skin": 1, "hair": 1, "cut": "coils", "beard": false, "wide": true},
	{"skin": 2, "hair": 2, "cut": "bob", "beard": false, "wide": false},
	{"skin": 0, "hair": 1, "cut": "braid", "beard": false, "wide": false},
	{"skin": 2, "hair": 3, "cut": "short", "beard": true, "wide": true},
	{"skin": 1, "hair": 4, "cut": "swept", "beard": false, "wide": false},
	{"skin": 0, "hair": 2, "cut": "short", "beard": true, "wide": true},
	{"skin": 2, "hair": 0, "cut": "braid", "beard": false, "wide": true},
]
const HEADWEAR := {
	"knight": ["helmet", "none", "circlet", "helmet", "none", "circlet", "helmet", "none"],
	"ranger": ["hood", "none", "hood", "none", "hood", "none", "none", "hood"],
	"wizard": ["hat", "circlet", "hat", "none", "hat", "circlet", "none", "hat"],
	"cleric": ["circlet", "hood", "none", "circlet", "hood", "none", "circlet", "hood"],
}


static func all() -> Array:
	var result: Array = []
	for class_id: String in CLASSES:
		for variant in range(8):
			result.append(_recipe("portrait", class_id, variant,
				PORTRAIT_SEEDS[class_id] + variant, 64, 64, true,
				"portraits/%s_%02d.png" % [class_id, variant]))
	result.append(_recipe("portrait", "unknown", 0, 1900, 64, 64, true, "portraits/unknown.png"))
	for group: String in ICON_GROUPS:
		for subject: String in ICON_GROUPS[group]:
			var size := 32 if group == "item" else 24
			var icon_id := group + "_" + subject
			result.append(_recipe("icon", icon_id, 0, ICON_SEEDS[icon_id],
				size, size, true, "icons/%s_%s.png" % [group, subject]))
	result.append(_recipe("icon", "unknown", 0, 2900, 24, 24, true, "icons/unknown.png"))
	for region: String in REGIONS:
		result.append(_recipe("backdrop", region, 0, BACKDROP_SEEDS[region],
			320, 144, false, "backdrops/%s.png" % region))
	for enemy: String in ENEMIES:
		var subject := "enemy_" + enemy
		result.append(_recipe("encounter", subject, 0, ENCOUNTER_SEEDS[subject],
			64, 64, true, "encounters/%s.png" % subject))
	for event: String in EVENTS:
		var subject := "event_" + event
		result.append(_recipe("encounter", subject, 0, ENCOUNTER_SEEDS[subject],
			64, 64, true, "encounters/%s.png" % subject))
	result.append(_recipe("encounter", "unknown", 0, ENCOUNTER_SEEDS.unknown,
		64, 64, true, "encounters/unknown.png"))
	result.append(_recipe("decoration", "home_crest", 0, DECORATION_SEEDS.home_crest,
		96, 96, true, "decorations/home_crest.png"))
	result.append(_recipe("decoration", "section_divider", 0, DECORATION_SEEDS.section_divider,
		320, 16, true, "decorations/section_divider.png"))
	result.append(_recipe("decoration", "formation_emblem", 0, DECORATION_SEEDS.formation_emblem,
		64, 64, true, "decorations/formation_emblem.png"))
	return result


static func _recipe(kind: String, subject: String, variant: int, seed_value: int,
		width: int, height: int, transparent: bool, suffix: String) -> Dictionary:
	return {
		"id": "%s.%s.%02d" % [kind, subject, variant],
		"kind": kind, "subject": subject, "variant": variant, "seed": seed_value,
		"width": width, "height": height, "transparent": transparent,
		"path": "assets/art/" + suffix,
		"recipe_version": VERSION, "palette_version": PALETTE.VERSION,
	}


static func validate_recipe(recipe: Dictionary) -> String:
	var canonical: Dictionary = {}
	for candidate: Dictionary in all():
		if candidate.id == recipe.get("id"):
			canonical = candidate
			break
	if canonical.is_empty():
		return "Unknown asset ID."
	if recipe.size() != canonical.size():
		return "Recipe keys do not match the pinned schema."
	for key: String in canonical:
		if not recipe.has(key) or typeof(recipe[key]) != typeof(canonical[key]):
			return "Missing or mistyped recipe field: %s." % key
		if recipe[key] != canonical[key]:
			return "Recipe field differs from the pinned contract: %s." % key
	return ""


static func validate(recipes: Array) -> String:
	if recipes.is_empty():
		return "No recipes."
	var ids := {}
	var paths := {}
	for recipe: Variant in recipes:
		if not recipe is Dictionary:
			return "Recipe must be a Dictionary."
		var error := validate_recipe(recipe)
		if not error.is_empty():
			return error
		if ids.has(recipe.id) or paths.has(recipe.path):
			return "Duplicate asset ID or destination."
		ids[recipe.id] = true
		paths[recipe.path] = true
	return ""
