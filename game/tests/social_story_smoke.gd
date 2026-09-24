extends SceneTree
## Real Colony dialogue and persistence. All save files are temporary test artifacts.
const Colony = preload("res://scripts/colony.gd")
const Navigation = preload("res://scripts/navigation.gd")
const CLAIM := "lupita_meal_worry"
const MENTION := "Me dijeron que te da miedo organizar la comida."
var checks := 0
var failures: Array[String] = []
var scratch: Array[String] = []
func _initialize(): call_deferred("run")
func expect(value: bool,label: String):
	checks+=1
	if not value: failures.append(label);push_error(label)
func fresh():
	var world=Colony.new()
	world.setup(false,true)
	world._social._willingness_roll=func():return 1.0
	world.minute=720
	for person: Dictionary in world.residents:
		person.room=person.id
		person.pos=[236.0,252.0];person.target=person.pos.duplicate()
		person.travel_intent=""
		person.erase("travel_route")
		person.erase("sleep")
	return world
func together(world,a: String,b: String):
	for id in [a,b]:
		var person: Dictionary=world.get_resident(id)
		person.room="street"
		person.pos=[240.0,210.0] if id==a else [260.0,210.0]
		person.target=person.pos.duplicate()
		person.travel_intent=""
		person.erase("travel_route")
	world.conversation_holds.clear()
func close_relation(world,owner: String,partner: String):
	var value: Dictionary=world.get_resident(owner).relationships[partner]
	value.trust=85.0;value.affection=65.0;value.frustration=0.0;value.tolerance=90.0;value.cooldown_until=0
	value.updated_at=world.minute
func leak_to_player(world) -> bool:
	together(world,"mateo","player")
	close_relation(world,"mateo","player")
	var allowed := false
	# Search a genuinely eligible authored window; never bypass can_share.
	for day in range(90):
		world.minute=720+day*1440
		if world.social_knowledge.can_share("mateo","player",CLAIM): allowed=true;break
	expect(allowed,"a trusted listener can reach a real eligible disclosure window")
	if not allowed:return false
	var prepared: String=world.social_knowledge.share_line("mateo","player",CLAIM)
	expect(not prepared.is_empty(),"allowed secret produces a bounded attributed line")
	expect(world.social_knowledge.knowledge_for("player",CLAIM).is_empty(),"preparing a line grants no player knowledge")
	var snapshot: String=JSON.stringify(world.social_knowledge.snapshot())
	world.social_dialogue.reply("mateo","player","¿Qué sabes de Lupita?")
	expect(JSON.stringify(world.social_knowledge.snapshot())==snapshot,"preparing a social reply is pure")
	var committed: bool=world.record_dialogue("player","mateo","¿Qué sabes de Lupita?",prepared,"Conversación local")
	expect(committed,"real completed Mateo conversation records successfully")
	var heard: Dictionary=world.social_knowledge.knowledge_for("player",CLAIM)
	expect(not heard.is_empty() and heard.get("source_id","")=="mateo","player learns only from the actual speaker")
	expect(heard.get("certainty","")!="observed","hearing a secret is not direct observation")
	return committed and not heard.is_empty()
func expose(world) -> bool:
	if not leak_to_player(world):return false
	together(world,"player","lupita")
	var response: String=world.social_dialogue.reply("lupita","player",MENTION)
	expect(response.contains("?") and not response.is_empty(),"Lupita recognizes a concrete undisclosed detail")
	expect(world.social_knowledge.pending_case("lupita","player").is_empty(),"prepared surprise creates no incident yet")
	expect(world.record_dialogue("player","lupita",MENTION,response,"Conversación local"),"natural mention actually reaches Lupita")
	var incident: Dictionary=world.social_knowledge.pending_case("lupita","player")
	expect(not incident.is_empty() and incident.get("suspects",[])==["mateo"],"suspects come only from Lupita's own deliberate confidants")
	return not incident.is_empty()
func answer_case(world,text: String) -> String:
	var reply: String=world.social_dialogue.reply("lupita","player",text)
	expect(not reply.is_empty(),"local case handles "+text)
	if not reply.is_empty():expect(world.record_dialogue("player","lupita",text,reply,"Conversación local"),"case reply commits "+text)
	return reply
func temp_path(label: String) -> String:
	var directory: String=ProjectSettings.globalize_path("res://../artifacts/social-gossip")
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String=directory+"/story-"+label+"-"+str(OS.get_process_id())+".json"
	scratch.append(path)
	return path
func review_privacy_boundaries():
	var world=fresh()
	together(world,"player","lupita")
	var unrelated := "Inés me contó que le da miedo organizar una comida y te quería preguntar por ella."
	expect(CLAIM not in world.social_knowledge.matched_claims("lupita",unrelated,"player","lupita"),"a pronoun elsewhere cannot change explicitly named Inés into Lupita")
	world.record_dialogue("player","lupita",unrelated,"No sé cómo se siente Inés.","Prueba local")
	expect(world.social_knowledge.pending_case("lupita","player").is_empty(),"another person's worry does not trigger Lupita's secret incident")
	world=fresh();together(world,"player","mateo")
	var before: Dictionary=world.social_knowledge.knowledge_for("mateo",CLAIM)
	world.record_dialogue("player","mateo","No es cierto que Inés tenga miedo de organizar una comida.","No sé cómo se siente Inés.","Prueba local")
	var after: Dictionary=world.social_knowledge.knowledge_for("mateo",CLAIM)
	expect(after.get("confidence")==before.get("confidence") and after.get("certainty")==before.get("certainty"),"denial about Inés cannot weaken an unrelated confidence about Lupita")
	# Repeating existing topics to a new listener must respect the same memory cap.
	world=fresh();together(world,"player","ines")
	for index in range(63):
		world.social_knowledge.hear_statement("ines","player","He visto una piedra numerada %d junto al camino." % index,"public")
	together(world,"player","mateo")
	for index in range(63):
		world.social_knowledge.hear_statement("mateo","player","He visto una piedra numerada %d junto al camino." % index,"public")
	var saturated: Dictionary=world.social_knowledge.snapshot()
	expect(saturated.knowledge.mateo.size()<=64,"known-topic repetition cannot overflow a listener's knowledge cap")
	expect(world.social_knowledge.validate(saturated,world.minute),"a saturated conversation remains a valid save state")
	# Hundreds of mundane tellings cannot erase the owner's deliberate confidants.
	world=fresh()
	for listener: String in ["ines","mateo","cesar","lupita","alma"]:
		together(world,"player",listener)
		for index in range(61):
			world.social_knowledge.hear_statement(listener,"player","Vi el objeto público número %d en el paseo." % index,"public")
	expect(world.social_knowledge.disclosed_to("lupita","mateo",CLAIM),"public chatter preserves the original deliberate confidence")
	together(world,"mateo","lupita")
	world.record_dialogue("mateo","lupita",world.social_knowledge.claim(CLAIM).text,"Gracias por escucharme.","Prueba local")
	expect(world.social_knowledge.pending_case("lupita","mateo").is_empty(),"bounded disclosure history cannot make an old confidant look unauthorized")
func run():
	if "--ui-test" not in OS.get_cmdline_user_args():quit(1);return
	review_privacy_boundaries()
	expect(Navigation.is_walkable(Vector2(240,210),"street") and Navigation.is_walkable(Vector2(260,210),"street") and Navigation._clear_segment(Vector2(240,210),Vector2(260,210),"street"),"story actors have real clear geometry")
	var world=fresh()
	for id in ["lupita","mateo","cesar","ines","alma","player"]:
		expect(world.social_knowledge.knowledge_for(id,CLAIM).is_empty()==(id not in ["lupita","mateo"]),"initial confidence limited: "+id)
	for text: String in ["¿Cuándo será la comida vecinal?","Me gusta la comida vecinal.","Lupita quiere organizar una comida vecinal."]:
		expect(CLAIM not in world.social_knowledge.matched_claims("lupita",text),"ordinary meal text is not a secret: "+text)
		together(world,"player","lupita")
		world.record_dialogue("player","lupita",text,"Todavía estoy pensando cómo organizarla.","Conversación local")
	expect(world.social_knowledge.pending_case("lupita","player").is_empty(),"ordinary conversation creates no privacy incident")
	world=fresh()
	if expose(world):
		var before: Dictionary=world.relationship_for("lupita","mateo")
		expect(world.social_dialogue.case_intent("lupita","player","Sí.").get("intent","")!="admit","yes after generic how is ambiguous")
		answer_case(world,"Sí.")
		expect(world.social_knowledge.pending_confrontation("lupita","mateo").is_empty(),"ambiguous yes cannot accuse Mateo")
		expect(world.social_dialogue.case_intent("lupita","player","¿Fue Inés?").get("intent","")!="admit","a question naming Inés is not testimony")
		answer_case(world,"¿Fue Inés?")
		expect(world.social_knowledge.pending_confrontation("lupita","ines").is_empty(),"question cannot create accusation against Inés")
		answer_case(world,"Me lo contó Mateo.")
		var confrontation: Dictionary=world.social_knowledge.pending_confrontation("lupita","mateo")
		expect(not confrontation.is_empty(),"explicit named testimony queues a later clarification")
		expect(world.relationship_for("lupita","mateo").trust==before.trust,"unresolved hearsay does not convict Mateo")
		var hidden: String=JSON.stringify(world.context_for("ines","player","Lupita"))
		expect(not hidden.contains("miedo a organizar") and not hidden.contains("miedo organizar") and not hidden.contains("que nadie vaya"),"unrelated NPC context does not inherit the leaked private detail")
		# Save and load the actual chain/case before the later physical meeting.
		var persisted: Dictionary=world.social_knowledge.snapshot()
		world.save_path=temp_path("chain")
		expect(world.save_game(),"new social state passes production save validation")
		var loaded=fresh();loaded.save_path=world.save_path
		expect(loaded.load_game(),"saved social state loads through Colony")
		# JSON represents persisted integer counters as numbers on load.
		expect(loaded.social_knowledge.snapshot()==JSON.parse_string(JSON.stringify(persisted)),"source chain and pending cases survive reload")
		expect(not loaded.social_knowledge.knowledge_for("player",CLAIM).is_empty() and loaded.social_knowledge.knowledge_for("ines",CLAIM).is_empty(),"load preserves distinct individual knowledge")
		together(loaded,"lupita","mateo")
		close_relation(loaded,"lupita","mateo")
		var future_secret: String=loaded.social_knowledge.note_opinion("lupita","mateo","A Lupita le preocupa pedir ayuda para su siguiente reunión.","secret","review-next-confidence")
		expect(not future_secret.is_empty() and loaded.social_knowledge.can_share("lupita","mateo",future_secret),"high trust would permit a genuinely new confidence before the admitted breach")
		var lp: Array=loaded.get_resident("lupita").pos.duplicate()
		var mp: Array=loaded.get_resident("mateo").pos.duplicate()
		var lines: Dictionary=loaded.social_dialogue.encounter_pair("lupita","mateo")
		expect(lines.get("kind","")=="confrontation","a real later meeting prioritizes the pending issue")
		expect(loaded.get_resident("lupita").pos==lp and loaded.get_resident("mateo").pos==mp,"planning confrontation never pursues or teleports")
		if not lines.is_empty():
			expect(loaded.record_dialogue("lupita","mateo",lines.first,lines.reply,"Conversación local · confrontation"),"physical confrontation completes through standard dialogue")
			expect(loaded.social_knowledge.pending_confrontation("lupita","mateo").is_empty(),"completed confrontation is consumed once")
			expect(loaded.social_dialogue.encounter_pair("lupita","mateo").get("kind","")!="confrontation","same incident cannot repeat indefinitely")
			expect(loaded.relationship_for("lupita","mateo").trust>70,"breach test does not depend on crossing the ordinary trust threshold")
			expect(not loaded.social_knowledge.can_share("lupita","mateo",future_secret),"confirmed indiscretion blocks a new secret even after an immediate apology")
			loaded.minute+=1440
			expect(not loaded.social_knowledge.can_share("lupita","mateo",future_secret),"new-confidence boundary survives overnight emotional recovery")
			loaded.save_path=temp_path("boundary")
			expect(loaded.save_game(),"resolved breach and new private topic save correctly")
			var restored=fresh();restored.save_path=loaded.save_path
			expect(restored.load_game() and not restored.social_knowledge.can_share("lupita","mateo",future_secret),"new-confidence boundary survives a real reload")
	for answer: String in ["No me lo contó nadie.","Prefiero no decir quién fue.","Cambiemos de tema."]:
		world=fresh()
		if expose(world):
			answer_case(world,answer)
			expect(world.social_knowledge.pending_confrontation("lupita","mateo").is_empty(),"no invented source after "+answer)
	world=fresh()
	if expose(world):
		var before: float=world.relationship_for("lupita","ines").trust
		answer_case(world,"Me lo contó Inés.")
		var accusation: Dictionary=world.social_knowledge.pending_confrontation("lupita","ines")
		expect(not accusation.is_empty(),"player may give a disputable accusation")
		expect(accusation.get("stance","")=="suspicion" and accusation.get("heard_from","")=="player" and accusation.get("reported_source","")=="ines","false accusation remains attributed player testimony")
		expect(world.relationship_for("lupita","ines").trust==before,"false accusation alone does not punish the named NPC")
		expect(world.social_knowledge.knowledge_for("ines",CLAIM).is_empty(),"accusing Inés does not retroactively make her know the secret")
		# The report may be discussed, but cannot become verified disclosure.
		expect(not world.social_knowledge.disclosed_to("ines","player",CLAIM),"false named testimony never fabricates transmission evidence")
	world=fresh()
	world.save_path=temp_path("legacy")
	var legacy_written: bool=world.save_game()
	expect(legacy_written,"legacy fixture starts from a valid isolated save")
	if legacy_written:
		var payload: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(world.save_path))
		payload.erase("social_knowledge")
		var handle=FileAccess.open(world.save_path,FileAccess.WRITE);handle.store_string(JSON.stringify(payload));handle.close()
		var migrated=fresh();migrated.save_path=world.save_path
		expect(migrated.load_game(),"old save without ledger migrates")
		expect(not migrated.social_knowledge.knowledge_for("mateo",CLAIM).is_empty() and migrated.social_knowledge.knowledge_for("player",CLAIM).is_empty(),"migration restores authored seed only to its actual confidants")
	for path: String in scratch:
		for suffix in ["",".tmp",".bak"]:
			if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("Social story %d/%d" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
