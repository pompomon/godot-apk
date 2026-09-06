extends Control

const HeroUI = preload("res://scenes/ui/hero_ui.gd")
const ROSTER_SCREEN := "res://scenes/ui/roster/roster_screen.tscn"
const PARTY_SCREEN := "res://scenes/ui/party_formation/party_formation_screen.tscn"
const BALANCING: BalancingConfig = preload("res://data/balancing/default_balancing.tres")

@onready var _gold_label: Label = %GoldLabel
@onready var _roster_count_label: Label = %RosterCountLabel
@onready var _feedback_label: Label = %FeedbackLabel


func _ready() -> void:
	HeroUI.apply_theme(self)
	%CompanyRosterButton.pressed.connect(_open_roster)
	%FormationButton.pressed.connect(_open_formation)
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready():
		_refresh()


func _refresh() -> void:
	_gold_label.text = "Gold: %d" % GameState.gold
	_roster_count_label.text = "Roster: %d / %d" % [
		GameState.roster.size(), GameState.roster_capacity
	]
	var party := GameState.current_party
	%FormationButton.text = "Form Party" if party == null else "Edit Party"
	%FormationButton.disabled = not PartyFormationService.editing_error().is_empty()
	if party == null:
		%PartySummaryLabel.text = "No confirmed Party."
	else:
		var power := PartyEvaluator.compute_party_power(party, BALANCING)
		%PartySummaryLabel.text = "Current Party: %d / 4 Heroes · Power: %s" % [
			party.heroes().size(), String.num(power, 2) if is_finite(power) else "Unavailable"]
	HeroUI.show_feedback(_feedback_label)


func _open_roster() -> void:
	UIManager.show_screen(ROSTER_SCREEN)


func _open_formation() -> void:
	UIManager.show_screen(PARTY_SCREEN, {"origin": "home"})
