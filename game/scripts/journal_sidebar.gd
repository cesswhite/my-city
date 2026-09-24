extends RefCounted
## Container-only navigation and inventory. The journal owns every action/state change.
const Icons = preload("res://scripts/hud_icons.gd")
const FONT = preload("res://assets/fonts/PixelOperator.ttf")
const INK := Color("303e37")
const MUTED := Color("535f50")
const PAPER := Color("fff6e4")
const ACTIVE := Color("3f5846")
const ACCENT := Color("d8bd82")

static func _label(parent: Node, text: String, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_constant_override("line_spacing", 4)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

static func _surface(fill: Color, selected: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.anti_aliasing = false
	style.border_color = ACCENT
	style.border_width_left = 3 if selected else 0
	# A MarginContainer supplies the same content inset in every visual state.
	style.set_content_margin_all(0)
	return style

static func _scroll(parent: Container, name: String, minimum_height: float, expand: bool) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = name
	scroll.custom_minimum_size.y = minimum_height
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL if expand else Control.SIZE_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.clip_contents = true
	parent.add_child(scroll)
	return scroll

static func _quest_icon(quest: Dictionary) -> String:
	var station: Dictionary = quest.get("practice_station", {})
	return {"bicycle": "bicycle", "planting": "seed", "tea_station": "journal"}.get(str(station.get("id", "")), "journal")

static func _card(ui: RefCounted, parent: Container, quest: Dictionary) -> void:
	var quest_id: String = str(quest.id)
	var selected: bool = str(ui.selected_quest) == quest_id and str(ui.mode) == "journal"
	var status: String = str(ui.STATUS.get(str(quest.status), str(quest.status)))
	if quest.status == "accepted" and ui.host.colony.quest_status(quest_id).get("has_materials", false): status = "Materiales listos"
	var mentor: String = str(quest.get("mentor_name", ""))
	var title: String = str(quest.get("short_title", quest.title))
	var card := Button.new()
	card.name = "QuestCard_" + quest_id
	card.text = ""
	card.custom_minimum_size.y = 48
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.toggle_mode = true
	card.set_pressed_no_signal(selected)
	card.set_meta("quest_id", quest_id)
	card.set_meta("selected", selected)
	card.tooltip_text = "%s\n%s · %s" % [str(quest.title), mentor, status]
	card.accessibility_name = str(quest.title)
	card.accessibility_description = "%s · %s" % [mentor, status]
	card.add_theme_stylebox_override("normal", _surface(ACTIVE if selected else Color("f4efdd"), selected))
	card.add_theme_stylebox_override("hover", _surface(Color("4a6651") if selected else Color("e0e5ce"), selected))
	card.add_theme_stylebox_override("pressed", _surface(Color("354b3b") if selected else Color("d3dcc2"), selected))
	card.add_theme_stylebox_override("hover_pressed", _surface(Color("4a6651") if selected else Color("d3dcc2"), selected))
	var focus: StyleBoxFlat = _surface(Color.TRANSPARENT)
	focus.border_color = ACCENT if selected else Color("985239")
	focus.set_border_width_all(2)
	card.add_theme_stylebox_override("focus", focus)
	parent.add_child(card)
	var inset := MarginContainer.new()
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_theme_constant_override("margin_left", 10)
	inset.add_theme_constant_override("margin_right", 8)
	inset.add_theme_constant_override("margin_top", 6)
	inset.add_theme_constant_override("margin_bottom", 6)
	card.add_child(inset)
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(content)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 6)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(heading)
	var icon := TextureRect.new()
	icon.texture = Icons.texture(_quest_icon(quest))
	icon.custom_minimum_size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(icon)
	var caption: Label = _label(heading, title, PAPER if selected else INK)
	caption.name = "QuestTitle"
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.clip_text = true
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var details := HBoxContainer.new()
	details.add_theme_constant_override("separation", 4)
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(details)
	var author: Label = _label(details, mentor, Color("d9dfcb") if selected else MUTED)
	author.name = "Mentor"
	author.custom_minimum_size.x = minf(42, FONT.get_string_size(mentor, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x)
	author.clip_text = true
	author.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var state: Label = _label(details, status, PAPER if selected else INK)
	state.name = "QuestStatus"
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	card.pressed.connect(func(): ui.show_journal(quest_id))

static func build(ui: RefCounted, parent: Container) -> void:
	if parent is BoxContainer: parent.add_theme_constant_override("separation", 4)
	_label(parent, "Encargos")
	var quests: ScrollContainer = _scroll(parent, "QuestList", 160, true)
	quests.accessibility_name = "Encargos"
	var cards := VBoxContainer.new()
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 6)
	quests.add_child(cards)
	for quest: Dictionary in ui.host.colony.available_apprenticeships(): _card(ui, cards, quest)
	var separator := HSeparator.new()
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := StyleBoxLine.new()
	line.color = Color("c3cbb4")
	line.thickness = 1
	separator.add_theme_stylebox_override("separator", line)
	separator.add_theme_constant_override("separation", 4)
	parent.add_child(separator)
	var inventory: Dictionary = ui.host.colony.progression_state().get("inventory", {})
	var goods: Array[String] = []
	var count := 0
	for id: String in inventory:
		var quantity := int(inventory[id])
		if quantity <= 0: continue
		goods.append(id)
		count += quantity
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	parent.add_child(heading)
	var bag_title: Label = _label(heading, "Mochila")
	bag_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var total: Label = _label(heading, str(count), MUTED)
	total.name = "InventoryCount"
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.tooltip_text = "%d objetos en tu mochila" % count
	heading.mouse_filter = Control.MOUSE_FILTER_PASS
	var bag: ScrollContainer = _scroll(parent, "InventoryList", 64, false)
	bag.accessibility_name = "Contenido de tu mochila"
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag.add_child(rows)
	if goods.is_empty():
		var empty: Label = _label(rows, "Tu mochila está vacía.", MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id: String in goods:
		var row := HBoxContainer.new()
		row.name = "Item_" + id
		row.set_meta("item_id", id)
		row.add_theme_constant_override("separation", 8)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_child(row)
		var item: Label = _label(row, str(ui.item_name(id)))
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var amount: Label = _label(row, "×%d" % int(inventory[id]), MUTED)
		amount.name = "Quantity"
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
