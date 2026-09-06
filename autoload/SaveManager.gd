extends Node
## Owns future GameState serialization, migration, and backup recovery.
## GameState must initialize first. Milestone 2 implements persistence.

## All save, backup, and temporary paths must derive from this injectable directory.
## Keep I/O out of autoload initialization so tests can bind storage before bootstrap.
var storage_directory: String = OS.get_user_data_dir()


func get_save_path() -> String:
	return storage_directory.path_join("save.json")


## Startup placeholder: deliberately performs no I/O or new-game seeding.
func load_or_create() -> void:
	pass


## Not a successful save: callers must not rely on persistence until Milestone 2.
func save() -> void:
	push_warning("SaveManager.save is not implemented until Milestone 2.")
