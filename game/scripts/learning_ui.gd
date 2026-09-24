extends RefCounted
## The journal explains the next world action; Colony remains authoritative.
const Icons = preload("res://scripts/hud_icons.gd")
const Controls = preload("res://scripts/resident_controls.gd")
const Sidebar = preload("res://scripts/journal_sidebar.gd")
const INK = Color("303e37")
const PAPER = Color("f4edda")
const MUTED = Color("535f50")
const ACCENT = Color("92503b")
const GREEN = Color("476b50")
const STATUS = {"available":"Por empezar", "accepted":"Reúne materiales", "learned":"Para practicar", "completed":"Completado"}

var host: Control
var panel: Panel
var modal_shade: ColorRect
var selected_quest = "bicicleta_de_mateo"
var last_message = ""
var mode = "journal"
var _sidebar: VBoxContainer
var _detail: VBoxContainer
var _primary: Button
var _close_button: Button
var _feedback_ok := true

func _init(owner: Control) -> void:
	host = owner

func close() -> void:
	if is_instance_valid(modal_shade):
		modal_shade.get_parent().remove_child(modal_shade)
		modal_shade.queue_free()
	elif is_instance_valid(panel):
		panel.get_parent().remove_child(panel)
		panel.queue_free()
	panel = null
	modal_shade = null
	_primary = null

func layout() -> void:
	if not is_instance_valid(panel): return
	var extent: Vector2 = host.layout_size()
	panel.size = Vector2(minf(840, extent.x - 48), minf(480, extent.y - 40))
	panel.position = ((extent - panel.size) / 2.0).round()

func _vbox(parent: Node, gap: int = 12) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", gap)
	parent.add_child(box)
	return box

func _hbox(parent: Node, gap: int = 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", gap)
	parent.add_child(box)
	return box

func flow_text(parent: Container, text: String, font_size: int = 16, color: Color = INK) -> Label:
	var label: Label = host.label_at(parent, text, Vector2.ZERO, Vector2.ZERO, font_size, color)
	label.clip_text = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_constant_override("line_spacing", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _icon(parent: Container, id: String) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = Icons.texture(id)
	icon.custom_minimum_size = Vector2(16, 16)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	return icon

func _scroll(parent: Container) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "JournalContent"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.clip_contents = true
	parent.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 8)
	scroll.add_child(margin)
	return _vbox(margin)

func inset_group(parent: Container, fill: Color = Color("e3e8d4")) -> VBoxContainer:
	var surface := PanelContainer.new()
	surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var skin := Controls.surface(fill)
	skin.content_margin_left = 12
	skin.content_margin_right = 12
	skin.content_margin_top = 10
	skin.content_margin_bottom = 10
	surface.add_theme_stylebox_override("panel", skin)
	parent.add_child(surface)
	return _vbox(surface, 4)

func style_button(button: Button, primary: bool = false) -> void:
	Controls.style(button, primary)
	if not primary: button.add_theme_stylebox_override("normal", Controls.surface(Color("e6e7d6")))
	button.add_theme_stylebox_override("disabled", Controls.surface(Color("e7e4d6")))
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_constant_override("h_separation", 8)
	button.add_theme_stylebox_override("focus", Controls.surface(Color.TRANSPARENT, ACCENT))
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.custom_minimum_size.y = 32

func _action(parent: Container, text: String, callback: Callable, id: String, icon_id: String = "", primary: bool = false, hint: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL if primary else Control.SIZE_SHRINK_BEGIN
	button.icon = Icons.texture(icon_id) if not icon_id.is_empty() else null
	button.tooltip_text = hint if not hint.is_empty() else text
	button.accessibility_name = text if not text.is_empty() else hint
	button.set_meta("journal_action", id)
	button.pressed.connect(callback)
	style_button(button, primary)
	if text.is_empty():
		button.custom_minimum_size.x = 36
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elif not primary:
		button.custom_minimum_size.x = host.ui_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 16 + (24 if button.icon != null else 0)
	parent.add_child(button)
	if primary: _primary = button
	return button

func contain_focus() -> void:
	var controls: Array[Control] = []
	for child in panel.find_children("*", "Control", true, false):
		if child.focus_mode == Control.FOCUS_NONE or not child.is_visible_in_tree(): continue
		if child is BaseButton and child.disabled: continue
		controls.append(child)
	if controls.is_empty(): return
	for index in range(controls.size()):
		var current: Control = controls[index]
		var previous: NodePath = current.get_path_to(controls[posmod(index - 1, controls.size())])
		var following: NodePath = current.get_path_to(controls[(index + 1) % controls.size()])
		current.focus_previous = previous
		current.focus_next = following
		current.focus_neighbor_left = previous
		current.focus_neighbor_top = previous
		current.focus_neighbor_right = following
		current.focus_neighbor_bottom = following
	if is_instance_valid(_primary) and not _primary.disabled: _primary.grab_focus()
	else: _close_button.grab_focus()

func frame(title: String) -> void:
	close()
	if is_instance_valid(host.settlement_ui): host.settlement_ui.close()
	if is_instance_valid(host.home_ui): host.home_ui.close()
	host.close_door_panel()
	modal_shade = ColorRect.new()
	modal_shade.color = Color(0.10, 0.16, 0.13, 0.54)
	modal_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(modal_shade)
	modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = Panel.new()
	panel.name = "LearningJournal"
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var skin := Controls.surface(PAPER, Color("b6bba0"))
	skin.shadow_color = Color(0, 0, 0, 0.25)
	skin.shadow_size = 4
	skin.shadow_offset = Vector2(0, 3)
	panel.add_theme_stylebox_override("panel", skin)
	modal_shade.add_child(panel)
	layout()
	var margins := MarginContainer.new()
	panel.add_child(margins)
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]: margins.add_theme_constant_override("margin_" + side, 16)
	var shell := _vbox(margins, 16)
	var header := _hbox(shell, 12)
	_icon(header, "journal")
	var titles := _vbox(header, 2)
	flow_text(titles, title, 20)
	flow_text(titles, "Tus encargos y lo que has aprendido" if mode == "journal" else "Materiales para tus encargos", 16, MUTED)
	_action(header, "Pueblo", func():
		close()
		host.settlement_ui.show_overview(), "town", "home", false, "Ver recursos, proyectos y trabajos del pueblo")
	var wallet := _hbox(header, 6)
	wallet.size_flags_horizontal = Control.SIZE_SHRINK_END
	wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon(wallet, "coin")
	var coins := flow_text(wallet, str(int(host.colony.progression_state().coins)), 16)
	coins.autowrap_mode = TextServer.AUTOWRAP_OFF
	coins.tooltip_text = "Monedas disponibles"
	_close_button = _action(header, "×", close, "close", "", false, "Cerrar diario · Esc")
	_close_button.custom_minimum_size.x = 32
	_close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Controls.style(_close_button)
	var body := _hbox(shell, 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sidebar_surface := PanelContainer.new()
	sidebar_surface.custom_minimum_size.x = 204
	var sidebar_skin := Controls.surface(Color("e5e8d6"))
	for side in ["left", "right", "top", "bottom"]: sidebar_skin.set("content_margin_" + side, 12)
	sidebar_surface.add_theme_stylebox_override("panel", sidebar_skin)
	body.add_child(sidebar_surface)
	_sidebar = _vbox(sidebar_surface, 8)
	_detail = _vbox(body, 12)

func quest_cards() -> void:
	Sidebar.build(self, _sidebar)

func item_name(id: String) -> String:
	return host.colony.progression_item_name(id)

func has_station(station_id: String) -> bool:
	for quest in host.colony.available_apprenticeships():
		if quest.practice_station.id == station_id: return true
	return false

func show_for_mentor(mentor_id: String) -> void:
	for quest in host.colony.available_apprenticeships():
		if quest.mentor_id == mentor_id:
			show_journal(quest.id)
			return
	last_message = "Este vecino no tiene un aprendizaje disponible por ahora."
	_feedback_ok = false
	show_journal()

func show_station(station_id: String) -> void:
	for quest in host.colony.available_apprenticeships():
		if quest.practice_station.id == station_id:
			last_message = ""
			show_journal(quest.id)
			return

func _near_mentor(quest: Dictionary) -> bool:
	return host.colony._distance(host.colony.get_resident("player"), host.colony.get_resident(quest.mentor_id)) < host.colony.MAX_DISTANCE

func _near_station(quest: Dictionary) -> bool:
	var player: Dictionary = host.colony.get_resident("player")
	var station: Dictionary = quest.practice_station
	return player.room == station.room and host.colony._point_distance(player.pos, station.pos) <= float(station.radius)

func _feedback(parent: Container) -> void:
	if last_message.is_empty() or (mode == "journal" and _feedback_ok): return
	flow_text(inset_group(parent, Color("e4e9d7") if _feedback_ok else Color("eedec9")), last_message, 16, GREEN if _feedback_ok else ACCENT)

func _materials(parent: Container, quest: Dictionary, state: Dictionary) -> void:
	var section := _vbox(parent, 6)
	flow_text(section, "Materiales que necesitas", 16, MUTED)
	for id in quest.materials:
		var have: int = int(state.inventory.get(id, 0))
		var needed: int = int(quest.materials[id])
		var row := _hbox(section, 8)
		var check := flow_text(row, "✓" if have >= needed else "○", 16, GREEN if have >= needed else MUTED)
		check.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		check.custom_minimum_size.x = 16
		flow_text(row, item_name(id))
		var count := flow_text(row, "%d / %d" % [have, needed], 16, GREEN if have >= needed else MUTED)
		count.custom_minimum_size.x = 42
		count.size_flags_horizontal = Control.SIZE_SHRINK_END
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.autowrap_mode = TextServer.AUTOWRAP_OFF

func _procedure(parent: Container, quest: Dictionary, status: Dictionary) -> void:
	var section := _vbox(parent, 6)
	var done: int = int(status.get("step_index", 0))
	flow_text(section, "Práctica · %d de %d pasos" % [done, quest.steps.size()], 16, MUTED)
	for index in range(quest.steps.size()):
		var row := _hbox(section, 8)
		var color: Color = GREEN if index < done else INK if index == done else MUTED
		var number := flow_text(row, "✓" if index < done else str(index + 1), 16, color)
		number.custom_minimum_size.x = 16
		number.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		flow_text(row, str(quest.steps[index].label), 16, color)

func _lore(parent: Container, quest: Dictionary) -> void:
	var group := _vbox(parent, 8)
	var toggle := _action(group, "Sobre este encargo", func(): pass, "lore", "journal")
	toggle.toggle_mode = true
	Controls.style(toggle)
	var story := flow_text(group, str(quest.lore), 16, MUTED)
	story.hide()
	toggle.toggled.connect(func(open: bool): story.visible = open)

func show_journal(quest_id: String = "") -> void:
	if not quest_id.is_empty() and quest_id != selected_quest: last_message = ""
	if not quest_id.is_empty(): selected_quest = quest_id
	if mode != "journal": last_message = ""
	mode = "journal"
	var available: Array = host.colony.available_apprenticeships()
	if not available.any(func(entry): return entry.id == selected_quest) and not available.is_empty():
		selected_quest = str(available[0].id)
	frame("Diario")
	quest_cards()
	var quest: Dictionary = {}
	for entry in host.colony.available_apprenticeships():
		if entry.id == selected_quest: quest = entry
	var content := _scroll(_detail)
	if quest.is_empty():
		flow_text(content, "Elige un encargo", 20)
		flow_text(content, "Aquí verás qué necesitas y cómo seguir.", 16, MUTED)
		contain_focus()
		return
	var state: Dictionary = host.colony.progression_state()
	var status: Dictionary = host.colony.quest_status(quest.id)
	_feedback(content)
	var heading := _vbox(content, 4)
	flow_text(heading, str(quest.title), 20)
	var subtitle := _hbox(heading, 12)
	flow_text(subtitle, "Con " + str(quest.mentor_name), 16, MUTED)
	var status_label := flow_text(subtitle, "Materiales listos" if quest.status == "accepted" and status.has_materials else str(STATUS.get(quest.status, quest.status)), 16, GREEN if quest.status == "completed" else ACCENT)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var next := inset_group(content)
	flow_text(next, "Lo que aprendiste" if quest.status == "completed" else "Qué hacer ahora", 16, GREEN)
	var hint: String
	match quest.status:
		"available": hint = "Habla con %s para empezar este encargo." % quest.mentor_name
		"accepted": hint = "Lleva los materiales a %s. Puedes entregarlos donde esté." % quest.mentor_name if status.has_materials else "Compra lo que falta en la tienda y llévaselo a %s." % quest.mentor_name
		"learned": hint = "En tu casa, completa el siguiente paso: " + str(status.next_step_label) + "."
		_: hint = str(quest.procedure_name)
	flow_text(next, hint)
	if quest.status in ["available", "accepted"]: _materials(content, quest, state)
	else: _procedure(content, quest, status)
	if quest.status == "completed":
		var rewards := _vbox(content, 4)
		flow_text(rewards, "Lo que conseguiste", 16, MUTED)
		for id in quest.produces: flow_text(rewards, item_name(id), 16, GREEN)
	_lore(content, quest)
	if quest.status != "completed": _journal_actions(quest, status)
	contain_focus()

func _journal_actions(quest: Dictionary, status: Dictionary) -> void:
	var rail := _vbox(_detail, 4)
	var row := _hbox(rail, 8)
	var near: bool = _near_mentor(quest)
	var primary_id: String
	if quest.status == "available" and near:
		primary_id = "start"
		_action(row, "Aceptar encargo", func():
			host.take_control()
			apply_result(host.colony.start_apprenticeship(quest.id)), primary_id, "people", true, "Pedir a %s que me enseñe" % quest.mentor_name)
	elif quest.status == "accepted" and status.has_materials and near:
		primary_id = "deliver"
		_action(row, "Entregar materiales", func():
			host.take_control()
			apply_result(host.colony.deliver_apprenticeship(quest.id)), primary_id, "seed", true, "Entregar materiales y recibir la lección")
	elif quest.status == "accepted" and not status.has_materials:
		primary_id = "shop"
		_action(row, "Ir a la tienda", host.walk_to_shop, primary_id, "coin", true)
	elif quest.status == "learned":
		if _near_station(quest):
			primary_id = "practice"
			var current: Dictionary = quest.steps[int(status.step_index)]
			_action(row, "Hacer paso %d" % [int(status.step_index) + 1], func():
				host.take_control()
				apply_result(host.colony.perform_procedure(quest.procedure_id, current.id)), primary_id, "hand", true, str(current.label))
		else:
			primary_id = "station"
			_action(row, "Ir al proyecto", func(): host.walk_to_station(quest.practice_station), primary_id, "home", true, "Caminar hasta este proyecto en tu casa")
	else:
		primary_id = "mentor"
		_action(row, "Ir con " + str(quest.mentor_name), func(): host.walk_to_mentor(quest.mentor_id), primary_id, "people", true)
	if quest.status in ["available", "accepted"]:
		if primary_id != "mentor": _action(row, "", func(): host.walk_to_mentor(quest.mentor_id), "mentor", "people", false, "Ir con " + str(quest.mentor_name))
		if primary_id != "shop" and quest.status == "accepted": _action(row, "", host.walk_to_shop, "shop", "coin", false, "Ir a la tienda")

func show_shop() -> void:
	if mode != "shop": last_message = ""
	mode = "shop"
	frame("Tienda del barrio")
	quest_cards()
	var column := _scroll(_detail)
	_feedback(column)
	flow_text(column, "Para tus proyectos", 20)
	flow_text(column, "Compra lo que falta para un encargo aceptado.", 16, MUTED)
	_action(column, "Vender recursos del pueblo", func():
		close()
		host.settlement_ui.show_market(), "market", "coin")
	var state: Dictionary = host.colony.progression_state()
	for item in host.colony.shop_catalog():
		var row := inset_group(column, Color("ebe9da"))
		flow_text(row, str(item.name))
		var pending: bool = int(item.available_quantity) > 0
		var affordable: bool = int(state.coins) >= int(item.price)
		var reason := "Necesitas %d" % int(item.available_quantity) if pending else "Sin material pendiente"
		if pending and not affordable: reason = "Te faltan %d monedas" % (int(item.price) - int(state.coins))
		elif not pending:
			var quest_state: Dictionary = host.colony.quest_status(item.quest_id)
			reason = "Acepta primero el encargo" if quest_state.status == "available" else "Ya tienes lo necesario" if quest_state.status == "accepted" else "Material entregado"
		flow_text(row, reason, 16, MUTED)
		var actions := _hbox(row)
		flow_text(actions, "%d monedas" % int(item.price), 16, MUTED)
		var buy := _action(actions, "Comprar 1", func():
			host.take_control()
			apply_result(host.colony.buy_item(item.id)), "buy", "coin", pending and affordable and not is_instance_valid(_primary), "Comprar una unidad de " + str(item.name))
		buy.set_meta("item_id", item.id)
		buy.disabled = not pending or not affordable
	contain_focus()

func apply_result(result: Dictionary) -> void:
	last_message = str(result.get("message", "No se pudo realizar esa acción."))
	_feedback_ok = bool(result.get("ok", false))
	host.message(last_message)
	host.scenery.interior_state = host.home_project_state()
	host.scenery.queue_redraw()
	host.actors.queue_redraw()
	if mode == "shop": show_shop()
	else: show_journal()

func knowledge_lines() -> Array[String]:
	var lines: Array[String] = []
	var state: Dictionary = host.colony.progression_state()
	for quest in host.colony.available_apprenticeships():
		if state.procedures.has(quest.procedure_id):
			var procedure: Dictionary = state.procedures[quest.procedure_id]
			lines.append(str(quest.title).to_upper() + "\n" + ("Lo demostraste en casa." if procedure.world_verified else "Conoces el procedimiento; falta aplicarlo.") + "\nTe enseñó " + str(quest.mentor_name) + ".")
	return lines
