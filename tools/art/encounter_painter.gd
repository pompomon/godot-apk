extends RefCounted
## Compact encounter vignettes share the release palette and leave transparent corners.

const CANVAS := preload("res://tools/art/pixel_canvas.gd")


static func paint(recipe: Dictionary) -> Image:
	var c := CANVAS.new(64, 64)
	_frame(c, recipe.subject)
	match recipe.subject:
		"enemy_bandit_skirmishers":
			_bandits(c)
		"enemy_forest_wolves":
			_beast(c, "moss_dark", "leaf", false)
		"enemy_ashen_raiders":
			_raider(c)
		"enemy_ashen_jackals":
			_beast(c, "rust", "copper", true)
		"enemy_frostbound_sentinels":
			_sentinel(c)
		"enemy_frostbound_prowlers":
			_beast(c, "teal_dark", "ice", false)
		"event_green_hollow_bridge":
			_bridge(c)
		"event_green_hollow_spring":
			_spring(c)
		"event_green_hollow_caravan":
			_caravan(c)
		"event_green_hollow_fireflies":
			_fireflies(c)
		"event_green_hollow_ruins":
			_ruins(c)
		"event_ashen_cistern":
			_cistern(c)
		"event_ashen_kiln":
			_kiln(c)
		"event_ashen_obelisk":
			_obelisk(c)
		"event_ashen_glass":
			_glass(c)
		"event_ashen_pilgrims":
			_pilgrims(c)
		"event_frostbound_bells":
			_bells(c)
		"event_frostbound_crevasse":
			_crevasse(c)
		"event_frostbound_shelter":
			_shelter(c)
		"event_frostbound_aurora":
			_aurora(c)
		"event_frostbound_sled":
			_sled(c)
		_:
			_unknown(c)
	_signature(c, recipe.seed)
	return c.image


static func _frame(c: RefCounted, subject: String) -> void:
	var ground := "slate"
	var sky := "navy"
	if subject.contains("green_hollow") or subject == "enemy_forest_wolves":
		ground = "moss_dark"
		sky = "pine"
	elif subject.contains("ashen") or subject == "enemy_bandit_skirmishers":
		ground = "rust"
		sky = "earth"
	elif subject.contains("frostbound"):
		ground = "teal"
		sky = "teal_dark"
	c.rect(3, 3, 58, 58, "ink")
	c.rect(5, 5, 54, 54, sky)
	c.rect(5, 43, 54, 16, ground)
	c.line(7, 7, 56, 7, "gold_dark")
	c.line(7, 57, 56, 57, "gold_dark")
	c.dot(6, 6, "gold")
	c.dot(57, 6, "gold")


static func _signature(c: RefCounted, seed_value: int) -> void:
	var colors := ["gold", "cream", "ice", "lavender"]
	for index in 3:
		c.dot(52 + index * 2, 54, colors[(seed_value + index) % colors.size()])


static func _bandits(c: RefCounted) -> void:
	for offset in [-10, 9]:
		c.poly([[32 + offset, 17], [39 + offset, 22], [37 + offset, 39],
			[27 + offset, 39], [25 + offset, 23]], "ink")
		c.poly([[32 + offset, 19], [36 + offset, 23], [35 + offset, 37],
			[29 + offset, 37], [28 + offset, 24]], "hair_brown")
		c.rect(29 + offset, 25, 6, 5, "skin_deep")
	c.line(14, 45, 47, 13, "silver", 3)
	c.line(17, 48, 50, 16, "ink")
	c.line(38, 16, 51, 43, "gold_dark", 3)


static func _beast(c: RefCounted, main: String, light: String, long_ears: bool) -> void:
	var ear_height := 11 if long_ears else 7
	c.poly([[15, 24], [21, 13 - ear_height / 3], [27, 20], [38, 20],
		[45, 13 - ear_height / 3], [50, 27], [46, 42], [35, 49], [21, 43]], "ink")
	c.poly([[19, 25], [23, 17], [28, 23], [38, 23], [44, 17], [47, 28],
		[43, 39], [34, 45], [24, 40]], main)
	c.poly([[24, 27], [31, 24], [29, 35], [21, 34]], light)
	c.poly([[42, 27], [35, 24], [36, 35], [44, 34]], light)
	c.rect(25, 29, 4, 3, "cream")
	c.rect(37, 29, 4, 3, "cream")
	c.dot(27, 30, "ink", 2)
	c.dot(38, 30, "ink", 2)
	c.diamond(33, 38, 3, "ink")
	c.line(33, 41, 28, 44, "cream")
	c.line(34, 41, 39, 44, "cream")


static func _raider(c: RefCounted) -> void:
	c.poly([[18, 24], [24, 13], [43, 13], [49, 24], [46, 45], [20, 45]], "ink")
	c.poly([[21, 24], [26, 16], [41, 16], [46, 24], [43, 42], [23, 42]], "red_dark")
	c.line(20, 24, 47, 24, "copper", 3)
	c.rect(25, 26, 17, 8, "ink")
	c.rect(27, 28, 5, 3, "gold_light")
	c.rect(36, 28, 5, 3, "gold_light")
	c.poly([[31, 8], [35, 8], [39, 17], [27, 17]], "steel")
	c.line(15, 48, 51, 12, "silver", 3)


static func _sentinel(c: RefCounted) -> void:
	c.poly([[23, 13], [41, 13], [49, 26], [45, 47], [19, 47], [15, 26]], "ink")
	c.poly([[25, 16], [39, 16], [45, 27], [42, 43], [22, 43], [19, 27]], "ice")
	c.poly([[20, 27], [32, 18], [44, 27], [39, 40], [25, 40]], "teal")
	c.rect(25, 27, 5, 4, "white")
	c.rect(35, 27, 5, 4, "white")
	c.dot(27, 28, "teal_dark", 2)
	c.dot(36, 28, "teal_dark", 2)
	c.diamond(32, 38, 6, "silver")
	c.diamond(32, 37, 3, "ice_light")


static func _bridge(c: RefCounted) -> void:
	c.poly([[8, 39], [15, 28], [24, 23], [40, 23], [50, 29], [56, 39],
		[56, 48], [48, 48], [43, 37], [21, 37], [16, 48], [8, 48]], "ink")
	c.poly([[10, 38], [17, 30], [25, 26], [39, 26], [48, 31], [54, 38],
		[54, 43], [49, 43], [44, 34], [20, 34], [15, 43], [10, 43]], "earth_light")
	c.line(12, 34, 51, 34, "cream", 2)
	c.line(7, 51, 57, 51, "teal", 3)
	c.line(16, 55, 45, 55, "ice")


static func _spring(c: RefCounted) -> void:
	c.disc(32, 39, 18, "ink")
	c.disc(32, 39, 15, "teal")
	c.disc(29, 36, 10, "ice")
	c.line(20, 39, 43, 39, "ice_light", 2)
	c.line(12, 46, 7, 35, "moss", 3)
	c.line(52, 46, 57, 34, "moss", 3)
	for x in [9, 14, 49, 54]:
		c.line(x, 43, x - 2, 31, "leaf")


static func _caravan(c: RefCounted) -> void:
	c.rect(13, 27, 36, 19, "ink")
	c.rect(16, 29, 30, 14, "hair_brown")
	c.poly([[16, 28], [25, 18], [42, 18], [48, 28]], "cream")
	c.line(20, 25, 44, 25, "gold_dark", 2)
	for x in [21, 42]:
		c.disc(x, 47, 7, "ink")
		c.disc(x, 47, 3, "gold")
	c.line(49, 36, 57, 32, "gold_dark", 3)


static func _fireflies(c: RefCounted) -> void:
	for point: Array in [[14, 25], [23, 18], [35, 27], [47, 16], [52, 34], [28, 39]]:
		c.diamond(point[0], point[1], 3, "gold")
		c.dot(point[0] - 1, point[1] - 1, "gold_light")
	c.line(8, 54, 12, 34, "moss", 2)
	c.line(18, 55, 22, 37, "leaf", 2)
	c.line(45, 55, 42, 37, "moss", 2)
	c.line(55, 55, 51, 40, "leaf", 2)


static func _ruins(c: RefCounted) -> void:
	c.rect(14, 18, 10, 34, "ink")
	c.rect(17, 20, 5, 30, "earth_light")
	c.rect(40, 13, 10, 39, "ink")
	c.rect(42, 16, 5, 34, "slate")
	c.poly([[20, 20], [31, 13], [44, 19], [44, 25], [31, 19], [20, 26]], "ink")
	c.poly([[22, 21], [31, 17], [42, 21], [42, 23], [31, 20], [22, 24]], "silver")
	c.line(8, 51, 56, 51, "moss", 3)


static func _cistern(c: RefCounted) -> void:
	c.disc(32, 37, 20, "ink")
	c.disc(32, 36, 16, "earth")
	c.disc(32, 35, 11, "ink")
	c.disc(32, 37, 8, "teal_dark")
	c.line(16, 20, 48, 20, "sand", 3)
	c.line(22, 18, 22, 43, "gold_dark", 2)
	c.line(43, 18, 43, 43, "gold_dark", 2)


static func _kiln(c: RefCounted) -> void:
	c.poly([[14, 50], [18, 25], [24, 17], [42, 17], [48, 25], [52, 50]], "ink")
	c.poly([[18, 47], [21, 27], [26, 21], [40, 21], [45, 27], [48, 47]], "earth")
	c.disc(33, 39, 11, "ink")
	c.poly([[27, 43], [29, 34], [34, 28], [39, 36], [38, 44]], "rust")
	c.poly([[31, 43], [32, 36], [35, 32], [37, 39], [36, 44]], "gold_light")
	c.line(20, 24, 44, 24, "copper", 2)


static func _obelisk(c: RefCounted) -> void:
	c.poly([[26, 51], [28, 16], [34, 8], [40, 18], [43, 51]], "ink")
	c.poly([[29, 48], [31, 18], [34, 12], [37, 19], [39, 48]], "slate")
	c.line(32, 18, 36, 45, "steel", 2)
	c.diamond(34, 29, 3, "gold")
	c.line(14, 52, 52, 52, "earth", 3)


static func _glass(c: RefCounted) -> void:
	for shard: Array in [[13, 47, 19, 20], [23, 52, 30, 14], [35, 50, 43, 18], [46, 53, 52, 27]]:
		c.poly([[shard[0], shard[1]], [shard[2], shard[3]],
			[shard[2] + 3, shard[1] - 2]], "ink")
		c.line(shard[0] + 2, shard[1] - 2, shard[2], shard[3] + 2, "ice_light", 2)
	c.line(9, 54, 55, 54, "copper", 2)


static func _pilgrims(c: RefCounted) -> void:
	for offset in [-13, 0, 13]:
		c.disc(32 + offset, 23 + absi(offset) / 4, 7, "ink")
		c.poly([[25 + offset, 31], [32 + offset, 26], [39 + offset, 31],
			[43 + offset, 51], [21 + offset, 51]], "ink")
		c.poly([[28 + offset, 32], [32 + offset, 29], [36 + offset, 32],
			[39 + offset, 48], [25 + offset, 48]], "cream" if offset == 0 else "rust")
	c.line(7, 53, 57, 53, "gold_dark", 2)


static func _bells(c: RefCounted) -> void:
	for offset in [-11, 11]:
		c.poly([[21 + offset, 37], [24 + offset, 22], [29 + offset, 17],
			[35 + offset, 22], [39 + offset, 37]], "ink")
		c.poly([[24 + offset, 35], [26 + offset, 24], [30 + offset, 20],
			[33 + offset, 24], [36 + offset, 35]], "gold")
		c.rect(22 + offset, 36, 16, 4, "gold_dark")
		c.dot(29 + offset, 42, "gold_light", 3)
	c.line(10, 15, 54, 15, "silver", 2)


static func _crevasse(c: RefCounted) -> void:
	c.poly([[7, 47], [16, 20], [28, 28], [34, 12], [43, 29], [56, 20],
		[58, 51]], "ice_light")
	c.poly([[28, 27], [34, 12], [38, 30], [34, 35], [40, 45], [31, 55],
		[25, 43], [30, 36]], "ink")
	c.poly([[31, 28], [34, 18], [35, 31], [32, 36], [36, 44], [31, 49],
		[28, 43]], "teal")
	c.line(10, 48, 25, 44, "white", 2)
	c.line(40, 46, 55, 49, "white", 2)


static func _shelter(c: RefCounted) -> void:
	c.poly([[9, 31], [31, 13], [55, 31], [51, 35], [31, 20], [13, 35]], "ink")
	c.poly([[14, 34], [31, 20], [50, 34], [50, 52], [14, 52]], "earth")
	c.rect(28, 36, 9, 16, "ink")
	c.rect(30, 38, 5, 14, "hair_brown")
	c.rect(18, 35, 7, 7, "ice")
	c.line(12, 31, 31, 16, "white", 3)
	c.line(32, 17, 53, 31, "silver", 2)


static func _aurora(c: RefCounted) -> void:
	c.line(8, 19, 22, 11, "teal", 4)
	c.line(22, 11, 36, 23, "teal", 4)
	c.line(36, 23, 55, 10, "teal", 4)
	c.line(7, 25, 21, 17, "ice", 3)
	c.line(21, 17, 36, 29, "ice", 3)
	c.line(36, 29, 57, 16, "lavender", 3)
	c.poly([[7, 51], [18, 37], [27, 45], [36, 33], [44, 43], [57, 35],
		[58, 55]], "ink")
	c.poly([[10, 51], [19, 41], [28, 48], [37, 37], [45, 47], [55, 40],
		[56, 53]], "silver")


static func _sled(c: RefCounted) -> void:
	c.line(12, 49, 50, 49, "ink", 3)
	c.line(15, 53, 53, 53, "ice", 2)
	c.line(15, 53, 10, 47, "ice", 2)
	c.line(53, 53, 57, 47, "ice", 2)
	c.rect(18, 30, 29, 17, "ink")
	c.rect(21, 32, 23, 12, "hair_brown")
	c.line(23, 31, 23, 45, "gold_dark", 2)
	c.line(41, 31, 41, 45, "gold_dark", 2)
	c.poly([[18, 29], [29, 21], [48, 28], [46, 32], [29, 25], [21, 32]], "cream")


static func _unknown(c: RefCounted) -> void:
	c.diamond(32, 31, 22, "ink")
	c.diamond(32, 30, 18, "slate")
	c.line(24, 22, 37, 22, "cream", 4)
	c.line(37, 23, 41, 29, "cream", 4)
	c.line(40, 30, 31, 37, "cream", 4)
	c.rect(29, 36, 5, 7, "cream")
	c.rect(29, 47, 5, 5, "gold")
