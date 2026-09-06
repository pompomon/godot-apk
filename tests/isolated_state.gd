extends RefCounted
## Each case owns disposable OS storage and restores every touched singleton.

var directory: String = ""
var _temporary_directory: DirAccess
var _state: Dictionary
var _manager: Dictionary
var _recruitment_error: String


func begin() -> bool:
	_state = GameState.checkpoint()
	_manager = {
		"storage_directory": SaveManager.storage_directory,
		"last_success": SaveManager.last_success, "last_committed": SaveManager.last_committed,
		"last_error": SaveManager.last_error, "last_warning": SaveManager.last_warning,
		"new_game_seed_override": SaveManager.new_game_seed_override,
		"fault_injector": SaveManager.fault_injector,
	}
	_recruitment_error = RecruitmentService.last_error
	_temporary_directory = DirAccess.create_temp("godot-apk-case")
	if _temporary_directory == null:
		return false
	directory = _temporary_directory.get_current_dir()
	SaveManager.storage_directory = directory
	SaveManager.new_game_seed_override = 12345
	SaveManager.fault_injector = Callable()
	SaveManager.last_success = false
	SaveManager.last_committed = false
	SaveManager.last_error = ""
	SaveManager.last_warning = ""
	RecruitmentService.last_error = ""
	GameState.reset()
	return true


func finish() -> void:
	GameState.restore_checkpoint(_state)
	for key in _manager:
		SaveManager.set(key, _manager[key])
	RecruitmentService.last_error = _recruitment_error
	_temporary_directory = null
