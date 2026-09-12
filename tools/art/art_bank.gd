extends RefCounted
## Offline-only bank operations; paths and recipes never come from player data.

const RECIPES := preload("res://tools/art/art_recipes.gd")
const PALETTE := preload("res://tools/art/art_palette.gd")
const PORTRAITS := preload("res://tools/art/portrait_painter.gd")
const ICONS := preload("res://tools/art/icon_painter.gd")
const BACKDROPS := preload("res://tools/art/backdrop_painter.gd")
const ENCOUNTERS := preload("res://tools/art/encounter_painter.gd")
const DECORATIONS := preload("res://tools/art/decoration_painter.gd")
const CONTACT := preload("res://tools/art/contact_sheet.gd")
const MANIFEST_PATH := "res://tools/art/manifest.json"


static func render(recipe: Dictionary) -> Image:
	if not RECIPES.validate_recipe(recipe).is_empty():
		return null
	match recipe.kind:
		"portrait": return PORTRAITS.paint(recipe)
		"icon": return ICONS.paint(recipe)
		"backdrop": return BACKDROPS.paint(recipe)
		"encounter": return ENCOUNTERS.paint(recipe)
		"decoration": return DECORATIONS.paint(recipe)
	return null


static func pixel_sha256(image: Image) -> String:
	if image == null or image.get_format() != Image.FORMAT_RGBA8:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(image.get_data())
	return context.finish().hex_encode()


static func manifest_entry(recipe: Dictionary, image: Image) -> Dictionary:
	var entry := recipe.duplicate(true)
	entry["pixel_sha256"] = pixel_sha256(image)
	return entry


static func manifest(entries: Array) -> String:
	return JSON.stringify({
		"recipe_version": RECIPES.VERSION,
		"palette_version": PALETTE.VERSION,
		"pixel_format": "RGBA8",
		"pixel_hash": "SHA256 of decoded RGBA8 bytes, row-major, top-left origin",
		"palette": PALETTE.HEX,
		"assets": entries,
	}, "\t", true, true) + "\n"


static func check() -> String:
	var recipes := RECIPES.all()
	var error := RECIPES.validate(recipes)
	if not error.is_empty():
		return error
	var entries: Array = []
	for recipe: Dictionary in recipes:
		var image := render(recipe)
		var path: String = "res://" + recipe.path
		if not FileAccess.file_exists(path):
			return "Missing PNG: %s." % recipe.path
		var committed := Image.new()
		if committed.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
			return "Cannot decode PNG: %s." % recipe.path
		committed.convert(Image.FORMAT_RGBA8)
		if committed.get_size() != image.get_size() or pixel_sha256(committed) != pixel_sha256(image):
			return "Decoded pixels differ: %s." % recipe.path
		entries.append(manifest_entry(recipe, image))
	if not FileAccess.file_exists(MANIFEST_PATH):
		return "Missing manifest."
	if FileAccess.get_file_as_string(MANIFEST_PATH) != manifest(entries):
		return "Manifest differs from pinned recipes or decoded pixel hashes."
	return ""


static func write() -> String:
	var recipes := RECIPES.all()
	var error := RECIPES.validate(recipes)
	if not error.is_empty():
		return error
	# Check every output before the first write; reject links rather than following them.
	for recipe: Dictionary in recipes:
		error = validate_bank_destination(recipe.path)
		if not error.is_empty():
			return error
	error = _reject_links(ProjectSettings.globalize_path(MANIFEST_PATH))
	if not error.is_empty():
		return error
	var entries: Array = []
	for recipe: Dictionary in recipes:
		var image := render(recipe)
		error = _save_png(image, "res://" + recipe.path)
		if not error.is_empty():
			return error
		entries.append(manifest_entry(recipe, image))
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	if file == null:
		return "Cannot open manifest for writing (error %s)." % FileAccess.get_open_error()
	file.store_string(manifest(entries))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return "Cannot write manifest (error %s)." % write_error
	return check()


static func validate_bank_destination(path: String) -> String:
	var known := false
	for recipe: Dictionary in RECIPES.all():
		if recipe.path == path:
			known = true
			break
	if not known:
		return "Output is not a canonical bank PNG."
	return _reject_links(ProjectSettings.globalize_path("res://" + path))


static func validate_preview_directory(directory: String) -> String:
	if directory.is_empty() or not directory.is_absolute_path() or directory.begins_with("res://") or directory.begins_with("user://"):
		return "Preview directory must be an explicit absolute filesystem path."
	var path := directory.simplify_path().trim_suffix("/")
	if path.is_empty() or path == "." or path == ".." or path == "/":
		return "Preview destination cannot be a filesystem root."
	var project := ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	if path == project or path.begins_with(project + "/"):
		return "Preview output must be outside the project and exported assets."
	if FileAccess.file_exists(path):
		return "Preview destination is a file."
	var error := _reject_links(path)
	if not error.is_empty():
		return error
	for filename in ["representative.png", "portrait_variants.png"]:
		error = _reject_links(path.path_join(filename))
		if not error.is_empty():
			return error
	return ""


static func preview(directory: String) -> String:
	var error := validate_preview_directory(directory)
	if not error.is_empty():
		return error
	var images := {}
	for recipe: Dictionary in RECIPES.all():
		images[recipe.id] = render(recipe)
	error = _save_png(CONTACT.representative(images), directory.path_join("representative.png"))
	if not error.is_empty():
		return error
	error = _save_png(CONTACT.variants(images), directory.path_join("portrait_variants.png"))
	if not error.is_empty():
		return error
	return _save_png(CONTACT.encounters(images), directory.path_join("encounters_and_decorations.png"))


static func _reject_links(path: String) -> String:
	var cursor := path
	while not cursor.is_empty():
		var parent := cursor.get_base_dir()
		var access := DirAccess.open(parent)
		if access != null and access.is_link(cursor.get_file()):
			return "Refusing symbolic-link output: %s." % cursor
		if parent == cursor:
			break
		cursor = parent
	return ""


static func _save_png(image: Image, path: String) -> String:
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		return "Cannot create PNG directory (error %s): %s." % [error, path.get_base_dir()]
	error = image.save_png(path)
	if error != OK:
		return "Cannot write PNG (error %s): %s." % [error, path]
	return ""
