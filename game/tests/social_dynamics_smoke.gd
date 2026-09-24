extends SceneTree
## Isolated actual encounters, no providers, no user save.
const Colony = preload("res://scripts/colony.gd")
const Dynamics = preload("res://scripts/social_dynamics.gd")
const Navigation = preload("res://scripts/navigation.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: "+label)
	else:
		failures.append(label)
		push_error("FAIL: "+label)

func fixture():
	var world = Colony.new()
	world.save_path = "user://never-written-social-dynamics-%d.json" % OS.get_process_id()
	world.setup(false,true)
	world.settlement_jobs.autonomous_enabled = false
	for person: Dictionary in world.residents: place(world,str(person.id),str(person.id),[236,252])
	return world

func dynamics(world):
	var helper = Dynamics.new()
	helper.setup(world)
	return helper

func place(world, id: String, room: String, position: Array) -> void:
	var person: Dictionary = world.get_resident(id)
	person.room = room
	person.pos = position.duplicate()
	person.target = position.duplicate()
	person.travel_intent = ""
	person.erase("sleep")

func relation(world, owner: String, partner: String, trust: float, affection: float, tolerance: float = 80.0, frustration: float = 0.0) -> void:
	var value: Dictionary = world.get_resident(owner).relationships[partner]
	value.trust = trust
	value.affection = affection
	value.tolerance = tolerance
	value.frustration = frustration
	value.updated_at = world.minute

func opinions(world, owner: String, subject: String) -> Array:
	var output: Array = []
	var state: Dictionary = world.social_knowledge.snapshot()
	for id: String in state.knowledge[owner]:
		if id.begins_with("opinion:") and state.topics[id].owner_id == owner and subject in state.topics[id].subjects: output.append(world.social_knowledge.knowledge_for(owner,id))
	return output

func containing(items: Array, fragment: String) -> Dictionary:
	for item: Dictionary in items:
		if str(item.text).contains(fragment): return item
	return {}

func run() -> void:
	var world = fixture()
	var helper = dynamics(world)
	place(world,"lupita","street",[240,210])
	place(world,"mateo","street",[260,210])
	relation(world,"lupita","mateo",82,78)
	relation(world,"mateo","lupita",22,20)
	expect(opinions(world,"lupita","mateo").is_empty(),"high metrics alone create no new opinion")
	expect(world.record_dialogue("lupita","mateo","Gracias por escucharme.","Me gusta platicar contigo.","fixture"),"physical completed conversation is recorded")
	helper.note_exchange("lupita","mateo","Gracias por escucharme.","Me gusta platicar contigo.","fixture-one")
	var thoughts: Array = opinions(world,"lupita","mateo")
	expect(not containing(thoughts,"a gusto").is_empty(),"own warm relationship becomes subjective friendship after encounter")
	var interest := containing(thoughts,"sentí interés")
	expect(not interest.is_empty() and interest.privacy == "secret" and interest.source_id == "lupita", "authored admiration may become Lupita's private interest")
	expect(str(interest.get("text","")).contains("no sé si él siente lo mismo"),"interest does not claim mutual romance or consent")
	expect(containing(opinions(world,"mateo","lupita"),"sentí interés").is_empty(),"reverse relationship is not invented")
	expect(not world.social_knowledge.can_share("lupita","player",str(interest.get("id",""))),"private interest stays hidden from unfamiliar listener")
	var state: Dictionary = world.social_knowledge.snapshot()
	helper.note_exchange("lupita","mateo","Gracias por escucharme.","Me gusta platicar contigo.","fixture-one")
	expect(state == world.social_knowledge.snapshot(),"duplicate callback does not duplicate feelings or memories")
	relation(world,"mateo","lupita",20,20,15,80)
	helper.note_exchange("mateo","lupita","Ahora prefiero estar solo.","Está bien.","fixture-frustration")
	expect(not containing(opinions(world,"mateo","lupita"),"tomar distancia").is_empty(),"frustration creates only own wish for distance")
	relation(world,"alma","cesar",90,90)
	place(world,"alma","street",[240,210])
	place(world,"cesar","street",[260,210])
	helper.note_exchange("alma","cesar","Hola.","Hola.","fixture-unrelated")
	expect(containing(opinions(world,"alma","cesar"),"sentí interés").is_empty(),"high affection in unrelated pair does not generate automatic romance")

	world = fixture()
	helper = dynamics(world)
	place(world,"lupita","street",[240,210])
	place(world,"mateo","homes",[240,210])
	relation(world,"lupita","mateo",90,90)
	helper.note_exchange("lupita","mateo","Hola.","Hola.","different-area")
	expect(opinions(world,"lupita","mateo").is_empty(),"identical coordinates in different areas cannot form impressions")
	place(world,"mateo","street",[400,210])
	helper.note_exchange("lupita","mateo","Hola.","Hola.","far-away")
	expect(opinions(world,"lupita","mateo").is_empty(),"remote exchange is ignored")
	place(world,"mateo","street",[260,210])
	world.get_resident("mateo")["sleep"] = {"started":world.minute,"until":world.minute+30}
	helper.note_exchange("lupita","mateo","Hola.","Hola.","sleeping")
	expect(opinions(world,"lupita","mateo").is_empty(),"sleeping participant cannot supply a new social event")

	world = fixture()
	helper = dynamics(world)
	place(world,"mateo","street",[240,210])
	place(world,"ines","street",[260,210])
	place(world,"lupita","street",[248,195])
	relation(world,"lupita","mateo",80,75,45,10)
	var before: float = world.relationship_for("lupita","mateo").frustration
	helper.note_exchange("mateo","ines","Buenas tardes.","Hola, Mateo.","witnessed-one")
	var own: Dictionary = containing(opinions(world,"lupita","mateo"),"me sentí un poco fuera")
	expect(not own.is_empty(),"awake close friend may notice their own feeling of exclusion")
	expect(is_equal_approx(world.relationship_for("lupita","mateo").frustration,before+2),"inclusion frustration is small and bounded")
	expect(str(own.get("text","")).contains("no sé si fue intencional"),"feeling is not proof of intentional rejection")
	var feelings: Array = world.get_resident("lupita").memories.filter(func(memory): return memory.kind == "sentimiento")
	expect(feelings.size() == 1 and feelings[0].participants == ["lupita"],"private episode belongs only to actual witness")
	expect(world.get_resident("ines").memories.is_empty(),"other participants do not learn the witness's unspoken feelings")
	helper.note_exchange("mateo","ines","Qué gusto.","Igualmente.","witnessed-two")
	expect(is_equal_approx(world.relationship_for("lupita","mateo").frustration,before+2),"different conversation same day cannot stack frustration")
	# Recreate helper as on reload: the already persisted episode enforces the cap.
	helper = dynamics(world)
	helper.note_exchange("mateo","ines","Hasta luego.","Nos vemos.","witnessed-after-load")
	expect(is_equal_approx(world.relationship_for("lupita","mateo").frustration,before+2),"reinitializing helper cannot bypass persisted daily cap")
	var restored = fixture()
	restored.get_resident("lupita").memories = feelings.duplicate(true)
	restored.get_resident("lupita").relationships = world.get_resident("lupita").relationships.duplicate(true)
	expect(restored.social_knowledge.restore(world.social_knowledge.snapshot()),"dynamic opinions round-trip through existing ledger validation")
	world.minute += 1440
	relation(world,"lupita","mateo",80,75,45,10)
	helper.note_exchange("mateo","ines","Buenas tardes.","Hola.","witnessed-next-day")
	expect(is_equal_approx(world.relationship_for("lupita","mateo").frustration,12),"another day's firsthand event can have one small new effect")
	expect(opinions(world,"lupita","mateo").size() == 1,"daily observations reuse stable bounded opinion")

	world = fixture()
	helper = dynamics(world)
	place(world,"mateo","street",[240,210])
	place(world,"ines","street",[260,210])
	place(world,"lupita","homes",[248,195])
	relation(world,"lupita","mateo",80,75,45,10)
	helper.note_exchange("mateo","ines","Hola.","Hola.","remote-witness")
	expect(world.relationship_for("lupita","mateo").frustration == 10,"remote close friend feels no unseen exclusion")
	place(world,"lupita","street",[244,250])
	helper.note_exchange("mateo","ines","Hola.","Hola.","occluded-witness")
	expect(opinions(world,"lupita","mateo").is_empty(),"a fountain blocking sight prevents witnessing the conversation")
	place(world,"lupita","street",[248,195])
	world.get_resident("lupita")["sleep"] = {"started":world.minute,"until":world.minute+30}
	helper.note_exchange("mateo","ines","Hola.","Hola.","sleeping-witness")
	expect(opinions(world,"lupita","mateo").is_empty(),"sleeping close friend witnesses nothing")
	world.get_resident("lupita").erase("sleep")
	relation(world,"lupita","mateo",80,75,90,0)
	helper.note_exchange("mateo","ines","Hola.","Hola.","secure-witness")
	expect(opinions(world,"lupita","mateo").is_empty(),"warm friendship alone never implies jealousy")

	world = fixture()
	helper = dynamics(world)
	place(world,"mateo","street",[240,210])
	place(world,"ines","street",[260,210])
	world.settlement.note_event("mateo","Mateo aportó materiales al barrio.","comunidad")
	var memory: Dictionary = world.get_resident("ines").memories.back()
	helper.note_world_memory("ines",memory)
	expect(not containing(opinions(world,"ines","mateo"),"hacer equipo").is_empty(),"witnessed community help can create own willingness to cooperate")
	expect(opinions(world,"alma","mateo").is_empty(),"absent residents gain no opinion of unseen help")
	var topics: int = world.social_knowledge.snapshot().topics.size()
	helper.note_world_memory("ines",memory)
	expect(world.social_knowledge.snapshot().topics.size() == topics,"replaying world memory cannot duplicate alliance")
	place(world,"alma","street",[250,230])
	var reported: Dictionary = world._memory("ayuda",["mateo","alma"],"Mateo ayudó.","informe escuchado de Mateo")
	reported["heard_from"] = "mateo"
	world._remember(world.get_resident("alma"),reported)
	helper.note_world_memory("alma",reported)
	expect(opinions(world,"alma","mateo").is_empty(),"hearsay is not treated as firsthand cooperation")
	var unrecorded: Dictionary = world._memory("ayuda",["mateo","alma"],"Mateo ayudó.","actividad presencial verificada")
	helper.note_world_memory("alma",unrecorded)
	expect(opinions(world,"alma","mateo").is_empty(),"uncommitted action preview creates no opinion")
	expect(not FileAccess.file_exists(world.save_path),"fixture never writes a user save")
	print("SOCIAL DYNAMICS: %d/%d" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
