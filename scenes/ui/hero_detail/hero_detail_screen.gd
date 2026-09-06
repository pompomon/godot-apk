extends Control

const HeroUI = preload("res://scenes/ui/hero_ui.gd")
const ROSTER_SCREEN := "res://scenes/ui/roster/roster_screen.tscn"

var _hero_id: String = ""

@onready var _hero_name_label: Label = %HeroNameLabel
@onready var _feedback_label: Label = %FeedbackLabel
@onready var _missing_label: Label = %MissingHeroLabel
@onready var _hero_content: VBoxContainer = %HeroContent
@onready var _hero_summary_label: Label = %HeroSummaryLabel
@onready var _attributes_and_stats: VBoxContainer = %AttributesAndStats
@onready var _traits: VBoxContainer = %TraitDetails
@onready var _xp_label: Label = %XPLabel
@onready var _weapon_label: Label = %WeaponLabel
@onready var _armor_label: Label = %ArmorLabel


func configure(context: Dictionary) -> void:
	var requested_id: Variant = context.get("hero_id", "")
	_hero_id = requested_id if requested_id is String else ""
	if is_node_ready():
		_refresh()


func _ready() -> void:
	HeroUI.apply_theme(self)
	%BackButton.pressed.connect(_go_back)
	ExpeditionManager.changed.connect(_refresh_expedition_state)
	ExpeditionManager.operation_failed.connect(_refresh_expedition_state)
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready():
		_refresh()


func _refresh() -> void:
	HeroUI.show_feedback(_feedback_label)
	var hero: HeroData = GameState.find_hero(_hero_id) if not _hero_id.is_empty() else null
	_missing_label.visible = hero == null
	_hero_content.visible = hero != null
	if hero == null:
		_hero_name_label.text = "Hero unavailable"
		if _hero_id.is_empty():
			_missing_label.text = "No hero was selected. Return to Company Roster and choose a hero."
		else:
			_missing_label.text = "This hero is no longer in your company. Return to Company Roster and choose another hero."
		return
	_hero_name_label.text = hero.hero_name
	_hero_summary_label.text = HeroUI.hero_summary(hero)
	HeroUI.clear_children(_attributes_and_stats)
	HeroUI.clear_children(_traits)
	HeroUI.add_attributes_and_stats(_attributes_and_stats, hero)
	HeroUI.add_traits(_traits, hero)
	_xp_label.text = "Cumulative XP: %d" % hero.xp
	_weapon_label.text = "Weapon: %s" % (
		hero.equipped_weapon.display_name if hero.equipped_weapon != null else "Empty")
	_armor_label.text = "Armor: %s" % (
		hero.equipped_armor.display_name if hero.equipped_armor != null else "Empty")


func _go_back() -> void:
	UIManager.show_screen(ROSTER_SCREEN)


func _refresh_expedition_state() -> void:
	var hero := GameState.find_hero(_hero_id)
	if hero != null:
		_hero_summary_label.text = HeroUI.hero_summary(hero)
	else:
		_refresh()
	HeroUI.show_feedback(_feedback_label, ExpeditionManager.last_error)
