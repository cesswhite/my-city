extends SceneTree
## Deterministic conversation coherence with real world/controller and no provider or save.
class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func request_dialogue(_resident: String, _speaker: String, _utterance: String) -> void:
		provider_calls += 1
	func decide_with_jev() -> void:
		provider_calls += 1

var checks := 0
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
	for _frame in range(3): await process_frame

func fixture() -> MainProbe:
	var scene := MainProbe.new()
	root.add_child(scene)
	scene.colony._social._willingness_roll = func(): return 1.0 # Keep local reply scenarios independent of random availability.
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.set_process(false)
	scene.save_allowed = false
	scene.controls_active = false
	scene.use_jev = false
	scene.service_token = ""
	scene.service_url = ""
	for resident: Dictionary in scene.colony.residents:
		resident.room = resident.id
		resident.pos = [236.0, 252.0]
		resident.target = resident.pos.duplicate()
		resident.travel_intent = ""
	place(scene, "player", [338.0, 178.0])
	place(scene, "mateo", [354.0, 178.0])
	scene.selected_id = "mateo"
	scene.page = "hablar"
	scene.build_inspector()
	return scene

func place(scene, id: String, point: Array, room: String = "street") -> void:
	var person: Dictionary = scene.colony.get_resident(id)
	person.room = room
	person.pos = point.duplicate()
	person.target = point.duplicate()
	person.travel_intent = ""
	scene.colony._daily_life.forget(id)

func set_task(scene, id: String, action: String, label: String, kind: String = "working") -> void:
	var person: Dictionary = scene.colony.get_resident(id)
	var state: Dictionary = scene.colony._daily_life._new_state(person, "taller")
	state.phase = "active"
	state.task = {"action": action, "kind": kind, "label": label, "duration": 20}
	state.until = scene.colony.minute + 20
	scene.colony._daily_life._states[id] = state
	person.activity = label

func turn(scene, text: String) -> String:
	scene.send_chat_text(text)
	await settle()
	if scene.player_chat.ended("mateo"):
		return str(scene.player_chat.messages("mateo").back().text)
	return scene.player_chat.last_reply("mateo")

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Run with -- --ui-test to isolate the player's save.")
		quit(1)
		return
	root.size = Vector2i(768, 432)
	var scene := fixture()
	set_task(scene, "mateo", "sort_tools", "Ordenando herramientas")
	expect(scene.start_player_conversation("mateo"), "a nearby manual encounter captures the actual interrupted task")
	var captured: Dictionary = scene.player_chat.scene_for("mateo")
	expect(captured.ongoing_action == "sort_tools" and captured.activity_before_chat == "Ordenando herramientas" and captured.paused_for_chat, "scene snapshot contains the pre-chat action before reservations hide it")
	expect(scene.colony.daily_state("mateo").kind == "speaking", "live daily state is speaking while the snapshot remains about the interrupted activity")
	for question in ["¿Qué hacías?", "¿En qué andas?", "¿En qué andabas?", "¿Qué estás haciendo hoy?", "¿Qué estabas haciendo?", "¿Qué andas haciendo?", "¿Ordenando las herramientas?", "¿Ya casi terminas de ordenar?", "¿Qué estás reparando?"]:
		var answer: String = scene.player_chat.local_reply("mateo", question)
		expect(answer == "Estaba ordenando herramientas.", "activity question describes the real task: " + question)
	captured.activity_before_chat = "Una actividad inventada"
	expect(scene.player_chat.scene_for("mateo").activity_before_chat == "Ordenando herramientas", "caller mutation cannot change the captured scene")
	var person: Dictionary = scene.colony.get_resident("mateo")
	person.target = scene.colony.PLACES.huerto.duplicate()
	person.travel_intent = "huerto"
	person.activity = "Caminando al huerto"
	scene.player_chat.hold()
	expect(scene.player_chat.local_reply("mateo", "¿Qué hacías?") == "Estaba ordenando herramientas." and scene.player_chat.goals.mateo.intent == "huerto", "a new route goal cannot rewrite what happened before the encounter")
	var start_next_plan: String = scene.player_chat._scene.next_plan
	scene.colony.minute = 850
	person.routine = "Compartir el oficio"
	var live_scene: Dictionary = scene.player_chat.scene_for("mateo")
	expect(live_scene.next_plan == scene.colony.conversation_scene_for("mateo").next_plan and live_scene.next_plan != start_next_plan and live_scene.routine == "Compartir el oficio", "a long encounter refreshes its upcoming plan and current routine as the clock advances")
	expect(live_scene.activity_before_chat == "Ordenando herramientas" and scene.player_chat._scene.next_plan == start_next_plan, "refreshing future plans never mutates the original interrupted-action snapshot")
	var greeting: String = await turn(scene, "Hola, Mateo. ¿Cómo estás?")
	expect(greeting == "Bien, gracias. ¿Y tú?" and not greeting.contains("aprender"), "a greeting answers the greeting without starting a lesson")
	var feeling: String = await turn(scene, "Bien, gracias.")
	expect(feeling.contains("Me alegra") and not feeling.contains("bicicleta") and not feeling.contains("¿"), "a short wellbeing answer acknowledges the last turn without reciting a goal")
	greeting = await turn(scene, "¿Cómo estás?")
	var reciprocal: String = await turn(scene, "¿Y tú?")
	expect(reciprocal.contains("estoy bien") and not reciprocal.contains("herramientas"), "a reciprocal question after wellbeing stays on the wellbeing topic")
	await turn(scene, "¿Qué hacías?")
	var continuation: String = await turn(scene, "¿Y eso?")
	expect(continuation.contains("herramienta") and not continuation.contains("¿"), "an elliptical follow-up explains the actual previous topic rather than asking for clarification")
	var method: String = scene.player_chat.local_reply("mateo", "¿Cómo las organizas?")
	expect(method.contains("por tipo") and not method.contains("ya"), "the organizing follow-up explains a method without inventing completed work")
	var remaining: String = scene.player_chat.local_reply("mateo", "¿Te falta mucho por ordenar?")
	expect(remaining == "Estaba ordenando las herramientas cuando llegaste.", "a progress question does not invent how much sorting remains")
	reciprocal = await turn(scene, "¿Y tú?")
	expect(reciprocal.contains("ordenando herramientas"), "a reciprocal follow-up after an activity stays on that activity")
	var after: String = scene.player_chat.local_reply("mateo", "¿Y después?")
	expect(after.begins_with("Después pensaba ") and not after.contains("bicicleta"), "the next-plan question names the schedule's future destination without reciting a lifelong goal")
	expect(scene.player_chat.local_reply("mateo", "¿Qué planes tienes?") == after, "different future questions use the same grounded next plan")
	expect(scene.player_chat.local_reply("mateo", "Ya veo.") == "Sí.", "a simple acknowledgment receives a simple acknowledgment")
	var farewell: String = await turn(scene, "Me tengo que ir, nos vemos.")
	expect(farewell == "Nos vemos. Que estés bien." and not farewell.contains("¿") and scene.player_chat.ended("mateo") and scene.colony.conversation_holds.is_empty(), "a farewell ends the exchange naturally without another question or mission")
	expect(scene.provider_calls == 0, "all local turns complete with no provider request")
	var messages: Array = scene.player_chat.messages("mateo")
	var bounded := true
	for message: Dictionary in messages:
		if message.speaker_id == "mateo": bounded = bounded and message.text.length() <= 180 and message.text.split(" ", false).size() <= 30
	expect(bounded, "every completed local reply obeys the same compact voice limits")
	expect(scene.colony.get_resident("mateo").memories.back().origin == "Conversación local · respuesta predeterminada", "local conversations keep their actual predetermined source")
	scene.end_player_conversation()
	expect(scene.player_chat.scene_for("mateo").is_empty(), "finishing an encounter discards its temporary scene")
	scene.free()
	await process_frame

	scene = fixture()
	place(scene, "mateo", [236.0, 230.0], "mateo")
	place(scene, "player", [220.0, 230.0], "mateo")
	person = scene.colony.get_resident("mateo")
	person.routine_place = "casa"
	person.routine = "Descanso"
	scene.start_player_conversation("mateo")
	var rest: String = scene.player_chat.local_reply("mateo", "¿Qué estás haciendo hoy?")
	expect(rest.contains("descansando en casa") and not rest.contains("bicicleta") and not rest.contains("durmiendo"), "an awake neighbor at home describes actual rest rather than their profession or sleep")
	expect(scene.player_chat.local_reply("mateo", "¿Te acompaño un rato?").contains("compañía"), "a request for company receives an answer rather than a lesson")
	scene.free()
	await process_frame

	scene = fixture()
	person = scene.colony.get_resident("mateo")
	person.target = scene.colony.PLACES.huerto.duplicate()
	person.travel_intent = "huerto"
	scene.start_player_conversation("mateo")
	var walking: String = scene.player_chat.local_reply("mateo", "¿Hacia dónde vas?")
	expect(walking.contains("hacia el huerto") and not walking.contains("repar"), "a walking neighbor names the actual interrupted destination")
	scene.free()
	await process_frame

	scene = fixture()
	person = scene.colony.get_resident("mateo")
	person.routine = "Reparar bicicletas"
	scene.start_player_conversation("mateo")
	var idle: String = scene.player_chat.local_reply("mateo", "¿Qué hacías?")
	expect(idle == "Estaba haciendo una pausa aquí.", "an idle routine title is not claimed as an action already underway")
	for question in ["¿Qué tal va todo?", "No muy bien", "Gracias", "¿Dónde consigo aceite?", "Ya tengo el aceite.", "Aún no tengo aceite.", "¿Cómo aplico el aceite?", "¿Quién te enseñó el oficio?", "¿Me enseñas tu dibujo?", "Ahora prefiero conversar.", "No entiendo esa explicación."]:
		var answer: String = scene.player_chat.local_reply("mateo", question)
		expect(not answer.is_empty() and answer.length() <= 180 and answer.split(" ", false).size() <= 30 and not answer.contains("Conversando con"), "bounded local response remains contextual: " + question)
	expect(not scene.player_chat.local_reply("mateo", "¿Cómo aplico el aceite?").contains("tienda"), "an oil application follow-up advances beyond the already explained shop")
	var inventory_reply: String = scene.player_chat.local_reply("mateo", "Ya tengo el aceite.")
	expect(inventory_reply.contains("Puedes dármelo aquí") and not inventory_reply.contains("taller"), "an inventory statement offers delivery beside the mentor without claiming it already occurred or requiring the workshop")
	expect(scene.colony.get_resident("mateo").memories.is_empty() and scene.colony.progression_state().quests.is_empty(), "pure reply selection neither fabricates exchanges nor grants progression")
	scene.free()
	await process_frame
	print("LOCAL CHAT: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
