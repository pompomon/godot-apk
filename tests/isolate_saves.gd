extends GutHookScript
## Bind disposable storage before any tests can bootstrap the application.

var _directory: String


func run() -> void:
	_directory = ProjectSettings.globalize_path("res://.godot/test-state/suite-%d" % OS.get_process_id())
	if DirAccess.make_dir_recursive_absolute(_directory) != OK:
		gut.logger.error("Cannot create isolated save storage; refusing to run tests.")
		gut.get_post_run_script_instance().set_exit_code(1)
		abort()
		return
	SaveManager.storage_directory = _directory
