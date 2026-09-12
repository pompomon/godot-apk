extends Control

signal closed

var _return_focus: Control


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
	for child in %ModalOptions.get_children():
		if child is BaseButton and child.visible and not child.disabled:
			call_deferred("_grab_focus_if_available", child)
			return
	call_deferred("_grab_focus_if_available", %ModalCloseButton)


func _grab_focus_if_available(target: Control) -> void:
	if (is_instance_valid(target) and target.is_inside_tree()
			and target.is_visible_in_tree() and target.focus_mode != Control.FOCUS_NONE):
		target.grab_focus()
