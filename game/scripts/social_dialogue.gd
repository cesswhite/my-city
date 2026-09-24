extends RefCounted
## Local conversational intent. Preparation is pure; only completed exchanges commit.
const Navigation = preload("res://scripts/navigation.gd")
const Layout = preload("res://scripts/world_layout.gd")
var _world: WeakRef
var _last_topics: Dictionary = {}
var _last_exchange: Dictionary = {}
var _last_lines: Dictionary = {}

func setup(world) -> void:
	_world = weakref(world)
	_last_topics.clear()
	_last_exchange.clear()
	_last_lines.clear()

func _fold(value: String) -> String:
	var text := value.to_lower().replace("á","a").replace("é","e").replace("í","i").replace("ó","o").replace("ú","u").replace("ü","u")
	for mark in ["¿","?","¡","!",",",".",":",";","\n","\t"]: text = text.replace(mark," ")
	return " ".join(text.split(" ",false))

func _has(text: String, phrases: Array) -> bool:
	for phrase in phrases:
		if text.contains(str(phrase)): return true
	return false

func _key(a: String, b: String) -> String:
	return a + ">" + b

func _name(id: String) -> String:
	return str(_world.get_ref().get_resident(id).get("name",id))

func _mentioned(text: String, except_ids: Array = []) -> Array[String]:
	var result: Array[String] = []
	var folded := " " + _fold(text) + " "
	for person: Dictionary in _world.get_ref().residents:
		if person.id in except_ids: continue
		if folded.contains(" " + _fold(person.name) + " ") or folded.contains(" " + str(person.id) + " "): result.append(person.id)
	return result

func case_intent(owner: String, partner: String, text: String) -> Dictionary:
	var folded := _fold(text)
	var people := _mentioned(text,[owner,partner])
	# Asking about a possible source is not an accusation or an admission.
	if text.contains("?") or text.contains("¿"): return {}
	if _has(folded,["cambiemos de tema","otra cosa","otro tema","hablemos de algo mas"]): return {"intent":"change","source_id":""}
	if _has(folded,["prefiero no decir","no quiero decir","no voy a decir","no te puedo decir","no preguntes","prefiero no responder"]): return {"intent":"avoid","source_id":""}
	if _has(folded,["no fue","no me lo dijo","no me lo conto","no me dijo","no me conto","nadie me","no lo se","no se quien","no se lo conte","no dije"]) or folded in ["no","no es cierto"]: return {"intent":"deny","source_id":people[0] if not people.is_empty() else ""}
	if _has(folded,["se me escapo","si se lo conte","yo se lo conte","lo conte yo","si lo dije"]): return {"intent":"admit","source_id":""}
	if _has(folded,["perdon","lo siento","disculpa"]): return {"intent":"apology","source_id":""}
	if not people.is_empty() and (_has(folded,["me dijo","me conto","me lo dijo","me lo conto","fue ","lo escuche de"]) or folded == _fold(_name(people[0])) or folded == people[0]): return {"intent":"admit","source_id":people[0]}
	if folded in ["si","si fue","asi es","si me lo conto"]:
		var incident: Dictionary = _world.get_ref().social_knowledge.pending_case(owner,partner)
		var previous: String = str(_last_lines.get(_key(owner,partner),""))
		var named := _mentioned(previous,[owner,partner])
		if previous.contains("?") and _has(_fold(previous),["te lo conto","te lo dijo"]) and named.size() == 1 and named[0] in incident.get("suspects",[]): return {"intent":"admit","source_id":named[0]}
	return {}

func _case_reply(owner: String, partner: String, text: String) -> String:
	var intent := case_intent(owner,partner,text)
	match str(intent.get("intent","")):
		"admit": return "Me dolió que lo contaras. Necesito recuperar la confianza." if str(intent.source_id).is_empty() else "Gracias por decírmelo. Hablaré con %s para aclararlo." % _name(intent.source_id)
		"deny": return "Está bien. No voy a acusar a nadie sin aclararlo."
		"avoid": return "Entiendo. Me inquieta que algo privado esté circulando."
		"change": return "Está bien, cambiemos de tema."
		"apology": return "Gracias por decirlo. Te pido que no lo sigas contando."
	return ""

func _answers_case(owner: String, partner: String, text: String, incident: Dictionary) -> bool:
	if incident.is_empty(): return false
	var topics: Array = _world.get_ref().social_knowledge.matched_claims(owner,text,partner,owner)
	return topics.is_empty() or str(incident.claim_id) in topics

func reply(owner: String, partner: String, text: String) -> String:
	var world = _world.get_ref()
	var ledger = world.social_knowledge
	if not world.is_present(owner) or not world.is_present(partner): return ""
	var incident: Dictionary = ledger.pending_case(owner,partner)
	if _answers_case(owner,partner,text,incident):
		var response := _case_reply(owner,partner,text)
		if not response.is_empty(): return response
		if _fold(text) in ["si","si fue","asi es","si me lo conto"]: return "¿Quién te lo contó? Prefiero aclararlo antes de sacar conclusiones."
		if text.contains("?") and _has(_fold(text),["fue ","te lo conto","te lo dijo"]): return "No lo sé. ¿Tú se lo escuchaste a alguien?"
	var folded := _fold(text)
	if _has(folded,["cambiemos de tema","hablemos de otra cosa"]): return "Claro, hablemos de otra cosa."
	# The owner recognizes a concrete detail, not a generic question about secrets.
	for claim_id: String in ledger.matched_claims(owner,text,partner,owner):
		var topic: Dictionary = ledger.claim(claim_id)
		if topic.get("owner_id","") == owner and topic.get("privacy","") == "secret" and not ledger.disclosed_to(owner,partner,claim_id):
			if not incident.is_empty() and str(incident.claim_id) == claim_id:
				var suspects: Array = incident.get("suspects",[])
				if suspects.size() == 1: return "¿Te lo contó %s? Se lo había confiado." % _name(suspects[0])
			if ledger.noticed_before(owner,partner,claim_id): return "Ya sé que te llegó ese comentario. Prefiero dejarlo ahí."
			return "Eso no te lo había contado. ¿Cómo lo supiste?"
	var last_id: String = str(_last_topics.get(_key(owner,partner),""))
	if not last_id.is_empty() and _has(folded,["te lo conto","te lo dijo","como lo sabes","quien te conto","quien te dijo","es verdad","estas seguro","estas segura"]):
		var known: Dictionary = ledger.knowledge_for(owner,last_id)
		if not known.is_empty() and ledger.can_share(owner,partner,last_id):
			if known.certainty == "observed": return "Lo sé por mi propia experiencia."
			return "Me lo comentó %s. No lo comprobé por mi cuenta." % _name(known.source_id)
	var mentioned := _mentioned(text,[owner,partner])
	var asking: bool = text.contains("?") or _has(folded,["cuentame","hablame","que sabes","que opinas","conoces","algo sobre","secreto","rumor","chisme"])
	if asking and not mentioned.is_empty():
		var subject: String = mentioned[0]
		var candidates: Array = ledger.candidates_for(owner,partner,subject)
		for matched: String in ledger.matched_claims(owner,text,partner,owner):
			if matched in candidates:
				candidates.erase(matched)
				candidates.push_front(matched)
				break
		if not candidates.is_empty(): return ledger.share_line(owner,partner,str(candidates[0]))
		var personally_known := false
		for item: String in ledger.matched_claims(owner,_name(subject)):
			if not ledger.knowledge_for(owner,item).is_empty(): personally_known = true
		if _has(folded,["secreto","vida privada","personal"]): return "Prefiero que %s decida qué contarte." % _name(subject)
		return "No tengo nada concreto que contarte sobre %s." % _name(subject) if not personally_known else "Prefiero hablar de lo que conozco de primera mano."
	if _has(folded,["no se lo digas a nadie","esto queda entre nosotros","es un secreto"]): return "Te escucho. Voy a tratarlo con cuidado."
	return ""

func requires_local_reply(owner: String, partner: String, text: String) -> bool:
	# A connected model can phrase ordinary gossip; evidence decisions stay local.
	var ledger = _world.get_ref().social_knowledge
	if not ledger.pending_case(owner,partner).is_empty():
		if not case_intent(owner,partner,text).is_empty() or _fold(text) in ["si","si fue","asi es","si me lo conto"]: return true
		if text.contains("?") and _has(_fold(text),["fue ","te lo conto","te lo dijo"]): return true
	for claim_id: String in ledger.matched_claims(owner,text,partner,owner):
		var topic: Dictionary = ledger.claim(claim_id)
		if topic.get("owner_id","") == owner and topic.get("privacy","") == "secret" and not ledger.disclosed_to(owner,partner,claim_id): return true
	var folded := _fold(text)
	if _last_topics.has(_key(owner,partner)) and _has(folded,["te lo conto","te lo dijo","como lo sabes","quien te conto","quien te dijo","es verdad","estas seguro","estas segura"]): return true
	var subjects := _mentioned(text,[owner,partner])
	return not subjects.is_empty() and ledger.candidates_for(owner,partner,subjects[0]).is_empty()

func _can_meet(a: String, b: String) -> bool:
	var world = _world.get_ref()
	if a == b or not world.is_present(a) or not world.is_present(b) or world.is_sleeping(a) or world.is_sleeping(b): return false
	var first: Dictionary = world.get_resident(a)
	var second: Dictionary = world.get_resident(b)
	return world._distance(first,second) < world.MAX_DISTANCE and Navigation._clear_segment(Layout.point(first.pos),Layout.point(second.pos),first.room)

func _confrontation_lines(a: String, b: String) -> Dictionary:
	var world = _world.get_ref()
	var incident: Dictionary = world.social_knowledge.pending_confrontation(a,b)
	if incident.is_empty(): return {}
	var claimant: String = str(incident.get("claimant",a))
	var accused: String = str(incident.get("accused",b))
	if claimant != a or accused != b: return {}
	var question := "%s, ¿contaste algo que te confié? Quiero aclararlo contigo." % _name(accused)
	if not world.social_knowledge.disclosed_to(claimant,accused,str(incident.claim_id)): question = "%s, me dijeron que hablaste de algo privado mío. ¿Podemos aclararlo?" % _name(accused)
	# The accused consults only their own acts, not the hidden origin of a rumor.
	var admitted: bool = world.social_knowledge.disclosed_to(accused,str(incident.heard_from),str(incident.claim_id))
	var answer := "Sí, se me escapó. Debí preguntarte antes. Lo siento." if admitted else "No se lo conté a esa persona. Prefiero aclararlo contigo."
	if world.social_knowledge.knowledge_for(accused,str(incident.claim_id)).is_empty(): answer = "No sé de qué me hablas. No me habías contado eso."
	return {"first":question,"reply":answer,"kind":"confrontation","admitted":admitted}

func encounter_pair(a: String, b: String) -> Dictionary:
	if not _can_meet(a,b): return {}
	var world = _world.get_ref()
	var confrontation := _confrontation_lines(a,b)
	if not confrontation.is_empty(): return confrontation
	var last: int = maxi(int(_last_exchange.get(_key(a,b),-240)),int(_last_exchange.get(_key(b,a),-240)))
	if world.minute - last < 120 or world._day_seed(int(world.minute / 30),a+b) % 4 != 0: return {}
	for pair in [[a,b]]:
		var speaker: String = pair[0]
		var listener: String = pair[1]
		var choices: Array = world.social_knowledge.candidates_for(speaker,listener)
		choices = choices.filter(func(id): return world.social_knowledge.knowledge_for(listener,str(id)).is_empty())
		if choices.is_empty(): continue
		var line: String = world.social_knowledge.share_line(speaker,listener,str(choices[0]))
		if line.is_empty(): continue
		var answer: String = reply(listener,speaker,line)
		if answer.is_empty(): answer = "Gracias por contármelo. Lo tendré en cuenta." if str(world.social_knowledge.claim(str(choices[0])).get("kind","")) == "fact" else "Puede ser. Prefiero sacar mis propias conclusiones."
		return {"first":line if speaker == a else answer,"reply":answer if speaker == a else line,"kind":"gossip"}
	return {}

func on_exchange(a: String, b: String, first: String, second: String, event_id: String) -> void:
	if not _can_meet(a,b): return
	var world = _world.get_ref()
	var ledger = world.social_knowledge
	var old_cases := {a:ledger.pending_case(a,b),b:ledger.pending_case(b,a)}
	var confrontation := _confrontation_lines(a,b)
	var performed: bool = not confrontation.is_empty() and first == confrontation.first and second == confrontation.reply
	ledger.note_exchange(a,b,first,second,event_id)
	for pair in [[a,b,first],[b,a,second]]:
		var speaker: String = pair[0]
		var listener: String = pair[1]
		var spoken: String = pair[2]
		if _answers_case(listener,speaker,spoken,old_cases[listener]) and not (performed and listener == a):
			var intent := case_intent(listener,speaker,spoken)
			if not intent.is_empty(): ledger.respond_case(listener,speaker,intent.intent,intent.source_id,event_id)
		for claim_id: String in ledger.matched_claims(speaker,spoken,speaker,listener):
			if not ledger.knowledge_for(listener,claim_id).is_empty():
				_last_topics[_key(speaker,listener)] = claim_id
				_last_exchange[_key(speaker,listener)] = world.minute
		var folded := _fold(spoken)
		var secret: bool = _has(folded,["no se lo digas a nadie","esto queda entre nosotros","es un secreto"])
		var testimony: bool = folded.begins_with("me contaron que ") or folded.begins_with("me dijeron que ") or folded.begins_with("escuche que ")
		if speaker == "player" and not spoken.contains("?") and (secret or testimony) and ledger.matched_claims(speaker,spoken,speaker,listener).is_empty() and ledger.matched_claims(listener,spoken,speaker,listener).is_empty():
			var detail: String = spoken.substr(spoken.find(":")+1).strip_edges() if spoken.contains(":") else spoken
			var subjects := _mentioned(detail,[speaker])
			if detail.length() >= 24: ledger.hear_statement(listener,speaker,detail.left(240),"secret" if secret else "personal",subjects[0] if not subjects.is_empty() else speaker)
	for pair in [[a,b,first],[b,a,second]]: _last_lines[_key(pair[0],pair[1])] = pair[2]
	if performed:
		ledger.resolve_confrontation(a,b,event_id)
		ledger.respond_case(a,b,"admit" if confrontation.admitted else "deny","",event_id)
		if confrontation.admitted: ledger.respond_case(a,b,"apology","",event_id+":apology")

func suggestions(owner: String, partner: String, last_reply: String) -> Array[Dictionary]:
	var ledger = _world.get_ref().social_knowledge
	var incident: Dictionary = ledger.pending_case(owner,partner)
	if not incident.is_empty() and last_reply.contains("?"):
		var source := ""
		var own: Dictionary = ledger.knowledge_for(partner,str(incident.claim_id))
		if not own.is_empty() and own.get("source_id",partner) != partner: source = str(own.source_id)
		if not source.is_empty(): return [_option("Me lo contó %s." % _name(source)),_option("Prefiero no decir quién fue.")]
		return [_option("Prefiero no responder."),_option("Cambiemos de tema.")]
	if last_reply.is_empty(): return []
	var topic: String = str(_last_topics.get(_key(owner,partner),""))
	if not topic.is_empty() and topic in ledger.matched_claims(owner,last_reply):
		return [_option("¿Cómo lo sabes?"),_option("Prefiero sacar mis conclusiones.")]
	return []

func _option(text: String) -> Dictionary:
	return {"label":text,"text":text}
