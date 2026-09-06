extends Control

const HeroUI = preload("res://scenes/ui/hero_ui.gd")
const HOME_SCREEN := "res://scenes/ui/home/home_screen.tscn"
const DETAIL_SCREEN := "res://scenes/ui/hero_detail/hero_detail_screen.tscn"
const PARTY_SCREEN := "res://scenes/ui/party_formation/party_formation_screen.tscn"
const BALANCING: BalancingConfig = preload("res://data/balancing/default_balancing.tres")

var _feedback_message: String = ""

@onready var _gold_label: Label = %GoldLabel
@onready var _roster_count_label: Label = %RosterCountLabel
@onready var _feedback_label: Label = %FeedbackLabel
@onready var _roster_list: VBoxContainer = %RosterList
@onready var _offer_list: VBoxContainer = %OfferList


func _ready() -> void:
	HeroUI.apply_theme(self)
	%BackButton.pressed.connect(_go_home)
	%FormationButton.pressed.connect(_open_formation)
	ExpeditionManager.changed.connect(_refresh_expedition_state)
	ExpeditionManager.operation_failed.connect(_refresh_expedition_state)
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready():
		_refresh()


func _refresh() -> void:
	%FormationButton.text = "Form Party" if GameState.current_party == null else "Edit Party"
	%FormationButton.disabled = not PartyFormationService.editing_error().is_empty()
	_gold_label.text = "Gold: %d" % GameState.gold
	_roster_count_label.text = "Roster: %d / %d" % [
		GameState.roster.size(), GameState.roster_capacity
	]
	HeroUI.clear_children(_roster_list)
	HeroUI.clear_children(_offer_list)
	for index in GameState.roster.size():
		var hero: HeroData = GameState.roster[index]
		var row := HeroUI.hero_row(hero, _open_detail.bind(hero.hero_id))
		row.name = "HeroRow%d" % index
		_roster_list.add_child(row)
	if GameState.roster.is_empty():
		_roster_list.add_child(HeroUI.label("Your company is empty. Recruit a hero below."))
	for index in GameState.recruitment_offers.size():
		var hero: HeroData = GameState.recruitment_offers[index]
		_offer_list.add_child(_offer_card(hero, index))
	if GameState.recruitment_offers.is_empty():
		_offer_list.add_child(HeroUI.label(
			"No recruitment offers are available. Return Home and check any save or recovery message."))
	HeroUI.show_feedback(_feedback_label, _feedback_message)


func _offer_card(hero: HeroData, index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "OfferCard%d" % index
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.set_meta("hero_id", hero.hero_id)
	var content := VBoxContainer.new()
	content.name = "Content"
	card.add_child(content)
	var name_label := HeroUI.label(hero.hero_name, 36)
	name_label.name = "HeroName"
	content.add_child(name_label)
	var summary := HeroUI.label(HeroUI.hero_summary(hero))
	summary.name = "HeroSummary"
	content.add_child(summary)
	HeroUI.add_attributes_and_stats(content, hero)
	HeroUI.add_traits(content, hero)
	var price := HeroUI.label("Price: %d gold" % BALANCING.recruitment_cost, 32)
	price.name = "PriceLabel"
	content.add_child(price)
	var reason := RecruitmentService.availability_error(hero.hero_id, BALANCING)
	var availability := HeroUI.label(reason)
	availability.name = "AvailabilityLabel"
	availability.visible = not reason.is_empty()
	availability.add_theme_color_override("font_color", HeroUI.NOTICE_COLOR)
	content.add_child(availability)
	var recruit_button := HeroUI.button("Recruit · %d gold" % BALANCING.recruitment_cost)
	recruit_button.name = "RecruitButton"
	recruit_button.disabled = not reason.is_empty()
	recruit_button.pressed.connect(_recruit.bind(hero.hero_id))
	content.add_child(recruit_button)
	return card


func _recruit(hero_id: String) -> void:
	var offer: HeroData = null
	for candidate in GameState.recruitment_offers:
		if candidate.hero_id == hero_id:
			offer = candidate
			break
	if offer == null:
		_feedback_message = "This offer is no longer available. Choose one of the current offers below."
	elif RecruitmentService.recruit(offer, BALANCING):
		_feedback_message = (
			"%s joined your company. Gold, roster and offers have been updated." % offer.hero_name)
	else:
		var reason := RecruitmentService.last_error
		if reason.is_empty():
			reason = "The recruitment could not be completed."
		_feedback_message = (
			"Recruitment failed: %s\nCheck your gold and roster space. "
			+ "For a save error, check device storage, then retry this offer."
		) % reason
	_refresh()


func _open_detail(hero_id: String) -> void:
	UIManager.show_screen(DETAIL_SCREEN, {"hero_id": hero_id})


func _go_home() -> void:
	UIManager.show_screen(HOME_SCREEN)


func _open_formation() -> void:
	UIManager.show_screen(PARTY_SCREEN, {"origin": "roster"})


func _refresh_expedition_state() -> void:
	_gold_label.text = "Gold: %d" % GameState.gold
	%FormationButton.disabled = not PartyFormationService.editing_error().is_empty()
	for row in _roster_list.get_children():
		var hero := GameState.find_hero(row.get_meta("hero_id", ""))
		if hero != null:
			row.find_child("HeroSummary", true, false).text = HeroUI.hero_summary(hero)
			row.find_child("StatusBadge", true, false).text = HeroUI.status_name(hero)
	for card in _offer_list.get_children():
		var reason := RecruitmentService.availability_error(card.get_meta("hero_id", ""), BALANCING)
		var availability: Label = card.find_child("AvailabilityLabel", true, false)
		if availability != null:
			availability.text = reason
			availability.visible = not reason.is_empty()
			card.find_child("RecruitButton", true, false).disabled = not reason.is_empty()
	HeroUI.show_feedback(_feedback_label, ExpeditionManager.last_error)
