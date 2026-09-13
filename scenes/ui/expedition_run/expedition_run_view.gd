class_name ExpeditionRunView
extends VBoxContainer
## Read-only presentation of committed Expedition progress.

const HeroUI = preload("res://scenes/ui/hero_ui.gd")
const FORMATION_SLOTS := ["FRONT_LEFT", "FRONT_RIGHT", "BACK_LEFT", "BACK_RIGHT"]
const STATE_KEYS := [
	"cursor", "credited_elapsed_seconds", "duration_seconds", "total_step_count",
	"completed", "revealed_steps", "newly_revealed_indexes",
]
const STAGE_HEIGHT := 320.0
const PORTRAIT_SIZE := 64.0

var _stage: PanelContainer
var _layers: Control
var _backdrop: TextureRect
var _party_art: Control
var _reveal_art: Control
var _flash: ColorRect
var _status: Label
var _progress: ProgressBar
var _motion_toggle: Button
var _step_icon: TextureRect
var _encounter_art: TextureRect
var _outcome_icon: TextureRect
var _reward_icon: TextureRect
var _reveal_tween: Tween
var _configured: bool = false
var _completed: bool = false
var _presented_cursor: int = -2
var _motion_paused: bool = false
var _application_active: bool = true
var _motion_time: float = 0.0


func _ready() -> void:
	name = "ExpeditionRunView"
	custom_minimum_size.y = 488
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_stage = PanelContainer.new()
	_stage.name = "AnimatedStage"
	_stage.custom_minimum_size.y = STAGE_HEIGHT
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.clip_contents = true
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)

	_layers = Control.new()
	_layers.name = "StageLayers"
	_layers.custom_minimum_size.y = STAGE_HEIGHT
	_layers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_layers)

	var background := ColorRect.new()
	background.color = HeroUI.BACKGROUND_COLOR
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layers.add_child(background)

	_backdrop = HeroUI.artwork(HeroUI.Art.region(""))
	_backdrop.name = "RegionBackdrop"
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layers.add_child(_backdrop)

	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.07, 0.12, 0.38)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layers.add_child(shade)

	_party_art = Control.new()
	_party_art.name = "DispatchedPartyArt"
	_party_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_party_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layers.add_child(_party_art)

	_reveal_art = Control.new()
	_reveal_art.name = "RunRevealArt"
	_reveal_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reveal_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layers.add_child(_reveal_art)

	_flash = ColorRect.new()
	_flash.name = "RevealFlash"
	_flash.color = Color(1.0, 0.86, 0.48, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layers.add_child(_flash)

	_status = HeroUI.label("", 24)
	_status.name = "RunStatusLabel"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_status.offset_left = 12
	_status.offset_top = 8
	_status.offset_right = -12
	_status.offset_bottom = 76
	_layers.add_child(_status)

	_progress = ProgressBar.new()
	_progress.name = "RunProgressBar"
	_progress.custom_minimum_size.y = 40
	_progress.max_value = 1
	_progress.show_percentage = false
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_progress)

	_motion_toggle = HeroUI.button("Pause motion · Static summary remains")
	_motion_toggle.name = "MotionToggleButton"
	_motion_toggle.pressed.connect(_toggle_motion)
	add_child(_motion_toggle)

	_layers.resized.connect(_layout_visuals)
	visibility_changed.connect(_update_processing)
	_clear_run()


func begin_run(region_id: String, party_slots: Dictionary) -> bool:
	if region_id.is_empty() or party_slots.size() != FORMATION_SLOTS.size():
		_clear_run()
		return false
	_cancel_reveal()
	_configured = true
	_completed = false
	_presented_cursor = -2
	_motion_time = 0.0
	_backdrop.texture = HeroUI.Art.region(region_id)
	_clear_children(_party_art)
	for slot_name in FORMATION_SLOTS:
		var member: Variant = party_slots.get(slot_name)
		if member == null:
			continue
		if not member is Dictionary:
			_clear_run()
			return false
		var hero_id := String(member.get("hero_id", ""))
		var class_id := String(member.get("class_id", ""))
		if hero_id.is_empty() or class_id.is_empty():
			_clear_run()
			return false
		var portrait := HeroUI.artwork(
			HeroUI.Art.portrait(hero_id, class_id),
			Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE))
		portrait.name = "RunHero_%s" % hero_id
		portrait.set_meta("hero_id", hero_id)
		portrait.set_meta("formation_slot", slot_name)
		portrait.tooltip_text = "%s · %s (at dispatch)" % [
			String(member.get("hero_name", "Hero")),
			String(member.get("class_name", "Unknown class")),
		]
		_party_art.add_child(portrait)
	_clear_step_visuals()
	_progress.value = 0
	_status.text = "The Party is travelling.\nStep 0"
	visible = true
	_layout_visuals.call_deferred()
	_update_processing()
	return true


func present_committed_state(state: Dictionary) -> bool:
	if not _configured or not _state_valid(state):
		return false
	_cancel_reveal()
	var snapshot := state.duplicate(true)
	var cursor := int(snapshot.cursor)
	var total := int(snapshot.total_step_count)
	var revealed: Array = snapshot.revealed_steps
	var newly_revealed: Array = snapshot.newly_revealed_indexes
	_completed = bool(snapshot.completed)
	_progress.max_value = int(snapshot.duration_seconds)
	_progress.value = int(snapshot.credited_elapsed_seconds)
	_progress.tooltip_text = "Expedition progress: %d of %d steps · %d of %d seconds" % [
		cursor + 1, total, int(snapshot.credited_elapsed_seconds), int(snapshot.duration_seconds)]
	if cursor == _presented_cursor and newly_revealed.is_empty():
		_update_processing()
		return true
	if cursor < 0:
		_clear_step_visuals()
		_status.text = "The Party is travelling.\nStep 0 of %d" % total
		_presented_cursor = cursor
		_update_processing()
		return true

	var step: Dictionary = revealed[cursor]
	_show_step(step)
	var prefix := ""
	if newly_revealed.size() > 1:
		prefix = "%s%d steps completed while away · Latest reveal\n" % [
			"Expedition complete · " if _completed else "",
			newly_revealed.size(),
		]
	elif _completed:
		prefix = "Expedition complete\n"
	_status.text = prefix + _step_summary(step, cursor, total)
	if newly_revealed.size() == 1:
		_animate_reveal()
	else:
		_show_static_reveal()
	_presented_cursor = cursor
	_update_processing()
	return true


func clear_run() -> void:
	_clear_run()


func set_application_active(active: bool) -> void:
	_application_active = active
	if not active:
		_cancel_reveal()
		_apply_static_positions()
	_update_processing()


func motion_paused() -> bool:
	return _motion_paused


func _state_valid(state: Dictionary) -> bool:
	if state.size() != STATE_KEYS.size():
		return false
	for key in STATE_KEYS:
		if not state.has(key):
			return false
	for key in ["cursor", "credited_elapsed_seconds", "duration_seconds", "total_step_count"]:
		if not state[key] is int:
			return false
	if not state.completed is bool or not state.revealed_steps is Array \
			or not state.newly_revealed_indexes is Array:
		return false
	var cursor := int(state.cursor)
	var total := int(state.total_step_count)
	var elapsed := int(state.credited_elapsed_seconds)
	var duration := int(state.duration_seconds)
	if total < 1 or cursor < -1 or cursor >= total or elapsed < 0 or duration < 1 or elapsed > duration:
		return false
	if state.revealed_steps.size() != cursor + 1:
		return false
	var previous := -1
	for index in state.newly_revealed_indexes:
		if not index is int or index < 0 or index > cursor or index <= previous:
			return false
		previous = index
	for step in state.revealed_steps:
		if not step is Dictionary:
			return false
		for key in ["kind", "content_id", "title", "result"]:
			if not step.has(key):
				return false
	return true


func _show_step(step: Dictionary) -> void:
	_clear_step_visuals()
	var kind := int(step.kind)
	_step_icon = HeroUI.artwork(HeroUI.Art.journal_icon(kind), Vector2(48, 48))
	_step_icon.name = "RunStepKindIcon"
	_reveal_art.add_child(_step_icon)
	match kind:
		ExpeditionStep.StepKind.EVENT:
			_encounter_art = HeroUI.artwork(
				HeroUI.Art.event(String(step.content_id)), Vector2(128, 128))
		ExpeditionStep.StepKind.COMBAT:
			_encounter_art = HeroUI.artwork(
				HeroUI.Art.enemy(String(step.content_id)), Vector2(128, 128))
			_outcome_icon = HeroUI.artwork(
				HeroUI.Art.outcome_icon(String(step.result.get("outcome", ""))),
				Vector2(48, 48))
			_outcome_icon.name = "RunOutcomeIcon"
			_reveal_art.add_child(_outcome_icon)
	if _encounter_art != null:
		_encounter_art.name = "RunEncounterArt"
		_reveal_art.add_child(_encounter_art)
	var item_ids: Array = step.result.get("item_ids", [])
	if not item_ids.is_empty():
		_reward_icon = HeroUI.artwork(
			HeroUI.Art.item_icon(String(item_ids[0])), Vector2(64, 64))
		_reward_icon.name = "RunRewardItemIcon"
		_reveal_art.add_child(_reward_icon)
	_layout_visuals()


func _step_summary(step: Dictionary, cursor: int, total: int) -> String:
	var result: Dictionary = step.result
	var detail := ""
	match int(step.kind):
		ExpeditionStep.StepKind.TRAVEL:
			detail = "Travel revealed"
		ExpeditionStep.StepKind.LOOT:
			detail = "Loot revealed · +%d gold" % int(result.get("gold", 0))
		ExpeditionStep.StepKind.EVENT:
			detail = "Event revealed · +%d gold" % int(result.get("gold", 0))
		ExpeditionStep.StepKind.COMBAT:
			detail = "Combat outcome: %s" % String(
				result.get("outcome", "Unknown")).capitalize()
	var item_count: int = result.get("item_ids", []).size()
	if item_count > 0:
		detail += " · %d item%s" % [item_count, "" if item_count == 1 else "s"]
	return "Step %d of %d · %s\n%s" % [
		cursor + 1, total, String(step.title), detail]


func _animate_reveal() -> void:
	if _motion_paused or not _application_active or not is_visible_in_tree():
		_show_static_reveal()
		return
	_flash.color.a = 0.32
	for image in [_step_icon, _encounter_art, _outcome_icon, _reward_icon]:
		if is_instance_valid(image):
			image.modulate.a = 0.0
			image.scale = Vector2(0.86, 0.86)
			image.pivot_offset = image.size / 2.0
	_reveal_tween = create_tween()
	_reveal_tween.set_parallel(true)
	_reveal_tween.tween_property(_flash, "color:a", 0.0, 0.35)
	for image in [_step_icon, _encounter_art, _reward_icon]:
		if is_instance_valid(image):
			_reveal_tween.tween_property(image, "modulate:a", 1.0, 0.24)
			_reveal_tween.tween_property(image, "scale", Vector2.ONE, 0.24)
	if is_instance_valid(_outcome_icon):
		_reveal_tween.tween_property(_outcome_icon, "modulate:a", 1.0, 0.32).set_delay(0.16)
		_reveal_tween.tween_property(_outcome_icon, "scale", Vector2.ONE, 0.32).set_delay(0.16)


func _show_static_reveal() -> void:
	_flash.color.a = 0.0
	for image in [_step_icon, _encounter_art, _outcome_icon, _reward_icon]:
		if is_instance_valid(image):
			image.modulate = Color.WHITE
			image.scale = Vector2.ONE


func _toggle_motion() -> void:
	_motion_paused = not _motion_paused
	_motion_toggle.text = (
		"Resume motion · Static summary shown"
		if _motion_paused
		else "Pause motion · Static summary remains"
	)
	if _motion_paused:
		_cancel_reveal()
		_apply_static_positions()
		_show_static_reveal()
	_update_processing()


func _process(delta: float) -> void:
	_motion_time = fmod(_motion_time + delta, 1000.0)
	var travel_offset := sin(_motion_time * 1.4) * 5.0
	for index in _party_art.get_child_count():
		var portrait := _party_art.get_child(index) as TextureRect
		var base: Vector2 = portrait.get_meta("base_position", portrait.position)
		portrait.position = base + Vector2(
			travel_offset, sin(_motion_time * 3.0 + float(index)) * 3.0)
	var backdrop_offset := sin(_motion_time * 0.35) * 6.0
	_backdrop.offset_left = -8.0 + backdrop_offset
	_backdrop.offset_right = 8.0 + backdrop_offset


func _layout_visuals() -> void:
	if not is_instance_valid(_layers) or _layers.size.x <= 0:
		return
	var positions := {
		"FRONT_LEFT": Vector2(0.43, 0.38),
		"FRONT_RIGHT": Vector2(0.49, 0.67),
		"BACK_LEFT": Vector2(0.19, 0.43),
		"BACK_RIGHT": Vector2(0.25, 0.72),
	}
	for portrait in _party_art.get_children():
		var slot_name := String(portrait.get_meta("formation_slot", ""))
		var ratio: Vector2 = positions.get(slot_name, Vector2(0.3, 0.5))
		var base := Vector2(
			_layers.size.x * ratio.x - PORTRAIT_SIZE / 2.0,
			_layers.size.y * ratio.y - PORTRAIT_SIZE / 2.0)
		portrait.position = base
		portrait.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
		portrait.set_meta("base_position", base)
	if is_instance_valid(_step_icon):
		_step_icon.position = Vector2(14, _layers.size.y - 62)
		_step_icon.size = Vector2(48, 48)
	if is_instance_valid(_encounter_art):
		_encounter_art.position = Vector2(
			_layers.size.x * 0.76 - 64, _layers.size.y * 0.56 - 64)
		_encounter_art.size = Vector2(128, 128)
	if is_instance_valid(_outcome_icon):
		_outcome_icon.position = Vector2(
			_layers.size.x * 0.82 - 24, _layers.size.y * 0.78 - 24)
		_outcome_icon.size = Vector2(48, 48)
	if is_instance_valid(_reward_icon):
		_reward_icon.position = Vector2(
			_layers.size.x * 0.68 - 32, _layers.size.y * 0.78 - 32)
		_reward_icon.size = Vector2(64, 64)
	if _motion_paused or not _application_active:
		_apply_static_positions()


func _apply_static_positions() -> void:
	if not is_instance_valid(_backdrop):
		return
	_backdrop.offset_left = -8
	_backdrop.offset_right = 8
	for portrait in _party_art.get_children():
		portrait.position = portrait.get_meta("base_position", portrait.position)


func _update_processing() -> void:
	set_process(
		_configured and not _completed and not _motion_paused
		and _application_active and is_visible_in_tree())


func _cancel_reveal() -> void:
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_reveal_tween = null


func _clear_step_visuals() -> void:
	_cancel_reveal()
	_clear_children(_reveal_art)
	_step_icon = null
	_encounter_art = null
	_outcome_icon = null
	_reward_icon = null
	if is_instance_valid(_flash):
		_flash.color.a = 0.0


func _clear_run() -> void:
	_cancel_reveal()
	_configured = false
	_completed = false
	_presented_cursor = -2
	_motion_time = 0.0
	if is_instance_valid(_party_art):
		_clear_children(_party_art)
	if is_instance_valid(_reveal_art):
		_clear_step_visuals()
	if is_instance_valid(_status):
		_status.text = ""
	if is_instance_valid(_progress):
		_progress.value = 0
	visible = false
	set_process(false)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _exit_tree() -> void:
	_cancel_reveal()
	set_process(false)
