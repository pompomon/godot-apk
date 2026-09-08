extends Control

const HeroUI = preload("res://scenes/ui/hero_ui.gd")
const ROSTER_SCREEN := "res://scenes/ui/roster/roster_screen.tscn"
const EQUIPMENT_SCREEN := "res://scenes/ui/equipment/equipment_screen.tscn"

var _hero_id: String = ""
var _portrait: TextureRect
var _class_icon: TextureRect
var _status_icon: TextureRect
var _weapon_icon: TextureRect
var _armor_icon: TextureRect

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
	var identity := HBoxContainer.new()
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_content.add_child(identity)
	_hero_content.move_child(identity, 0)
	_portrait = HeroUI.portrait(null, 192)
	identity.add_child(_portrait)
	_class_icon = HeroUI.artwork(HeroUI.Art.UNKNOWN_ICON)
	_class_icon.name = "ClassIcon"
	identity.add_child(_class_icon)
	_status_icon = HeroUI.artwork(HeroUI.Art.UNKNOWN_ICON)
	_status_icon.name = "StatusIcon"
	identity.add_child(_status_icon)
	_weapon_icon = HeroUI.decorate_label(_weapon_label,
		HeroUI.Art.equipment_icon(null, "Weapon"), "WeaponIcon")
	_armor_icon = HeroUI.decorate_label(_armor_label,
		HeroUI.Art.equipment_icon(null, "Armor"), "ArmorIcon")
	HeroUI.decorate_label(_xp_label, HeroUI.Art.utility_icon("xp"), "XPIcon")
	%BackButton.pressed.connect(_go_back)
	%EquipmentButton.pressed.connect(_open_equipment)
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
	_portrait.texture = HeroUI.portrait_texture(hero)
	_class_icon.texture = HeroUI.class_icon_for(hero)
	_status_icon.texture = HeroUI.Art.status_icon(hero.status)
	_weapon_icon.texture = HeroUI.Art.equipment_icon(hero.equipped_weapon, "Weapon")
	_armor_icon.texture = HeroUI.Art.equipment_icon(hero.equipped_armor, "Armor")
	_weapon_icon.custom_minimum_size = _weapon_icon.texture.get_size() * 2
	_armor_icon.custom_minimum_size = _armor_icon.texture.get_size() * 2
	HeroUI.clear_children(_traits)
	if _attributes_and_stats.get_child_count() == 0:
		HeroUI.add_attributes_and_stats(_attributes_and_stats, hero)
	else:
		var values := {"Attributes": HeroStats.effective_attributes(hero),
			"Stats": HeroStats.compute_derived_stats(hero)}
		for section in values:
			var keys: Array = HeroCatalog.ATTRIBUTES if section == "Attributes" else HeroCatalog.STATS
			for key in keys:
				var label: Label = _attributes_and_stats.get_node("%s/Values/%sValue" % [section, key])
				label.text = HeroUI._number(values[section].get(key, 0), key)
	HeroUI.add_traits(_traits, hero)
	_xp_label.text = "Cumulative XP: %d" % hero.xp
	var threshold := Leveling.threshold(hero.level)
	var next_threshold := Leveling.threshold(hero.level + 1)
	var progress: ProgressBar = %XPProgressBar
	progress.modulate = Color.WHITE
	progress.max_value = 1.0
	progress.value = 0.0
	if next_threshold >= 0 and threshold >= 0:
		progress.max_value = maxi(1, next_threshold - threshold)
		progress.value = clampi(hero.xp - threshold, 0, next_threshold - threshold)
		%ProgressionNotice.text = "Next level: %d cumulative XP · %d XP remaining." % [
			next_threshold, maxi(0, next_threshold - hero.xp)]
	else:
		%ProgressionNotice.text = "Maximum level reached." if hero.level == HeroCatalog.MAX_LEVEL else "Next level is outside the supported XP range."
	if hero.status == HeroData.HeroStatus.RESTING and hero.recovery_ready_at > 0:
		%RecoveryNotice.text = "Resting until %s UTC. Availability refreshes when recovery is saved." % Time.get_datetime_string_from_unix_time(hero.recovery_ready_at, true)
	else:
		%RecoveryNotice.text = ""
	%EquipmentButton.disabled = not EquipmentService.new(hero).validation_error().is_empty()
	_weapon_label.text = "Weapon: %s" % (
		hero.equipped_weapon.display_name if hero.equipped_weapon != null else "Empty")
	_armor_label.text = "Armor: %s" % (
		hero.equipped_armor.display_name if hero.equipped_armor != null else "Empty")


func _go_back() -> void:
	UIManager.show_screen(ROSTER_SCREEN)


func _open_equipment() -> void:
	UIManager.show_screen(EQUIPMENT_SCREEN, {"hero_id": _hero_id})


func _refresh_expedition_state() -> void:
	_refresh()
	HeroUI.show_feedback(_feedback_label, ExpeditionManager.last_error)
