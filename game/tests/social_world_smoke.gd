extends SceneTree
## Real chat completion, release, walking, passing greetings and provider boundaries.
const Navigation = preload("res://scripts/navigation.gd")
const Encounters = preload("res://scripts/social_encounters.gd")
var checks := 0
var failures: Array[String] = []

class Probe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func request_dialogue(_resident: String, _speaker: String, _utterance: String) -> void:
		provider_calls += 1
	func decide_with_jev() -> void: provider_calls += 1

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func fixture() -> Probe:
	var scene := Probe.new()
	root.add_child(scene)
	scene.colony._social._willingness_roll = func(): return 1.0
	scene.set_process(false)
	scene.save_allowed = false
	scene.service_url = ""
	scene.service_token = ""
	scene.use_jev = false
	scene.paused = false
	scene.controls_active = true
	scene.hide_inspector()
	scene.colony.minute = 720
	for person: Dictionary in scene.colony.residents:
		person.room = person.id
		person.pos = [236.0,252.0]
		person.target = person.pos.duplicate()
		person.travel_intent = ""
	return scene

func place(scene: Probe, id: String, at: Vector2) -> Dictionary:
	var person: Dictionary = scene.colony.get_resident(id)
	person.room = "street"
	person.pos = [at.x,at.y]
	person.target = person.pos.duplicate()
	person.travel_intent = ""
	scene.paths.erase(id)
	if id == "player": scene.update_room()
	return person

func settle() -> void:
	await process_frame
	await process_frame

func say(scene: Probe, text: String) -> void:
	scene.send_chat_text(text)
	await settle()

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		quit(1)
		return
	root.size = Vector2i(960,540)
	var scene := fixture()
	await settle()
	var player: Dictionary = place(scene,"player",Vector2(200,180))
	var mateo: Dictionary = place(scene,"mateo",Vector2(224,180))
	expect(scene.start_player_conversation("mateo"),"a fresh neighbor accepts a normal greeting")
	await say(scene,"Hola, Mateo. ¿Cómo estás?")
	expect(scene.chat_partner_id == "mateo" and scene.player_chat.messages("mateo").size() == 2,"one ordinary greeting stays open with two short voices")
	expect("player" in scene.colony.conversation_holds and "mateo" in scene.colony.conversation_holds,"a willing pair remains still between replies")
	expect(not scene.player_chat._biography_reply("mateo").contains("abuelos"),"a new acquaintance cannot read private family history through the local fallback")
	var baseline: Dictionary = scene.colony.relationship_for("mateo","player")
	var turns := 0
	for _attempt in range(20):
		if scene.player_chat.ended("mateo"): break
		await say(scene,"¿Qué estás haciendo?")
		turns += 1
	var upset: Dictionary = scene.colony.relationship_for("mateo","player")
	expect(scene.player_chat.ended("mateo") and turns > 1 and turns <= 20,"repeated questions eventually make the neighbor end the conversation")
	expect(upset.frustration > baseline.frustration and upset.tolerance < baseline.tolerance,"repetition changes this neighbor's tolerance and frustration")
	expect(scene.chat_partner_id.is_empty() and scene.colony.conversation_holds.is_empty(),"the closing reply releases both reservations immediately")
	expect(scene.player_chat.messages("mateo").size() == 1 and not scene.player_chat.messages("mateo")[0].text.is_empty(),"the final line stays readable without replaying previous chat history")
	expect(scene.player_chat.suggestions("mateo").is_empty() and not scene.chat_input.visible and not scene.resident_ui._chat_can_send("mateo"),"a finished chat has no follow-up questions or hidden active composer")
	expect(mateo.target != mateo.pos,"the neighbor takes a real route away after setting a boundary")
	var origin: Vector2 = scene.position_of(mateo)
	var valid_steps := true
	for _step in range(240):
		var before: Vector2 = scene.position_of(mateo)
		scene.move_resident(mateo,1.0/30.0)
		var after: Vector2 = scene.position_of(mateo)
		valid_steps = valid_steps and Navigation.is_walkable(after) and after.distance_to(before) <= 1.01
	expect(valid_steps and scene.position_of(mateo).distance_to(origin) >= 18,"the departure walks around obstacles without teleporting")
	# A test placement brings the player back in hearing range of the moving NPC.
	place(scene,"player",Navigation.recover_position(scene.position_of(mateo)+Vector2(18,0)))
	scene.service_token = "captured-never-sent"
	var calls: int = scene.provider_calls
	expect(not scene.start_player_conversation("mateo"),"immediate recontact respects the neighbor's requested space")
	var refusal: Array[Dictionary] = scene.player_chat.messages("mateo")
	expect(refusal.size() == 1 and scene.chat_partner_id.is_empty() and "mateo" not in scene.colony.conversation_holds,"recontact shows only the new refusal and never pins the NPC")
	expect(scene.provider_calls == calls,"a social refusal does not wait for or spend a provider call")
	expect(scene.colony.relationship_for("mateo","player").frustration >= upset.frustration,"insisting during the cooldown cannot improve the relationship")
	place(scene,"player",Vector2(200,180))
	place(scene,"ines",Vector2(224,180))
	expect(scene.start_player_conversation("ines"),"annoying Mateo does not make Inés reject the player")
	scene.player_chat.finish()
	var trust: float = scene.colony.relationship_for("mateo","player").trust
	scene.colony.minute += 1440
	var recovered: Dictionary = scene.colony.relationship_for("mateo","player")
	expect(recovered.frustration < upset.frustration and recovered.tolerance > upset.tolerance and recovered.trust <= trust,"time and space calm emotions without manufacturing trust")
	scene.free()

	scene = fixture()
	await settle()
	place(scene,"player",Vector2(200,180))
	place(scene,"mateo",Vector2(224,180))
	scene.start_player_conversation("mateo")
	await say(scene,"¿Cómo era tu familia?")
	var privacy_choices: Array = scene.player_chat.suggestions("mateo")
	expect(not scene.player_chat.ended("mateo") and privacy_choices.size() == 2 and privacy_choices[0].text == "Lo entiendo, cambiemos de tema.","a private-topic refusal offers changing subject instead of further personal questions")
	await say(scene,"Te dejo seguir. Hasta luego.")
	expect(scene.player_chat.ended("mateo") and scene.colony.relationship_for("mateo","player").cooldown_until <= scene.colony.minute,"a polite farewell closes the encounter without treating it as harassment")
	scene.free()

	for closing: String in ["Necesito espacio.", "No quiero seguir conversando."]:
		scene = fixture()
		await settle()
		place(scene,"player",Vector2(200,180))
		place(scene,"mateo",Vector2(224,180))
		scene.service_token = "captured-never-sent"
		scene.start_player_conversation("mateo")
		scene.send_chat_text("Hola, Mateo. ¿Cómo estás?")
		scene._dialogue_completed({"text":closing})
		expect(scene.player_chat.ended("mateo") and scene.colony.conversation_holds.is_empty() and scene.player_chat.suggestions("mateo").is_empty(),"an explicit model boundary also closes the actual encounter: " + closing)
		expect(scene.colony.relationship_for("mateo","player").cooldown_until > scene.colony.minute,"model departure receives the same local cooldown without trusting model stat changes")
		scene.free()

	# Autonomous neighbors give a short actual exchange, then resume original routes.
	scene = fixture()
	await settle()
	place(scene,"player",Vector2(448,288))
	var cesar: Dictionary = place(scene,"cesar",Vector2(200,180))
	var lupita: Dictionary = place(scene,"lupita",Vector2(224,180))
	cesar.target = [280.0,180.0]
	lupita.target = [300.0,180.0]
	var before_c: int = cesar.memories.size()
	scene.encounters.advance(2.2)
	expect(not scene.encounters._active.is_empty() and "cesar" in scene.colony.conversation_holds and "lupita" in scene.colony.conversation_holds,"two passing neighbors reserve only their short greeting")
	var opening: String = str(scene.encounters.visible_for("cesar").get("text",""))
	expect(not opening.is_empty() and opening.length() <= 100 and scene.encounters.visible_for("lupita").is_empty(),"only the first concise greeting is visible at first")
	scene.encounters.advance(2.3)
	var reply: String = str(scene.encounters.visible_for("lupita").get("text",""))
	expect(not reply.is_empty() and reply.length() <= 100 and scene.encounters.visible_for("cesar").is_empty(),"the other neighbor answers briefly without overlapping dialogue badges")
	scene.encounters.advance(2.3)
	expect(scene.encounters._active.is_empty() and scene.colony.conversation_holds.is_empty() and cesar.target == [280.0,180.0] and lupita.target == [300.0,180.0],"both neighbors recover their routes after the greeting")
	expect(cesar.memories.size() == before_c+1 and lupita.memories.size() == 1,"one completed greeting produces one shared encounter per participant")
	for _tick in range(50): scene.encounters.advance(0.2)
	expect(cesar.memories.size() == before_c+1 and scene.encounters._active.is_empty(),"remaining side by side does not repeat or farm greetings")
	# A later physical encounter after leaving the radius uses a new brief phrase.
	lupita.pos = [310.0,180.0]
	scene.encounters.advance(0.2)
	scene.colony.minute += 180
	lupita.pos = [224.0,180.0]
	lupita.target = [300.0,180.0]
	scene.encounters.advance(0.2)
	var second: String = str(scene.encounters.visible_for("cesar").get("text",""))
	expect(not second.is_empty() and second != opening,"meeting again later produces a distinct greeting for that pair")
	var partial_count: int = cesar.memories.size()
	scene.encounters.cancel_for("cesar")
	expect(cesar.memories.size() == partial_count and scene.colony.conversation_holds.is_empty(),"interrupting a passing greeting clears holds without storing invented dialogue")
	expect(scene.provider_calls == 0,"passing greetings run entirely locally without model calls")
	# Autonomous request selection checks both directed relationships before transport.
	cesar.relationships.lupita.cooldown_until = scene.colony.minute + 90
	var before_calls: int = scene.provider_calls
	expect(not scene.begin_npc_dialogue("cesar") and scene.provider_calls == before_calls,"an NPC cannot initiate a provider conversation with someone it asked to leave it alone")
	scene.free()

	scene = fixture()
	await settle()
	scene.colony.set_player_autonomy(true)
	player = place(scene,"player",Vector2(200,180))
	place(scene,"mateo",Vector2(224,180))
	scene.encounters.advance(2.2)
	expect("player" in scene.colony.conversation_holds,"an autonomous player may exchange a passing greeting")
	var incomplete: int = player.memories.size()
	scene.take_control()
	expect(scene.encounters._active.is_empty() and scene.colony.conversation_holds.is_empty(),"taking keyboard control immediately cancels an autonomous player's greeting")
	scene.encounters.advance(10)
	expect(player.memories.size() == incomplete and scene.provider_calls == 0,"taking control never commits an unfinished greeting or consults a provider")
	scene.free()
	print("SOCIAL WORLD: %d/%d checks passed" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
