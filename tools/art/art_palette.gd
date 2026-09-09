extends RefCounted
## Shared opaque ramps; transparent pixels are always zero RGBA.

const VERSION := "march-dusk-1"
const HEX := {
	"ink": "172333", "navy": "25364a", "slate": "40546a", "steel": "708799",
	"silver": "a9b9be", "cream": "eee4c9", "white": "faf3df",
	"gold_dark": "856037", "gold": "bc914b", "gold_light": "e0b96b",
	"skin_light_shadow": "a56b56", "skin_light": "d49a75", "skin_light_hi": "edbc91",
	"skin_warm_shadow": "815344", "skin_warm": "b97a55", "skin_warm_hi": "dca270",
	"skin_deep_shadow": "533e3b", "skin_deep": "805743", "skin_deep_hi": "ac7957",
	"hair_dark": "302e35", "hair_brown": "584238", "hair_brown_hi": "856043",
	"rust": "94563c", "copper": "c07b48", "sand": "d1a46e",
	"pine": "263f3e", "moss_dark": "36554a", "moss": "54745a", "leaf": "82946a",
	"mist": "b9c5a8", "teal_dark": "345b62", "teal": "54818a", "ice": "91b4b5",
	"ice_light": "c6d8ce", "purple_dark": "423b5a", "purple": "68577b",
	"lavender": "9b87a4", "red_dark": "683f43", "red": "a15b50",
	"earth": "645349", "earth_light": "91816a",
}

const SKIN := [
	["skin_warm_shadow", "skin_warm", "skin_warm_hi"],
	["skin_deep_shadow", "skin_deep", "skin_deep_hi"],
	["skin_light_shadow", "skin_light", "skin_light_hi"],
]
const HAIR := [
	["hair_dark", "hair_brown", "hair_brown_hi"],
	["hair_dark", "hair_dark", "slate"],
	["hair_brown", "rust", "copper"],
	["earth", "silver", "cream"],
	["hair_brown", "gold", "gold_light"],
]


static func color(key: String) -> Color:
	return Color("#" + HEX[key])


static func contains_rgba(value: Color) -> bool:
	if value == Color(0, 0, 0, 0):
		return true
	for hex: String in HEX.values():
		if value.to_rgba32() == Color("#" + hex).to_rgba32():
			return true
	return false
