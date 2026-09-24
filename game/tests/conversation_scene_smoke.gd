extends SceneTree
## The real request builder gets physical facts through a socket-free transport.
const Main = preload("res://scenes/main.tscn")
const Layout = preload("res://scripts/world_layout.gd")
class Transport:
	extends "res://scripts/dialogue_stream.gd"
	var payloads: Array[Dictionary] = []
	func start(_url: String, _headers: PackedStringArray, payload: Dictionary) -> Error:
		payloads.append(payload.duplicate(true))
		return OK

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error(label)

func task(world, id: String, place: String, kind: String, action: String, label: String) -> void:
	var resident: Dictionary = world.get_resident(id)
	resident.room = Layout.place_area(place)
	resident.pos = world.PLACES[place].duplicate()
	resident.target = resident.pos.duplicate()
	resident.travel_intent = ""
	resident.activity = label
	resident.routine = "Reparar bicicletas" if id == "mateo" else "Paseo"
	resident.routine_place = place
	world._daily_life._states[id] = {"key": "fixture", "place": place, "phase": "active", "until": world.minute + 20, "source": "routine", "task": {"kind": kind, "action": action, "label": label, "duration": 20}}

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Requires -- --ui-test to protect progress.")
		quit(1)
		return
	root.size = Vector2i(768, 432)
	var scene = Main.instantiate()
	root.add_child(scene)
	scene.colony._social._willingness_roll = func(): return 1.0 # This suite checks physical context, not random willingness.
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_token = "no-network-fixture"
	scene.dialogue_request.free()
	var transport := Transport.new()
	scene.add_child(transport)
	scene.dialogue_request = transport
	var world = scene.colony
	world.minute = 600
	for resident: Dictionary in world.residents:
		resident.room = resident.id
	task(world, "mateo", "taller", "working", "sort_tools", "Ordenando herramientas")
	var mateo: Dictionary = world.get_resident("mateo")
	var player: Dictionary = world.get_resident("player")
	player.room = mateo.room
	player.pos = [float(mateo.pos[0]) - 20.0, float(mateo.pos[1])]
	player.target = player.pos.duplicate()
	scene.update_room()
	var before: Dictionary = world.conversation_scene_for("mateo")
	expect(before.ongoing_action == "sort_tools" and before.activity_before_chat == "Ordenando herramientas" and before.place == "taller", "snapshot uses the actual task and its physical place")
	expect(before.next_plan.contains("Pausa para comer"), "a future schedule block is separately described as a plan")
	scene.selected_id = "mateo"
	scene.page = "hablar"
	scene.build_inspector()
	scene.send_chat_text("¿En qué andabas?")
	var payload: Dictionary = transport.payloads.back()
	var context: Dictionary = payload.resident
	expect(mateo.activity.begins_with("Conversando") and context.conversation_scene.activity_before_chat == "Ordenando herramientas", "real manual request preserves the interrupted task despite the speaking label")
	expect(context.conversation_scene.paused_for_chat and context.conversation_scene.ongoing_action == "sort_tools", "the model can distinguish doing work from pausing it to talk")
	expect(payload.suggest_replies and "Aún no tengo aceite." in payload.reply_facts, "request still includes literal choices grounded in player inventory")
	expect(JSON.stringify(context).length() <= 12000 and not context.has("progression"), "extra scene facts retain context limits and private player inventory isolation")
	scene._dialogue_completed({"text": "Estaba ordenando las herramientas del taller."})
	mateo.routine = "Pasear por la colonia"
	mateo.target = world.PLACES.plaza.duplicate()
	mateo.travel_intent = "plaza"
	scene.player_chat.hold()
	scene.send_chat_text("¿Y después?")
	expect(transport.payloads.back().resident.conversation_scene.activity_before_chat == "Ordenando herramientas", "a route update does not rewrite the activity interrupted at this encounter")
	scene.end_player_conversation()
	world._daily_life.forget("mateo")
	mateo.room = "mateo"
	mateo.pos = [180, 230]
	mateo.target = mateo.pos.duplicate()
	mateo.travel_intent = ""
	mateo.routine_place = "casa"
	mateo.routine = "Descanso"
	var at_home: Dictionary = world.conversation_scene_for("mateo")
	expect(at_home.place == "casa" and at_home.ongoing_action == "take_break" and not at_home.activity_before_chat.contains("biciclet"), "resting at home is not described as workshop work")
	mateo.room = "street"
	mateo.pos = world.PLACES.plaza.duplicate()
	mateo.target = world.PLACES.cafe.duplicate()
	mateo.travel_intent = "cafe"
	var walking: Dictionary = world.conversation_scene_for("mateo")
	expect(walking.phase == "walking" and walking.intent == "cafe" and walking.place != "cafe", "walking destination is distinct from physical location")
	mateo.target = mateo.pos.duplicate()
	mateo.travel_intent = ""
	mateo.routine = "Reparar bicicletas"
	mateo.routine_place = "taller"
	var unknown: Dictionary = world.conversation_scene_for("mateo")
	expect(unknown.ongoing_action.is_empty() and unknown.activity_before_chat.is_empty(), "a schedule or profession alone does not fabricate an active task")
	world._daily_life.forget("cesar")
	world._daily_life.forget("lupita")
	task(world, "cesar", "plaza", "leisure", "look_around", "Observando la plaza")
	task(world, "lupita", "plaza", "leisure", "take_break", "Disfrutando una pausa")
	player.room = "player"
	mateo.room = "mateo"
	world.get_resident("lupita").pos[0] += 12
	world.get_resident("lupita").target = world.get_resident("lupita").pos.duplicate()
	expect(scene.begin_npc_dialogue("cesar"), "autonomous neighbors also start a bounded conversation")
	if not scene.dialogue_job.is_empty():
		expect(transport.payloads.back().resident.conversation_scene.ongoing_action == "look_around", "the first autonomous voice receives its own pre-conversation scene")
		scene._dialogue_completed({"text": "Estaba mirando la plaza. ¿Qué tal estás?"})
		scene.continue_npc_dialogue(scene.dialogue_job.serial)
		expect(transport.payloads.back().resident.identity.id == "lupita" and transport.payloads.back().resident.conversation_scene.ongoing_action == "take_break", "the second voice gets its own scene, not the first speaker's task")
	scene.suspend_for_menu()
	scene.free()
	await process_frame
	print("CONVERSATION SCENE: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
