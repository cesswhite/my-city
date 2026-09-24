extends SceneTree
## Rendered encounter, literal choices, live typing, and clean re-entry. No providers/save.
const Navigation = preload("res://scripts/navigation.gd")
class Probe:
	extends "res://scripts/main.gd"
	var calls: Array[String] = []
	func request_dialogue(_id: String, _speaker: String, utterance: String) -> void:
		calls.append(utterance)
		stream_text = ""
	func decide_with_jev() -> void: pass

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if value: print("PASS: " + description)
	else:
		failures.append(description)
		push_error(description)

func settle() -> void:
	for _frame in range(5): await process_frame

func visible_text(node: Node) -> String:
	var text := ""
	if node is Control and not node.is_visible_in_tree(): return text
	if node is Label or node is Button: text = node.text + "\n"
	for child in node.get_children(): text += visible_text(child)
	return text

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		quit(1)
		return
	root.size = Vector2i(768, 432)
	var scene := Probe.new()
	root.add_child(scene)
	scene.colony._social._willingness_roll = func(): return 1.0
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_token = "isolated-no-network"
	scene.paused = true
	for id in ["player", "mateo"]:
		var person: Dictionary = scene.colony.get_resident(id)
		person.room = "street"
		# Keep this encounter on the plaza's open walking area. The previous
		# coordinates intersect plaza_flowers in the connected-neighborhood layout.
		person.pos = [260 if id == "mateo" else 236, 210]
		person.target = person.pos.duplicate()
		person.travel_intent = ""
	scene.colony.get_resident("player").name = "Céss"
	expect(Navigation._clear_segment(Vector2(236,210), Vector2(260,210), "street"), "the fixture speakers have a clear conversation path in the current neighborhood")
	expect(scene.colony.record_dialogue("player", "mateo", "Esta charla pertenece al pasado.", "Un recuerdo que sigue guardado.", "fixture"), "the fixture seeds a valid completed shared memory before opening the clean chat")
	scene.start_player_conversation("mateo")
	scene.build_inspector()
	await settle()
	expect(not visible_text(scene.inspector).contains("pasado") and scene.player_chat.messages("mateo").is_empty(), "a fresh encounter shows no saved transcript")
	for unwanted in ["OpenAI", "Tu turno", "respuesta en directo", "Historia", "Memoria", "Aspecto", "Enter:"]:
		expect(not visible_text(scene.inspector).contains(unwanted), "chat excludes unnecessary label: " + unwanted)
	expect(not scene.provider_label.visible, "world notices do not display the provider badge")
	var hello := scene.inspector.find_child("ChatSuggestion0", true, false) as Button
	var spoken: String = hello.get_meta("spoken_text")
	hello.pressed.emit()
	expect(scene.calls == [spoken], "clicking a choice sends exactly its visible sentence")
	await settle()
	var input_id: int = scene.chat_input.get_instance_id()
	scene.chat_input.text = "¿Qué herramientas necesito?"
	scene.chat_input.text_changed.emit()
	scene.chat_input.grab_focus()
	scene.chat_input.set_caret_column(8)
	scene._dialogue_delta("Bien, gracias. Podemos revisar tu bicicleta.")
	await settle()
	expect(scene.chat_input.get_instance_id() == input_id and scene.chat_input.has_focus() and scene.chat_input.get_caret_column() == 8, "streaming changes only the pending bubble and preserves the editor")
	expect(scene.inspector.find_children("PlayerMessage", "PanelContainer", true, false).size() == 1 and scene.inspector.find_children("NeighborMessage", "PanelContainer", true, false).size() == 1, "player and neighbor each have their own message bubble")
	scene._dialogue_completed({"text": "Bien, gracias. Podemos revisar tu bicicleta.", "suggestions": ["¿Qué reviso primero en la bici?", "¿Qué herramientas necesito?"]})
	await settle()
	expect(scene.chat_input.text == "¿Qué herramientas necesito?", "completion preserves text composed during the reply")
	scene.send_chat_text("Quiero arreglar mi bicicleta.")
	scene._dialogue_delta("Primero consigue aceite en la tienda. Luego revisamos juntos la cadena.")
	scene._dialogue_completed({"text": "Primero consigue aceite en la tienda. Luego revisamos juntos la cadena.", "suggestions": ["¿Dónde está la tienda?", "¿Cuánto aceite necesito?"]})
	scene.chat_input.text = ""
	scene.chat_input.text_changed.emit()
	scene.chat_input.release_focus()
	scene.refresh_status()
	await settle()
	for size: Vector2i in [Vector2i(768, 432), Vector2i(960, 600)]:
		root.size = size
		await settle()
		var first := scene.inspector.find_child("ChatSuggestion0", true, false) as Button
		var second := scene.inspector.find_child("ChatSuggestion1", true, false) as Button
		expect(scene.chat_scroll.get_rect().end.y < first.position.y and first.get_rect().end.y < second.position.y and second.get_rect().end.y < scene.chat_input.position.y, "%s separates transcript, full reply options and composer" % size)
		expect(scene.inspector.get_rect().size.y >= scene.chat_send.get_rect().end.y and not scene.chat_input.get_rect().intersects(scene.chat_send.get_rect()), "%s keeps the editor and send button inside the panel" % size)
		for choice: Button in [first, second]:
			var caption := choice.get_child(0) as Label
			expect(caption.text == str(choice.get_meta("spoken_text")) and caption.get_line_count() <= 2 and caption.get_minimum_size().y <= 34, "the actual suggested sentence fits without ellipsis")
	var destination: String = OS.get_environment("MY_CITY_CAPTURE")
	if not destination.is_empty():
		root.size = Vector2i(768, 432)
		await settle()
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(destination) == OK, "chat screenshot exported")
	scene.close_chat_panel()
	expect(scene.page == "historia" and scene.chat_partner_id.is_empty(), "close returns to the profile and ends the encounter")
	scene.start_player_conversation("mateo")
	scene.build_inspector()
	await settle()
	expect(scene.player_chat.messages("mateo").is_empty() and scene.chat_input.text.is_empty() and not visible_text(scene.inspector).contains("cadena"), "the next encounter starts with a clean transcript and composer")
	expect(not scene.colony.context_for("mateo", "player", "¿Recuerdas mi bici?").recent_conversation.is_empty(), "the neighbor still receives actual shared memories")
	scene.close_chat_panel()
	scene.page = "hablar"
	scene.build_inspector()
	scene.chat_input.text = "Un borrador antes del saludo"
	scene.close_chat_panel()
	scene.page = "hablar"
	scene.build_inspector()
	expect(scene.chat_input.text.is_empty(), "closing before the first greeting also clears a prepared draft")
	scene.open_inspector("mateo", "recuerdos")
	await settle()
	expect(not visible_text(scene.inspector).contains("OpenAI") and visible_text(scene.inspector).contains("Conversación"), "memory cards retain the experience without exposing provider metadata")
	scene.free()
	await process_frame
	print("CHAT VIEW: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
