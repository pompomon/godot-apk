extends RefCounted

const CANVAS := preload("res://tools/art/pixel_canvas.gd")
const PALETTE := preload("res://tools/art/art_palette.gd")
const RECIPES := preload("res://tools/art/art_recipes.gd")


static func paint(recipe: Dictionary) -> Image:
	var c := CANVAS.new(64, 64)
	if recipe.subject == "unknown":
		_unknown(c)
		return c.image
	var face: Dictionary = RECIPES.FACES[recipe.variant]
	var skin: Array = PALETTE.SKIN[face.skin]
	var hair: Array = PALETTE.HAIR[face.hair]
	var wear: String = RECIPES.HEADWEAR[recipe.subject][recipe.variant]
	var cloth: Array = {
		"knight": ["navy", "slate", "steel"],
		"ranger": ["pine", "moss_dark", "moss"],
		"wizard": ["purple_dark", "purple", "lavender"],
		"cleric": ["teal_dark", "teal", "ice"],
	}[recipe.subject]
	# Back hair and the neck sit behind the costume; headwear is constrained by class.
	c.poly([[20, 15], [24, 9], [38, 9], [44, 16], [45, 39], [40, 46],
		[20, 43], [18, 30]], "ink")
	c.poly([[22, 17], [25, 11], [37, 11], [41, 17], [42, 40],
		[21, 40]], hair[0])
	if face.cut in ["bob", "braid"]:
		c.poly([[21, 19], [25, 21], [24, 42], [18, 44], [19, 31]], hair[1])
		c.line(21, 25, 20, 38, hair[2])
	c.rect(26, 31, 12, 14, "ink")
	c.rect(28, 32, 8, 11, skin[0])
	c.rect(28, 34, 5, 6, skin[1])
	c.poly([[23, 37], [28, 41], [36, 41], [41, 37], [53, 43], [57, 51],
		[60, 62], [4, 62], [7, 50], [12, 44]], "ink")
	c.poly([[23, 40], [30, 46], [37, 43], [42, 40], [51, 45], [55, 52],
		[57, 60], [7, 60], [10, 50], [14, 46]], cloth[0])
	c.poly([[23, 40], [28, 45], [24, 59], [8, 59], [11, 50], [15, 46]], cloth[1])
	c.poly([[15, 47], [23, 43], [22, 50], [11, 55]], cloth[2])
	c.poly([[38, 44], [43, 43], [53, 52], [55, 60], [40, 60]], cloth[1])
	c.line(10, 59, 54, 59, "gold_dark")
	_costume(c, recipe.subject, cloth)
	# Faceted cheeks, stepped jaw and two-pixel eye clusters keep faces legible at 64px.
	var cheek := 1 if face.wide else 0
	c.poly([[23 - cheek, 19], [25, 15], [37, 15], [41 + cheek, 20],
		[40 + cheek, 31], [36, 37], [29, 37], [23 - cheek, 31]], "ink")
	c.rect(21 - cheek, 23, 3, 7, skin[0])
	c.rect(22 - cheek, 23, 2, 4, skin[1])
	c.rect(40 + cheek, 23, 3, 7, skin[0])
	c.poly([[25, 19], [28, 16], [36, 17], [40, 21], [39, 31],
		[35, 35], [29, 35], [24 - cheek, 30], [24 - cheek, 23]], skin[1])
	c.poly([[26, 19], [29, 17], [33, 18], [31, 26], [26, 27], [24, 24]], skin[2])
	c.poly([[37, 20], [40, 22], [39, 31], [35, 35], [33, 34], [35, 29]], skin[0])
	c.line(26, 23, 29, 23, hair[0])
	c.line(35, 23, 38, 24, hair[0])
	c.rect(26, 25, 4, 2, "cream")
	c.rect(35, 25, 3, 2, "cream")
	c.rect(28, 25, 2, 2, "ink")
	c.rect(36, 25, 2, 2, "ink")
	c.line(32, 25, 31, 29, skin[0])
	c.rect(31, 29, 3, 1, skin[2])
	c.line(29, 32, 34, 32, skin[0])
	c.rect(30, 33, 3, 1, skin[2])
	_hair(c, face, hair)
	if face.beard:
		c.poly([[24, 29], [27, 31], [29, 34], [35, 34], [39, 29],
			[38, 34], [34, 39], [29, 38], [25, 34]], hair[1])
		c.rect(29, 31, 6, 1, hair[0])
		c.rect(30, 33, 4, 1, skin[0])
		c.line(27, 33, 30, 36, hair[2])
	_headwear(c, wear, recipe.subject, cloth)
	if face.cut == "braid" and wear != "helmet":
		c.line(42, 29, 43, 45, hair[0], 4)
		for y in range(30, 45, 4):
			c.rect(42, y, 3, 3, hair[1])
			c.dot(42, y, hair[2])
		c.rect(42, 45, 4, 2, "gold")
	# Seed selects a bounded clasp stone, not unstructured random pixels.
	var stone: String = ["teal", "red", "lavender"][recipe.seed % 3]
	c.diamond(32, 44, 3, "ink")
	c.diamond(32, 43, 2, "gold")
	c.dot(32, 42, stone)
	return c.image


static func _costume(c: RefCounted, subject: String, cloth: Array) -> void:
	match subject:
		"knight":
			c.poly([[11, 43], [22, 39], [26, 44], [24, 51], [8, 53], [7, 49]], "ink")
			c.poly([[12, 44], [21, 41], [24, 44], [22, 49], [9, 51], [9, 48]], "steel")
			c.line(12, 44, 20, 42, "silver", 2)
			c.line(11, 48, 22, 46, "silver")
			c.poly([[42, 40], [53, 44], [57, 50], [56, 53], [41, 50], [38, 44]], "ink")
			c.poly([[43, 42], [51, 45], [54, 49], [54, 51], [42, 48], [40, 44]], "slate")
			c.line(43, 42, 51, 45, "steel")
			c.poly([[25, 44], [31, 47], [37, 44], [40, 60], [22, 60]], "navy")
			c.line(25, 47, 24, 59, "gold")
			c.line(37, 47, 38, 59, "gold_dark")
			c.diamond(31, 53, 4, "gold")
			c.rect(30, 50, 2, 7, "gold_light")
			c.line(13, 55, 20, 54, "steel")
		"ranger":
			c.line(45, 39, 18, 60, "ink", 5)
			c.line(45, 39, 18, 60, "hair_brown", 3)
			c.line(45, 39, 18, 60, "gold_dark")
			c.rect(31, 49, 5, 5, "gold")
			c.rect(32, 50, 3, 3, "hair_brown")
			c.line(26, 45, 23, 57, "moss")
			c.line(39, 53, 43, 59, "pine")
			c.line(49, 38, 54, 19, "ink", 3)
			c.line(50, 38, 55, 20, "gold_dark")
			c.poly([[53, 22], [54, 16], [57, 17], [57, 20]], "cream")
			c.line(51, 24, 55, 24, "silver")
		"wizard":
			c.poly([[20, 35], [26, 38], [30, 44], [23, 48], [18, 40]], "ink")
			c.poly([[21, 38], [25, 40], [28, 44], [23, 45]], "lavender")
			c.poly([[39, 36], [46, 35], [44, 43], [37, 47], [34, 44]], "ink")
			c.poly([[40, 39], [43, 38], [42, 42], [37, 45]], "purple")
			c.line(27, 49, 24, 60, "gold")
			c.line(37, 48, 40, 60, "gold_dark")
			c.diamond(32, 54, 2, "gold_light")
			c.rect(51, 32, 4, 30, "ink")
			c.rect(52, 32, 2, 28, "gold_dark")
			c.diamond(53, 30, 6, "ink")
			c.diamond(53, 29, 4, "teal")
			c.poly([[53, 25], [53, 29], [49, 29]], "ice_light")
			c.dot(53, 25, "white")
			c.rect(50, 34, 6, 2, "gold")
		"cleric":
			c.poly([[23, 38], [30, 44], [26, 61], [17, 61]], "gold_dark")
			c.poly([[24, 41], [28, 45], [24, 59], [19, 59]], "cream")
			c.line(24, 46, 21, 57, "white")
			c.poly([[39, 39], [46, 61], [37, 61], [34, 44]], "gold_dark")
			c.poly([[39, 42], [43, 59], [39, 59], [36, 45]], "silver")
			c.diamond(22, 54, 2, "gold")
			c.diamond(40, 54, 2, "gold")
			c.line(13, 50, 11, 57, cloth[2])


static func _hair(c: RefCounted, face: Dictionary, hair: Array) -> void:
	match face.cut:
		"coils":
			for cluster: Array in [[24, 16, 4], [28, 13, 4], [33, 12, 4], [38, 14, 4], [41, 18, 3]]:
				c.disc(cluster[0], cluster[1], cluster[2], "ink")
				c.disc(cluster[0], cluster[1] - 1, cluster[2] - 1, hair[1])
				c.rect(cluster[0] - 1, cluster[1] - 2, 2, 1, hair[2])
		"bob":
			c.poly([[21, 23], [21, 15], [25, 11], [36, 11], [41, 15], [42, 29],
				[38, 25], [37, 18], [31, 21], [27, 20], [24, 24]], hair[1])
			c.line(25, 14, 35, 13, hair[2], 2)
			c.line(23, 17, 23, 21, hair[2])
		"swept", "braid":
			c.poly([[22, 24], [21, 17], [24, 12], [34, 10], [40, 13],
				[42, 21], [38, 20], [35, 16], [30, 20], [25, 20]], hair[1])
			c.line(25, 15, 33, 12, hair[2], 2)
			c.line(24, 17, 29, 15, hair[2])
		_:
			c.poly([[22, 22], [22, 16], [26, 12], [37, 12], [41, 16],
				[41, 23], [38, 20], [37, 17], [32, 18], [28, 16], [25, 19]], hair[1])
			c.line(26, 14, 35, 14, hair[2], 2)


static func _headwear(c: RefCounted, wear: String, subject: String, cloth: Array) -> void:
	match wear:
		"helmet":
			c.poly([[20, 25], [20, 15], [24, 9], [37, 8], [43, 14], [44, 27],
				[39, 27], [38, 20], [25, 20], [24, 28], [20, 28]], "ink")
			c.poly([[22, 24], [22, 15], [26, 11], [35, 10], [40, 14],
				[41, 24], [40, 24], [39, 18], [24, 18], [23, 24]], "steel")
			c.poly([[24, 16], [27, 12], [32, 11], [30, 17]], "silver")
			c.line(32, 10, 33, 19, "gold")
			c.line(23, 19, 39, 19, "gold_dark")
			c.rect(19, 23, 4, 9, "ink")
			c.rect(20, 23, 2, 7, "steel")
			c.rect(40, 24, 4, 8, "ink")
			c.rect(41, 24, 2, 6, "slate")
		"hood":
			var pale := subject == "cleric"
			var main: String = "cream" if pale else cloth[1]
			var light: String = "white" if pale else cloth[2]
			var shadow: String = "silver" if pale else cloth[0]
			c.poly([[18, 30], [18, 18], [22, 10], [31, 6], [40, 10], [45, 19],
				[46, 35], [39, 39], [40, 21], [35, 16], [28, 16], [23, 22], [24, 39]], "ink")
			c.poly([[20, 29], [20, 18], [24, 12], [31, 8], [39, 12], [43, 20],
				[43, 34], [41, 35], [42, 20], [36, 14], [27, 14], [21, 22], [22, 34]], main)
			c.line(24, 13, 30, 10, light, 2)
			c.line(20, 20, 20, 29, light)
			c.line(40, 15, 43, 25, shadow, 2)
		"hat":
			c.poly([[14, 19], [20, 16], [25, 5], [32, 2], [33, 6], [38, 12],
				[40, 17], [47, 19], [46, 23], [17, 23]], "ink")
			c.poly([[21, 18], [26, 7], [30, 5], [32, 9], [36, 13], [39, 19]], "purple")
			c.poly([[24, 16], [27, 8], [30, 6], [29, 13]], "lavender")
			c.line(21, 18, 39, 18, "gold", 2)
			c.line(17, 21, 44, 21, "purple")
			c.diamond(34, 15, 2, "gold_light")
		"circlet":
			c.line(24, 20, 39, 20, "gold_dark", 2)
			c.line(24, 19, 31, 19, "gold_light")
			c.line(34, 19, 39, 19, "gold")
			c.diamond(32, 19, 3, "ink")
			c.diamond(32, 18, 2, "gold")
			c.dot(32, 17, "ice_light")


static func _unknown(c: RefCounted) -> void:
	c.poly([[6, 61], [9, 47], [21, 39], [19, 23], [23, 12], [31, 7],
		[40, 12], [45, 24], [42, 39], [54, 47], [58, 61]], "ink")
	c.poly([[9, 59], [12, 48], [24, 40], [21, 23], [25, 14], [31, 10],
		[39, 14], [42, 25], [39, 41], [51, 48], [55, 59]], "navy")
	c.poly([[23, 24], [27, 17], [35, 16], [39, 23], [37, 34], [28, 35]], "slate")
	c.poly([[26, 23], [29, 19], [35, 19], [37, 24], [35, 32], [29, 32]], "ink")
	c.line(14, 49, 24, 44, "steel")
	c.line(25, 45, 23, 57, "gold_dark")
	c.line(39, 45, 42, 57, "gold_dark")
	c.diamond(32, 45, 3, "gold")
