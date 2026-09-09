extends RefCounted
## Shared presentation only: hero values always come from the domain calculators.

const Art = preload("res://scenes/ui/art_catalog.gd")
const TEXT_COLOR := Color("#edf0f7")
const MUTED_COLOR := Color("#bdc7da")
const NOTICE_COLOR := Color("#f8d58b")


static func apply_theme(screen: Control) -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 28
	ui_theme.set_color("font_color", "Label", TEXT_COLOR)
	ui_theme.set_color("font_color", "Button", TEXT_COLOR)
	ui_theme.set_color("font_hover_color", "Button", TEXT_COLOR)
	ui_theme.set_color("font_pressed_color", "Button", TEXT_COLOR)
	ui_theme.set_color("font_focus_color", "Button", TEXT_COLOR)
	ui_theme.set_color("font_disabled_color", "Button", Color("#a5afc1"))
	ui_theme.set_font_size("font_size", "Button", 30)
	ui_theme.set_stylebox("normal", "Button", _box(Color("#263e61")))
	ui_theme.set_stylebox("hover", "Button", _box(Color("#355582")))
	ui_theme.set_stylebox("pressed", "Button", _box(Color("#1b2e4a")))
	ui_theme.set_stylebox("disabled", "Button", _box(Color("#282f3c")))
	var focus := _box(Color.TRANSPARENT)
	focus.set_border_width_all(3)
	focus.border_color = Color("#f8d58b")
	ui_theme.set_stylebox("focus", "Button", focus)
	ui_theme.set_stylebox("panel", "PanelContainer", _box(Color("#1c273b")))
	ui_theme.set_constant("separation", "VBoxContainer", 16)
	ui_theme.set_constant("separation", "HBoxContainer", 16)
	ui_theme.set_constant("h_separation", "GridContainer", 20)
	ui_theme.set_constant("v_separation", "GridContainer", 8)
	screen.theme = ui_theme


static func _box(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(16)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	return style


static func label(text: String, font_size: int = 28) -> Label:
	var result := Label.new()
	result.text = text
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_theme_font_size_override("font_size", font_size)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


static func button(text: String) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size = Vector2(0, 96)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.mouse_filter = Control.MOUSE_FILTER_PASS
	return result


static func artwork(texture: Texture2D, extent: Vector2 = Vector2(48, 48)) -> TextureRect:
	var image := TextureRect.new()
	image.texture = texture
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = extent
	image.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	image.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image


static func portrait(hero: HeroData, pixels: int = 128) -> TextureRect:
	var image := artwork(portrait_texture(hero), Vector2(pixels, pixels))
	image.name = "Portrait"
	return image


static func portrait_texture(hero: HeroData) -> Texture2D:
	if hero == null or hero.hero_class == null:
		return Art.UNKNOWN_PORTRAIT
	return Art.portrait(hero.hero_id, String(hero.hero_class.class_id))


static func region_banner(region_id: String) -> TextureRect:
	var image := artwork(Art.region(region_id), Vector2(0, 288))
	image.name = "RegionBackdrop"
	image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return image


static func set_button_icon(target: Button, texture: Texture2D) -> void:
	target.icon = texture
	target.expand_icon = true
	if texture != null:
		target.add_theme_constant_override("icon_max_width", texture.get_width() * 2)
		target.custom_minimum_size.y = maxf(target.custom_minimum_size.y, texture.get_height() * 2 + 40)
	target.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


static func decorate_label(target: Label, texture: Texture2D, icon_name: String) -> TextureRect:
	var parent := target.get_parent()
	var index := target.get_index()
	var line := HBoxContainer.new()
	line.name = "%sLine" % target.name
	line.size_flags_horizontal = target.size_flags_horizontal
	line.size_flags_vertical = target.size_flags_vertical
	line.size_flags_stretch_ratio = target.size_flags_stretch_ratio
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	parent.move_child(line, index)
	var image := artwork(texture)
	image.name = icon_name
	line.add_child(image)
	target.reparent(line)
	target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image


static func scrollable_content(screen: Control) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 32)
	screen.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	margin.add_child(scroll)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.get_child(0).add_child(content)
	return content


static func class_name_for(hero: HeroData) -> String:
	return hero.hero_class.display_name if hero.hero_class != null else "Unknown class"


static func class_icon_for(hero: HeroData) -> Texture2D:
	return Art.class_icon(String(hero.hero_class.class_id)) if hero.hero_class != null else Art.UNKNOWN_ICON


static func status_name(hero: HeroData) -> String:
	match hero.status:
		HeroData.HeroStatus.IDLE:
			return "Idle"
		HeroData.HeroStatus.ASSIGNED:
			return "Assigned"
		HeroData.HeroStatus.ON_EXPEDITION:
			return "On expedition"
		HeroData.HeroStatus.RESTING:
			return "Resting"
		HeroData.HeroStatus.WOUNDED:
			return "Wounded"
		HeroData.HeroStatus.DEAD:
			return "Dead"
		_:
			return "Unknown"


static func hero_summary(hero: HeroData) -> String:
	return "%s · Level %d\nStatus: %s" % [
		class_name_for(hero), hero.level, status_name(hero)
	]


static func status_badge(hero: HeroData) -> Label:
	var badge := label(status_name(hero), 24)
	badge.name = "StatusBadge"
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	badge.add_theme_color_override("font_color", Color("#182235"))
	var background := _box(NOTICE_COLOR)
	background.content_margin_left = 12
	background.content_margin_right = 12
	background.content_margin_top = 6
	background.content_margin_bottom = 6
	badge.add_theme_stylebox_override("normal", background)
	return badge


static func hero_header(hero: HeroData) -> HBoxContainer:
	var header := HBoxContainer.new()
	header.name = "HeroHeader"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(portrait(hero))
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(content)
	var name_label := label(hero.hero_name, 34)
	name_label.name = "HeroName"
	content.add_child(name_label)
	var summary := label(hero_summary(hero))
	summary.name = "HeroSummary"
	content.add_child(summary)
	var badges := HBoxContainer.new()
	badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(badges)
	var class_image := artwork(class_icon_for(hero))
	class_image.name = "ClassIcon"
	badges.add_child(class_image)
	var status_image := artwork(Art.status_icon(hero.status))
	status_image.name = "StatusIcon"
	badges.add_child(status_image)
	badges.add_child(status_badge(hero))
	return header


static func refresh_hero_header(parent: Node, hero: HeroData) -> void:
	parent.find_child("HeroSummary", true, false).text = hero_summary(hero)
	parent.find_child("StatusBadge", true, false).text = status_name(hero)
	parent.find_child("StatusIcon", true, false).texture = Art.status_icon(hero.status)


static func hero_row(
	hero: HeroData, open_detail: Callable, hint: String = "View hero details"
) -> Button:
	var row := button("")
	row.set_meta("hero_id", hero.hero_id)
	row.tooltip_text = "View %s's details" % hero.hero_name
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 20)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(margin)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(content)
	content.add_child(hero_header(hero))
	var detail_hint := label(hint, 24)
	detail_hint.name = "DetailHint"
	detail_hint.add_theme_color_override("font_color", MUTED_COLOR)
	content.add_child(detail_hint)
	margin.minimum_size_changed.connect(func() -> void:
		row.custom_minimum_size.y = maxf(144.0, margin.get_combined_minimum_size().y))
	row.custom_minimum_size.y = maxf(144.0, margin.get_combined_minimum_size().y)
	row.pressed.connect(open_detail)
	return row


static func add_attributes_and_stats(parent: VBoxContainer, hero: HeroData) -> void:
	_add_values(parent, "Attributes", "Effective attributes",
		HeroCatalog.ATTRIBUTES, HeroStats.effective_attributes(hero))
	_add_values(parent, "Stats", "Derived stats",
		HeroCatalog.STATS, HeroStats.compute_derived_stats(hero))


static func _add_values(
	parent: VBoxContainer, node_name: String, title: String,
	keys: Array, values: Dictionary
) -> void:
	var section := VBoxContainer.new()
	section.name = node_name
	parent.add_child(section)
	section.add_child(label(title, 30))
	var grid := GridContainer.new()
	grid.name = "Values"
	grid.columns = 2
	section.add_child(grid)
	for key in keys:
		var key_label := label(str(key))
		key_label.name = "%sLabel" % key
		grid.add_child(key_label)
		var value_label := label(_number(values.get(key, 0), str(key)))
		value_label.name = "%sValue" % key
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value_label)


static func _number(value: Variant, key: String) -> String:
	if key in ["Evasion", "CritChance"]:
		return "%s%%" % String.num(float(value) * 100.0, 2)
	if value is float:
		return String.num(value, 2)
	return str(value)


static func add_traits(parent: VBoxContainer, hero: HeroData) -> void:
	var section := VBoxContainer.new()
	section.name = "Traits"
	parent.add_child(section)
	section.add_child(label("Traits", 30))
	var shown := 0
	for hero_trait in hero.traits:
		if hero_trait == null:
			continue
		section.add_child(label(hero_trait.display_name, 28))
		var description := hero_trait.description
		if description.is_empty():
			description = "No trait description available."
		var description_label := label(description, 26)
		description_label.add_theme_color_override("font_color", MUTED_COLOR)
		section.add_child(description_label)
		shown += 1
	if shown == 0:
		section.add_child(label("No traits"))


static func clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


static func save_feedback() -> String:
	var messages := PackedStringArray()
	if not SaveManager.last_error.is_empty():
		messages.append(SaveManager.last_error)
	if not SaveManager.last_warning.is_empty():
		messages.append(SaveManager.last_warning)
	return "\n".join(messages)


static func show_feedback(target: Label, message: String = "") -> void:
	var persistence_message := save_feedback()
	if not persistence_message.is_empty():
		if not message.is_empty():
			message += "\n"
		message += persistence_message
	target.text = message
	target.visible = not message.is_empty()
	target.add_theme_color_override("font_color", NOTICE_COLOR)
