extends RefCounted
## Tiny authored bitmap lettering avoids fonts, GPU drawing and platform differences.

const CANVAS := preload("res://tools/art/pixel_canvas.gd")
const RECIPES := preload("res://tools/art/art_recipes.gd")
const PALETTE := preload("res://tools/art/art_palette.gd")
const GLYPHS := {
	"A": "010101111101101", "B": "110101110101110", "C": "011100100100011",
	"D": "110101101101110", "E": "111100110100111", "F": "111100110100100",
	"G": "011100101101011", "H": "101101111101101", "I": "111010010010111",
	"J": "001001001101010", "K": "101101110101101", "L": "100100100100111",
	"M": "101111111101101", "N": "101111111111101", "O": "010101101101010",
	"P": "110101110100100", "Q": "010101101111011", "R": "110101110101101",
	"S": "011100010001110", "T": "111010010010010", "U": "101101101101111",
	"V": "101101101101010", "W": "101101111111101", "X": "101101010101101",
	"Y": "101101010010010", "Z": "111001010100111",
	"0": "111101101101111", "1": "010110010010111", "2": "110001010100111",
	"3": "110001010001110", "4": "101101111001001", "5": "111100110001110",
	"6": "011100111101111", "7": "111001010010010", "8": "111101111101111",
	"9": "111101111001110", "-": "000000111000000", ".": "000000000000010",
}


static func representative(images: Dictionary) -> Image:
	var c := CANVAS.new(1024, 1568, "navy")
	_text(c, 16, 14, "ADVENTURERS MARCH - PIXEL BANK V1", 3)
	_text(c, 16, 40, "NATIVE AND 2X - NEAREST PIXELS - SHARED PALETTE", 2)
	for index in range(4):
		var subject: String = RECIPES.CLASSES[index]
		var x := 16 + index * 252
		_text(c, x, 68, subject.to_upper(), 2)
		_tile(c, images["portrait.%s.00" % subject], x, 90, 1)
		_tile(c, images["portrait.%s.00" % subject], x + 78, 90, 2)
		_text(c, x, 226, "64", 1)
		_text(c, x + 78, 226, "128", 1)
	var subjects := ["class_knight", "class_ranger", "class_wizard", "class_cleric",
		"status_wounded", "status_resting", "utility_gold", "outcome_victory",
		"journal_travel", "utility_locked", "item_short_sword", "item_chainmail"]
	for index in range(subjects.size()):
		var x := 16 + (index % 6) * 168
		var y := 254 + (index / 6) * 96
		var image: Image = images["icon.%s.00" % subjects[index]]
		_tile(c, image, x, y, 1)
		_tile(c, image, x + 40, y, 2)
		_text(c, x, y + 70, subjects[index].replace("_", " ").to_upper(), 1)
	_text(c, 16, 451, "41 OPAQUE COLORS PLUS TRANSPARENCY", 2)
	var index := 0
	for key: String in PALETTE.HEX:
		var x := 16 + (index % 21) * 47
		var y := 472 + (index / 21) * 32
		c.rect(x, y, 39, 16, key)
		_text(c, x, y + 20, PALETTE.HEX[key].to_upper(), 1)
		index += 1
	for region_index in range(3):
		var region: String = RECIPES.REGIONS[region_index]
		var y := 556 + region_index * 336
		_text(c, 16, y, region.replace("_", " ").to_upper(), 2)
		_text(c, 16, y + 19, "320 X 144", 1)
		_text(c, 352, y + 19, "640 X 288", 1)
		var image: Image = images["backdrop.%s.00" % region]
		_tile(c, image, 16, y + 32, 1)
		# Displaying 2x in a dedicated fixed-size row preserves the original grid.
		_tile(c, image, 352, y + 32, 2)
	return c.image


static func variants(images: Dictionary) -> Image:
	var c := CANVAS.new(1168, 672, "navy")
	_text(c, 16, 14, "RELEASE-STABLE PORTRAIT VARIANTS 00-07 AT 2X", 2)
	for class_index in range(4):
		var subject: String = RECIPES.CLASSES[class_index]
		var y := 40 + class_index * 156
		_text(c, 16, y, subject.to_upper(), 2)
		for variant in range(8):
			var x := 16 + variant * 144
			_tile(c, images["portrait.%s.%02d" % [subject, variant]], x, y + 16, 2)
			_text(c, x + 110, y + 3, "%02d" % variant, 1)
	return c.image


static func _tile(c: RefCounted, image: Image, x: int, y: int, scale: int) -> void:
	var displayed := image.duplicate() as Image
	if scale > 1:
		displayed.resize(image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST)
	c.rect(x, y, displayed.get_width(), displayed.get_height(), "ink")
	c.image.blend_rect(displayed, Rect2i(Vector2i.ZERO, displayed.get_size()), Vector2i(x, y))


static func _text(c: RefCounted, x: int, y: int, text: String, scale: int) -> void:
	for letter: String in text:
		var bits: String = GLYPHS.get(letter, "000000000000000")
		for index in range(15):
			if bits[index] == "1":
				c.rect(x + (index % 3) * scale, y + (index / 3) * scale, scale, scale, "cream")
		x += 4 * scale
