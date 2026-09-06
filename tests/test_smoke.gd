extends GutTest


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


## Milestone 2 replaces these foundation-only expectations with isolated new-game tests.
func test_foundation_state_is_empty_and_loading_is_side_effect_free() -> void:
	SaveManager.load_or_create()
	assert_eq(GameState.roster, [])
	assert_false(GameState.roster.is_typed())
	assert_eq(GameState.inventory, [])
	assert_false(GameState.inventory.is_typed())
	assert_eq(GameState.gold, 0)
	assert_eq(typeof(GameState.gold), TYPE_INT)
	assert_true(GameState.unlocked_regions.is_empty())
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


func test_mobile_project_settings_are_preserved() -> void:
	var expected := {
		"application/run/main_scene": "res://main.tscn",
		"display/window/size/viewport_width": 720,
		"display/window/size/viewport_height": 1280,
		"display/window/size/window_width_override": 360,
		"display/window/size/window_height_override": 640,
		"display/window/stretch/mode": "canvas_items",
		"display/window/handheld/orientation": 1,
		"rendering/renderer/rendering_method": "gl_compatibility",
		"rendering/renderer/rendering_method.mobile": "gl_compatibility",
	}
	for setting in expected:
		assert_eq(ProjectSettings.get_setting(setting), expected[setting], setting)
