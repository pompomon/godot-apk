extends SceneTree
## Usage: godot --headless --path . -s res://tools/art/generate_art.gd -- MODE
## No arguments is read-only help. --check never writes; --write is explicit regeneration.

const BANK := preload("res://tools/art/art_bank.gd")
const HELP := """Offline pixel-art authoring (CPU Image; no player-save access).
Choose exactly one mode after --:
  --check                     Compare committed decoded PNG pixels and manifest (read only).
  --write                     Regenerate the 66 pinned PNGs and tools/art/manifest.json.
  --preview-dir=/absolute/path Write representative.png and portrait_variants.png outside
                              the checkout; never writes the runtime asset bank.
No arguments or --help prints this message without changing files."""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty() or arguments == PackedStringArray(["--help"]):
		print(HELP)
		quit(0)
		return
	if arguments.size() != 1:
		_fail("Choose exactly one mode.\n" + HELP)
		return
	var argument: String = arguments[0]
	var error := ""
	if argument == "--check":
		error = BANK.check()
	elif argument == "--write":
		error = BANK.write()
	elif argument.begins_with("--preview-dir="):
		error = BANK.preview(argument.trim_prefix("--preview-dir="))
	else:
		_fail("Unknown mode.\n" + HELP)
		return
	if not error.is_empty():
		_fail(error)
		return
	print("Pixel-art %s complete." % argument)
	quit(0)


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
