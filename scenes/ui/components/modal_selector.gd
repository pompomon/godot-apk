extends Control

signal closed

const ScreenMargin = preload("res://scenes/ui/screen_margin.gd")

@export var use_safe_area_margins: bool = false
var _return_focus: Control


func _enter_tree() -> void:
	if use_safe_area_margins:
		get_node("ModalMargin").set_script(ScreenMargin)


func _ready() -> void:
	%ModalCloseButton.pressed.connect(close)
	hide()


func show_selector(title: String, help: String, return_focus: Control = null) -> void:
	_return_focus = return_focus
	%ModalTitle.text = title
	%ModalHelp.text = help
	clear_options()
	set_empty("")
	set_feedback("")
	%ModalScroll.scroll_vertical = 0
	show()
	move_to_front()
	%ModalCloseButton.grab_focus()


func close() -> void:
	if not visible:
		return
	hide()
	clear_options()
	set_empty("")
	set_feedback("")
	closed.emit()
	call_deferred("_grab_focus_if_available", _return_focus)
	_return_focus = null


func is_open() -> bool:
	return visible


func clear_options() -> void:
	for child in %ModalOptions.get_children():
		%ModalOptions.remove_child(child)
		child.queue_free()


func add_option(option: Control) -> void:
	%ModalOptions.add_child(option)


func options_container() -> VBoxContainer:
	return %ModalOptions


func set_empty(message: String) -> void:
	%ModalEmptyLabel.text = message
	%ModalEmptyLabel.visible = not message.is_empty()


func set_feedback(message: String) -> void:
	%ModalFeedback.text = message
	%ModalFeedback.visible = not message.is_empty()


func focus_first_option() -> void:
	var focusable := _focusable_controls()
	_link_focus_cycle(focusable)
	for child in %ModalOptions.get_children():
		if child is BaseButton and child.visible and not child.disabled:
			call_deferred("_grab_focus_if_available", child)
			return
	call_deferred("_grab_focus_if_available", %ModalCloseButton)


func _focusable_controls() -> Array[Control]:
	var controls: Array[Control] = []
	for child in %ModalOptions.get_children():
		if (child is Control and child.visible and child.focus_mode != Control.FOCUS_NONE
				and (not child is BaseButton or not child.disabled)):
			controls.append(child)
	controls.append(%ModalCloseButton)
	return controls


func _link_focus_cycle(controls: Array[Control]) -> void:
	for index in controls.size():
		var control := controls[index]
		var previous := controls[posmod(index - 1, controls.size())]
		var next := controls[(index + 1) % controls.size()]
		control.focus_previous = control.get_path_to(previous)
		control.focus_next = control.get_path_to(next)
		control.focus_neighbor_top = control.get_path_to(previous)
		control.focus_neighbor_bottom = control.get_path_to(next)
		control.focus_neighbor_left = control.get_path_to(control)
		control.focus_neighbor_right = control.get_path_to(control)


func _grab_focus_if_available(target: Control) -> void:
	if (is_instance_valid(target) and target.is_inside_tree()
			and target.is_visible_in_tree() and target.focus_mode != Control.FOCUS_NONE):
		target.grab_focus()
