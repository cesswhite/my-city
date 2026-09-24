extends SceneTree
## Real controller, widgets, clock, input and SSE parser; the request boundary is in memory.
## Requires -- --ui-test so this fixture never reads or writes the player's save.
const Navigation = preload("res://scripts/navigation.gd")
const Layout = preload("res://scripts/world_layout.gd")

class MainProbe:
	extends "res://scripts/main.gd"
	var dialogue_calls: Array[Dictionary] = []

	func request_dialogue(resident_id: String, speaker_id: String, utterance: String) -> void:
		if dialogue_job.is_empty(): return
		dialogue_calls.append({"resident_id": resident_id, "speaker_id": speaker_id, "utterance": utterance, "serial": dialogue_job.serial})
		stream_text = ""
		stream_prefix = colony.get_resident(resident_id).name + ": "
		# Exercise the production parser and connected signals without opening a socket.
		dialogue_request._reset_state()
		dialogue_request.busy = true
		dialogue_request.set_process(false)

	func decide_with_jev() -> void:
		pass # An accidental scheduler dispatch cannot reach a provider in this fixture.

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func settle() -> void:
	for _frame in range(4): await process_frame

func fixture() -> MainProbe:
	var scene = MainProbe.new()
	root.add_child(scene)
	scene.colony._social._willingness_roll = func(): return 1.0
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.set_process(false)
	scene.save_allowed = false
	scene.controls_active = false
	scene.use_jev = false
	scene.service_token = "offline-test-never-sent"
	scene.service_url = ""
	for resident in scene.colony.residents:
		resident.room = resident.id
		resident.pos = [88.0, 212.0]
		resident.target = resident.pos.duplicate()
		resident.travel_intent = ""
	place(scene, "player", Vector2(236, 210))
	place(scene, "mateo", Vector2(260, 210))
	scene.update_room()
	scene.selected_id = "mateo"
	scene.page = "hablar"
	scene.build_inspector()
	return scene

func place(scene, id: String, point: Vector2, room: String = "street") -> void:
	var resident: Dictionary = scene.colony.get_resident(id)
	resident.room = room
	resident.pos = [point.x, point.y]
	resident.target = resident.pos.duplicate()
	resident.travel_intent = ""
	scene.paths.erase(id)

func event(scene, kind: String, data: Dictionary) -> void:
	scene.dialogue_request._accept_bytes(("event: " + kind + "\ndata: " + JSON.stringify(data) + "\n\n").to_utf8_buffer())

func reply(scene, text: String) -> void:
	event(scene, "delta", {"text": text})
	event(scene, "done", {"text": text, "source": "openai"})

func conversation_count(scene, id: String) -> int:
	var count := 0
	for memory in scene.colony.get_resident("player").memories:
		if memory.get("kind", "") == "conversacion" and id in memory.get("participants", []): count += 1
	return count

func edit(scene, text: String) -> void:
	scene.chat_input.text = text
	scene.chat_input.text_changed.emit()

func button_named(scene, name: String) -> Button:
	return scene.inspector.find_child(name, true, false) as Button

func button_with_text(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text: return child
		var nested: Button = button_with_text(child, text)
		if is_instance_valid(nested): return nested
	return null

func contains_label(node: Node, text: String) -> bool:
	for child in node.get_children():
		if child is Label and child.text.contains(text): return true
		if contains_label(child, text): return true
	return false

func enter(scene, shift: bool = false) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.physical_keycode = KEY_ENTER
	key.pressed = true
	key.shift_pressed = shift
	scene.get_viewport().push_input(key)
	key = key.duplicate()
	key.pressed = false
	scene.get_viewport().push_input(key)

func check_prepared_cleanup() -> void:
	var scene := fixture()
	place(scene, "player", Vector2(100, 280))
	place(scene, "mateo", Vector2(354, 178))
	edit(scene, "Un saludo que aún no envié")
	scene.approach_chat("mateo")
	scene.player_chat.errors.mateo = "Acércate para conversar."
	scene.player_chat.error_details.mateo = "fixture"
	scene.player_chat.retry_text.mateo = "Texto anterior"
	scene.player_chat.scroll_positions.mateo = 81
	scene.player_chat.scroll_follow.mateo = false
	scene.chat_drafts.lupita = "Otro borrador independiente"
	var before: int = conversation_count(scene, "mateo")
	scene.player_chat.clear_prepared("mateo")
	expect(scene.chat_input.text.is_empty() and not scene.chat_drafts.has("mateo"), "clearing a prepared greeting empties its widget before inspector state can recapture it")
	expect(not scene.player_chat.errors.has("mateo") and not scene.player_chat.error_details.has("mateo") and not scene.player_chat.retry_text.has("mateo") and not scene.player_chat.scroll_positions.has("mateo") and not scene.player_chat.scroll_follow.has("mateo"), "prepared cleanup clears only that neighbor's error, retry and reading state")
	expect(scene.player_chat.approach_id.is_empty() and scene.pending_mentor.is_empty() and scene.colony.get_resident("player").target == scene.colony.get_resident("player").pos, "closing an unsent approach cancels its actual following route")
	expect(scene.chat_drafts.lupita == "Otro borrador independiente" and conversation_count(scene, "mateo") == before and scene.dialogue_calls.is_empty(), "prepared cleanup preserves unrelated drafts and every real memory without a request")
	scene.page = "historia"
	scene.build_inspector()
	scene.page = "hablar"
	scene.build_inspector()
	expect(scene.chat_input.text.is_empty(), "reopening after prepared cleanup cannot resurrect the unsent greeting")
	place(scene, "player", Vector2(236, 210))
	place(scene, "mateo", Vector2(260, 210))
	scene.send_chat_text("Hola, Mateo.")
	reply(scene, "Hola, qué gusto verte.")
	var active_messages: Array = scene.player_chat.messages("mateo")
	scene.player_chat.clear_prepared("lupita")
	expect(scene.chat_partner_id == "mateo" and scene.player_chat.messages("mateo") == active_messages and "mateo" in scene.colony.conversation_holds, "clearing another prepared panel cannot end the active pair or discard its messages")
	scene.free()
	await process_frame

func check_explicit_chat_entry() -> void:
	var scene := fixture()
	var mateo: Dictionary = scene.colony.get_resident("mateo")
	mateo.target = [296.0, 210.0]
	mateo.travel_intent = "taller"
	scene.open_inspector("mateo", "historia")
	scene.paused = false
	var profile_position: Vector2 = scene.position_of(mateo)
	scene._process(0.1)
	expect(scene.chat_partner_id.is_empty() and scene.colony.conversation_holds.is_empty() and scene.position_of(mateo) != profile_position, "reading a profile does not reserve or freeze the walking neighbor")
	var talk_tab: Button = button_named(scene, "ResidentTabHablar")
	expect(is_instance_valid(talk_tab), "the profile exposes the real Talk tab")
	if not is_instance_valid(talk_tab):
		scene.free()
		return
	talk_tab.pressed.emit()
	expect(scene.chat_partner_id == "mateo" and ["player", "mateo"].all(func(id): return id in scene.colony.conversation_holds), "clicking Talk reserves both people before a greeting is sent")
	if scene.chat_partner_id != "mateo":
		scene.free()
		return
	expect(scene.dialogue_calls.is_empty() and scene.player_chat.messages("mateo").is_empty(), "opening Talk neither sends a provider request nor invents an exchange")
	edit(scene, "Un saludo que todavía estoy escribiendo")
	scene.chat_input.grab_focus()
	var positions := {"player": scene.colony.get_resident("player").pos.duplicate(), "mateo": mateo.pos.duplicate()}
	var minute_before: int = scene.colony.minute
	mateo.schedule = [{"start": 0, "end": 1440, "place": "huerto", "label": "Cuidar el huerto"}]
	scene.colony._routine_keys.erase("mateo")
	scene.use_jev = true
	for _frame in range(180): scene._process(0.1)
	expect(scene.colony.minute > minute_before and mateo.pos == positions.mateo and scene.colony.get_resident("player").pos == positions.player, "live routine ticks and enabled AI cannot move either person while the first draft is being composed")
	expect(mateo.target == mateo.pos and mateo.travel_intent.is_empty() and scene.player_chat.goals.mateo.intent == "huerto", "the session keeps the new routine as a resumable goal without starting its route")
	expect(scene.chat_input.text == "Un saludo que todavía estoy escribiendo" and scene.dialogue_calls.is_empty() and conversation_count(scene, "mateo") == 0, "waiting to greet preserves the unsent draft and creates no request or memory")
	expect(not scene.colony.decision_due("mateo") and not scene.colony.apply_decision("mateo", "cafe") and not scene.begin_npc_dialogue("mateo"), "a reserved neighbor cannot accept Jev movement or another automatic conversation")
	scene.colony.conversation_holds.erase("mateo")
	scene.player_chat.hold()
	expect("mateo" in scene.colony.conversation_holds and "player" in scene.colony.conversation_holds, "the active session renews both reservations when it holds the pair")
	scene.close_chat_panel()
	expect(scene.chat_partner_id.is_empty() and scene.colony.conversation_holds.is_empty() and mateo.travel_intent == "huerto", "closing an unsent conversation releases both people and resumes the current schedule")
	var released_position: Vector2 = scene.position_of(mateo)
	scene.get_viewport().gui_release_focus()
	scene._process(0.1)
	expect(scene.position_of(mateo) != released_position and conversation_count(scene, "mateo") == 0, "the released neighbor walks again without recording an unsent greeting")
	scene.free()
	await process_frame

func check_reserved_portals() -> void:
	var scene := fixture()
	var mateo: Dictionary = scene.colony.get_resident("mateo")
	var player: Dictionary = scene.colony.get_resident("player")
	var door: Vector2 = Navigation.door_positions().mateo
	var outside: String = Layout.home_area("mateo")
	place(scene, "mateo", door, outside)
	place(scene, "player", door + Vector2(-12, 4), outside)
	scene.update_room()
	mateo.travel_intent = "casa"
	expect(scene.start_player_conversation("mateo"), "a manual conversation can begin beside a scheduled home arrival")
	# Simulate a pending route/arrival callback, without letting it bypass the reservation.
	mateo.travel_intent = "casa"
	scene.colony.on_arrival("mateo")
	expect(mateo.room == outside and not scene.colony.enter_home("mateo", "mateo") and mateo.pos == [door.x, door.y], "neither pending arrival nor an explicit portal transition moves a reserved neighbor indoors")
	scene.end_player_conversation()
	scene.colony.on_arrival("mateo")
	expect(mateo.room == "mateo", "home arrival becomes available again after the conversation ends")
	for person in [player, mateo]:
		person.room = "mateo"
		person.pos = scene.colony.ROOM_EXIT.duplicate() if person.id == "mateo" else scene.colony.ROOM_ENTRY.duplicate()
		person.target = person.pos.duplicate()
	mateo.travel_intent = "cafe"
	scene.update_room()
	expect(scene.start_player_conversation("mateo"), "a manual conversation can begin beside an interior exit")
	mateo.travel_intent = "cafe"
	scene.colony.on_arrival("mateo")
	expect(mateo.room == "mateo" and not scene.colony.leave_home("mateo"), "a reserved neighbor stays in the room when a pending route reaches the exit")
	scene.end_player_conversation()
	scene.colony.on_arrival("mateo")
	expect(mateo.room == outside and scene.colony.conversation_holds.is_empty(), "ending the conversation restores the pending exit and clears both reservations")
	scene.free()
	await process_frame

func check_independent_conversation_holds() -> void:
	# A completed manual turn keeps its session open while a different NPC pair
	# may use the free transport. Each session must own only its own reservations.
	for ending in ["finish", "preempt", "menu"]:
		var scene := fixture()
		scene.send_chat_text("Hola, Mateo.")
		reply(scene, "Hola, me alegra verte.")
		place(scene, "cesar", Vector2(320, 280))
		place(scene, "lupita", Vector2(344, 280))
		var admitted: bool = scene.begin_npc_dialogue("cesar")
		expect(admitted, "%s: independent NPC pair may talk between manual turns" % ending)
		if not admitted:
			scene.free()
			continue
		var npc_serial: int = scene.dialogue_job.serial
		expect(scene.colony.conversation_holds.size() == 4 and ["player", "mateo", "cesar", "lupita"].all(func(id): return id in scene.colony.conversation_holds), "%s: both pairs retain four distinct reservations" % ending)
		var positions: Dictionary = {}
		for id in scene.colony.conversation_holds: positions[id] = scene.colony.get_resident(id).pos.duplicate()
		scene.paused = false
		var started_at: int = scene.colony.minute
		for _frame in range(45): scene._process(0.1)
		var stationary := true
		for id in positions:
			if scene.colony.get_resident(id).pos != positions[id]: stationary = false
		expect(scene.colony.minute > started_at and stationary and scene.colony.conversation_holds.size() == 4, "%s: a live routine tick preserves both reserved pairs" % ending)
		# A schedule change while streaming must still resume the right person's route.
		for id in ["mateo", "cesar", "lupita"]:
			var resident: Dictionary = scene.colony.get_resident(id)
			resident.target = scene.colony.PLACES.taller.duplicate()
			resident.travel_intent = "taller"
		scene.player_chat.hold()
		scene.freeze_conversation()
		var cesar: Dictionary = scene.colony.get_resident("cesar")
		var lupita: Dictionary = scene.colony.get_resident("lupita")
		var memories_before: int = cesar.memories.size()
		if ending == "finish":
			scene.end_player_conversation()
			expect(scene.chat_partner_id.is_empty() and scene.colony.conversation_holds == ["cesar", "lupita"], "ending manual chat releases only its pair while the NPC stream stays reserved")
			expect(scene.dialogue_job.get("serial", -1) == npc_serial and scene.dialogue_request.busy and scene.colony.get_resident("mateo").target == scene.colony.PLACES.taller, "ending manual chat resumes Mateo without cancelling the independent NPC job")
			reply(scene, "Hola, Lupita. ¿Cómo estás?")
			await settle()
			reply(scene, "Bien, gracias por preguntar.")
			expect(scene.dialogue_job.is_empty() and scene.colony.conversation_holds.is_empty() and cesar.memories.size() == memories_before + 1, "independent NPC exchange completes normally after manual chat ends")
		elif ending == "preempt":
			reply(scene, "Esta apertura será interrumpida.")
			var calls_before: int = scene.dialogue_calls.size()
			scene.send_chat_text("Mateo, tengo otra pregunta.")
			await settle()
			expect(scene.chat_partner_id == "mateo" and scene.colony.conversation_holds == ["player", "mateo"] and scene.dialogue_job.get("manual_session", false), "next manual turn cancels only the NPC pair and retains its original session reservations")
			expect(scene.dialogue_calls.size() == calls_before + 1 and cesar.memories.size() == memories_before and scene.dialogue_calls.back().resident_id == "mateo", "preemption suppresses the queued NPC reply and stores no partial NPC exchange")
			reply(scene, "Te escucho, dime.")
			expect(scene.colony.conversation_holds == ["player", "mateo"] and conversation_count(scene, "mateo") == 2, "completed manual follow-up remains reserved and appends to the original pair history")
			scene.end_player_conversation()
		else:
			scene.suspend_for_menu()
			expect(scene.colony.conversation_holds.is_empty() and scene.chat_partner_id.is_empty() and scene.dialogue_job.is_empty() and not scene.dialogue_request.busy, "menu cancels both independent sessions and releases all four reservations")
			scene.resume_from_menu()
			scene.set_process(false)
			expect(not scene._menu_suspended and not scene.paused and scene.colony.conversation_holds.is_empty() and cesar.memories.size() == memories_before, "menu resume preserves prior pause state without reviving cancelled reservations or partial dialogue")
		expect(cesar.target == scene.colony.PLACES.taller and lupita.target == scene.colony.PLACES.taller and cesar.travel_intent == "taller" and lupita.travel_intent == "taller", "%s: released NPC pair resumes its latest saved routes" % ending)
		scene.free()
		await process_frame

func complete_with_choices(scene, text: String, choices: Array) -> void:
	# Exercise the controller's completed API without assuming a provider transport.
	var job: Dictionary = scene.dialogue_job.duplicate(true)
	scene.dialogue_request.cancel()
	scene.dialogue_job.clear()
	scene.player_chat.completed(job, text, "fixture completion", choices)

func check_ephemeral_session_and_choices() -> void:
	var scene := fixture()
	var path := "user://chat_session_%d.json" % OS.get_process_id()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	scene.colony.save_path = path
	# This transport/suggestion scenario concerns a relationship which already
	# permits family history; ordinary fixtures keep their stranger baseline.
	var relationship: Dictionary = scene.colony.get_resident("mateo").relationships.player
	relationship.trust = 80.0
	relationship.affection = 60.0
	expect(scene.colony.relationship_for("mateo", "player").disclosure == "intimate", "private-history fixture explicitly begins with earned intimate disclosure")
	scene.send_chat_text("¿Quién te enseñó el oficio?")
	var choices: Array = ["¿Cómo era el taller de tus abuelos?", "¿Qué herramientas conservas?"]
	event(scene, "delta", {"text": "Aprendí el oficio con mis abuelos."})
	event(scene, "done", {"text": "Aprendí el oficio con mis abuelos.", "source": "openai", "suggestions": choices})
	var suggestions: Array = scene.chat_suggestions_for("mateo")
	expect(suggestions.size() == 2 and suggestions[0].text == choices[0] and suggestions[0].label == choices[0] and suggestions[1].text == choices[1], "validated provider choices use exactly the text the player will send")
	suggestions[0].text = "Changed snapshot"
	choices[0] = "Changed caller array"
	expect(scene.chat_suggestions_for("mateo")[0].text == "¿Cómo era el taller de tus abuelos?", "provider choices are isolated from caller and UI mutation")
	scene.build_inspector()
	var button := button_named(scene, "ChatSuggestion0")
	expect(button.get_meta("spoken_text", "") == "¿Cómo era el taller de tus abuelos?", "the full choice displayed by the bubble UI equals its send payload")
	button.pressed.emit()
	expect(scene.dialogue_calls.back().utterance == "¿Cómo era el taller de tus abuelos?", "choosing a provider suggestion sends its exact concrete sentence once")
	complete_with_choices(scene, "Me gustaba observar las herramientas.", ["x".repeat(46), "Texto\ncon control"])
	suggestions = scene.chat_suggestions_for("mateo")
	expect(suggestions.size() == 2 and not suggestions[0].text.contains("\n") and suggestions[0].text.length() <= 45, "invalid provider choices fall back to bounded local context suggestions")
	expect(scene.player_chat._validated_suggestions(["¿Qué reparas?", "¿Qué reparas?"]).size() == 1 and scene.player_chat._validated_suggestions(["**Marcado**", {"text": "Objeto inválido"}]).is_empty(), "suggestion validation removes duplicates, markdown and unexpected shapes")
	var context: Dictionary = scene.colony.context_for("mateo", "player", "abuelos")
	expect(JSON.stringify(context).contains("Aprendí el oficio con mis abuelos"), "the neighbor's model context retains the encounter independently of UI messages")
	edit(scene, "Borrador de este encuentro")
	scene.suspend_for_menu()
	expect(scene.player_chat.messages("mateo").is_empty() and scene.player_chat.last_reply("mateo").is_empty() and str(scene.chat_drafts.get("mateo", "")).is_empty(), "menu ends and clears the encounter including its pending draft")
	scene.resume_from_menu()
	scene.set_process(false)
	expect(scene.start_player_conversation("mateo") and scene.player_chat.messages("mateo").is_empty(), "reopening after the menu starts another empty encounter")
	expect(scene.chat_suggestions_for("mateo")[0].text == "Hola, Mateo. ¿Cómo estás?", "reopening removes prior provider suggestions and restores a fresh greeting")
	var count: int = conversation_count(scene, "mateo")
	expect(count == 2 and scene.colony.save_game(), "saving preserves the two real exchanges without saving the encounter UI")
	scene.free()
	await process_frame
	scene = fixture()
	scene.colony.save_path = path
	expect(scene.colony.load_game() and conversation_count(scene, "mateo") == count, "real participant memories survive a fresh controller and reload")
	scene.build_inspector()
	expect(scene.player_chat.messages("mateo").is_empty() and scene.chat_transcript_for("mateo").is_empty() and scene.player_chat.last_reply("mateo").is_empty(), "reload does not replay old messages or reply context into chat")
	expect(JSON.stringify(scene.colony.context_for("mateo", "player", "abuelos")).contains("abuelos"), "an empty chat after reload still gives the neighbor its real remembered context")
	scene.free()
	await process_frame
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func check_legacy_memory_presentation() -> void:
	# Historical imports have their own world: recording them must not exhaust the
	# live transport scenario's intentional emotional/session turn allowance.
	var scene := fixture()
	var player: Dictionary = scene.colony.get_resident("player")
	var mateo: Dictionary = scene.colony.get_resident("mateo")
	expect(scene.start_player_conversation("mateo"), "legacy fixture starts an independent current encounter")
	# Old saves predate structured turns. Reading them must format a view, not migrate memories.
	scene.colony.record_dialogue("player", "mateo", "Mi mensaje antiguo\ncon dos líneas", "Un recuerdo — de antes.\n\n   Seguimos aquí.", "fixture legado")
	player.memories.back().erase("turns")
	mateo.memories.back().erase("turns")
	var legacy_player_source: Dictionary = player.memories.back().duplicate(true)
	var legacy_mateo_source: Dictionary = mateo.memories.back().duplicate(true)
	var legacy_history: String = scene.chat_transcript_for("mateo")
	expect(not legacy_history.contains("Mi mensaje antiguo") and not legacy_history.contains("Un recuerdo"), "saved legacy memories do not appear in the current encounter")
	expect(player.memories.back() == legacy_player_source and mateo.memories.back() == legacy_mateo_source and not player.memories.back().has("turns"), "reading compact legacy history never mutates either participant's source memory")
	var old_recall := "Recuerdo que el día 1 a las 08:00 me contaste: «Quiero reparar mi bici.» Quiero ayudarte."
	scene.colony.record_dialogue("player", "mateo", old_recall, "Con gusto te enseño.", "conversación directa")
	player.memories.back().erase("turns")
	mateo.memories.back().erase("turns")
	var dated_source: Dictionary = player.memories.back().duplicate(true)
	var natural_history: String = scene.chat_transcript_for("mateo")
	expect(natural_history == legacy_history and not natural_history.contains("día 1 a las"), "old automatic recalls remain outside the current encounter")
	expect(player.memories.back() == dated_source, "natural presentation leaves the original dated experience intact")
	scene.colony.record_dialogue("player", "mateo", old_recall, "Te escucho.", "fixture de texto libre")
	expect(scene.chat_transcript_for("mateo") == legacy_history and player.memories.back().turns[0].text == old_recall, "a saved date remains in memory without being replayed in the encounter")
	scene.free()
	await process_frame

func social_metrics(scene, id: String) -> Array:
	var relation: Dictionary = scene.colony.relationship_for(id, "player")
	return [relation.trust, relation.affection, relation.tolerance, relation.frustration]

func check_voluntary_refusal() -> void:
	var scene := fixture()
	scene.colony._social._willingness_roll = func(): return 0.0
	var mateo: Dictionary = scene.colony.get_resident("mateo")
	mateo.target = [352.0,180.0]
	mateo.travel_intent = "taller"
	var destination: Array = mateo.target.duplicate()
	var activity: String = mateo.activity
	var initial: Array = social_metrics(scene,"mateo")
	var memories: int = conversation_count(scene,"mateo")
	edit(scene,"Un borrador anterior al rechazo")
	scene.player_chat.errors.mateo = "Error antiguo"
	scene.player_chat.error_details.mateo = "Detalles antiguos"
	scene.player_chat.retry_text.mateo = "Reintento antiguo"
	scene.player_chat.scroll_positions.mateo = 74
	scene.player_chat.approach_id = "mateo"
	scene.pending_mentor = "mateo"
	scene.chat_drafts.lupita = "Borrador independiente"
	expect(not scene.start_player_conversation("mateo"),"a neighbor with a healthy relationship may politely decline a new invitation")
	expect(social_metrics(scene,"mateo") == initial,"the first voluntary no changes neither trust, affection, tolerance nor frustration")
	expect(scene.player_chat.ended("mateo") and scene.player_chat.messages("mateo").size() == 1 and not scene.chat_input.visible and not scene.chat_send.visible and scene.player_chat.suggestions("mateo").is_empty(),"refusal shows exactly one clean neighbor bubble and closes the composer and reply choices")
	expect(scene.chat_partner_id.is_empty() and scene.colony.conversation_holds.is_empty() and scene.dialogue_calls.is_empty() and scene.dialogue_job.is_empty(),"a rejected invitation creates no reservation, provider call or pending reply")
	expect(mateo.target == destination and mateo.travel_intent == "taller" and mateo.activity == activity,"the first refusal preserves the neighbor's actual activity and destination")
	expect(scene.player_chat.approach_id.is_empty() and scene.pending_mentor.is_empty(),"refusal stops the prepared following loop instead of automatically asking again")
	expect(scene.chat_input.text.is_empty() and str(scene.chat_drafts.get("mateo","")).is_empty() and not scene.player_chat.errors.has("mateo") and not scene.player_chat.error_details.has("mateo") and not scene.player_chat.retry_text.has("mateo"),"refusal removes stale widget text, errors and retry state before the inspector rebuild")
	expect(scene.chat_drafts.lupita == "Borrador independiente" and conversation_count(scene,"mateo") == memories,"refusal preserves unrelated drafts and does not manufacture a completed conversation")
	for _rebuild in 3:
		scene.build_inspector()
		scene.refresh_status()
	expect(social_metrics(scene,"mateo") == initial,"redrawing or refreshing the refusal is not another invitation and adds no pressure")
	button_named(scene,"ChatSuggestion0").pressed.emit()
	expect(not scene.inspector.visible and social_metrics(scene,"mateo") == initial,"the visible Close action respects the no without a penalty")
	expect(not scene.start_player_conversation("mateo"),"an explicit new invitation during the requested pause remains declined")
	var insisted: Array = social_metrics(scene,"mateo")
	expect(insisted[3] > initial[3] and insisted[2] < initial[2] and insisted[0] == initial[0] and insisted[1] == initial[1],"insisting changes frustration and tolerance only after the first no")
	scene.start_player_conversation("mateo")
	expect(social_metrics(scene,"mateo") == insisted,"duplicate starts within the same simulated minute cannot multiply the pressure charge")
	scene.close_chat_panel()
	var until: int = maxi(int(mateo.chat_availability.until),int(scene.colony.relationship_for("mateo","player").cooldown_until))
	scene.colony.minute = until+1
	expect(scene.start_player_conversation("mateo") and scene.chat_partner_id == "mateo","allowing the pause to pass permits a fresh session even when the random source still returns refusal")
	expect(scene.player_chat.messages("mateo").is_empty() and scene.chat_input.text.is_empty() and scene.dialogue_calls.is_empty(),"acceptance after the pause starts clean and waits for an explicit message")
	scene.player_chat.finish()
	scene.free()
	await process_frame

	# The rejection branch must not cancel a separate pair's in-flight exchange.
	scene = fixture()
	place(scene,"cesar",Vector2(200,180))
	place(scene,"lupita",Vector2(224,180))
	expect(scene.begin_npc_dialogue("cesar"),"independent background conversation starts before a manual refusal")
	var job: Dictionary = scene.dialogue_job.duplicate(true)
	var reservations: Array = scene.colony.conversation_holds.duplicate()
	var calls: int = scene.dialogue_calls.size()
	scene.colony._social._willingness_roll = func(): return 0.0
	expect(not scene.start_player_conversation("mateo"),"the separate manual invitation can still receive its own refusal")
	expect(scene.dialogue_job == job and scene.colony.conversation_holds == reservations and scene.dialogue_calls.size() == calls and scene.dialogue_request.busy,"refusal preserves the other pair's transport, reservations and request count")
	scene.free()
	await process_frame

func run() -> void:
	# Apply after engine startup: the headless window otherwise remains 64×64.
	root.size = Vector2i(768, 432)
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Run with -- --ui-test; refusing to access real player progress.")
		quit(1)
		return
	var scene = fixture()
	await settle()
	var player: Dictionary = scene.colony.get_resident("player")
	var mateo: Dictionary = scene.colony.get_resident("mateo")
	expect(scene.preview_mode and scene.paused and not scene.save_allowed, "fixture isolates progress and provider requests")
	expect(not scene.chat_input.has_focus(), "opening chat does not take keyboard focus")
	expect(scene.player_chat.messages("mateo").is_empty(), "a new encounter starts with no replayed messages")
	mateo.target = [386.0, 178.0]
	mateo.travel_intent = "taller"
	button_named(scene, "ChatSuggestion0").pressed.emit()
	expect(scene.dialogue_calls.size() == 1 and scene.dialogue_calls.back().utterance == "Hola, Mateo. ¿Cómo estás?", "initial suggestion sends the selected neighbor's greeting exactly once")
	expect(scene.chat_partner_id == "mateo" and scene.colony.conversation_holds == ["player", "mateo"], "greeting opens one reserved player conversation")
	expect(scene.chat_send.disabled and button_named(scene, "ChatSuggestion0").disabled and scene.chat_input.editable, "stream locks sending while allowing the next draft")
	var first_partial := "Hola. Estoy bien, gracias. "
	event(scene, "delta", {"text": first_partial})
	expect(conversation_count(scene, "mateo") == 0, "partial streaming text creates no memory")
	var pending_messages: Array = scene.player_chat.messages("mateo")
	expect(pending_messages.size() == 2 and pending_messages[0].speaker_id == "player" and pending_messages[1].speaker_id == "mateo" and pending_messages[1].get("pending", false), "bubble data identifies both speakers and the pending response")
	pending_messages[1].text = "MODIFIED COPY"
	expect(not scene.player_chat.transcript("mateo").contains("MODIFIED COPY"), "message snapshots cannot mutate the live encounter")
	edit(scene, "Mi siguiente pregunta, todavía sin enviar.")
	scene.chat_input.grab_focus()
	scene.chat_input.set_caret_column(9)
	scene.build_inspector()
	await settle()
	expect(scene.chat_input.text == "Mi siguiente pregunta, todavía sin enviar." and scene.chat_input.has_focus() and scene.chat_input.get_caret_column() == 9, "inspector rebuild preserves the draft, focus and caret during streaming")
	event(scene, "delta", {"text": "¿Y tú, cómo estás?"})
	event(scene, "done", {"text": first_partial + "¿Y tú, cómo estás?", "source": "openai"})
	await settle()
	expect(conversation_count(scene, "mateo") == 1 and not scene.chat_busy() and scene.chat_partner_id == "mateo", "completed reply saves one exchange and leaves the session open")
	expect(scene.player_chat.messages("mateo").size() == 2 and not scene.player_chat.messages("mateo")[1].get("pending", false), "completion replaces the pending bubble with one complete exchange")
	expect(scene.seen_world_events.has(scene.colony.events.back()), "a manual transcript is not repeated among neighborhood notices")
	expect(scene.chat_suggestions_for("mateo")[0].text == "Bien, gracias.", "next suggestions respond to the neighbor's actual last question")
	var held_player: Vector2 = scene.position_of(player)
	var held_mateo: Vector2 = scene.position_of(mateo)
	var minute_before: int = scene.colony.minute
	scene.paused = false
	scene.get_viewport().gui_release_focus()
	for _frame in range(85): scene._process(0.1)
	expect(scene.colony.minute >= minute_before + 10, "the real simulation clock advances between conversational turns")
	expect(scene.position_of(player) == held_player and scene.position_of(mateo) == held_mateo and scene.chat_partner_id == "mateo", "schedule ticks cannot move either reserved participant between turns")
	place(scene, "lupita", Vector2(280, 210))
	var requests_before: int = scene.dialogue_calls.size()
	expect(not scene.begin_npc_dialogue("mateo") and not scene.begin_npc_dialogue("lupita"), "automatic dialogue cannot use a held speaker or choose held partners")
	scene.colony.converse("lupita", "mateo")
	expect(scene.dialogue_calls.size() == requests_before and conversation_count(scene, "mateo") == 1, "local automatic encounters cannot add a turn to the reserved chat")
	button_named(scene, "ChatSuggestion0").pressed.emit()
	expect(scene.dialogue_calls.size() == 2 and scene.dialogue_calls.back().utterance.begins_with("Bien, gracias"), "second turn uses the contextual suggestion in the existing session")
	expect(scene.chat_input.text == "Mi siguiente pregunta, todavía sin enviar.", "sending a suggestion preserves an unrelated typed draft")
	reply(scene, "Podemos visitar el taller. Me gusta reparar bicicletas con mis vecinos.")
	edit(scene, "¿Qué revisas al reparar una bicicleta?")
	scene.chat_send.pressed.emit()
	expect(scene.dialogue_calls.size() == 3 and scene.dialogue_calls.back().resident_id == "mateo", "free text sends the third turn to the same neighbor")
	reply(scene, "Primero reviso las ruedas; luego compruebo los frenos con cuidado.")
	await settle()
	var own_history: String = scene.chat_transcript_for("mateo")
	expect(conversation_count(scene, "mateo") == 3 and own_history.contains("Hola, Mateo") and own_history.contains("Bien, gracias") and own_history.contains("reviso las ruedas"), "all three complete exchanges remain in this pair's history")
	expect(not own_history.contains("día 1 a las") and not str(player.memories.back().time).is_empty(), "chat omits timestamp headers while preserving the dated memory internally")
	var multiline_player := "Hola de nuevo.\nTengo una pregunta."
	edit(scene, multiline_player)
	scene.send_player_dialogue()
	var raw_compact_reply := "Hola — qué gusto.\n\n   ¿Cómo estás?"
	# Whitespace and punctuation cross token boundaries as they do in real SSE.
	for fragment in ["Hola ", "—", " qué gusto.\n", "\n   ¿Cómo estás?"]:
		event(scene, "delta", {"text": fragment})
	var compact_expected := "Hola, qué gusto. ¿Cómo estás?"
	expect(scene.stream_text == raw_compact_reply and scene.chat_output.text == compact_expected, "stream preserves raw SSE while displaying one compact NPC paragraph in the latest bubble across chunk boundaries")
	event(scene, "done", {"text": raw_compact_reply, "source": "openai"})
	var compact_memory: Dictionary = player.memories.back()
	expect(compact_memory.heard_text == compact_expected and compact_memory.turns[1].text == compact_expected and mateo.memories.back().turns[1].text == compact_expected, "both participants store the same compact NPC voice without em dashes or line breaks")
	expect(compact_memory.turns[0].text == multiline_player and mateo.memories.back().heard_text == multiline_player, "compacting the NPC never changes the player's deliberate newline")
	edit(scene, "¿Qué recuerdas de tu taller?")
	scene.send_player_dialogue()
	reply(scene, "Recuerdo cuando abrimos el taller. " + "Después aprendimos a reparar bicicletas con paciencia y a compartir cada paso con los vecinos. ".repeat(8))
	var bounded_reply: String = player.memories.back().heard_text
	expect(bounded_reply.length() <= 180 and bounded_reply.split(" ", false).size() <= 30 and not bounded_reply.contains("\n") and not bounded_reply.contains("  "), "an oversized provider reply is stored within the compact character and word limits")
	expect(bounded_reply.begins_with("Recuerdo cuando abrimos el taller.") and bounded_reply.ends_with("."), "an oversized reply keeps a complete sentence instead of an unfinished word")
	# Rendering inserts only single separators; the sole intentional player newline remains.
	expect(not scene.chat_transcript_for("mateo").contains("\n\n"), "chat history uses compact spacing between speakers and exchanges")
	edit(scene, "Borrador sólo para Mateo")
	expect(scene.colony.record_dialogue("player", "lupita", "Pregunta exclusiva para Lupita", "Respuesta exclusiva de Lupita", "fixture"), "second neighbor fixture records a real separate exchange")
	scene.selected_id = "lupita"
	scene.build_inspector()
	await settle()
	expect(scene.player_chat.messages("lupita").is_empty() and scene.chat_transcript_for("lupita").is_empty(), "selecting another neighbor never replays its saved conversation")
	expect(not scene.chat_input.visible and not scene.chat_input.editable and contains_label(scene.inspector, "Estás hablando con Mateo"), "another selected neighbor cannot receive text during the active session")
	var return_button := button_named(scene, "ChatSuggestion0")
	expect(is_instance_valid(return_button) and return_button.get_meta("spoken_text", "") == "Volver a Mateo", "other neighbor provides an explicit return to the active conversation")
	if is_instance_valid(return_button): return_button.pressed.emit()
	await settle()
	expect(scene.selected_id == "mateo" and scene.chat_input.text == "Borrador sólo para Mateo", "returning restores the correct neighbor and their unsent draft")
	if "--capture-chat" in OS.get_cmdline_user_args():
		var capture_path := OS.get_environment("MY_CITY_CHAT_CAPTURE")
		if not capture_path.is_empty():
			scene.queue_redraw()
			scene.actors.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(capture_path) == OK, "chat screenshot saved to the requested artifact path")

	# Stream a large response and use the actual scrollbar, then rebuild its widgets.
	edit(scene, "Cuéntame una historia larga.")
	scene.send_player_dialogue()
	var long_reply := "En el taller recordamos lo que aprendimos juntos. "
	event(scene, "delta", {"text": long_reply})
	await settle()
	expect(scene.chat_scroll.get_v_scroll_bar().max_value > scene.chat_scroll.get_v_scroll_bar().page, "long chat history scrolls within its fixed reading viewport")
	scene.chat_scroll.scroll_vertical = 16
	var reading_position: int = scene.chat_scroll.scroll_vertical
	event(scene, "delta", {"text": "Una frase adicional."})
	await settle()
	expect(scene.chat_scroll.scroll_vertical == reading_position, "streaming does not pull a reader away from older messages")
	edit(scene, "Un borrador durante la historia larga")
	scene.chat_input.grab_focus()
	scene.chat_input.set_caret_column(7)
	scene.build_inspector()
	await settle()
	expect(scene.chat_scroll.scroll_vertical == reading_position and scene.chat_input.text == "Un borrador durante la historia larga", "rebuilding preserves both a reader's scroll and their pending draft")
	scene.chat_scroll.scroll_vertical = 100000
	event(scene, "delta", {"text": "\n" + "El final de la historia.\n".repeat(4)})
	await settle()
	var bar: VScrollBar = scene.chat_scroll.get_v_scroll_bar()
	expect(bar.value >= bar.max_value - bar.page - 1, "streaming follows new text when the reader was already at the end")
	event(scene, "done", {"text": long_reply + "Una frase adicional.\n" + "El final de la historia.\n".repeat(4), "source": "openai"})
	edit(scene, "Mensaje que podrá reintentarse")
	var emotions_before_retry: Array = [scene.colony.relationship_for("mateo", "player"), scene.colony.relationship_for("player", "mateo")]
	scene.send_player_dialogue()
	var count_before_error := conversation_count(scene, "mateo")
	event(scene, "delta", {"text": "Esta respuesta quedará incompleta"})
	event(scene, "error", {"error": "Interrupción de prueba"})
	await settle()
	expect(conversation_count(scene, "mateo") == count_before_error and scene.chat_partner_id == "mateo", "a failed partial reply saves no exchange and keeps the session open")
	expect([scene.colony.relationship_for("mateo", "player"), scene.colony.relationship_for("player", "mateo")] == emotions_before_retry, "failed transport and partial text change neither direction of the relationship")
	expect(scene.chat_input.text == "Mensaje que podrá reintentarse" and contains_label(scene.inspector, "No llegó la respuesta") and not contains_label(scene.inspector, "Interrupción de prueba"), "failure gives a short human message and restores the sendable original text")
	var failed_job: Dictionary = {"a": "player", "b": "mateo", "first": "Mensaje que podrá reintentarse", "serial": scene.dialogue_serial}
	for example in [["connection_failed", "Se perdió la conexión"], ["upstream_timeout", "tardó demasiado"], ["upstream_busy", "está ocupado"], ["upstream_incomplete", "se interrumpió"], ["http_503", "está ocupado"], ["upstream_auth", "No se pudo acceder"]]:
		scene.dialogue_request.failure_code = example[0]
		scene.player_chat.failed(failed_job, "Provider private diagnostic: must never be visible")
		expect(contains_label(scene.inspector, example[1]) and not contains_label(scene.inspector, "Provider private diagnostic"), "failure UI explains %s using only curated player-facing text" % example[0])
		expect(scene.player_chat.retry_text.mateo == failed_job.first and scene.chat_partner_id == "mateo", "%s retains the original retry message and active pair" % example[0])
	expect([scene.colony.relationship_for("mateo", "player"), scene.colony.relationship_for("player", "mateo")] == emotions_before_retry and conversation_count(scene, "mateo") == count_before_error, "classified technical failures do not change social metrics or save unfinished dialogue")
	requests_before = scene.dialogue_calls.size()
	button_named(scene, "ChatSuggestion0").pressed.emit()
	expect(scene.dialogue_calls.size() == requests_before + 1 and scene.dialogue_calls.back().utterance == "Mensaje que podrá reintentarse", "retry sends the original question once")
	expect([scene.colony.relationship_for("mateo", "player"), scene.colony.relationship_for("player", "mateo")] == emotions_before_retry, "retry dispatch does not count as a second emotional exchange")
	reply(scene, "Ahora sí llegó la respuesta completa.")
	expect(conversation_count(scene, "mateo") == count_before_error + 1 and scene.chat_error_for("mateo").is_empty(), "successful retry records once and clears the previous error")
	var latest_goal: Dictionary = scene.player_chat.goals.mateo.duplicate(true)
	scene.end_player_conversation()
	expect(scene.chat_partner_id.is_empty() and scene.colony.conversation_holds.is_empty(), "ending the session releases both reserved participants")
	expect(scene.player_chat.messages("mateo").is_empty() and scene.player_chat.last_reply("mateo").is_empty() and not scene.player_chat.scroll_positions.has("mateo") and not scene.player_chat.retry_text.has("mateo") and not scene.player_chat.errors.has("mateo"), "ending clears messages, reply context, scroll, retry and errors")
	expect(mateo.target == latest_goal.target and mateo.travel_intent == latest_goal.intent, "ending resumes the neighbor's most recent scheduled destination")
	var history_before_reopening: String = scene.chat_transcript_for("mateo")
	var exchanges_before_reopening := conversation_count(scene, "mateo")
	expect(scene.start_player_conversation("mateo"), "a neighbor with saved exchanges can begin a new conversation session")
	scene.build_inspector()
	expect(scene.chat_suggestions_for("mateo")[0].text == "Hola, Mateo. ¿Cómo estás?", "reopened session starts with a greeting instead of answering the old final turn")
	expect(history_before_reopening.is_empty() and scene.chat_transcript_for("mateo").is_empty() and scene.player_chat.messages("mateo").is_empty() and conversation_count(scene, "mateo") == exchanges_before_reopening, "reopening starts with an empty encounter while preserving every real memory")
	button_named(scene, "ChatSuggestion0").pressed.emit()
	reply(scene, "Hola de nuevo. Estoy bien, ¿y tú cómo estás?")
	expect(scene.chat_suggestions_for("mateo")[0].text == "Bien, gracias.", "first new reply replaces the greeting with suggestions for the current session")
	expect(conversation_count(scene, "mateo") == exchanges_before_reopening + 1 and scene.player_chat.messages("mateo").size() == 2 and not scene.chat_transcript_for("mateo").contains("reviso las ruedas"), "the new encounter shows only its own first exchange while memory continues accumulating")
	scene.end_player_conversation()

	edit(scene, "Mensaje cancelado al caminar")
	var emotions_before_cancel: Array = [scene.colony.relationship_for("mateo", "player"), scene.colony.relationship_for("player", "mateo")]
	scene.send_player_dialogue()
	event(scene, "delta", {"text": "Fragmento antes de caminar"})
	var count_before_move := conversation_count(scene, "mateo")
	scene.get_viewport().gui_release_focus()
	scene.controls_active = true
	scene.paused = false
	var before_move: Vector2 = scene.position_of(player)
	Input.action_press("city_right")
	scene._process(0.1)
	Input.action_release("city_right")
	expect(scene.position_of(player) != before_move and scene.chat_partner_id.is_empty() and not scene.dialogue_request.busy, "real held movement closes the chat and cancels its active transport")
	event(scene, "delta", {"text": "Fragmento tardío"})
	event(scene, "done", {"text": "Fragmento antes de caminarFragmento tardío", "source": "openai"})
	scene._dialogue_completed({"text": "Callback tardío", "source": "openai"})
	expect(conversation_count(scene, "mateo") == count_before_move and scene.dialogue_job.is_empty(), "late stream events and completion after cancellation create no memory")
	expect([scene.colony.relationship_for("mateo", "player"), scene.colony.relationship_for("player", "mateo")] == emotions_before_cancel, "cancelling an incomplete reply and its late callbacks changes neither relationship")
	expect(str(scene.chat_drafts.get("mateo", "")).is_empty() and scene.player_chat.messages("mateo").is_empty() and scene.player_chat.last_reply("mateo").is_empty(), "walking clears the cancelled encounter and its draft")

	# Viewport dispatch lets Shift+Enter reach TextEdit while plain Enter is consumed.
	place(scene, "mateo", scene.position_of(player) + Vector2(24, 0))
	scene.open_inspector("mateo", "hablar")
	edit(scene, "Una línea")
	scene.chat_input.grab_focus()
	scene.chat_input.set_caret_column(scene.chat_input.text.length())
	requests_before = scene.dialogue_calls.size()
	enter(scene, true)
	await settle()
	expect(scene.chat_input.text == "Una línea\n" and scene.dialogue_calls.size() == requests_before, "Shift+Enter inserts a real editor newline without sending")
	edit(scene, "Pregunta enviada con Enter")
	enter(scene)
	expect(scene.dialogue_calls.size() == requests_before + 1 and scene.dialogue_calls.back().utterance == "Pregunta enviada con Enter", "plain Enter sends exactly one message through viewport input")
	reply(scene, "Respuesta a la pregunta del teclado.")
	scene.end_player_conversation()
	scene.service_token = ""
	scene.build_inspector()
	expect(not contains_label(scene.inspector, "Charla local · sin IA") and not contains_label(scene.inspector, "OpenAI"), "the chat surface omits provider metadata while memory retains source provenance")
	requests_before = scene.dialogue_calls.size()
	scene.send_chat_text("Hola, Mateo. ¿Cómo estás?")
	await settle()
	expect(scene.dialogue_calls.size() == requests_before and not scene.chat_busy() and scene.chat_partner_id == "mateo", "local reply completes asynchronously without a provider request and keeps the session open")
	expect(str(player.memories.back().origin) == "Conversación local · respuesta predeterminada", "local exchange memory preserves its explicit predetermined origin")
	expect(str(player.memories.back().heard_text).length() <= 180 and not str(player.memories.back().heard_text).contains("\n"), "local NPC replies follow the same compact display and memory limits")
	scene.end_player_conversation()
	expect(scene.colony.conversation_holds.is_empty() and not scene.begin_npc_dialogue("mateo"), "manual session releases reservations but retains the neighbor's real social cooldown")
	# Autonomous neighbors use the same formatting before either voice reaches memory.
	# Use rested idle neighbors rather than bypassing the preceding conversation cooldown.
	scene.free()
	scene = fixture()
	mateo = scene.colony.get_resident("mateo")
	scene.service_token = "offline-test-never-sent"
	place(scene, "player", Vector2(100, 280))
	place(scene, "mateo", Vector2(236, 210))
	place(scene, "lupita", Vector2(260, 210))
	var automatic_admitted: bool = scene.begin_npc_dialogue("mateo")
	expect(automatic_admitted, "rested idle neighbors can open an autonomous conversation")
	if not automatic_admitted:
		scene.free()
		quit(1)
		return
	reply(scene, "Hola — Lupita.\n\n   ¿Cómo estás?")
	await settle()
	reply(scene, "Bien — gracias.\n\n   ¿Y tú?")
	var autonomous_turns: Array = mateo.memories.back().turns
	expect(autonomous_turns[0].text == "Hola, Lupita. ¿Cómo estás?" and autonomous_turns[1].text == "Bien, gracias. ¿Y tú?", "autonomous opening and reply are compacted before the complete exchange is recorded")
	scene.free()
	await process_frame

	# A distant neighbor moves with real schedules while the player follows a real route.
	scene = fixture()
	scene.controls_active = false
	place(scene, "player", Vector2(100, 280))
	place(scene, "mateo", Vector2(386, 178))
	scene.build_inspector()
	edit(scene, "Un saludo preparado antes de llegar")
	var approach_start: Vector2 = scene.position_of(scene.colony.get_resident("player"))
	scene.approach_chat("mateo")
	expect(scene.chat_partner_id.is_empty() and scene.dialogue_calls.is_empty() and scene.position_of(scene.colony.get_resident("player")) == approach_start, "approach begins walking without teleporting or sending a greeting")
	var walked_safely := true
	var previous: Vector2 = approach_start
	for _frame in range(1800):
		scene._process(0.1)
		var point: Vector2 = scene.position_of(scene.colony.get_resident("player"))
		var maximum_step: float = scene.resident_walk_speed(scene.colony.get_resident("player")) * 0.1 + 0.01
		if not Navigation.is_walkable(point, "street") or point.distance_to(previous) > maximum_step: walked_safely = false
		previous = point
		if scene.chat_partner_id == "mateo": break
	expect(scene.chat_partner_id == "mateo" and scene.player_chat.nearby("mateo") and previous != approach_start, "approach reaches the moving neighbor and opens a nearby session")
	expect(walked_safely, "approach follows collision-safe continuous movement during live clock ticks")
	expect(scene.dialogue_calls.is_empty() and scene.chat_input.text == "Un saludo preparado antes de llegar", "arrival preserves the prepared draft and waits for an explicit send")
	scene.free()
	await process_frame
	await check_independent_conversation_holds()
	await check_ephemeral_session_and_choices()
	await check_legacy_memory_presentation()
	await check_prepared_cleanup()
	await check_explicit_chat_entry()
	await check_reserved_portals()
	await check_voluntary_refusal()
	print("PLAYER CHAT: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
