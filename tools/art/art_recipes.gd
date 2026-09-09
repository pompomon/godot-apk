extends RefCounted
## Canonical authoring inputs. IDs, seeds and variant ordering are release-stable.

const PALETTE := preload("res://tools/art/art_palette.gd")
const VERSION := "busts-and-waypoints-1"
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
