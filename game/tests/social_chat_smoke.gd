extends SceneTree
## Main and real chat completion; in-memory transport, no personal save or provider.
class MainProbe:
	extends "res://scripts/main.gd"
	var calls: Array[Dictionary] = []
	func request_dialogue(resident_id: String, speaker_id: String, utterance: String) -> void:
		if dialogue_job.is_empty(): return
		calls.append(colony.context_for(resident_id,speaker_id,utterance))
		stream_text = ""
	func decide_with_jev() -> void: pass

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func settle() -> void:
	for i in range(4): await process_frame

func place(scene, id: String, x: float) -> void:
	var person: Dictionary = scene.colony.get_resident(id)
	person.room = "street"
	person.pos = [x,210.0]
	person.target = person.pos.duplicate()
	person.travel_intent = ""
	person.erase("travel_route")
	person.erase("sleep")
	scene.colony._daily_life.forget(id)

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --ui-test; this never loads a real save.")
		quit(1)
		return
	var scene := MainProbe.new()
	root.add_child(scene)
	scene.set_process(false)
	scene.save_allowed = false
	scene.controls_active = false
	scene.use_jev = false
	scene.service_token = "test-no-network"
	scene.service_url = ""
	scene.colony._social._willingness_roll = func(): return 1.0
	for person in scene.colony.residents:
		person.room = person.id
		person.pos = [88.0,212.0]
		person.target = person.pos.duplicate()
	place(scene,"player",236)
	place(scene,"mateo",260)
	var bond: Dictionary = scene.colony.get_resident("mateo").relationships.player
	bond.trust = 80.0
	bond.affection = 70.0
	var eligible := false
	for day in range(30):
		scene.colony.minute = day*1440+600
		if scene.colony.social_knowledge.can_share("mateo","player","lupita_meal_worry"):
			eligible = true
			break
	expect(eligible,"fixture finds an authored eligible disclosure day without bypassing policy")
	scene.selected_id = "mateo"
	scene.page = "hablar"
	scene.update_room()
	scene.build_inspector()
	var before: Dictionary = scene.colony.social_knowledge.snapshot()
	scene.send_chat_text("¿Qué sabes de Lupita?")
	expect(scene.calls.size() == 1,"ordinary connected gossip uses the existing nonblocking dialogue request")
	expect(scene.colony.social_knowledge.snapshot() == before,"preparing context and showing a pending bubble transmits nothing")
	var line: String = scene.colony.social_knowledge.share_line("mateo","player","lupita_meal_worry")
	scene._dialogue_delta(line.left(30))
	expect(scene.colony.social_knowledge.knowledge_for("player","lupita_meal_worry").is_empty(),"a partial stream does not teach a rumor")
	scene._dialogue_failed("isolated network failure")
	expect(scene.colony.social_knowledge.knowledge_for("player","lupita_meal_worry").is_empty(),"failed response leaves social knowledge unchanged")
	scene.send_chat_text("¿Qué sabes de Lupita?")
	expect(scene.calls.size() == 2,"retry requests the same pair without a second knowledge transaction")
	scene._dialogue_completed({"text":line,"suggestions":[]})
	var known: Dictionary = scene.colony.social_knowledge.knowledge_for("player","lupita_meal_worry")
	expect(not known.is_empty() and known.get("source_id","") == "mateo","completed real chat teaches only the actually spoken claim with Mateo as source")
	expect(scene.player_chat.messages("mateo").size() == 2,"failed partial attempt is absent from the clean chat")
	var after: Dictionary = scene.colony.social_knowledge.snapshot()
	scene._dialogue_completed({"text":line})
	expect(scene.colony.social_knowledge.snapshot() == after,"late duplicate completion does not spread or penalize again")
	scene.player_chat.finish()
	place(scene,"mateo",390)
	place(scene,"lupita",260)
	scene.selected_id = "lupita"
	scene.page = "hablar"
	scene.build_inspector()
	var queries: int = scene.calls.size()
	scene.send_chat_text("Me contaron que te da miedo que nadie vaya a la comida vecinal.")
	await settle()
	expect(scene.calls.size() == queries,"recognition of an undisclosed secret is resolved without an invented model accusation")
	expect(scene.player_chat.last_reply("lupita").contains("Cómo lo supiste"),"Lupita asks how the player learned her private detail")
	var choices: Array = scene.player_chat.suggestions("lupita")
	expect(choices.size() == 2 and choices[0].text.contains("Mateo") and choices[1].text.contains("Prefiero"),"quick replies offer the player's remembered source or withholding it")
	scene.send_chat_text("Me lo contó Mateo.")
	await settle()
	expect(scene.player_chat.last_reply("lupita").contains("aclararlo"),"admission leads to clarification rather than omniscient blame")
	expect(not scene.colony.social_knowledge.pending_confrontation("lupita","mateo").is_empty(),"a later physical conversation is queued from the completed admission")
	expect(scene.colony.get_resident("mateo").room == "street" and Vector2(scene.colony.get_resident("mateo").pos[0],scene.colony.get_resident("mateo").pos[1]).is_equal_approx(Vector2(390,210)),"suspicion neither teleports Mateo nor forces an instant confrontation")
	expect(scene.colony.social_knowledge.validate(scene.colony.social_knowledge.snapshot()),"all real-controller social state remains persistent and valid")
	scene.player_chat.finish()
	expect(scene.player_chat.messages("lupita").is_empty(),"closing keeps the next chat visually clean while social memory survives")
	var repeat: String = scene.colony.social_dialogue.reply("lupita","player","Me contaron que te da miedo que nadie vaya a la comida vecinal.")
	expect(not repeat.contains("Cómo lo supiste"),"an already addressed disclosure is not rediscovered as a fresh mystery")
	expect(scene.colony.social_dialogue.reply("lupita","player","Me da miedo que nadie vaya a mi comida vecinal.").is_empty(),"the player's own worry is not confused with Lupita's secret")
	var literal := "Me dijeron que Mateo quiere pintar su taller de azul."
	var economy: Dictionary = scene.colony.progression_state().duplicate(true)
	expect(scene.colony.record_dialogue("player","lupita",literal,"No lo sabía. Tendría que preguntarle.","Prueba local"),"a new literal player report can be heard in a physical conversation")
	var recorded := false
	var ledger: Dictionary = scene.colony.social_knowledge.snapshot()
	for topic_id: String in ledger.topics:
		if ledger.topics[topic_id].text != literal: continue
		var version: Dictionary = scene.colony.social_knowledge.knowledge_for("lupita",topic_id)
		recorded = not version.is_empty() and version.kind == "rumor" and version.source_id == "player" and version.subject_id == "mateo" and version.certainty == "heard"
	expect(recorded,"a new report stays literal testimony from the player about the named person")
	expect(scene.colony.progression_state() == economy,"a player's rumor cannot modify the actual workshop, inventory or economy")
	expect(scene.colony.social_knowledge.validate(scene.colony.social_knowledge.snapshot(),scene.colony.minute),"new reported information remains save-compatible")
	expect(not scene.save_allowed and scene.service_url.is_empty(),"fixture used no personal save or external provider")
	scene.queue_free()
	await settle()
	print("SOCIAL CHAT: %d/%d checks passed" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
