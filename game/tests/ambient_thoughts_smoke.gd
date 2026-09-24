extends SceneTree
## Local presentation and live-scene suppression, without providers or saved progress.
const Colony = preload("res://scripts/colony.gd")
const Thoughts = preload("res://scripts/ambient_thoughts.gd")
const Layout = preload("res://scripts/world_layout.gd")

class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func decide_with_jev() -> void: provider_calls += 1
	func request_dialogue(_resident: String, _speaker: String, _utterance: String) -> void: provider_calls += 1

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func place(world, id: String, room: String, point: Vector2) -> void:
	var resident: Dictionary = world.get_resident(id)
	resident.room = room
	resident.pos = [point.x,point.y]
	resident.target = resident.pos.duplicate()
	resident.travel_intent = ""

func visible(thoughts, world) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for resident: Dictionary in world.residents:
		var thought: Dictionary = thoughts.visible_for(resident.id)
		if not thought.is_empty(): result.append(thought)
	return result

func next_visible(thoughts, world, room: String = "street") -> Dictionary:
	for _frame in range(260):
		thoughts.advance(0.25,room)
		var entries := visible(thoughts,world)
		if not entries.is_empty(): return entries.front()
	return {}

func texts(thoughts, id: String) -> Array[String]:
	var result: Array[String] = []
	for candidate: Dictionary in thoughts.candidates(id): result.append(candidate.text)
	return result

func snapshot(world) -> String:
	return JSON.stringify({"minute": world.minute, "residents": world.residents, "events": world.events, "progression": world.progression_state()})

func fixture_world():
	var world = Colony.new()
	world.setup(false, true)
	for resident: Dictionary in world.residents:
		place(world,resident.id,"street",Vector2(280,180))
	world._daily_life.setup(world)
	return world

func run() -> void:
	root.size = Vector2i(768,432)
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --ui-test; refusing to access normal progress.")
		quit(1)
		return
	var world = fixture_world()
	var thoughts = Thoughts.new(world)
	var untouched := snapshot(world)
	var appearances: Array[Dictionary] = []
	var previous_signature := ""
	var maximum := 0
	var valid := true
	var no_player := true
	for _frame in range(3000):
		thoughts.advance(0.1,"street")
		var entries := visible(thoughts,world)
		maximum = maxi(maximum,entries.size())
		if entries.is_empty(): continue
		var entry: Dictionary = entries.front()
		valid = valid and entry.alpha > 0.0 and entry.alpha <= 1.0 and entry.text.length() <= 60 and not "\n" in entry.text
		valid = valid and float(entry.until) - float(entry.started) >= 3.0 and float(entry.until) - float(entry.started) <= 4.5
		no_player = no_player and entry.id != "player"
		var signature := "%s:%s" % [entry.id,entry.started]
		if signature != previous_signature:
			appearances.append(entry)
			previous_signature = signature
	expect(appearances.size() >= 12 and maximum == 1, "five visible neighbors produce occasional thoughts with at most one on screen")
	expect(valid and no_player, "thoughts are short, fade within valid alpha bounds, last three to four-and-a-half seconds and exclude the manual player")
	var cadence := true
	var cooldown := true
	var prior_by_id: Dictionary = {}
	var prior_texts: Dictionary = {}
	var varied := true
	for index in range(appearances.size()):
		var entry: Dictionary = appearances[index]
		if index > 0:
			var gap: float = float(entry.started) - float(appearances[index-1].until)
			cadence = cadence and gap >= 9.99 and gap <= 16.11
		if prior_by_id.has(entry.id): cooldown = cooldown and float(entry.started) - float(prior_by_id[entry.id]) >= 40.0
		if prior_texts.has(entry.id): varied = varied and entry.text != prior_texts[entry.id]
		prior_by_id[entry.id] = entry.started
		prior_texts[entry.id] = entry.text
	expect(cadence and cooldown, "appearances leave ten to sixteen seconds of quiet and at least forty seconds before the same neighbor returns")
	expect(prior_by_id.size() == 5 and varied, "every available neighbor gets a turn without immediately repeating their own thought")
	expect(snapshot(world) == untouched, "five presentation minutes change no clock, memories, relationships, skills, inventory or events")

	var active := next_visible(thoughts,world)
	expect(not active.is_empty(), "a concrete active thought is available for interruption checks")
	if not active.is_empty():
		world.conversation_holds.assign([str(active.id)])
		expect(thoughts.visible_for(active.id).is_empty(), "reserving the thinker for a conversation removes the thought immediately")
		world.conversation_holds.clear()
		thoughts.advance(0.1,"player")
		expect(visible(thoughts,world).is_empty(), "changing rooms clears the old room's thought without carrying it indoors")
	thoughts = Thoughts.new(world)
	active = next_visible(thoughts,world)
	thoughts.advance(0.1,"street",true)
	expect(visible(thoughts,world).is_empty(), "explicit suppression removes an active thought")
	thoughts.advance(0.1,"street")
	expect(visible(thoughts,world).is_empty(), "ending suppression does not immediately replay the previous thought")

	# With one eligible neighbor, silence wins over filling the display before their cooldown.
	for resident: Dictionary in world.residents:
		if resident.id != "cesar": place(world,resident.id,resident.id,Layout.point(Layout.data().entry))
	thoughts = Thoughts.new(world)
	var first := next_visible(thoughts,world)
	thoughts.advance(4.1,"street")
	var second := next_visible(thoughts,world)
	expect(first.get("id","") == "cesar" and second.get("id","") == "cesar" and second.started-first.started >= 40.0, "a lone neighbor cannot repeatedly fill the screen during their cooldown")
	place(world,"cesar","cesar",Layout.stand_at("bed","cesar"))
	world.start_sleep("cesar",60)
	thoughts = Thoughts.new(world)
	for _frame in range(120): thoughts.advance(0.5,"cesar")
	expect(visible(thoughts,world).is_empty(), "a physically sleeping neighbor does not display awake thoughts")
	world.wake_resident("cesar")
	world.player_autonomy = true
	place(world,"player","street",Vector2(280,180))
	thoughts = Thoughts.new(world)
	expect(next_visible(thoughts,world).get("id","") == "player", "the autonomous protagonist can think when they are the only person on screen")
	world.player_autonomy = false
	expect(thoughts.visible_for("player").is_empty(), "taking manual control immediately removes the protagonist's autonomous thought")

	# Candidate content follows observable context; desires are not completed actions.
	world = fixture_world()
	thoughts = Thoughts.new(world)
	place(world,"cesar",Layout.place_area("huerto"),Layout.point(world.PLACES.huerto))
	place(world,"ines",Layout.place_area("cafe"),Layout.point(world.PLACES.cafe))
	expect("Me alegra ver las plantas." in texts(thoughts,"cesar") and "Se me antoja un cafecito." in texts(thoughts,"ines"), "nearby plants and cafe add physically local ideas")
	place(world,"cesar","cesar",Layout.point(Layout.data().entry))
	expect("Qué a gusto en casa." in texts(thoughts,"cesar") and "Me alegra ver las plantas." not in texts(thoughts,"cesar"), "being home removes outdoor location thoughts")
	expect("Sin prisa sale mejor." in texts(thoughts,"cesar") and "Qué ganas de ver amigos." in texts(thoughts,"lupita") and "Todo tiene su arreglo." in texts(thoughts,"mateo"), "personality and role contribute distinct first-person thoughts")
	world.minute = 3*1440 + 900
	expect(world.weather_state().feeling == "calor" and "Qué calor hace hoy." in texts(thoughts,"ines"), "hot daytime thoughts agree with the fictional saved game clock")
	world.minute = 180
	expect(world.weather_state().period == "noche" and world.weather_state().feeling == "fresco" and "Qué tranquila la noche." in texts(thoughts,"ines") and "Qué calor hace hoy." not in texts(thoughts,"ines"), "cool night replaces daytime heat rather than claiming real-world weather")
	expect("Está fresco afuera." not in texts(thoughts,"cesar"), "an indoor resident does not claim the outdoor weather as their current place")
	world.minute = 600
	place(world,"mateo",Layout.place_area("taller"),Layout.point(world.PLACES.taller))
	world.tick(false)
	world.apply_decision("mateo","taller")
	for _tick in range(3):
		var mateo: Dictionary = world.get_resident("mateo")
		mateo.pos = mateo.target.duplicate()
		world.on_arrival("mateo")
		world.tick(false)
	var task: Dictionary = world.daily_state("mateo")
	var task_text: String = "A ver si ahora gira." if task.action == "repair" else "Cada cosa en su lugar."
	expect(task.kind == "working" and task.action in ["repair","sort_tools"] and task_text in texts(thoughts,"mateo"), "a real active workshop task contributes its specific thought")
	world.apply_decision("mateo","huerto")
	expect(task_text not in texts(thoughts,"mateo"), "leaving the task removes that concrete work thought while traveling")

	var scene := MainProbe.new()
	scene.managed_by_shell = true
	root.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_url = ""
	scene.service_token = ""
	for action in ["city_left","city_right","city_up","city_down"]: Input.action_release(action)
	for resident: Dictionary in scene.colony.residents: place(scene.colony,resident.id,"street",Vector2(280,180))
	scene.colony._daily_life.setup(scene.colony)
	scene.paused = false
	scene.controls_active = true
	expect(not next_visible(scene.ambient_thoughts,scene.colony).is_empty(), "live scene owns the same local thought controller")
	scene.paused = true
	scene._process(0.1)
	expect(scene.ambient_suppressed() and visible(scene.ambient_thoughts,scene.colony).is_empty(), "pause clears the visible thought through the real frame loop")
	scene.paused = false
	next_visible(scene.ambient_thoughts,scene.colony)
	scene.suspend_for_menu()
	expect(visible(scene.ambient_thoughts,scene.colony).is_empty(), "opening the menu clears the thought before another frame is drawn")
	scene.resume_from_menu()
	scene.set_process(false)
	scene.controls_active = true
	scene.paused = false
	next_visible(scene.ambient_thoughts,scene.colony)
	expect(scene.start_player_conversation("mateo"), "fixture starts a genuine nearby manual encounter without sending a message")
	scene._process(0.1)
	expect(scene.ambient_suppressed() and visible(scene.ambient_thoughts,scene.colony).is_empty(), "a manual encounter suppresses ambient thoughts instead of mixing them with chat")
	scene.close_chat_panel()
	scene.show_help()
	scene._process(0.1)
	expect(scene.ambient_suppressed() and visible(scene.ambient_thoughts,scene.colony).is_empty(), "a modal reading panel also keeps the world quiet")
	scene.close_help()
	place(scene.colony,"player","player",Layout.stand_at("bed","player"))
	scene.update_room()
	expect(scene.sleep_ui.start(60), "fixture starts physical sleep at the actual bed")
	scene._process(1.0)
	expect(not scene.colony.is_sleeping("player") and visible(scene.ambient_thoughts,scene.colony).is_empty(), "accelerated sleep stays silent even on the frame that reaches wake-up")
	expect(scene.provider_calls == 0 and scene.dialogue_job.is_empty() and not scene.dialogue_request.busy, "presentation and every suppression path dispatch no Jev, OpenAI or pending dialogue")
	scene.free()
	await process_frame
	print("AMBIENT THOUGHTS: %d/%d checks passed" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
