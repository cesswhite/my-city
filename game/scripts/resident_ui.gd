extends RefCounted
## Resident panels share a scrollable reading area and a separate action area.

const INK = Color("303e37")
const PAPER = Color("f4edda")
const MUTED = Color("535f50")
const ACCENT = Color("a85540")
const BORDER = Color("c4c6a8")
const SURFACE = Color("fff9e9")
const ChatView = preload("res://scripts/chat_view.gd")
const RelationshipUI = preload("res://scripts/relationship_ui.gd")
const Controls = preload("res://scripts/resident_controls.gd")
var chat_view: RefCounted
var relationship_block: VBoxContainer
var relationship_owner: String = ""
var relationship_disclosure: String = ""

var host: Control
var appearance_scroll: Dictionary = {}

func _init(owner: Control) -> void:
	host = owner

func _column(y: float, height: float, spacing: int = 12) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(12, y)
	scroll.size = Vector2(230, height)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	host.inspector.add_child(scroll)
	var column = VBoxContainer.new()
	column.custom_minimum_size.x = 214
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", spacing)
	scroll.add_child(column)
	return column

func _text(parent: Node, content: String, font_size: int = 16, color: Color = INK) -> Label:
	var label = Label.new()
	label.text = content
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _group(parent: Node, heading: String, content: String, color: Color = INK) -> Label:
	var group = VBoxContainer.new()
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_theme_constant_override("separation", 4)
	parent.add_child(group)
	_text(group, heading, 16, ACCENT)
	return _text(group, content, 16, color)

func _style(button: Button, primary: bool = false) -> void:
	button.add_theme_font_size_override("font_size", 16)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if host.has_method("style_button"):
		host.style_button(button, primary)
		return
	button.add_theme_stylebox_override("normal", host.box(INK if primary else PAPER, INK if primary else BORDER))
	button.add_theme_stylebox_override("hover", host.box(Color("435847") if primary else Color("e4e6cc"), INK))
	button.add_theme_stylebox_override("pressed", host.box(ACCENT, ACCENT))
	button.add_theme_stylebox_override("focus", host.box(Color.TRANSPARENT, ACCENT, 2))
	button.add_theme_color_override("font_color", PAPER if primary else INK)
	button.add_theme_color_override("font_hover_color", PAPER if primary else INK)
	button.add_theme_color_override("font_pressed_color", PAPER)

func _page(name: String) -> void:
	host.page = name
	host.build_inspector()

func build_story(resident: Dictionary) -> void:
	var column = _column(84, 224)
	_text(column, str(resident.role), 16, MUTED)
	if resident.id != "player":
		relationship_owner = str(resident.id)
		var relationship: Dictionary = host.colony.relationship_for(relationship_owner, "player")
		relationship_disclosure = str(relationship.get("disclosure", "public"))
		relationship_block = RelationshipUI.build(column, relationship)
	host.activity_label = _group(column, "Ahora", str(resident.activity))
	var profile: Dictionary = host.colony.visible_profile_for(str(resident.id), "player")
	var biography: String = str(profile.get("biography", ""))
	_group(column, "Tu historia" if resident.id == "player" else "Su historia", biography if not biography.is_empty() else "Aún no te ha contado su historia.")
	var personality: Array = profile.get("personality", [])
	if not personality.is_empty(): _group(column, "Personalidad", " · ".join(personality))
	var goal: String = str(profile.get("goal", ""))
	if not goal.is_empty(): _group(column, "Lo que desea", goal)
	Controls.action_bar(host, [
		{"icon":"people", "title":"Conversar", "name":"ResidentTalk", "callback":host.talk_nearby, "primary":true, "hint":"Acércate para hablar"},
		{"icon":"seed", "title":"Encargos y aprendizajes", "name":"ResidentLearning", "callback":func(): host.learning.show_for_mentor(host.selected_id)},
		{"icon":"hand", "title":"Pedir ayuda", "name":"ResidentWork", "callback":func(): host.settlement_ui.show_person(host.selected_id)},
		{"icon":"clock", "title":"Ver su horario", "name":"ResidentSchedule", "callback":func(): _page("agenda")}
	])

func refresh_relationship() -> void:
	if not is_instance_valid(relationship_block) or relationship_owner.is_empty(): return
	if host.page != "historia" or host.selected_id != relationship_owner: return
	var snapshot: Dictionary = host.colony.relationship_for(relationship_owner, "player")
	if str(snapshot.get("disclosure", "public")) != relationship_disclosure:
		# Keep an already open profile consistent when its disclosure level changes.
		host.build_inspector()
		return
	RelationshipUI.update(relationship_block, snapshot)

func build_schedule(resident: Dictionary) -> void:
	var player: bool = resident.id == "player"
	var column = _column(84, 224)
	_text(column, "Un día en su vida", 16, ACCENT)
	var explanation = "Sus horarios pueden variar un poco cada día."
	if player:
		explanation = "Este horario guía a tu personaje al activar Vivir solo. Cuando tomas el control, tú decides."
	_text(column, explanation, 16, MUTED)
	var schedule: Array = resident.get("schedule", [])
	if schedule.is_empty():
		_text(column, "Todavía no tiene actividades programadas.")
	var now: int = int(host.colony.minute) % 1440
	for entry in schedule:
		var active: bool = now >= int(entry.start) and now < int(entry.end)
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		column.add_child(row)
		var hour = _text(row, "%02d:%02d" % [int(entry.start) / 60, int(entry.start) % 60], 16, ACCENT if active else MUTED)
		hour.custom_minimum_size.x = 38
		hour.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var details = VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_theme_constant_override("separation", 4)
		row.add_child(details)
		_text(details, str(entry.label), 16)
		if active:
			_text(details, "Franja actual", 16, ACCENT)
	var actions: Array = [{"icon":"journal", "title":"Volver a su historia", "callback":func(): _page("historia")}]
	if player: actions.push_front({"icon":"people", "title":"Reunir al barrio en el café", "callback":host.gather_neighbors, "primary":true})
	Controls.action_bar(host, actions)

func build_memories(resident: Dictionary) -> void:
	var column = _column(84, 272, 16)
	var own: bool = resident.id == "player"
	var memories: Array[Dictionary] = visible_memories(resident)
	if own: _build_own_knowledge(column, resident)
	else: _text(column, "Momentos compartidos contigo.", 16, MUTED)
	_text(column, ("Experiencias · %d" if own else "Recuerdos contigo · %d") % memories.size(), 16, ACCENT)
	if memories.is_empty():
		_text(column, "Tus encuentros y aprendizajes aparecerán aquí, con su origen y fecha." if own else "Cuando conversen o hagan algo juntos, podrás recordarlo aquí.")
	for i in range(memories.size() - 1, maxi(-1, memories.size() - 21), -1):
		var memory: Dictionary = memories[i]
		var experience = VBoxContainer.new()
		experience.add_theme_constant_override("separation", 4)
		column.add_child(experience)
		var origin: String = "Conversación" if memory.get("kind", "") == "conversacion" else str(memory.get("origin", ""))
		_text(experience, str(memory.get("time", "")) + " · " + origin, 16, MUTED)
		_text(experience, str(memory.get("content", "")))
	var scroll: ScrollContainer = column.get_parent()
	scroll.set_deferred("scroll_vertical", int(host.memory_scroll.get(resident.id, 0)))

static func visible_memories(resident: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for memory: Dictionary in resident.get("memories", []):
		var participants: Array = memory.get("participants", [])
		if resident.id == "player" or (resident.id in participants and "player" in participants): result.append(memory)
	return result

func _build_own_knowledge(column: VBoxContainer, resident: Dictionary) -> void:
	var known: Array[String] = []
	for person_id in resident.known_people:
		var person: Dictionary = host.colony.get_resident(person_id)
		known.append(str(person.get("name", person_id)))
	_group(column, "Conoce a", ", ".join(known) if not known.is_empty() else "Todavía no se ha presentado.")
	var skills: Dictionary = resident.skills
	if skills.is_empty():
		_group(column, "Conocimientos", "Los oficios se aprenden con los vecinos y se demuestran al practicar.")
	else:
		for skill_id in skills:
			var skill: Dictionary = skills[skill_id]
			var section = VBoxContainer.new()
			section.add_theme_constant_override("separation", 4)
			column.add_child(section)
			_text(section, str(skill.get("name", skill_id.replace("_", " "))), 16, MUTED)
			_text(section, "Aprendizaje demostrado" if skill.get("status") == "demostrada" else "Conoce las instrucciones; falta practicar.")
			if not str(skill.get("source", "")).is_empty():
				_text(section, str(skill.source), 16, MUTED)

func _chat_nearby(resident_id: String) -> bool:
	var player: Dictionary = host.colony.get_resident("player")
	var resident: Dictionary = host.colony.get_resident(resident_id)
	return not resident.is_empty() and resident_id != "player" and player.get("room", "street") == resident.get("room", "street") and host.position_of(player).distance_to(host.position_of(resident)) < 45.0

func _chat_can_send(resident_id: String) -> bool:
	if host.player_chat.ended(resident_id): return false
	var partner: String = host.chat_partner_id
	return not host.colony.is_sleeping(resident_id) and _chat_nearby(resident_id) and (partner.is_empty() or partner == resident_id) and not host.chat_busy()

func _send_chat_suggestion(resident_id: String, text: String) -> void:
	# Recheck on activation: a walking neighbor may have moved since this panel built.
	if text.strip_edges().is_empty() or not _chat_can_send(resident_id):
		return
	if host.chat_partner_id != resident_id and not host.start_player_conversation(resident_id):
		return
	host.send_chat_text(text)

func build_chat(resident: Dictionary) -> void:
	chat_view = ChatView.new(host, self)
	chat_view.build(resident)

func update_chat_stream(id: String) -> void:
	if is_instance_valid(chat_view): chat_view.update_stream(id)

func build_appearance(resident: Dictionary) -> void:
	var editable: bool = host.can_edit_appearance(str(resident.id))
	# Main draws the enlarged sprite to the right of these name controls.
	host.label_at(host.inspector, "Nombre", Vector2(12, 84), Vector2(136, 16), 16, ACCENT)
	var name_edit = LineEdit.new()
	name_edit.position = Vector2(12, 108)
	name_edit.size = Vector2(136, 28)
	name_edit.text = resident.name
	name_edit.max_length = 20
	name_edit.placeholder_text = "Nombre"
	name_edit.editable = editable
	if not editable:
		name_edit.focus_mode = Control.FOCUS_NONE
		name_edit.add_theme_color_override("font_uneditable_color", INK)
	name_edit.add_theme_font_size_override("font_size", 16)
	name_edit.add_theme_stylebox_override("normal", host.sprite_box("input") if host.has_method("sprite_box") else host.box(SURFACE, BORDER))
	name_edit.add_theme_stylebox_override("focus", host.sprite_box("input_focus") if host.has_method("sprite_box") else host.box(SURFACE, ACCENT, 2))
	name_edit.text_changed.connect(func(value: String):
		if not host.can_edit_appearance(str(resident.id)): return
		if not value.strip_edges().is_empty(): resident.name = value.strip_edges()
		host.queue_redraw())
	host.inspector.add_child(name_edit)
	host.label_at(host.inspector, "Tu estilo, a tu ritmo" if editable else "Aspecto actual", Vector2(12, 144), Vector2(142, 16), 16, MUTED)
	var column = _column(172, 166, 12)
	for spec in host.APPEARANCE:
		var value: int = posmod(int(resident.appearance.get(spec[0], 0)), spec[2].size())
		var row = HBoxContainer.new()
		row.custom_minimum_size.y = 40
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		column.add_child(row)
		var details = VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_theme_constant_override("separation", 4)
		row.add_child(details)
		_text(details, str(spec[1]), 16, MUTED)
		_text(details, str(spec[2][value]), 16)
		if not editable: continue
		for direction in [-1, 1]:
			var button = Button.new()
			button.text = "<" if direction == -1 else ">"
			button.custom_minimum_size = Vector2(28, 32)
			button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			button.tooltip_text = ("Anterior: " if direction == -1 else "Siguiente: ") + str(spec[1]).to_lower()
			button.pressed.connect(func():
				appearance_scroll[resident.id] = (column.get_parent() as ScrollContainer).scroll_vertical
				host.change_look(spec, direction))
			row.add_child(button)
			Controls.style(button)
	(column.get_parent() as ScrollContainer).set_deferred("scroll_vertical", int(appearance_scroll.get(resident.id, 0)))
	if editable or resident.id == "player":
		host.label_at(host.inspector, "Guarda para conservar tus cambios." if editable else "Personaliza en el clóset de tu casa.", Vector2(12, 346), Vector2(230, 16), 16, MUTED)
