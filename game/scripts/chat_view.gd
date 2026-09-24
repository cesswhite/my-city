extends RefCounted
## A single encounter: quiet layout, distinct voices, exact reply choices.
const INK := Color("303e37")
const MUTED := Color("535f50")
const ACCENT := Color("a85540")
var host: Control
var ui: RefCounted:
	get: return host.resident_ui
var pending_label: Label
var pending_serial := -1
var resident_id := ""

func _init(owner: Control, _panels: RefCounted) -> void:
	host = owner

func _label(parent: Node, content: String, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = content
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_constant_override("line_spacing", 2)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _bubble(column: VBoxContainer, turn: Dictionary) -> Label:
	var mine: bool = turn.get("speaker_id", "") == "player"
	var row := MarginContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("margin_left", 24 if mine else 0)
	row.add_theme_constant_override("margin_right", 0 if mine else 16)
	column.add_child(row)
	var bubble := PanelContainer.new()
	bubble.name = "PlayerMessage" if mine else "NeighborMessage"
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color("dee5d1") if mine else Color("fff9e9")
	skin.content_margin_left = 8
	skin.content_margin_right = 8
	skin.content_margin_top = 6
	skin.content_margin_bottom = 6
	bubble.add_theme_stylebox_override("panel", skin)
	row.add_child(bubble)
	var text: String = str(turn.get("text", ""))
	var label := _label(bubble, "…" if text.is_empty() and turn.get("pending", false) else text)
	label.name = "ChatMessageText"
	bubble.accessibility_name = str(turn.get("name", "Tú" if mine else resident_id)) + ": " + label.text
	bubble.tooltip_text = str(turn.get("name", ""))
	if turn.get("pending", false) and not mine:
		pending_label = label
		pending_serial = int(host.dialogue_job.get("serial", -1))
	return label

func _choice(text: String, index: int, enabled: bool, callback: Callable) -> Button:
	var button: Button = host.button_at(host.inspector, "", Vector2(12, 232 + index * 42), Vector2(230, 38), callback)
	button.name = "ChatSuggestion%d" % index
	button.accessibility_name = text
	button.tooltip_text = text
	button.set_meta("spoken_text", text)
	button.set_meta("chat_bottom", true)
	ui._style(button)
	button.disabled = not enabled
	var caption := Label.new()
	caption.text = text
	caption.position = Vector2(10, 2)
	caption.size = Vector2(210, 34)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_constant_override("line_spacing", 0)
	caption.add_theme_color_override("font_color", MUTED if not enabled else INK)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(caption)
	return button

func build(resident: Dictionary) -> void:
	resident_id = str(resident.id)
	pending_label = null
	pending_serial = -1
	var partner: String = host.chat_partner_id
	var is_self: bool = resident_id == "player"
	var elsewhere: bool = not partner.is_empty() and partner != resident_id
	var nearby: bool = ui._chat_nearby(resident_id)
	var asleep: bool = host.colony.is_sleeping(resident_id)
	var ended: bool = host.player_chat.ended(resident_id)
	var conversation: VBoxContainer = ui._column(40, 184, 8)
	conversation.custom_minimum_size.x = 214
	host.chat_scroll = conversation.get_parent()
	host.chat_scroll.name = "ChatTranscript"
	host.chat_scroll.follow_focus = false
	var turns: Array[Dictionary] = host.player_chat.messages(resident_id)
	if turns.is_empty():
		var empty: String
		if elsewhere: empty = "Estás hablando con %s." % str(host.colony.get_resident(partner).name)
		elif is_self: empty = "Elige a un vecino en el mapa."
		elif asleep: empty = "%s está durmiendo." % str(resident.name)
		elif nearby: empty = "Empieza con un saludo."
		else: empty = "Acércate a %s para conversar." % str(resident.name)
		host.chat_output = _label(conversation, empty, MUTED)
		host.chat_output.name = "ChatEmpty"
	else:
		for turn: Dictionary in turns:
			host.chat_output = _bubble(conversation, turn)
	var error: String = host.chat_error_for(resident_id)
	if not error.is_empty():
		var error_label := _label(conversation, error, ACCENT)
		error_label.name = "ChatError"
	if ended:
		_choice("Cerrar", 0, true, host.close_chat_panel)
	elif elsewhere:
		_choice("Volver a " + str(host.colony.get_resident(partner).name), 0, true, host.return_to_conversation)
	elif not is_self and not nearby and not asleep:
		_choice("Acercarme a " + str(resident.name), 0, true, func(): host.approach_chat(resident_id))
	elif not is_self and not asleep:
		var suggestions: Array = host.chat_suggestions_for(resident_id)
		for index in range(mini(2, suggestions.size())):
			var spoken: String = str(suggestions[index].get("text", ""))
			var caption: String = str(suggestions[index].get("label", spoken)) if suggestions[index].get("action", "") == "retry" else spoken
			_choice(caption, index, ui._chat_can_send(resident_id) and not spoken.is_empty(), ui._send_chat_suggestion.bind(resident_id, spoken))
	_build_composer(resident_id, is_self or elsewhere or asleep or ended)

func _build_composer(id: String, unavailable: bool) -> void:
	host.chat_input = TextEdit.new()
	var input: TextEdit = host.chat_input
	input.name = "ChatComposer"
	input.position = Vector2(12, 320)
	input.size = Vector2(166, 44)
	input.set_meta("chat_bottom", true)
	input.placeholder_text = "Escribe un mensaje…"
	input.text = str(host.chat_drafts.get(id, ""))
	input.editable = not unavailable
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.add_theme_font_size_override("font_size", 16)
	input.add_theme_constant_override("line_spacing", 2)
	input.tooltip_text = "Enter: enviar. Shift+Enter: nueva línea."
	input.accessibility_name = "Mensaje para " + str(host.colony.get_resident(id).name)
	input.add_theme_stylebox_override("normal", host.sprite_box("input"))
	input.add_theme_stylebox_override("focus", host.sprite_box("input_focus"))
	input.add_theme_color_override("font_color", INK)
	input.add_theme_color_override("caret_color", INK)
	input.add_theme_color_override("font_placeholder_color", MUTED)
	host.inspector.add_child(input)
	input.size = Vector2(166, 44)
	host.chat_send = host.button_at(host.inspector, "Enviar", Vector2(186, 320), Vector2(56, 44), host.send_player_dialogue, "Enter: enviar")
	var send: Button = host.chat_send
	send.name = "ChatSend"
	send.set_meta("chat_bottom", true)
	ui._style(send, true)
	send.disabled = not ui._chat_can_send(id) or input.text.strip_edges().is_empty()
	input.visible = not unavailable
	send.visible = not unavailable
	input.text_changed.connect(func():
		host.chat_drafts[id] = input.text
		if is_instance_valid(send): send.disabled = not ui._chat_can_send(id) or input.text.strip_edges().is_empty())

func update_stream(id: String) -> void:
	if id != resident_id: return
	if not is_instance_valid(pending_label) or pending_serial != int(host.dialogue_job.get("serial", -1)):
		host.build_inspector()
		return
	pending_label.text = host.player_chat.compact_reply(host.stream_text) if not host.stream_text.is_empty() else "…"
