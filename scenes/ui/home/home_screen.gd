extends Control

const HeroUI = preload("res://scenes/ui/hero_ui.gd")
const ROSTER_SCREEN := "res://scenes/ui/roster/roster_screen.tscn"

@onready var _gold_label: Label = %GoldLabel
@onready var _roster_count_label: Label = %RosterCountLabel
@onready var _feedback_label: Label = %FeedbackLabel


func _ready() -> void:
	HeroUI.apply_theme(self)
	%CompanyRosterButton.pressed.connect(_open_roster)
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready():
		_refresh()


func _refresh() -> void:
	_gold_label.text = "Gold: %d" % GameState.gold
	_roster_count_label.text = "Roster: %d / %d" % [
		GameState.roster.size(), GameState.roster_capacity
	]
	HeroUI.show_feedback(_feedback_label)


func _open_roster() -> void:
	UIManager.show_screen(ROSTER_SCREEN)
