extends GutTest

const HOME := "res://scenes/ui/home/home_screen.tscn"
const ALTERNATE := "res://tests/fixtures/alternate_screen.tscn"

var _manager: Node
var _screen_root: Control


func before_each() -> void:
	_manager = add_child_autofree(load("res://autoload/UIManager.gd").new())
	_screen_root = add_child_autofree(Control.new())


func test_navigation_before_binding_is_rejected() -> void:
	_manager.show_screen(HOME)
	assert_eq(_screen_root.get_child_count(), 0)
	_manager.bind_screen_root(_screen_root)
	_manager.show_screen(HOME)
	assert_eq(_screen_root.get_child_count(), 1)


func test_unready_root_is_rejected() -> void:
	var unready := Control.new()
	_manager.bind_screen_root(unready)
	_manager.show_screen(HOME)
	assert_eq(unready.get_child_count(), 0)
	unready.free()


func test_switching_releases_previous_screen_and_fills_root() -> void:
	_manager.bind_screen_root(_screen_root)
	for path in [HOME, ALTERNATE, HOME, HOME]:
		var previous: Node = _screen_root.get_child(0) if _screen_root.get_child_count() else null
		_manager.show_screen(path)
		assert_eq(_screen_root.get_child_count(), 1)
		var current := _screen_root.get_child(0) as Control
		assert_eq(current.scene_file_path, path)
		assert_eq(current.anchor_left, 0.0)
		assert_eq(current.anchor_top, 0.0)
		assert_eq(current.anchor_right, 1.0)
		assert_eq(current.anchor_bottom, 1.0)
		assert_eq(current.offset_left, 0.0)
		assert_eq(current.offset_top, 0.0)
		assert_eq(current.offset_right, 0.0)
		assert_eq(current.offset_bottom, 0.0)
		if previous != null:
			assert_null(previous.get_parent())
			assert_true(previous.is_queued_for_deletion())
			await get_tree().process_frame
			assert_false(is_instance_valid(previous))


func test_invalid_screens_preserve_current_screen() -> void:
	_manager.bind_screen_root(_screen_root)
	_manager.show_screen(HOME)
	var current := _screen_root.get_child(0)
	for invalid_path in [
		"",
		"res://missing_screen.tscn",
		"user://untrusted_screen.tscn",
		"res://data/balancing/default_balancing.tres",
		"res://tests/fixtures/not_control.tscn",
	]:
		_manager.show_screen(invalid_path)
		assert_eq(_screen_root.get_child_count(), 1)
		assert_eq(_screen_root.get_child(0), current)
		assert_false(current.is_queued_for_deletion())


func test_navigation_from_outgoing_exit_callback_is_deferred() -> void:
	_manager.bind_screen_root(_screen_root)
	_manager.show_screen(HOME)
	var outgoing := _screen_root.get_child(0)
	outgoing.tree_exiting.connect(_manager.show_screen.bind(HOME), CONNECT_ONE_SHOT)
	_manager.show_screen(ALTERNATE)
	assert_eq(_screen_root.get_child_count(), 1)
	assert_eq(_screen_root.get_child(0).scene_file_path, ALTERNATE)
	await get_tree().process_frame
	assert_false(is_instance_valid(outgoing))
	assert_eq(_screen_root.get_child_count(), 1)
	assert_eq(_screen_root.get_child(0).scene_file_path, HOME)


func test_navigation_from_incoming_ready_callback_is_deferred() -> void:
	_manager.bind_screen_root(_screen_root)
	_screen_root.child_entered_tree.connect(_redirect_alternate_on_ready)
	_manager.show_screen(ALTERNATE)
	var outgoing := _screen_root.get_child(0)
	assert_eq(outgoing.scene_file_path, ALTERNATE)
	await get_tree().process_frame
	assert_false(is_instance_valid(outgoing))
	assert_eq(_screen_root.get_child_count(), 1)
	assert_eq(_screen_root.get_child(0).scene_file_path, HOME)


func _redirect_alternate_on_ready(screen: Node) -> void:
	if screen.scene_file_path == ALTERNATE:
		screen.ready.connect(_manager.show_screen.bind(HOME), CONNECT_ONE_SHOT)


func test_second_live_root_is_rejected() -> void:
	_manager.bind_screen_root(_screen_root)
	var second_root: Control = add_child_autofree(Control.new())
	_manager.bind_screen_root(second_root)
	_manager.show_screen(HOME)
	assert_eq(_screen_root.get_child_count(), 1)
	assert_eq(second_root.get_child_count(), 0)


func test_nonempty_root_is_rejected() -> void:
	_screen_root.add_child(Control.new())
	_manager.bind_screen_root(_screen_root)
	_manager.show_screen(HOME)
	assert_eq(_screen_root.get_child_count(), 1)
	assert_eq(_screen_root.get_child(0).scene_file_path, "")


func test_root_teardown_allows_rebinding() -> void:
	_manager.bind_screen_root(_screen_root)
	_manager.show_screen(HOME)
	var previous := _screen_root.get_child(0)
	remove_child(_screen_root)
	_manager.show_screen(HOME)
	assert_eq(_screen_root.get_child_count(), 1)
	assert_eq(_screen_root.get_child(0), previous)
	var next_root: Control = add_child_autofree(Control.new())
	_manager.bind_screen_root(next_root)
	_manager.show_screen(HOME)
	assert_eq(next_root.get_child_count(), 1)
