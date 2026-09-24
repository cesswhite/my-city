extends SceneTree
const Colony = preload("res://scripts/colony.gd")
const Knowledge = preload("res://scripts/social_knowledge.gd")
var checks := 0
var failures: Array[String] = []
var paths: Array[String] = []
const SECRET := "lupita_meal_worry"

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: "+label)
	else: failures.append(label); push_error("FAIL: "+label)

func fixture():
	var world = Colony.new()
	world.save_path = "user://social_knowledge_%d_%d.json" % [OS.get_process_id(),paths.size()]
	paths.append(world.save_path)
	world.setup(false,true)
	world.settlement_jobs.autonomous_enabled = false
	return world

func place(world, id: String, point: Vector2, room: String = "street") -> void:
	var actor: Dictionary = world.get_resident(id)
	actor.room = room; actor.pos = [point.x,point.y]; actor.target = actor.pos.duplicate()
	actor.travel_intent = ""; actor.erase("travel_route"); actor.erase("sleep")

func pair(world, a: String, b: String) -> void:
	place(world,a,Vector2(240,210)); place(world,b,Vector2(260,210))

func trust(world, a: String, b: String) -> void:
	var relation: Dictionary = world.get_resident(a).relationships[b]
	relation.trust = 85.0; relation.affection = 65.0; relation.frustration = 0.0
	relation.tolerance = 80.0; relation.cooldown_until = 0; relation.updated_at = world.minute

func leak_day(world, speaker: String, listener: String, id: String) -> bool:
	trust(world,speaker,listener)
	for day in 90:
		world.minute = day*1440+480
		if world.social_knowledge.can_share(speaker,listener,id): return true
	return false

func invalid(ledger, base: Dictionary, change: Callable, label: String) -> void:
	var modified: Dictionary = base.duplicate(true)
	change.call(modified)
	expect(not ledger.validate(modified),label)

func run() -> void:
	var inert = Knowledge.new()
	inert.note_world_memory("player",{"kind":"trabajo"})
	expect(inert.snapshot().is_empty(),"pre-setup observations are harmless")
	var world = fixture()
	var ledger = world.social_knowledge
	var initial: Dictionary = ledger.snapshot()
	expect(ledger.validate(initial),"authored historical ledger validates")
	expect(ledger.knowledge_for("player",SECRET).is_empty(),"player does not start with another person's secret")
	expect(ledger.knowledge_for("mateo",SECRET).source_id == "lupita" and ledger.knowledge_for("mateo",SECRET).certainty == "heard","historical confidence preserves immediate source and testimony")
	expect(ledger.disclosed_to("lupita","mateo",SECRET),"subject remembers historical authorized recipient")
	expect(world.get_resident("lupita").memories.is_empty() and world.get_resident("mateo").known_people.is_empty(),"historical seed invents no present meeting")
	var detached: Dictionary = ledger.snapshot(); detached.knowledge.player[SECRET] = {}
	expect(ledger.knowledge_for("player",SECRET).is_empty(),"snapshot cannot mutate ledger")
	var private_line: String = ledger.claim(SECRET).text
	var before: Dictionary = ledger.snapshot()
	for ignored in 10: ledger.context_for("mateo","player","Lupita"); ledger.candidates_for("mateo","player")
	expect(before == ledger.snapshot(),"context and candidate previews are pure")
	expect(not JSON.stringify(ledger.context_for("mateo","player","Lupita")).contains("nadie vaya"),"low-trust context withholds secret")
	expect(ledger.matched_claims("lupita","¿Cómo va la comida vecinal?").is_empty(),"generic food topic is not a secret")
	expect(SECRET in ledger.matched_claims("lupita","Me contaron que te da miedo que nadie vaya a tu comida."),"private semantic anchors survive pronoun changes")
	expect(ledger.matched_claims("lupita","No es verdad que "+private_line).is_empty(),"denial never becomes an affirmative transfer")
	pair(world,"mateo","player")
	expect(leak_day(world,"mateo","player",SECRET),"bounded deliberate leak becomes eligible in finite days")
	var eligible_day: int = int(world.minute/1440)
	expect(eligible_day < 30,"mixed day hash avoids long decimal-prefix runs")
	before = ledger.snapshot()
	expect(not ledger.transfer("mateo","player",SECRET,"inventé otro hecho","badvariant") and before == ledger.snapshot(),"unapproved model variant is rejected without mutation")
	expect(ledger.transfer("mateo","player",SECRET,"","first"),"eligible physical completed disclosure transfers known claim")
	var heard: Dictionary = ledger.knowledge_for("player",SECRET)
	expect(heard.source_id == "mateo" and heard.certainty == "heard" and heard.confidence < 80,"hearing retains immediate source and reduces confidence per hop")
	expect(ledger.pending_case("lupita","player").is_empty(),"absent subject cannot magically notice gossip")
	before = ledger.snapshot()
	expect(not ledger.transfer("mateo","player",SECRET,"","first") and before == ledger.snapshot(),"completed exchange receipt prevents duplicate propagation")
	var variant: String = ledger.claim(SECRET).variants[0]
	expect(ledger.transfer("mateo","player",SECRET,variant,"variant"),"authored uncertain distortion can be heard")
	expect(ledger.knowledge_for("player",SECRET).certainty == "uncertain","different heard versions create uncertainty")
	expect(ledger.snapshot().knowledge.player[SECRET].versions.size() == 2,"bounded evidence retains both versions")
	ledger.note_exchange("mateo","player","No es verdad que "+private_line,"Entiendo.","disagreement")
	expect(ledger.snapshot().knowledge.player[SECRET].versions.back().kind == "disagreement","disagreement is evidence rather than a verified replacement")
	var confidence: int = ledger.knowledge_for("player",SECRET).confidence
	pair(world,"player","lupita")
	ledger.note_exchange("player","lupita",private_line,"¿Cómo lo supiste?","subject-hears")
	var incident: Dictionary = ledger.pending_case("lupita","player")
	expect(not incident.is_empty() and incident.suspects == ["mateo"] and incident.stance == "suspicion","subject suspects only their own remembered recipient")
	expect(ledger.knowledge_for("lupita",SECRET).certainty == "observed" and ledger.knowledge_for("player",SECRET).confidence == confidence,"returning rumor does not downgrade firsthand knowledge or upgrade rumor")
	var actor_relation: Dictionary = world.relationship_for("lupita","mateo")
	expect(ledger.respond_case("lupita","player","admit","mateo","source-told"),"heard attribution schedules a question for the named source")
	expect(world.relationship_for("lupita","mateo") == actor_relation,"hearsay attribution alone does not punish its alleged source")
	expect(not ledger.pending_confrontation("lupita","mateo").is_empty(),"confrontation is queued only after subject hears attribution")
	pair(world,"lupita","mateo")
	trust(world,"lupita","mateo")
	var original_trust: float = world.relationship_for("lupita","mateo").trust
	expect(ledger.resolve_confrontation("lupita","mateo","question"),"face-to-face question is recorded")
	expect(world.relationship_for("lupita","mateo").trust == original_trust,"asking a question does not establish guilt")
	expect(ledger.respond_case("lupita","mateo","admit","","admit1"),"completed personal admission applies directed consequence")
	var damaged: float = world.relationship_for("lupita","mateo").trust
	expect(is_equal_approx(damaged,original_trust-10),"admission has bounded trust consequence")
	ledger.respond_case("lupita","mateo","admit","","admit2")
	expect(world.relationship_for("lupita","mateo").trust == damaged,"repeated admission cannot farm a penalty")
	expect(ledger.respond_case("lupita","mateo","apology","","apology") and is_equal_approx(world.relationship_for("lupita","mateo").trust,damaged+2),"apology repairs a small amount without resetting trust")
	expect(ledger.pending_case("lupita","mateo").is_empty(),"apology closes the confrontation")
	pair(world,"player","ines")
	var quote := "Me preocupa empezar de nuevo en este barrio sin conocer a nadie."
	var quote_id: String = ledger.hear_statement("ines","player",quote,"secret")
	expect(not quote_id.is_empty() and ledger.knowledge_for("ines",quote_id).kind == "rumor" and ledger.knowledge_for("ines",quote_id).certainty == "heard","literal confidence is unverified speaker testimony")
	expect(ledger.hear_statement("ines","player",quote,"secret") == quote_id,"same literal statement has one stable claim")
	expect(ledger.hear_statement("player","ines","Mi historia inventada cuenta como verdad.").is_empty(),"arbitrary NPC generated text cannot mint world facts")
	var impression: String = ledger.note_opinion("ines","player","Inés siente que puede hablar con calma con su nuevo vecino.","personal","friendship")
	expect(not impression.is_empty() and ledger.knowledge_for("ines",impression).kind == "opinion","a personal feeling remains a subjective opinion")
	expect(ledger.find_opinion("ines","player","friendship").id == impression,"stable opinion tag can be queried without private ledger access")
	var source: Dictionary = {"id":"private-test","kind":"conversacion","content":private_line,"heard_text":private_line,"turns":[{"text":private_line}]}
	var filtered: Dictionary = ledger.filter_memory("mateo","cesar",source)
	expect(not JSON.stringify(filtered).contains("nadie vaya") and source.content == private_line,"legacy transcript is filtered through every text route without mutation")
	expect(ledger.filter_text("mateo","",private_line) == private_line,"self decision context retains own knowledge")
	# Real observation is private to the engine-supplied witness; conversations never mint facts.
	var memory := {"id":"witness_test","kind":"trabajo","participants":["ines"],"content":"Inés terminó una cesta de panes.","origin":"Observación presencial","minute":world.minute}
	ledger.note_world_memory("ines",memory)
	expect(not ledger.knowledge_for("ines","world:witness_test").is_empty() and ledger.knowledge_for("cesar","world:witness_test").is_empty(),"world observation goes only to actual witness")
	memory.id = "not_witness"; ledger.note_world_memory("cesar",memory)
	expect(ledger.claim("world:not_witness").is_empty(),"nonwitness cannot claim engine observation")
	memory.id = "fake_chat_fact"; memory.kind = "conversacion"; ledger.note_world_memory("ines",memory)
	expect(ledger.claim("world:fake_chat_fact").is_empty(),"free dialogue is not retrospectively verified")
	# Physical permission applies independently of text and trust.
	pair(world,"cesar","player")
	place(world,"player",Vector2(260,210),"homes")
	expect(not ledger.transfer("cesar","player","cesar_morning_plants","","wrong-room"),"cross-area transfer is rejected")
	place(world,"player",Vector2(420,270))
	expect(not ledger.transfer("cesar","player","cesar_morning_plants","","far"),"distant transfer is rejected")
	pair(world,"cesar","player")
	world.get_resident("player").energy = 0.0; world.ensure_exhaustion()
	expect(not ledger.transfer("cesar","player","cesar_morning_plants","","sleep"),"sleeping listener cannot hear a new claim")
	world.advance_exhaustion(8.0)
	world.settlement.state.inhabitants.cesar.present = false
	expect(not ledger.transfer("cesar","player","cesar_morning_plants","","absent"),"absent speaker cannot tell a claim")
	world.settlement.state.inhabitants.cesar.present = true
	# Private anchors must refer to the actual subject, not a similar worry of the speaker.
	var subject_world = fixture()
	pair(subject_world,"player","lupita")
	var subject_ledger = subject_world.social_knowledge
	subject_ledger.note_exchange("player","lupita","Me da miedo que nadie vaya a mi comida vecinal.","Te entiendo.","own-worry")
	expect(subject_ledger.pending_case("lupita","player").is_empty(),"another person's similar worry does not expose the subject's secret")
	expect(SECRET in subject_ledger.matched_claims("lupita","Me contaron que te da miedo que nadie vaya a tu comida.","player","lupita"),"incoming second-person reference binds to listener")
	expect(subject_ledger.filter_text("lupita","cesar","Esto queda entre nosotros: quiero mudarme a una isla.").contains("reservado"),"unknown legacy explicit confidence is conservatively filtered")
	var new_secret: String = ledger.note_opinion("lupita","player","Me inquieta que mi vecino se marche sin despedirse.","secret","new-confidence")
	pair(world,"lupita","mateo")
	expect(not ledger.can_share("lupita","mateo",new_secret),"confirmed breach blocks new secrets despite remaining high trust")
	expect(ledger.can_share("lupita","mateo",SECRET),"already authorized knowledge is not magically forgotten")
	expect(ledger.noticed_before("lupita","mateo",SECRET),"closed case remains noticed without reopening surprise")
	world.minute += 4321
	expect(ledger.can_share("lupita","mateo",new_secret),"new confidence may become eligible after giving several days of space")
	var saturation = fixture()
	for index in 210:
		saturation.minute += 5
		saturation.social_knowledge.note_world_memory("player",{"id":"work_%d" % index,"kind":"trabajo","participants":["player"],"content":"Recogí una rama del camino: número %d." % index,"origin":"Observación directa","minute":saturation.minute})
	var saturated: Dictionary = saturation.social_knowledge.snapshot()
	expect(saturated.topics.size() <= 128 and saturated.knowledge.player.size() <= 64,"long-running town keeps bounded global and personal ledgers")
	expect(not saturation.social_knowledge.knowledge_for("player","world:work_209").is_empty() and saturation.social_knowledge.claim("world:work_0").is_empty(),"new information replaces oldest unprotected public events after saturation")
	expect(not saturation.social_knowledge.knowledge_for("mateo",SECRET).is_empty() and saturation.social_knowledge.validate(saturated,saturation.minute),"eviction preserves historical secrets and valid cross-references")
	var future: Dictionary = saturated.duplicate(true)
	future.receipts.future = saturation.minute+1
	expect(not saturation.social_knowledge.validate(future,saturation.minute),"loaded game clock rejects future knowledge receipts")
	# Persistence checks use only this process's isolated path.
	var valid: Dictionary = ledger.snapshot()
	expect(ledger.validate(valid),"ledger remains internally valid after disclosures and consequences")
	expect(ledger.validate(JSON.parse_string(JSON.stringify(valid))),"JSON roundtrip preserves integer and history invariants")
	invalid(ledger,valid,func(d): d.topics[SECRET].privacy = "public","save cannot silently downgrade authored secret privacy")
	invalid(ledger,valid,func(d): d.knowledge.player[SECRET].confidence = NAN,"nonfinite confidence is rejected")
	invalid(ledger,valid,func(d): d.knowledge.player[SECRET].source_id = "unknown","invalid source ID is rejected")
	invalid(ledger,valid,func(d): d.knowledge.player[SECRET].certainty = "observed","hearsay cannot forge firsthand status")
	invalid(ledger,valid,func(d): d.knowledge.player[SECRET].path = ["cesar"],"technical provenance must end at its holder")
	invalid(ledger,valid,func(d): d.knowledge.player[SECRET].versions[0].text = "Una invención nueva.","saved versions must come from approved claim vocabulary")
	invalid(ledger,valid,func(d): d.disclosures.append(d.disclosures[0].duplicate()),"duplicate disclosure records are rejected")
	invalid(ledger,valid,func(d): d.knowledge.player["ghost"] = d.knowledge.player[SECRET].duplicate(),"dangling claim reference is rejected")
	invalid(ledger,valid,func(d): d.receipts.bad = -1,"negative receipt time is rejected")
	var ctx: Dictionary = ledger.context_for("player","lupita","comida")
	expect(JSON.stringify(ctx).length() <= 2400 and ctx.claims.size() <= 4 and not JSON.stringify(ctx).contains('"path"'),"prompt is bounded and excludes technical chain")
	expect(world.save_game(),"social ledger saves with existing world state")
	var restored = fixture(); restored.save_path = world.save_path
	var loaded: bool = restored.load_game()
	if not loaded: print("LOAD ERROR: "+restored.last_error)
	expect(loaded and restored.social_knowledge.snapshot() == JSON.parse_string(JSON.stringify(valid)),"private ledger and receipts survive reload without replay")
	# A legacy save without this field seeds only authored knowledge, not transcript facts.
	var file := FileAccess.open(world.save_path,FileAccess.READ)
	var payload = JSON.parse_string(file.get_as_text()); file.close()
	payload.erase("social_knowledge")
	file = FileAccess.open(world.save_path,FileAccess.WRITE); file.store_string(JSON.stringify(payload)); file.close()
	expect(restored.load_game() and restored.social_knowledge.knowledge_for("player",SECRET).is_empty(),"legacy migration never mines old conversations as verified facts")
	for path in paths:
		for suffix in ["",".tmp",".bak"]:
			if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	print("Social knowledge: %d/%d passed" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
