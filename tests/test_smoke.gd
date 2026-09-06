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
	assert_false(GameState.inventory.is_typed())
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
