extends Control
## Bootstrap only; gameplay and navigation live in the autoloads.


func _ready() -> void:
	UIManager.bind_screen_root($ScreenRoot)
	SaveManager.load_or_create()
	UIManager.show_screen("res://scenes/ui/home/home_screen.tscn")
