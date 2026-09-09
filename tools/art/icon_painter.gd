extends RefCounted

const CANVAS := preload("res://tools/art/pixel_canvas.gd")


static func paint(recipe: Dictionary) -> Image:
	var c := CANVAS.new(recipe.width, recipe.height)
	if recipe.subject.begins_with("item_"):
		_item(c, recipe.subject.trim_prefix("item_"))
		return c.image
	match recipe.subject:
		"class_knight":
			_shield(c, "navy", "gold")
		"class_ranger":
			_bow(c)
		"class_wizard":
			_staff(c)
		"class_cleric":
			_sun(c, 12, 11)
			c.rect(10, 18, 4, 3, "gold_dark")
			c.rect(10, 18, 3, 2, "gold")
		"status_idle":
			c.poly([[4, 18], [4, 10], [12, 3], [20, 10], [20, 19], [4, 19]], "ink")
			c.poly([[6, 17], [6, 10], [12, 6], [18, 11], [18, 17]], "moss")
			c.line(5, 10, 12, 4, "leaf")
			c.rect(10, 12, 4, 7, "ink")
			c.rect(11, 13, 2, 5, "cream")
		"status_assigned":
			c.rect(5, 4, 14, 16, "ink")
			c.rect(7, 6, 10, 12, "cream")
			c.rect(9, 3, 6, 4, "gold_dark")
			c.rect(10, 3, 4, 2, "gold_light")
			c.line(9, 12, 11, 14, "pine", 2)
			c.line(11, 14, 15, 9, "pine", 2)
		"status_on_expedition", "journal_travel":
			c.poly([[4, 17], [5, 6], [10, 4], [15, 7], [20, 5], [19, 18],
				[14, 20], [9, 17]], "ink")
			c.poly([[6, 15], [7, 7], [10, 6], [14, 9], [18, 7], [17, 16],
				[14, 18], [10, 15]], "cream")
			c.line(10, 7, 10, 14, "gold_dark")
			c.line(14, 10, 14, 16, "sand")
			c.line(8, 12, 16, 12, "rust")
			c.dot(15, 11, "rust", 2)
			if recipe.subject == "status_on_expedition":
				c.line(5, 21, 17, 21, "gold_dark")
				c.poly([[19, 17], [22, 20], [18, 23]], "gold")
		"status_resting":
			c.rect(3, 10, 3, 11, "ink")
			c.rect(6, 12, 13, 7, "ink")
			c.rect(19, 9, 2, 12, "ink")
			c.rect(6, 13, 4, 3, "cream")
			c.rect(10, 13, 9, 4, "teal")
			c.line(10, 13, 18, 13, "ice")
			c.line(13, 3, 18, 3, "gold_light")
			c.line(18, 4, 14, 7, "gold_light")
			c.line(14, 8, 19, 8, "gold_light")
		"status_wounded":
			c.poly([[3, 13], [13, 3], [21, 11], [11, 21]], "ink")
			c.poly([[5, 13], [13, 5], [19, 11], [11, 19]], "cream")
			c.poly([[8, 10], [10, 8], [16, 14], [14, 16]], "sand")
			c.poly([[9, 9], [11, 7], [17, 13], [15, 15]], "white")
			c.dot(8, 13, "gold_dark")
			c.dot(11, 16, "gold_dark")
			c.dot(13, 8, "gold_dark")
			c.dot(16, 11, "gold_dark")
		"status_dead":
			c.poly([[5, 21], [5, 9], [8, 4], [15, 3], [19, 8], [19, 21]], "ink")
			c.poly([[7, 19], [7, 9], [10, 6], [14, 5], [17, 9], [17, 19]], "slate")
			c.line(8, 9, 10, 7, "steel")
			c.line(12, 9, 12, 16, "silver", 2)
			c.line(9, 11, 15, 11, "silver", 2)
			c.rect(3, 20, 19, 2, "earth")
		"slot_weapon", "journal_combat":
			_sword(c)
			if recipe.subject == "journal_combat":
				c.line(4, 5, 16, 18, "ink", 3)
				c.line(4, 4, 17, 17, "silver")
				c.line(5, 5, 17, 18, "steel")
				c.line(13, 19, 20, 13, "gold_dark", 2)
				c.line(17, 18, 20, 21, "hair_brown", 2)
		"slot_armor":
			_tunic(c, "slate", "steel")
		"journal_loot":
			_chest(c)
		"journal_event":
			c.poly([[4, 4], [19, 4], [19, 7], [17, 7], [17, 20],
				[5, 20], [5, 18], [7, 18], [7, 7], [4, 7]], "ink")
			c.rect(6, 5, 11, 2, "gold_light")
			c.rect(8, 7, 8, 11, "cream")
			c.rect(7, 18, 9, 1, "gold_dark")
			c.rect(11, 9, 2, 5, "rust")
			c.rect(11, 15, 2, 2, "rust")
		"outcome_victory":
			c.rect(8, 4, 8, 10, "ink")
			c.rect(9, 5, 6, 7, "gold")
			c.rect(9, 5, 2, 5, "gold_light")
			c.poly([[9, 11], [14, 11], [13, 14], [10, 14]], "gold")
			c.line(5, 5, 5, 10, "gold_dark", 2)
			c.line(5, 10, 9, 12, "gold")
			c.line(18, 5, 18, 10, "gold_dark", 2)
			c.line(18, 10, 14, 12, "gold_dark")
			c.rect(5, 4, 4, 2, "gold_light")
			c.rect(16, 4, 4, 2, "gold")
			c.rect(11, 14, 2, 4, "gold")
			c.rect(7, 18, 10, 3, "ink")
			c.rect(8, 18, 8, 2, "gold")
		"outcome_retreat":
			c.line(17, 4, 17, 21, "ink", 3)
			c.line(18, 4, 18, 20, "gold_dark")
			c.poly([[5, 4], [17, 4], [17, 13], [11, 11], [5, 12], [7, 8]], "ink")
			c.poly([[7, 6], [16, 6], [16, 11], [11, 9], [7, 10], [9, 8]], "cream")
			c.poly([[8, 14], [3, 18], [8, 22], [8, 19], [14, 19], [14, 17], [8, 17]], "gold")
		"outcome_defeat":
			_shield(c, "red_dark", "red")
			c.poly([[13, 4], [10, 10], [13, 12], [10, 19], [15, 12], [12, 10], [16, 4]], "ink")
		"utility_gold":
			c.rect(4, 14, 15, 6, "ink")
			c.rect(5, 14, 13, 2, "gold_light")
			c.rect(5, 17, 13, 2, "gold")
			c.disc(12, 9, 7, "ink")
			c.disc(12, 8, 6, "gold_dark")
			c.disc(11, 8, 5, "gold")
			c.line(8, 5, 12, 4, "gold_light", 2)
			c.rect(11, 6, 2, 5, "gold_dark")
			c.dot(11, 6, "gold_light")
		"utility_xp":
			c.poly([[12, 2], [15, 8], [22, 9], [17, 14], [18, 22], [12, 18],
				[5, 22], [7, 14], [2, 9], [9, 8]], "ink")
			c.poly([[12, 5], [14, 10], [19, 10], [15, 13], [16, 18], [12, 15],
				[8, 18], [9, 13], [5, 10], [10, 10]], "gold")
			c.poly([[12, 5], [12, 12], [8, 15], [9, 12], [6, 10], [10, 10]], "gold_light")
		"utility_locked":
			c.poly([[6, 11], [6, 6], [9, 3], [15, 3], [18, 6], [18, 12]], "ink")
			c.line(8, 6, 8, 11, "silver", 2)
			c.line(9, 5, 14, 5, "silver", 2)
			c.line(15, 6, 15, 11, "steel", 2)
			c.rect(4, 10, 16, 12, "ink")
			c.rect(6, 12, 12, 8, "gold_dark")
			c.rect(6, 12, 10, 6, "gold")
			c.line(6, 12, 15, 12, "gold_light")
			c.rect(11, 14, 3, 2, "ink")
			c.rect(12, 16, 1, 2, "ink")
		_:
			c.diamond(12, 12, 11, "ink")
			c.diamond(12, 11, 8, "slate")
			c.line(9, 7, 14, 7, "cream", 2)
			c.rect(14, 8, 2, 3, "cream")
			c.rect(11, 11, 4, 2, "cream")
			c.rect(11, 13, 2, 2, "cream")
			c.rect(11, 17, 2, 2, "gold")
	return c.image


static func _shield(c: RefCounted, main: String, light: String) -> void:
	c.poly([[3, 4], [12, 2], [21, 4], [20, 14], [17, 19], [12, 23],
		[6, 19], [3, 13]], "ink")
	c.poly([[5, 6], [12, 4], [19, 6], [18, 14], [15, 18], [12, 20], [7, 17], [5, 12]], "gold_dark")
	c.poly([[7, 7], [12, 6], [17, 7], [16, 14], [12, 18], [9, 16], [7, 12]], main)
	c.line(5, 6, 11, 4, "gold_light")
	c.line(5, 6, 6, 12, "gold")
	c.rect(11, 8, 2, 7, light)
	c.rect(9, 10, 6, 2, light)


static func _sword(c: RefCounted) -> void:
	c.poly([[6, 16], [16, 4], [22, 2], [20, 8], [10, 19]], "ink")
	c.poly([[8, 16], [17, 6], [20, 4], [18, 9], [10, 17]], "steel")
	c.line(8, 16, 19, 5, "cream")
	c.line(4, 13, 11, 20, "ink", 3)
	c.line(4, 13, 11, 20, "gold")
	c.line(6, 18, 3, 21, "hair_brown", 2)
	c.dot(2, 21, "gold_dark", 2)


static func _bow(c: RefCounted) -> void:
	c.line(5, 3, 7, 21, "cream")
	c.poly([[5, 2], [12, 3], [18, 7], [20, 12], [17, 17], [8, 22],
		[6, 20], [14, 15], [16, 11], [13, 7], [6, 5]], "ink")
	c.line(7, 4, 12, 5, "gold_light")
	c.line(12, 5, 17, 9, "gold")
	c.line(17, 9, 17, 13, "gold")
	c.line(17, 13, 14, 17, "gold_dark")
	c.line(14, 17, 8, 20, "gold_dark")
	c.line(2, 14, 20, 10, "hair_brown")
	c.poly([[18, 8], [23, 9], [19, 12]], "silver")
	c.line(2, 12, 4, 14, "cream")
	c.line(3, 16, 5, 14, "cream")


static func _staff(c: RefCounted) -> void:
	c.line(7, 22, 14, 8, "ink", 3)
	c.line(8, 21, 15, 8, "gold_dark")
	c.line(8, 19, 11, 13, "gold")
	c.diamond(16, 6, 6, "ink")
	c.diamond(16, 5, 4, "teal")
	c.poly([[16, 1], [16, 5], [12, 5]], "ice_light")
	c.line(12, 9, 17, 11, "gold", 2)
	c.dot(5, 5, "gold_light")
	c.dot(20, 16, "lavender")


static func _sun(c: RefCounted, x: int, y: int) -> void:
	c.line(x, y - 10, x, y + 10, "ink", 2)
	c.line(x - 10, y, x + 10, y, "ink", 2)
	c.line(x - 7, y - 7, x + 7, y + 7, "gold_dark")
	c.line(x - 7, y + 7, x + 7, y - 7, "gold_dark")
	c.disc(x, y, 7, "ink")
	c.disc(x, y - 1, 5, "gold")
	c.disc(x - 1, y - 2, 3, "gold_light")
	c.diamond(x, y - 1, 2, "cream")


static func _tunic(c: RefCounted, main: String, light: String) -> void:
	c.poly([[8, 3], [10, 5], [14, 5], [16, 3], [22, 9], [18, 13],
		[17, 11], [19, 22], [5, 22], [7, 11], [5, 13], [1, 9]], "ink")
	c.poly([[8, 5], [10, 7], [14, 7], [16, 5], [19, 9], [18, 10],
		[15, 8], [17, 20], [7, 20], [9, 8], [5, 10], [4, 9]], main)
	c.line(8, 5, 5, 8, light, 2)
	c.line(10, 8, 9, 17, light)
	c.rect(7, 17, 10, 2, "gold_dark")
	c.rect(11, 17, 3, 2, "gold")


static func _chest(c: RefCounted) -> void:
	c.poly([[3, 10], [5, 5], [18, 5], [21, 10], [21, 20], [3, 20]], "ink")
	c.poly([[5, 10], [7, 7], [17, 7], [19, 10]], "copper")
	c.rect(5, 12, 14, 6, "hair_brown")
	c.rect(6, 12, 4, 5, "rust")
	c.line(5, 10, 19, 10, "gold")
	c.rect(6, 7, 2, 11, "gold_dark")
	c.rect(16, 7, 2, 11, "gold_dark")
	c.rect(10, 10, 4, 5, "ink")
	c.rect(11, 11, 2, 3, "gold_light")


static func _item(c: RefCounted, subject: String) -> void:
	if subject in ["short_sword", "hunting_bow", "apprentice_staff"]:
		var small := CANVAS.new(24, 24)
		match subject:
			"short_sword": _sword(small)
			"hunting_bow": _bow(small)
			"apprentice_staff": _staff(small)
		c.image.blit_rect(small.image, Rect2i(0, 0, 24, 24), Vector2i(4, 4))
		return
	c.poly([[11, 4], [14, 7], [18, 7], [21, 4], [30, 11], [25, 17],
		[23, 14], [25, 29], [7, 29], [9, 14], [6, 17], [1, 11]], "ink")
	var main: String = {"leather_armor": "hair_brown", "chainmail": "slate", "robes": "purple_dark"}[subject]
	var light: String = {"leather_armor": "rust", "chainmail": "steel", "robes": "purple"}[subject]
	c.poly([[11, 6], [14, 9], [18, 9], [21, 6], [27, 11], [25, 14],
		[21, 10], [23, 27], [9, 27], [11, 10], [6, 14], [4, 11]], main)
	c.poly([[11, 6], [14, 9], [13, 24], [10, 25], [11, 11], [6, 13], [5, 11]], light)
	c.line(11, 6, 6, 10, "silver" if subject == "chainmail" else "gold_dark")
	match subject:
		"chainmail":
			for y in range(11, 23, 3):
				for x in range(12 + (y % 2), 21, 3):
					c.line(x, y, x + 1, y + 1, "steel")
					c.dot(x, y + 1, "silver")
			c.rect(9, 24, 14, 3, "navy")
			c.rect(10, 25, 12, 1, "gold_dark")
		"robes":
			c.poly([[14, 9], [16, 13], [12, 27], [9, 27]], "lavender")
			c.line(14, 10, 11, 27, "gold")
			c.line(18, 10, 22, 27, "gold_dark")
			c.diamond(17, 18, 2, "gold_light")
			c.line(17, 23, 17, 26, "purple")
		_:
			c.line(13, 10, 20, 25, "gold_dark", 2)
			c.line(18, 10, 12, 25, "ink")
			c.rect(10, 22, 13, 3, "ink")
			c.rect(10, 22, 12, 2, "gold_dark")
			c.rect(15, 21, 4, 4, "gold")
			c.rect(16, 22, 2, 2, "hair_brown")
