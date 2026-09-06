extends GutHookScript
## Bind disposable storage before any tests can bootstrap the application.

var _directory: DirAccess


func run() -> void:
	_directory = DirAccess.create_temp("godot-apk-tests")
	if _directory == null:
		gut.logger.error("Cannot create isolated save storage; refusing to run tests.")
		gut.get_post_run_script_instance().set_exit_code(1)
		abort()
		return
	SaveManager.storage_directory = _directory.get_current_dir()
