extends GutTest

const Bank = preload("res://tools/art/art_bank.gd")
const Recipes = preload("res://tools/art/art_recipes.gd")
const Palette = preload("res://tools/art/art_palette.gd")
const Canvas = preload("res://tools/art/pixel_canvas.gd")
const Contact = preload("res://tools/art/contact_sheet.gd")


func test_all_pinned_recipes_produce_palette_bounded_images_at_native_sizes() -> void:
	var recipes := Recipes.all()
	assert_eq(recipes.size(), 66)
	assert_eq(Recipes.validate(recipes), "")
	var colors := {0: true}
	for hex: String in Palette.HEX.values():
		colors[Color("#" + hex).to_rgba32()] = true
	for recipe: Dictionary in recipes:
		var image := Bank.render(recipe)
		assert_not_null(image, recipe.id)
		assert_eq(image.get_size(), Vector2i(recipe.width, recipe.height), recipe.id)
		assert_eq(image.get_format(), Image.FORMAT_RGBA8, recipe.id)
		assert_false(image.has_mipmaps(), recipe.id)
		var used := {}
		var has_clear := false
		var has_opaque := false
		for y in image.get_height():
			for x in image.get_width():
				var color := image.get_pixel(x, y)
				used[color.to_rgba32()] = true
				has_clear = has_clear or color.a8 == 0
				has_opaque = has_opaque or color.a8 == 255
		for color in used:
			assert_true(colors.has(color), "%s uses only palette colors or zero RGBA." % recipe.id)
		assert_true(has_opaque, recipe.id)
		assert_eq(has_clear, recipe.transparent, recipe.id)


func test_generation_is_repeatable_and_independent_of_asset_order() -> void:
	var recipes := Recipes.all()
	var checksums := {}
	var portraits := {}
	for recipe: Dictionary in recipes:
		var image := Bank.render(recipe)
		var hash_value := Bank.pixel_sha256(image)
		assert_eq(hash_value.length(), 64)
		assert_eq(hash_value, Bank.pixel_sha256(Bank.render(recipe)), recipe.id)
		checksums[recipe.id] = hash_value
		if recipe.kind == "portrait":
			assert_false(portraits.has(hash_value), "Portrait variants must be visually distinct.")
			portraits[hash_value] = true
	recipes.reverse()
	for recipe: Dictionary in recipes:
		assert_eq(Bank.pixel_sha256(Bank.render(recipe)), checksums[recipe.id], recipe.id)


func test_recipe_seeds_are_pinned_to_asset_identity() -> void:
	var seeds := {}
	for recipe: Dictionary in Recipes.all():
		seeds[recipe.id] = recipe.seed
	for class_id: String in Recipes.PORTRAIT_SEEDS:
		for variant in range(8):
			assert_eq(seeds["portrait.%s.%02d" % [class_id, variant]],
				Recipes.PORTRAIT_SEEDS[class_id] + variant)
	for icon_id: String in Recipes.ICON_SEEDS:
		assert_eq(seeds["icon.%s.00" % icon_id], Recipes.ICON_SEEDS[icon_id])
	for region_id: String in Recipes.BACKDROP_SEEDS:
		assert_eq(seeds["backdrop.%s.00" % region_id], Recipes.BACKDROP_SEEDS[region_id])
	assert_eq(seeds["portrait.unknown.00"], 1900)
	assert_eq(seeds["icon.unknown.00"], 2900)


func test_committed_bank_and_manifest_match_without_writes() -> void:
	var before := {}
	var paths: Array[String] = [Bank.MANIFEST_PATH]
	for recipe: Dictionary in Recipes.all():
		paths.append("res://" + recipe.path)
	for path in paths:
		before[path] = FileAccess.get_sha256(path)
	assert_eq(Bank.check(), "")
	for path in paths:
		assert_eq(FileAccess.get_sha256(path), before[path], path)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Bank.MANIFEST_PATH))
	assert_eq(manifest.recipe_version, Recipes.VERSION)
	assert_eq(manifest.palette_version, Palette.VERSION)
	assert_eq(manifest.assets.size(), 66)
	assert_eq(manifest.pixel_format, "RGBA8")


func test_invalid_recipes_and_duplicate_destinations_are_rejected() -> void:
	var recipe: Dictionary = Recipes.all()[0]
	for key in recipe:
		var missing := recipe.duplicate(true)
		missing.erase(key)
		assert_ne(Recipes.validate_recipe(missing), "", str(key))
	for change in [
		{"id": "unknown"}, {"kind": "unknown"}, {"subject": "unknown"},
		{"variant": 8}, {"seed": -1}, {"width": 0}, {"height": 1000000},
		{"path": "../save.json"}, {"recipe_version": "future"},
		{"palette_version": "future"}, {"transparent": false}, {"seed": "1100"},
		{"extra": true},
	]:
		var invalid := recipe.duplicate(true)
		invalid.merge(change, true)
		assert_ne(Recipes.validate_recipe(invalid), "", str(change))
		assert_null(Bank.render(invalid))
	assert_ne(Recipes.validate([]), "")
	assert_ne(Recipes.validate([null]), "")
	assert_ne(Recipes.validate([recipe, recipe.duplicate(true)]), "")


func test_output_paths_are_explicit_and_cannot_escape_the_bank() -> void:
	var recipe: Dictionary = Recipes.all()[0]
	assert_eq(Bank.validate_bank_destination(recipe.path), "")
	for path in ["", "assets/art/unknown.png", "../save.json", "user://save.json"]:
		assert_ne(Bank.validate_bank_destination(path), "")
	for path in ["", "/", "relative/path", "res://assets/art", "user://art",
		ProjectSettings.globalize_path("res://"),
		ProjectSettings.globalize_path("res://assets/art")]:
		assert_ne(Bank.validate_preview_directory(path), "", path)


func test_contact_sheets_are_deterministic_and_contain_nearest_scaled_portraits() -> void:
	var images := {}
	for recipe: Dictionary in Recipes.all():
		images[recipe.id] = Bank.render(recipe)
	var representative := Contact.representative(images)
	var variants := Contact.variants(images)
	assert_eq(representative.get_size(), Vector2i(1024, 1568))
	assert_eq(variants.get_size(), Vector2i(1168, 672))
	assert_eq(Bank.pixel_sha256(representative), Bank.pixel_sha256(Contact.representative(images)))
	assert_eq(Bank.pixel_sha256(variants), Bank.pixel_sha256(Contact.variants(images)))
	var portrait: Image = images["portrait.knight.00"]
	for y in portrait.get_height():
		for x in portrait.get_width():
			var expected := portrait.get_pixel(x, y)
			if expected.a8 == 0:
				expected = Palette.color("ink")
			assert_eq(variants.get_pixel(16 + x * 2, 56 + y * 2), expected)
			assert_eq(variants.get_pixel(17 + x * 2, 57 + y * 2), expected)


func test_canvas_clips_shapes_and_preserves_nearest_pixels() -> void:
	var canvas := Canvas.new(4, 4)
	canvas.rect(-2, -2, 3, 3, "gold")
	assert_eq(canvas.image.get_pixel(0, 0), Palette.color("gold"))
	assert_eq(canvas.image.get_pixel(1, 0), Color(0, 0, 0, 0))
	canvas.line(-1, 3, 5, 3, "ink")
	assert_eq(canvas.image.get_pixel(0, 3), Palette.color("ink"))
	assert_eq(canvas.image.get_pixel(3, 3), Palette.color("ink"))
	var doubled := canvas.doubled()
	assert_eq(doubled.get_size(), Vector2i(8, 8))
	for y in 8:
		for x in 8:
			assert_eq(doubled.get_pixel(x, y), canvas.image.get_pixel(x / 2, y / 2))
