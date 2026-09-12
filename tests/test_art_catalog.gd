extends GutTest

const Art = preload("res://scenes/ui/art_catalog.gd")


func test_all_current_content_has_art_without_fallbacks() -> void:
	for hero_class in HeroCatalog.classes():
		var id := String(hero_class.class_id)
		assert_ne(Art.class_icon(id), Art.UNKNOWN_ICON)
		assert_ne(Art.portrait("hero-1", id), Art.UNKNOWN_PORTRAIT)
		assert_eq(Art.PORTRAITS[id].size(), 8)
	for status in HeroData.HeroStatus.values():
		assert_ne(Art.status_icon(status), Art.UNKNOWN_ICON)
	for item in ItemCatalog.items():
		assert_ne(Art.item_icon(String(item.item_id)), Art.UNKNOWN_ICON)
		assert_same(Art.equipment_icon(item, item.slot), Art.item_icon(String(item.item_id)))
	for region in ExpeditionCatalog.regions():
		assert_ne(Art.region(String(region.region_id)), Art.UNKNOWN_REGION)
	for group in CombatCatalog.enemy_groups():
		assert_ne(Art.enemy(String(group.group_id)), Art.UNKNOWN_ENCOUNTER)
	for event in ExpeditionCatalog.events():
		assert_ne(Art.event(String(event.event_id)), Art.UNKNOWN_ENCOUNTER)
	for kind in ExpeditionStep.StepKind.values():
		assert_ne(Art.journal_icon(kind), Art.UNKNOWN_ICON)
	for outcome in CombatResult.OUTCOMES:
		assert_ne(Art.outcome_icon(outcome), Art.UNKNOWN_ICON)
	for slot in ["Weapon", "Armor"]:
		assert_ne(Art.equipment_icon(null, slot), Art.UNKNOWN_ICON)
	for key in ["gold", "xp", "locked"]:
		assert_ne(Art.utility_icon(key), Art.UNKNOWN_ICON)
	for key in ["home_crest", "section_divider", "formation_emblem"]:
		assert_ne(Art.decoration(key), Art.UNKNOWN_ICON)


func test_catalog_contains_91_unique_imported_textures_at_native_dimensions() -> void:
	var paths := {}
	for bank in Art.PORTRAITS.values():
		for texture in bank:
			_check_texture(texture, Vector2(64, 64), paths)
	_check_texture(Art.UNKNOWN_PORTRAIT, Vector2(64, 64), paths)
	for icons in [Art.CLASSES, Art.STATUSES, Art.SLOTS, Art.JOURNAL, Art.OUTCOMES, Art.UTILITIES]:
		for texture in icons.values():
			_check_texture(texture, Vector2(24, 24), paths)
	_check_texture(Art.UNKNOWN_ICON, Vector2(24, 24), paths)
	for texture in Art.ITEMS.values():
		_check_texture(texture, Vector2(32, 32), paths)
	for texture in Art.REGIONS.values():
		_check_texture(texture, Vector2(320, 144), paths)
	_check_texture(Art.UNKNOWN_REGION, Vector2(320, 144), paths)
	for texture in Art.ENEMIES.values():
		_check_texture(texture, Vector2(64, 64), paths)
	for texture in Art.EVENTS.values():
		_check_texture(texture, Vector2(64, 64), paths)
	_check_texture(Art.UNKNOWN_ENCOUNTER, Vector2(64, 64), paths)
	_check_texture(Art.DECORATIONS.home_crest, Vector2(96, 96), paths)
	_check_texture(Art.DECORATIONS.section_divider, Vector2(320, 16), paths)
	_check_texture(Art.DECORATIONS.formation_emblem, Vector2(64, 64), paths)
	assert_eq(paths.size(), 91)


func _check_texture(texture: Texture2D, expected: Vector2, paths: Dictionary) -> void:
	assert_eq(texture.get_size(), expected, texture.resource_path)
	assert_false(paths.has(texture.resource_path), "Each asset has a distinct explicit path.")
	paths[texture.resource_path] = true
	assert_true(ResourceLoader.exists(texture.resource_path))
	assert_false(texture.get_image().has_mipmaps())


func test_v1_portrait_mapping_is_pinned_not_dependent_on_bank_size_or_order_of_calls() -> void:
	var cases := [
		["hero-1", "knight", 3], ["hero-2", "ranger", 3],
		["hero-3", "wizard", 1], ["hero-4", "cleric", 2],
	]
	for entry in cases:
		assert_same(Art.portrait(entry[0], entry[1]), Art.PORTRAITS[entry[1]][entry[2]])
	cases.reverse()
	for entry in cases:
		assert_same(Art.portrait(entry[0], entry[1]), Art.PORTRAITS[entry[1]][entry[2]])


func test_unknown_ids_never_become_paths_and_have_neutral_fallbacks() -> void:
	for id in ["", "../branding/icon_1024.png", "res://assets/branding/icon_1024.png", "missing"]:
		assert_same(Art.class_icon(id), Art.UNKNOWN_ICON)
		assert_same(Art.item_icon(id), Art.UNKNOWN_ICON)
		assert_same(Art.region(id), Art.UNKNOWN_REGION)
		assert_same(Art.portrait("hero-1", id), Art.UNKNOWN_PORTRAIT)
		assert_same(Art.equipment_icon(null, id), Art.UNKNOWN_ICON)
		assert_same(Art.outcome_icon(id), Art.UNKNOWN_ICON)
		assert_same(Art.utility_icon(id), Art.UNKNOWN_ICON)
		assert_same(Art.enemy(id), Art.UNKNOWN_ENCOUNTER)
		assert_same(Art.event(id), Art.UNKNOWN_ENCOUNTER)
		assert_same(Art.decoration(id), Art.UNKNOWN_ICON)
	assert_same(Art.portrait("", "knight"), Art.UNKNOWN_PORTRAIT)
	assert_same(Art.status_icon(-1), Art.UNKNOWN_ICON)
	assert_same(Art.status_icon(999), Art.UNKNOWN_ICON)
	assert_same(Art.journal_icon(-1), Art.UNKNOWN_ICON)
