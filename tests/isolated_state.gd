extends RefCounted
## Each case owns disposable OS storage and restores every touched singleton.

var directory: String = ""
var _state: Dictionary
var _manager: Dictionary
var _expedition_state: Dictionary
var _expedition_manager: Dictionary
var _recruitment_error: String
var _formation_error: String


func begin() -> bool:
	_state = GameState.checkpoint()
	_expedition_state = ExpeditionManager.checkpoint()
	_expedition_manager = {}
	for key in ["clock", "balancing", "last_error", "last_committed", "_lifecycle_enabled", "_foreground", "_timer"]:
		_expedition_manager[key] = ExpeditionManager.get(key)
	ExpeditionManager._lifecycle_enabled = false
	ExpeditionManager._foreground = true
	ExpeditionManager.clock = func() -> int: return 1000
	ExpeditionManager.balancing = ExpeditionManager.DEFAULT_BALANCING
	_manager = {
		"storage_directory": SaveManager.storage_directory,
		"last_success": SaveManager.last_success, "last_committed": SaveManager.last_committed,
		"last_error": SaveManager.last_error, "last_warning": SaveManager.last_warning,
		"new_game_seed_override": SaveManager.new_game_seed_override,
		"fault_injector": SaveManager.fault_injector,
	}
	_recruitment_error = RecruitmentService.last_error
	_formation_error = PartyFormationService.last_error
	directory = ProjectSettings.globalize_path("res://.godot/test-state/case-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return false
	SaveManager.storage_directory = directory
	SaveManager.new_game_seed_override = 12345
	SaveManager.fault_injector = Callable()
	SaveManager.last_success = false
	SaveManager.last_committed = false
	SaveManager.last_error = ""
	SaveManager.last_warning = ""
	RecruitmentService.last_error = ""
	PartyFormationService.last_error = ""
	GameState.reset()
	return true


func finish() -> void:
	GameState.restore_checkpoint(_state)
	ExpeditionManager.restore_checkpoint(_expedition_state)
	for key in _expedition_manager:
		ExpeditionManager.set(key, _expedition_manager[key])
	for key in _manager:
		SaveManager.set(key, _manager[key])
	RecruitmentService.last_error = _recruitment_error
	PartyFormationService.last_error = _formation_error
	for file in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(file))
	DirAccess.remove_absolute(directory)
