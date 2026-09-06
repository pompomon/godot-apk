extends Node
## Owns future GameState serialization, migration, and backup recovery.
## GameState must initialize first. Milestone 2 implements persistence.


## Startup placeholder: deliberately performs no I/O or new-game seeding.
func load_or_create() -> void:
	pass


## Not a successful save: callers must not rely on persistence until Milestone 2.
func save() -> void:
	push_warning("SaveManager.save is not implemented until Milestone 2.")
