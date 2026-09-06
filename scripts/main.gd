extends Control
## Bootstrap and lifecycle persistence; gameplay lives in the autoloads.


func _ready() -> void:
	UIManager.bind_screen_root($ScreenRoot)
	SaveManager.load_or_create()
	ExpeditionManager.enable_lifecycle()
	UIManager.show_screen("res://scenes/ui/home/home_screen.tscn")
	get_tree().auto_accept_quit = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and UIManager.cancel_screen_draft():
		return
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST]:
		if GameState.initialized:
			SaveManager.save()
		if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST]:
			get_tree().quit()
