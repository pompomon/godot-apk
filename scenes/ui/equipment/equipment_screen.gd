extends Control

const HeroUI = preload("res://scenes/ui/hero_ui.gd")
const ModalSelector = preload("res://scenes/ui/components/modal_selector.gd")
const DETAIL_SCREEN := "res://scenes/ui/hero_detail/hero_detail_screen.tscn"
const ROSTER_SCREEN := "res://scenes/ui/roster/roster_screen.tscn"
var draft: EquipmentService
var _hero_id: String = ""
var _slot: String = "Weapon"
var _leaving: bool = false
var _title: Label
var _feedback: Label
var _slots: Label
var _stats: Label
var _confirm_button: Button
var _message: String = ""
var _portrait: TextureRect
var _slot_buttons: Dictionary = {}

@onready var _equipment_selector: ModalSelector = $EquipmentSelector


func configure(context: Dictionary) -> void:
	var requested: Variant = context.get("hero_id", "")
	_hero_id = requested if requested is String else ""
	if is_node_ready():
		draft = EquipmentService.new(GameState.find_hero(_hero_id))
		_refresh()


func _ready() -> void:
	HeroUI.apply_theme(self)
	draft = EquipmentService.new(GameState.find_hero(_hero_id))
	var content := HeroUI.scrollable_content(self)
	_title = HeroUI.label("Equipment", 44)
	content.add_child(_title)
	_portrait = HeroUI.portrait(draft.hero)
	content.add_child(_portrait)
	_feedback = HeroUI.label("")
	_feedback.name = "FeedbackLabel"
	content.add_child(_feedback)
	_slots = HeroUI.label("")
	_slots.name = "SlotsLabel"
	content.add_child(_slots)
	for slot in ["Weapon", "Armor"]:
		var button := HeroUI.button("Choose %s" % slot.to_lower())
		button.name = "%sButton" % slot
		button.pressed.connect(_choose_slot.bind(slot))
		content.add_child(button)
		_slot_buttons[slot] = button
	_stats = HeroUI.label("")
	_stats.name = "StatPreview"
	content.add_child(_stats)
	_confirm_button = HeroUI.button("Confirm equipment")
	_confirm_button.name = "ConfirmButton"
	_confirm_button.pressed.connect(_confirm)
	content.add_child(_confirm_button)
	var cancel := HeroUI.button("Cancel · Hero Detail")
	cancel.name = "CancelButton"
	cancel.pressed.connect(cancel_draft)
	content.add_child(cancel)
	ExpeditionManager.changed.connect(_refresh)
	ExpeditionManager.operation_failed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if _leaving or not is_inside_tree():
		return
	var reason := draft.validation_error()
	_portrait.texture = HeroUI.portrait_texture(draft.hero)
	_portrait.visible = draft.hero != null
	HeroUI.set_button_icon(_slot_buttons["Weapon"], HeroUI.Art.equipment_icon(draft.weapon, "Weapon"))
	HeroUI.set_button_icon(_slot_buttons["Armor"], HeroUI.Art.equipment_icon(draft.armor, "Armor"))
	_title.text = "Equipment · %s" % (draft.hero.hero_name if draft.hero != null else "Hero unavailable")
	_slots.text = "Weapon: %s\nArmor: %s\nSelecting: %s · Unequipped copies: %d" % [
		_item_name(draft.weapon), _item_name(draft.armor), _slot, GameState.inventory.size()]
	_confirm_button.disabled = not reason.is_empty()
	var preview := draft.preview_stats()
	_stats.text = "Choose equipment to preview stat changes."
	if not preview.is_empty():
		var before := HeroStats.compute_derived_stats(draft.hero)
		var lines := PackedStringArray(["Stats · current → preview (change)"])
		for stat in HeroCatalog.STATS:
			var delta: float = float(preview[stat]) - float(before[stat])
			var probability: bool = stat in ["Evasion", "CritChance"]
			var change := String.num(delta * 100.0, 2) + " pp" if probability else str(int(delta))
			lines.append("%s: %s → %s (%s%s)" % [
				stat, HeroUI._number(before[stat], stat), HeroUI._number(preview[stat], stat),
				"+" if delta >= 0 else "", change])
		_stats.text = "\n".join(lines)
	var message := _message
	for error in [reason, ExpeditionManager.last_error]:
		if not error.is_empty():
			message += ("\n" if not message.is_empty() else "") + error
	HeroUI.show_feedback(_feedback, message)
	if _equipment_selector.is_open():
		_refresh_item_picker()


func _open_item_picker(return_focus: Control) -> void:
	_equipment_selector.show_selector(
		"Choose %s" % _slot.to_lower(),
		"Select a compatible inventory item or unequip the current %s." % _slot.to_lower(),
		return_focus
	)
	_refresh_item_picker()


func _refresh_item_picker() -> void:
	_equipment_selector.clear_options()
	var remove := HeroUI.button("Unequip %s" % _slot.to_lower())
	remove.name = "UnequipButton"
	remove.disabled = draft.hero == null
	remove.pressed.connect(_select_item.bind(null))
	_equipment_selector.add_option(remove)
	var counts := {}
	for item in draft.available_items(_slot):
		counts[item] = counts.get(item, 0) + 1
	for item in counts:
		var button := HeroUI.button("%s · %s · ×%d" % [item.display_name, item.rarity, counts[item]])
		button.name = "Item_%s" % item.item_id
		button.set_meta("item_id", String(item.item_id))
		HeroUI.set_button_icon(button, HeroUI.Art.item_icon(String(item.item_id)))
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_select_item.bind(item))
		_equipment_selector.add_option(button)
	_equipment_selector.set_empty(
		"No %s items available." % _slot.to_lower() if counts.is_empty() else ""
	)
	var message := _message
	for error in [draft.validation_error(), ExpeditionManager.last_error]:
		if not error.is_empty():
			message += ("\n" if not message.is_empty() else "") + error
	_equipment_selector.set_feedback(message)
	_equipment_selector.focus_first_option()


func _item_name(item: ItemResource) -> String:
	return item.display_name if item != null else "Empty"


func _choose_slot(slot: String) -> void:
	if _leaving:
		return
	_slot = slot
	_refresh()
	_open_item_picker(_slot_buttons[slot])


func _select_item(item: ItemResource) -> void:
	if _leaving:
		return
	if _slot == "Weapon":
		draft.weapon = item
	else:
		draft.armor = item
	_message = ""
	_equipment_selector.close()
	_refresh()


func _confirm() -> void:
	if _leaving:
		return
	if draft.confirm():
		cancel_draft()
	else:
		_message = draft.last_error
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel_draft()


func cancel_draft() -> void:
	if _equipment_selector.is_open():
		_equipment_selector.close()
		return
	if not _leaving and is_inside_tree():
		_leaving = true
		if GameState.find_hero(_hero_id) != null:
			UIManager.show_screen(DETAIL_SCREEN, {"hero_id": _hero_id})
		else:
			UIManager.show_screen(ROSTER_SCREEN)
