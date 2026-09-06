extends Control
## Bootstrap and lifecycle persistence; gameplay lives in the autoloads.


func _ready() -> void:
	UIManager.bind_screen_root($ScreenRoot)
	SaveManager.load_or_create()
	UIManager.show_screen("res://scenes/ui/home/home_screen.tscn")
	get_tree().auto_accept_quit = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if GameState.initialized:
			SaveManager.save()
		if what == NOTIFICATION_WM_CLOSE_REQUEST:
			get_tree().quit()
