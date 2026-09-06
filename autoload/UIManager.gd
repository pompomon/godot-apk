extends Node
## Owns the one active screen under main's persistent UI root.
## Screens navigate only through show_screen; root binding is bootstrap-only.

var _screen_root: Control
var _current_screen: Control
var _root_generation: int = 0


## Bind an empty, ready screen container. Reject a second live UI root.
func bind_screen_root(screen_root: Control) -> void:
	if not is_instance_valid(screen_root) or not screen_root.is_node_ready():
		push_warning("UIManager requires a ready screen root.")
		return
	if is_instance_valid(_screen_root):
		if _screen_root != screen_root:
			push_warning("UIManager already has a screen root.")
		return
	if screen_root.get_child_count() != 0:
		push_warning("UIManager requires an empty screen root.")
		return
	_screen_root = screen_root
	_root_generation += 1
	_screen_root.tree_exiting.connect(_on_screen_root_exiting, CONNECT_ONE_SHOT)


## Calls before root binding are rejected, not queued. Invalid resources leave
## the current screen intact. Only project-owned Control scenes are supported.
## Apply navigation after tree callbacks finish, and discard requests for a root
## that has since exited (including redirects from outgoing screen callbacks).
func show_screen(scene_path: String) -> void:
	if not is_instance_valid(_screen_root):
		push_warning("UIManager cannot navigate before the screen root is ready.")
		return
	_show_screen.call_deferred(scene_path, _root_generation)


func _show_screen(scene_path: String, root_generation: int) -> void:
	if not is_instance_valid(_screen_root) or _root_generation != root_generation:
		return
	if not scene_path.begins_with("res://") or not ResourceLoader.exists(scene_path):
		push_warning("UIManager screen does not exist: %s" % scene_path)
		return
	var scene := load(scene_path) as PackedScene
	if scene == null or not scene.can_instantiate():
		push_warning("UIManager requires a PackedScene: %s" % scene_path)
		return
	var next_screen := scene.instantiate()
	if not next_screen is Control:
		if is_instance_valid(next_screen):
			next_screen.free()
		push_warning("UIManager requires a Control screen: %s" % scene_path)
		return

	var previous_screen := _current_screen
	if is_instance_valid(previous_screen):
		_screen_root.remove_child(previous_screen)
		previous_screen.queue_free()
	_current_screen = next_screen
	_screen_root.add_child(_current_screen)
	_current_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _on_screen_root_exiting() -> void:
	_current_screen = null
	_screen_root = null
