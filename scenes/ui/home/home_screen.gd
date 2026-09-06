extends Control

const HeroUI = preload("res://scenes/ui/hero_ui.gd")
const ROSTER_SCREEN := "res://scenes/ui/roster/roster_screen.tscn"
const PARTY_SCREEN := "res://scenes/ui/party_formation/party_formation_screen.tscn"
const REGION_SCREEN := "res://scenes/ui/region_select/region_select_screen.tscn"
const REPORT_SCREEN := "res://scenes/ui/expedition_report/expedition_report_screen.tscn"
const BALANCING: BalancingConfig = preload("res://data/balancing/default_balancing.tres")

@onready var _gold_label: Label = %GoldLabel
@onready var _roster_count_label: Label = %RosterCountLabel
@onready var _feedback_label: Label = %FeedbackLabel


func _ready() -> void:
	HeroUI.apply_theme(self)
	%CompanyRosterButton.pressed.connect(_open_roster)
	%FormationButton.pressed.connect(_open_formation)
	%ExpeditionButton.pressed.connect(_open_expedition)
	%RetryProgressButton.pressed.connect(_retry_progress)
	ExpeditionManager.changed.connect(_refresh)
	ExpeditionManager.operation_failed.connect(_refresh)
	ExpeditionManager.reveal_progress()
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
	var expedition := ExpeditionManager.get_active_expedition()
	%FormationButton.visible = not ExpeditionManager.is_expedition_active()
	%ExpeditionButton.disabled = expedition == null and party == null
	%ExpeditionButton.text = "View report" if expedition != null else "Choose Region"
	if expedition == null:
		%ExpeditionLabel.text = "Ready to dispatch." if party != null else "Form a Party to begin an Expedition."
	else:
		# Show the ORIGINAL planned count/time while running so a truncated schedule
		# never hints at an early ending before the terminal step is revealed.
		var ended_early := expedition.status == ExpeditionData.Status.COMPLETED and expedition.steps.size() < expedition.candidate_step_count
		if ended_early:
			%ExpeditionLabel.text = "%s · Ended early\nStep %d / %d revealed · 0 seconds remaining" % [
				expedition.region_name, expedition.last_revealed_index + 1, expedition.candidate_step_count]
		else:
			%ExpeditionLabel.text = "%s · %s\nStep %d / %d · %d seconds remaining" % [
				expedition.region_name, "Running" if ExpeditionManager.is_expedition_active() else "Completed",
				expedition.last_revealed_index + 1, expedition.candidate_step_count,
				maxi(0, expedition.duration_seconds - expedition.credited_elapsed_seconds)]
	%RetryProgressButton.visible = not ExpeditionManager.last_error.is_empty()
	HeroUI.show_feedback(_feedback_label, ExpeditionManager.last_error)
	if UIManager.is_current_screen(self) and ExpeditionManager.take_completion_route():
		UIManager.show_screen(REPORT_SCREEN)


func _open_roster() -> void:
	UIManager.show_screen(ROSTER_SCREEN)


func _open_formation() -> void:
	UIManager.show_screen(PARTY_SCREEN, {"origin": "home"})


func _open_expedition() -> void:
	UIManager.show_screen(REPORT_SCREEN if ExpeditionManager.get_active_expedition() != null else REGION_SCREEN)


func _retry_progress() -> void:
	ExpeditionManager.reveal_progress()
	ExpeditionManager.recover_wounded()
	_refresh()
