extends MarginContainer
## Shared portrait content bounds; backgrounds remain full-window.

const MAX_CONTENT_WIDTH := 840.0
const SIDES := ["left", "top", "right", "bottom"]
var _padding: PackedInt32Array
var _diagnostic_generation: int = -1
var _static_margins: bool = false


func _ready() -> void:
	_diagnostic_generation = UIManager.diagnostics.generation
	_static_margins = UIManager.diagnostics.static_margins()
	if _static_margins:
		UIManager.diagnostics.mark_for(
			_diagnostic_generation, "layout.screen_margins.static")
		return
	for side in SIDES:
		_padding.append(get_theme_constant("margin_%s" % side))
	resized.connect(_update_margins)
	get_viewport().size_changed.connect(_update_margins)
	_update_margins()


func _notification(what: int) -> void:
	if not _static_margins and what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready():
		_update_margins()


func _update_margins() -> void:
	UIManager.diagnostics.mark_for(_diagnostic_generation, "layout.screen_margins.begin")
	var safe := Rect2(Vector2.ZERO, size)
	if OS.has_feature("android") and get_viewport() == get_tree().root:
		UIManager.diagnostics.mark_for(
			_diagnostic_generation, "layout.screen_margins.safe_area.begin")
		var safe_pixels := Rect2(DisplayServer.get_display_safe_area())
		UIManager.diagnostics.mark_for(
			_diagnostic_generation, "layout.screen_margins.safe_area.end")
		UIManager.diagnostics.mark_for(
			_diagnostic_generation, "layout.screen_margins.transform.begin")
		var transform := physical_screen_transform()
		UIManager.diagnostics.mark_for(
			_diagnostic_generation, "layout.screen_margins.transform.end")
		UIManager.diagnostics.mark_for(
			_diagnostic_generation, "layout.screen_margins.conversion.begin")
		safe = local_safe_rect(size, safe_pixels, transform)
		UIManager.diagnostics.mark_for(
			_diagnostic_generation, "layout.screen_margins.conversion.end")
	UIManager.diagnostics.mark_for(
		_diagnostic_generation, "layout.screen_margins.calculation.begin")
	var margins := PackedInt32Array([
		ceili(safe.position.x) + _padding[0],
		ceili(safe.position.y) + _padding[1],
		ceili(size.x - safe.end.x) + _padding[2],
		ceili(size.y - safe.end.y) + _padding[3],
	])
	var extra := maxf(0.0, size.x - margins[0] - margins[2] - MAX_CONTENT_WIDTH)
	margins[0] += floori(extra / 2.0)
	margins[2] += ceili(extra / 2.0)
	UIManager.diagnostics.mark_for(
		_diagnostic_generation, "layout.screen_margins.calculation.end")
	UIManager.diagnostics.mark_for(
		_diagnostic_generation, "layout.screen_margins.overrides.begin")
	for index in SIDES.size():
		UIManager.diagnostics.mark_for(_diagnostic_generation,
			"layout.screen_margins.override.%s.begin" % SIDES[index])
		add_theme_constant_override("margin_%s" % SIDES[index], margins[index])
		UIManager.diagnostics.mark_for(_diagnostic_generation,
			"layout.screen_margins.override.%s.end" % SIDES[index])
	UIManager.diagnostics.mark_for(
		_diagnostic_generation, "layout.screen_margins.overrides.end")
	UIManager.diagnostics.mark_for(_diagnostic_generation, "layout.screen_margins.end")


func physical_screen_transform() -> Transform2D:
	# CanvasItem's popup transform omits stretch when subwindows are embedded (Android).
	var transform := get_viewport().get_screen_transform()
	transform.origin += Vector2(get_window().position)
	return transform * get_global_transform_with_canvas()


static func local_safe_rect(
	extent: Vector2, safe_pixels: Rect2, local_to_screen: Transform2D
) -> Rect2:
	var bounds := Rect2(Vector2.ZERO, extent)
	if not safe_pixels.has_area() or is_zero_approx(local_to_screen.determinant()):
		return bounds
	# Intersect once in local units: the window may already exclude system bars.
	var safe := bounds.intersection(local_to_screen.affine_inverse() * safe_pixels)
	return safe if safe.has_area() else bounds
