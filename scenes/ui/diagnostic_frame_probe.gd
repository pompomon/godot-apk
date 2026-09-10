extends Node
## Observe the first render cycle without awaiting or retaining an outgoing screen.

var diagnostics: UIDiagnostics
var _generation: int


func _ready() -> void:
	_generation = diagnostics.generation
	if DisplayServer.get_name() == "headless":
		diagnostics.mark("render.unavailable_headless")
		return
	RenderingServer.frame_pre_draw.connect(_before_draw, CONNECT_ONE_SHOT)
	RenderingServer.frame_post_draw.connect(_after_draw, CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	if _current():
		diagnostics.mark("layout.process_frame")
	set_process(false)


func _current() -> bool:
	return diagnostics.is_recording(_generation) and is_inside_tree()


func _before_draw() -> void:
	if _current():
		diagnostics.mark("layout.before_first_draw")
		diagnostics.mark("render.first_draw.begin")


func _after_draw() -> void:
	if _current():
		diagnostics.mark("render.first_draw.end")


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_before_draw):
		RenderingServer.frame_pre_draw.disconnect(_before_draw)
	if RenderingServer.frame_post_draw.is_connected(_after_draw):
		RenderingServer.frame_post_draw.disconnect(_after_draw)
