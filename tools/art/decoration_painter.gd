extends RefCounted

const CANVAS := preload("res://tools/art/pixel_canvas.gd")


static func paint(recipe: Dictionary) -> Image:
	var c := CANVAS.new(recipe.width, recipe.height)
	match recipe.subject:
		"home_crest":
			_home_crest(c)
		"section_divider":
			_section_divider(c)
		"formation_emblem":
			_formation_emblem(c)
	return c.image


static func _home_crest(c: RefCounted) -> void:
	c.poly([[16, 16], [48, 7], [80, 16], [76, 58], [64, 78], [48, 90],
		[31, 78], [20, 58]], "ink")
	c.poly([[20, 19], [48, 11], [76, 19], [72, 56], [61, 74], [48, 84],
		[35, 74], [24, 56]], "gold_dark")
	c.poly([[25, 22], [48, 15], [71, 22], [68, 52], [58, 69], [48, 77],
		[38, 69], [28, 52]], "navy")
	c.line(48, 20, 48, 70, "gold", 4)
	c.line(23, 45, 73, 45, "gold", 4)
	c.poly([[48, 17], [55, 39], [48, 45], [41, 39]], "gold_light")
	c.poly([[73, 45], [53, 52], [48, 45], [54, 39]], "gold")
	c.poly([[48, 73], [41, 52], [48, 45], [55, 52]], "gold_dark")
	c.poly([[23, 45], [42, 38], [48, 45], [41, 52]], "cream")
	c.diamond(48, 45, 7, "ink")
	c.diamond(48, 44, 4, "gold_light")
	c.dot(47, 43, "white", 2)


static func _section_divider(c: RefCounted) -> void:
	c.line(8, 8, 145, 8, "gold_dark", 2)
	c.line(175, 8, 311, 8, "gold_dark", 2)
	c.line(32, 6, 137, 6, "slate")
	c.line(183, 6, 287, 6, "slate")
	c.diamond(160, 7, 7, "ink")
	c.diamond(160, 7, 5, "gold")
	c.diamond(160, 7, 2, "gold_light")
	c.diamond(148, 7, 2, "gold_dark")
	c.diamond(172, 7, 2, "gold_dark")


static func _formation_emblem(c: RefCounted) -> void:
	c.diamond(32, 31, 29, "ink")
	c.diamond(32, 30, 25, "navy")
	for point: Array in [[21, 20], [43, 20], [21, 42], [43, 42]]:
		c.rect(point[0] - 7, point[1] - 7, 14, 14, "gold_dark")
		c.rect(point[0] - 5, point[1] - 5, 10, 10, "slate")
		c.rect(point[0] - 3, point[1] - 3, 6, 6, "cream")
	c.line(25, 20, 39, 20, "gold")
	c.line(25, 42, 39, 42, "gold")
	c.line(21, 25, 21, 37, "gold")
	c.line(43, 25, 43, 37, "gold")
	c.diamond(32, 31, 4, "gold_light")
