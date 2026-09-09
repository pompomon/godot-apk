extends GutTest

const Isolation = preload("res://tests/isolated_state.gd")
var _isolation: RefCounted
var _auto_accept_quit: bool


func before_each() -> void:
	_isolation = Isolation.new()
	assert_true(_isolation.begin())
	_auto_accept_quit = get_tree().auto_accept_quit


func after_each() -> void:
	get_tree().auto_accept_quit = _auto_accept_quit
	_isolation.finish()


func test_save_storage_is_isolated() -> void:
	assert_ne(SaveManager.storage_directory, OS.get_user_data_dir())
	assert_true(DirAccess.dir_exists_absolute(SaveManager.storage_directory))
	assert_eq(SaveManager.get_save_path(), SaveManager.storage_directory.path_join("save.json"))
	assert_false(FileAccess.file_exists(SaveManager.get_save_path()))


func test_save_path_follows_storage_override() -> void:
	var manager: Node = autofree(load("res://autoload/SaveManager.gd").new())
	assert_eq(manager.get_save_path(), OS.get_user_data_dir().path_join("save.json"))
	manager.storage_directory = SaveManager.storage_directory
	assert_eq(manager.get_save_path(), SaveManager.get_save_path())


func test_all_autoloads_exist() -> void:
	for singleton in [
		"GameState", "SaveManager", "CombatSimulator", "ExpeditionManager", "UIManager"
	]:
		assert_not_null(get_tree().root.get_node_or_null(singleton), singleton)


func test_new_company_has_four_typed_heroes_and_starting_gold() -> void:
	assert_false(FileAccess.file_exists(SaveManager.get_save_path()))
	SaveManager.load_or_create()
	assert_true(SaveManager.last_success)
	assert_true(FileAccess.file_exists(SaveManager.get_save_path()))
	assert_eq(GameState.roster.size(), 4)
	assert_eq(GameState.roster.get_typed_script(), HeroData)
	assert_eq(GameState.inventory, [])
	assert_eq(GameState.inventory.get_typed_script(), ItemResource)
	assert_eq(GameState.gold, 100)
	assert_eq(typeof(GameState.gold), TYPE_INT)
	assert_eq(GameState.roster_capacity, 12)
	assert_eq(GameState.recruitment_offers.size(), 3)
	assert_eq(GameState.recruitment_offers.get_typed_script(), HeroData)
	assert_eq(GameState.next_hero_id, 8)
	assert_eq(GameState.recruitment_sequence, 7)
	var ids := {}
	for hero in GameState.roster + GameState.recruitment_offers:
		assert_false(ids.has(hero.hero_id))
		ids[hero.hero_id] = true
	for index in 4:
		assert_same(GameState.roster[index].hero_class, HeroCatalog.classes()[index])
	assert_eq(GameState.unlocked_regions, [&"green_hollow"])
	assert_eq(GameState.unlocked_regions.get_typed_builtin(), TYPE_STRING_NAME)
	assert_false(ExpeditionManager.is_expedition_active())
	assert_null(ExpeditionManager.get_active_expedition())


func test_real_main_scene_boots_to_home() -> void:
	var main: Control = load("res://main.tscn").instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	var screen_root := main.get_node("ScreenRoot")
	assert_eq(screen_root.get_child_count(), 1)
	assert_eq(
		screen_root.get_child(0).scene_file_path,
		"res://scenes/ui/home/home_screen.tscn")
	assert_null(main.get_node_or_null("HelloWorld"))
	assert_eq(
		screen_root.get_child(0).get_node("Margin/Scroll/Content/Title").text,
		ProjectSettings.get_setting("application/config/name"))


func test_mobile_project_settings_are_preserved() -> void:
	var expected := {
		"application/run/main_scene": "res://main.tscn",
		"application/config/quit_on_go_back": false,
		"display/window/size/viewport_width": 720,
		"display/window/size/viewport_height": 1280,
		"display/window/size/window_width_override": 360,
		"display/window/size/window_height_override": 640,
		"display/window/stretch/mode": "canvas_items",
		"display/window/stretch/aspect": "expand",
		"display/window/handheld/orientation": 1,
		"rendering/renderer/rendering_method": "gl_compatibility",
		"rendering/renderer/rendering_method.mobile": "gl_compatibility",
	}
	for setting in expected:
		assert_eq(ProjectSettings.get_setting(setting), expected[setting], setting)


func test_root_window_expands_canvas_without_letterboxing_or_distortion() -> void:
	var window := get_tree().root
	var original_size := window.size
	var main: Control = autofree(load("res://main.tscn").instantiate())
	window.add_child(main)
	await get_tree().process_frame
	assert_eq(window.content_scale_aspect, Window.CONTENT_SCALE_ASPECT_EXPAND)
	for extent in [Vector2i(360, 640), Vector2i(360, 800), Vector2i(600, 800)]:
		window.size = extent
		await get_tree().process_frame
		await get_tree().process_frame
		var canvas := window.get_visible_rect()
		var transform := window.get_final_transform()
		assert_almost_eq(main.size, canvas.size, Vector2.ONE)
		assert_almost_eq(transform * canvas.position, Vector2.ZERO, Vector2.ONE)
		assert_almost_eq(transform * canvas.end, Vector2(window.size), Vector2.ONE)
		assert_almost_eq(transform.x.length(), transform.y.length(), 0.001)
		assert_gte(canvas.size.x, 720.0)
		assert_gte(canvas.size.y, 1280.0)
		if extent == Vector2i(360, 800):
			assert_almost_eq(canvas.size, Vector2(720, 1600), Vector2.ONE)
		if extent == Vector2i(600, 800):
			assert_almost_eq(canvas.size, Vector2(960, 1280), Vector2.ONE)
		var directory := OS.get_environment("ART_PREVIEW_DIR")
		if directory.begins_with("/tmp/") and DisplayServer.get_name() != "headless":
			assert_eq(DirAccess.make_dir_recursive_absolute(directory), OK)
			await RenderingServer.frame_post_draw
			assert_eq(window.get_texture().get_image().save_png(
				directory.path_join("window_%dx%d.png" % [extent.x, extent.y])), OK)
	window.size = original_size
	await get_tree().process_frame


func test_application_branding_preserves_android_identity() -> void:
	assert_eq(ProjectSettings.get_setting("application/config/name"), "Adventurer's March")
	var preset := ConfigFile.new()
	assert_eq(preset.load("res://export_presets.cfg"), OK)
	assert_eq(preset.get_value("preset.0", "name"), "Android")
	assert_eq(preset.get_value("preset.0", "export_path"), "build/android/hello-world.apk")
	assert_eq(preset.get_value("preset.0.options", "package/name"), "Adventurer's March")
	assert_eq(preset.get_value("preset.0.options", "package/unique_name"), "com.example.helloworld")
	assert_true(preset.get_value("preset.0.options", "package/signed"))
	assert_false(preset.get_value("preset.0.options", "gradle_build/use_gradle_build"))


func test_branding_preserves_legacy_user_data_directory() -> void:
	assert_true(ProjectSettings.get_setting("application/config/use_custom_user_dir"))
	for suffix in ["", ".windows", ".macos"]:
		var directory := "godot" if suffix.is_empty() else "Godot"
		assert_eq(
			ProjectSettings.get_setting("application/config/custom_user_dir_name" + suffix),
			directory.path_join("app_userdata/Hello World"))
	var current_directory := OS.get_user_data_dir()
	var current_name: String = ProjectSettings.get_setting("application/config/name")
	var current_custom: bool = ProjectSettings.get_setting("application/config/use_custom_user_dir")
	ProjectSettings.set_setting("application/config/name", "Hello World")
	ProjectSettings.set_setting("application/config/use_custom_user_dir", false)
	var legacy_directory := OS.get_user_data_dir()
	ProjectSettings.set_setting("application/config/name", current_name)
	ProjectSettings.set_setting("application/config/use_custom_user_dir", current_custom)
	assert_eq(current_directory, legacy_directory)


func test_project_and_launcher_icons_are_imported_at_export_sizes() -> void:
	var project_icon: String = ProjectSettings.get_setting("application/config/icon")
	assert_eq(project_icon, "res://assets/branding/icon_1024.png")
	var image := _load_branding_image(project_icon, 1024)
	if image != null:
		assert_eq(image.detect_alpha(), Image.ALPHA_NONE)
	var preset := ConfigFile.new()
	assert_eq(preset.load("res://export_presets.cfg"), OK)
	var expected := {
		"main_192x192": ["icon_192.png", 192],
		"adaptive_foreground_432x432": ["adaptive_foreground_432.png", 432],
		"adaptive_background_432x432": ["adaptive_background_432.png", 432],
		"adaptive_monochrome_432x432": ["adaptive_monochrome_432.png", 432],
	}
	for option in expected:
		var path: String = preset.get_value("preset.0.options", "launcher_icons/" + option)
		assert_eq(path, "res://assets/branding/" + expected[option][0])
		image = _load_branding_image(path, expected[option][1])
		if image == null:
			continue
		if option in ["main_192x192", "adaptive_background_432x432"]:
			assert_eq(image.detect_alpha(), Image.ALPHA_NONE, option)
		else:
			assert_ne(image.get_used_rect(), Rect2i(), option + " must not be empty")
			assert_true(_fits_adaptive_safe_circle(image), option)


func _load_branding_image(path: String, size: int) -> Image:
	var texture := load(path) as Texture2D
	assert_not_null(texture, path)
	if texture == null:
		return null
	var image := texture.get_image()
	assert_eq(image.get_size(), Vector2i(size, size), path)
	return image


func _fits_adaptive_safe_circle(image: Image) -> bool:
	# Android's guaranteed safe zone is a 66 dp circle on a 108 dp layer.
	var center := Vector2(image.get_size()) / 2.0
	var radius := image.get_width() * 66.0 / 108.0 / 2.0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				if Vector2(x + 0.5, y + 0.5).distance_squared_to(center) > radius * radius:
					return false
	return true
