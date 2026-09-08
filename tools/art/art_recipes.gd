extends RefCounted
## Canonical authoring inputs. IDs, seeds and variant ordering are release-stable.

const PALETTE := preload("res://tools/art/art_palette.gd")
const VERSION := "busts-and-waypoints-1"
const CLASSES := ["knight", "ranger", "wizard", "cleric"]
const ICON_GROUPS := {
	"class": CLASSES,
	"status": ["idle", "assigned", "on_expedition", "resting", "wounded", "dead"],
	"item": ["short_sword", "hunting_bow", "apprentice_staff", "leather_armor", "chainmail", "robes"],
	"slot": ["weapon", "armor"],
	"journal": ["travel", "loot", "event", "combat"],
	"outcome": ["victory", "retreat", "defeat"],
	"utility": ["gold", "xp", "locked"],
}
const REGIONS := ["green_hollow", "ashen_reach", "frostbound_pass", "unknown"]
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
	for class_index in range(CLASSES.size()):
		for variant in range(8):
			result.append(_recipe("portrait", CLASSES[class_index], variant,
				1100 + class_index * 100 + variant, 64, 64, true,
				"portraits/%s_%02d.png" % [CLASSES[class_index], variant]))
	result.append(_recipe("portrait", "unknown", 0, 1900, 64, 64, true, "portraits/unknown.png"))
	var icon_seed := 2100
	for group: String in ICON_GROUPS:
		for subject: String in ICON_GROUPS[group]:
			var size := 32 if group == "item" else 24
			result.append(_recipe("icon", group + "_" + subject, 0, icon_seed,
				size, size, true, "icons/%s_%s.png" % [group, subject]))
			icon_seed += 1
	result.append(_recipe("icon", "unknown", 0, 2900, 24, 24, true, "icons/unknown.png"))
	for index in range(REGIONS.size()):
		result.append(_recipe("backdrop", REGIONS[index], 0, 3100 + index,
			320, 144, false, "backdrops/%s.png" % REGIONS[index]))
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
