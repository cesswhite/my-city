extends RefCounted
## A bounded private ledger. A testimony keeps its source; repetition is never verification.
const Registry = preload("res://scripts/resident_catalog.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Layout = preload("res://scripts/world_layout.gd")
const MAX_TOPICS := 128
const MAX_KNOWN := 64
const MAX_CASES := 64
const MAX_DISCLOSURES := 256
const MAX_RECEIPTS := 512
const KINDS := ["fact","opinion","rumor","secret"]
const PRIVACY := ["public","personal","secret"]
const CERTAINTY := ["observed","heard","uncertain"]
var _world: WeakRef
var _state: Dictionary = {}
var _catalog: Dictionary = {}

func setup(world) -> void:
	_world = weakref(world)
	_state = {"version":1,"serial":0,"topics":{},"knowledge":{},"disclosures":[],"cases":{},"receipts":{}}
	_catalog.clear()
	for id in Registry.ids(): _state.knowledge[id] = {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/social_content.json"))
	if not parsed is Dictionary: return
	for topic: Dictionary in parsed.get("topics",[]):
		_catalog[topic.id] = topic.duplicate(true)
		_state.topics[topic.id] = topic.duplicate(true)
		for holder: String in topic.seed_holders:
			var own: bool = holder == topic.owner_id
			_state.knowledge[holder][topic.id] = _entry(topic,holder,str(topic.owner_id),"observed" if own else "heard",100 if own else 80,0,"history:"+topic.id)
			if not own:
				_add_disclosure(str(topic.owner_id),holder,topic.id,"history:"+topic.id,true,0)

func _ready_world() -> bool:
	return _world != null and _world.get_ref() != null and not _state.is_empty()

func _minute() -> int:
	return int(_world.get_ref().minute) if _ready_world() else 0

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func restore(value: Dictionary) -> bool:
	if not validate(value): return false
	_state = value.duplicate(true)
	return true

func claim(claim_id: String) -> Dictionary:
	return _state.get("topics",{}).get(claim_id,{}).duplicate(true)

func _entry(topic: Dictionary, holder: String, source: String, certainty: String, confidence: int, minute: int, evidence: String) -> Dictionary:
	return {"claim_id":topic.id,"text":topic.text,"certainty":certainty,"source_id":source,"confidence":confidence,"minute":minute,
		"authorized_by":str(topic.owner_id),"authorized_recipient":holder if holder == topic.owner_id or source == topic.owner_id else "",
		"path":[holder] if holder == source else [source,holder],"evidence":[evidence],
		"versions":[{"text":topic.text,"source_id":source,"confidence":confidence,"minute":minute,"event_id":evidence,"kind":"statement"}]}

func knowledge_for(owner: String, claim_id: String) -> Dictionary:
	var entry: Dictionary = _state.get("knowledge",{}).get(owner,{}).get(claim_id,{})
	var topic: Dictionary = _state.get("topics",{}).get(claim_id,{})
	if entry.is_empty() or topic.is_empty(): return {}
	return {"id":claim_id,"claim_id":claim_id,"subject_id":str(topic.subjects[0]),"text":entry.text,"kind":topic.kind,"privacy":topic.privacy,
		"certainty":entry.certainty,"source_id":entry.source_id,"confidence":entry.confidence,"minute":entry.minute,
		"authorized_by":entry.authorized_by,"authorized_recipient":entry.authorized_recipient}

func _pair(a: String, b: String) -> bool:
	return _ready_world() and a != b and a in Registry.ids() and b in Registry.ids()

func _physical(a: String, b: String) -> bool:
	if not _pair(a,b): return false
	var world = _world.get_ref()
	if not world.is_present(a) or not world.is_present(b) or world.is_sleeping(a) or world.is_sleeping(b): return false
	var first: Dictionary = world.get_resident(a)
	var second: Dictionary = world.get_resident(b)
	return world._distance(first,second) < world.MAX_DISTANCE and Navigation._clear_segment(Layout.point(first.pos),Layout.point(second.pos),str(first.room))

func disclosed_to(owner: String, partner: String, claim_id: String) -> bool:
	for item: Dictionary in _state.get("disclosures",[]):
		if item.speaker == owner and item.listener == partner and item.claim_id == claim_id: return true
	return false

func _authorized(owner: String, partner: String, claim_id: String) -> bool:
	for item: Dictionary in _state.get("disclosures",[]):
		if item.speaker == owner and item.listener == partner and item.claim_id == claim_id and item.authorized: return true
	return false

func can_share(owner: String, listener: String, claim_id: String) -> bool:
	if not _pair(owner,listener): return false
	var topic: Dictionary = _state.topics.get(claim_id,{})
	if topic.is_empty() or not _state.knowledge.get(owner,{}).has(claim_id): return false
	var world = _world.get_ref()
	if not world.is_present(owner) or not world.is_present(listener): return false
	if topic.privacy == "public": return true
	if listener == topic.owner_id or _authorized(str(topic.owner_id),listener,claim_id): return true
	var relation: Dictionary = world.relationship_for(owner,listener)
	if relation.is_empty() or relation.frustration >= 40 or relation.cooldown_until > _minute(): return false
	if topic.privacy == "personal": return relation.trust >= int(topic.require_trust)
	if owner == topic.owner_id:
		for incident: Dictionary in _state.cases.values():
			if incident.owner_id == owner and incident.partner_id == listener and "admission" in incident.effects and _minute() < int(incident.breached_at)+4320: return false
		return relation.trust >= int(topic.require_trust) and relation.affection >= 50 and relation.frustration < 25
	if not topic.leakable or relation.trust < 55: return false
	var traits: String = " ".join(world.get_resident(owner).get("personality",[])).to_lower()
	if traits.contains("reservad") or traits.contains("protector"): return false
	# The decision is stable during a day and pure when rendering/previewing a reply.
	var day: int = int(_minute() / 1440)
	for item: Dictionary in _state.disclosures:
		if item.speaker == owner and not item.authorized and int(item.minute / 1440) == day:
			return item.claim_id == claim_id and item.listener == listener
	return _stable(owner+":"+listener+":"+claim_id+":"+str(day)) % 100 < 20

func _stable(value: String) -> int:
	return value.sha256_text().left(7).hex_to_int()

func candidates_for(owner: String, listener: String, subject_id: String = "") -> Array[String]:
	var result: Array[String] = []
	for id: String in _state.get("knowledge",{}).get(owner,{}):
		var topic: Dictionary = _state.topics[id]
		if (subject_id.is_empty() or subject_id in topic.subjects) and can_share(owner,listener,id): result.append(id)
	result.sort_custom(func(a,b):
		var a_new: bool = not disclosed_to(owner,listener,a)
		var b_new: bool = not disclosed_to(owner,listener,b)
		return a_new if a_new != b_new else a < b)
	return result

func _own_line(id: String, fallback: String) -> String:
	return str({
		"lupita_meal_worry":"Me da miedo que nadie vaya a la comida vecinal; todavía no quiero anunciarla.",
		"cesar_asking_help":"Me da pena pedir ayuda con mi bicicleta; temo parecer una carga.",
		"mateo_teaching_patience":"Aprendí a reparar bicicletas en el taller familiar; todavía practico cómo explicar los pasos con paciencia.",
		"ines_saved_postcards":"Guardo una postal sin enviar. Todavía no sé cómo despedirme de aquella ciudad.",
		"alma_preserve_corners":"Creo que el barrio puede crecer sin borrar los rincones que dibujo y fotografío.",
		"lupita_mateo_admiration":"Siento cariño por Mateo; con él me siento escuchada.",
		"mateo_lupita_busy_plans":"A veces me abruman los planes de Lupita para reunirnos, aunque aprecio que quiera incluirme.",
		"cesar_morning_plants":"Conservo el hábito de cuidar las plantas al amanecer; lo aprendí mientras crecía en el campo."
	}.get(id,fallback))

func _heard_detail(id: String, fallback: String) -> String:
	return str({
		"lupita_meal_worry":"a Lupita le da miedo que nadie vaya a la comida vecinal",
		"cesar_asking_help":"a César le da pena pedir ayuda con su bicicleta",
		"mateo_teaching_patience":"Mateo aprendió en el taller familiar y practica cómo explicar los pasos con paciencia",
		"ines_saved_postcards":"Inés guarda una postal sin enviar",
		"alma_preserve_corners":"Alma quiere crecer sin borrar los rincones del barrio",
		"lupita_mateo_admiration":"Lupita siente cariño por Mateo y se siente escuchada con él",
		"mateo_lupita_busy_plans":"a Mateo le abruman los planes de Lupita, aunque aprecia que quiera incluirlo",
		"cesar_morning_plants":"César cuida las plantas al amanecer, un hábito de cuando crecía en el campo"
	}.get(id,fallback.trim_suffix(".")))

func share_line(owner: String, listener: String, claim_id: String) -> String:
	if not can_share(owner,listener,claim_id): return ""
	var known := knowledge_for(owner,claim_id)
	if known.certainty == "observed":
		if known.kind == "rumor": return "Yo lo conté así: " + str(known.text)
		return _own_line(claim_id,str(known.text))
	var selected: String = _heard_detail(claim_id,str(known.text)) if known.text == _state.topics[claim_id].text else str(known.text).trim_suffix(".")
	var variants: Array = _state.topics[claim_id].get("variants",[])
	if not variants.is_empty() and _stable(owner+listener+claim_id+str(int(_minute()/1440))) % 3 == 0: selected = str(variants[0]).trim_suffix(".")
	var line := "%s me contó que %s." % [_name(str(known.source_id)),selected]
	if known.certainty == "uncertain" or known.confidence < 70 or known.kind == "rumor": line += " No lo comprobé."
	return line

func _name(id: String) -> String:
	return str(_world.get_ref().get_resident(id).get("name",id)).left(40) if _ready_world() else id

func _receipt(key: String) -> bool:
	if _state.receipts.has(key): return false
	_state.receipts[key] = _minute()
	while _state.receipts.size() > MAX_RECEIPTS: _state.receipts.erase(_state.receipts.keys()[0])
	return true

func _event(value: String) -> String:
	if not value.is_empty(): return value.left(120)
	_state.serial = int(_state.serial) + 1
	return "knowledge-%d" % int(_state.serial)

func _disclosure_victim() -> int:
	for index in _state.disclosures.size():
		var record: Dictionary = _state.disclosures[index]
		if _state.topics[record.claim_id].privacy != "secret": return index
	for index in _state.disclosures.size():
		if not _state.disclosures[index].authorized: return index
	return -1

func _can_record_disclosure(speaker: String, listener: String, id: String) -> bool:
	return disclosed_to(speaker,listener,id) or _state.disclosures.size() < MAX_DISCLOSURES or _disclosure_victim() >= 0

func _add_disclosure(speaker: String, listener: String, id: String, event: String, authorized: bool, minute: int) -> void:
	# One durable record per directed disclosure is enough; repeated telling does not farm effects.
	if disclosed_to(speaker,listener,id): return
	_state.disclosures.append({"speaker":speaker,"listener":listener,"claim_id":id,"minute":minute,"authorized":authorized,"event_id":event.left(120)})
	while _state.disclosures.size() > MAX_DISCLOSURES:
		var victim := _disclosure_victim()
		if victim < 0: _state.disclosures.pop_back(); break
		_state.disclosures.remove_at(victim)

func transfer(speaker: String, listener: String, claim_id: String, variant: String = "", exchange_id: String = "") -> bool:
	if not _physical(speaker,listener) or not can_share(speaker,listener,claim_id) or not _can_record_disclosure(speaker,listener,claim_id): return false
	var topic: Dictionary = _state.topics[claim_id]
	var text: String = str(topic.text) if variant.is_empty() else variant
	if text not in [str(topic.text)] + topic.get("variants",[]): return false
	if not _state.knowledge[listener].has(claim_id) and not _make_room(listener,false): return false
	var event := _event(exchange_id)
	if not _receipt("transfer:"+event+":"+speaker+":"+listener+":"+claim_id): return false
	var source: Dictionary = _state.knowledge[speaker][claim_id]
	var authorized: bool = speaker == topic.owner_id or topic.privacy != "secret"
	_add_disclosure(speaker,listener,claim_id,event,authorized,_minute())
	if not _state.knowledge[listener].has(claim_id):
		var received := _entry(topic,listener,speaker,"heard",maxi(10,mini(85,int(source.confidence)-15)),_minute(),event)
		received.text = text
		received.versions[0].text = text
		received.authorized_by = str(topic.owner_id)
		received.authorized_recipient = listener if authorized else ""
		received.path = source.path.duplicate()
		if listener not in received.path: received.path.append(listener)
		while received.path.size() > 8: received.path.pop_front()
		_state.knowledge[listener][claim_id] = received
	else:
		var received: Dictionary = _state.knowledge[listener][claim_id]
		if event not in received.evidence: received.evidence.append(event)
		while received.evidence.size() > 4: received.evidence.pop_front()
		if not received.certainty == "observed":
			received.versions.append({"text":text,"source_id":speaker,"confidence":maxi(10,mini(85,int(source.confidence)-15)),"minute":_minute(),"event_id":event,"kind":"statement"})
			while received.versions.size() > 3: received.versions.pop_front()
			if text != received.text:
				received.certainty = "uncertain"
				received.confidence = maxi(10,int(received.confidence)-5)
	# Only the subject who actually heard it can notice the unauthorized knowledge.
	_notice(listener,speaker,claim_id,event)
	return true

func _clean(text: String) -> String:
	var result := ""
	for index in text.length():
		var code := text.unicode_at(index)
		result += " " if code < 32 or code == 127 else text[index]
	return result.strip_edges()

func _fold(text: String) -> String:
	var value := text.to_lower().replace("á","a").replace("é","e").replace("í","i").replace("ó","o").replace("ú","u").replace("ü","u")
	for mark in ["¿","?","¡","!",",",".",":",";","\n","\t","\"","'","—"]: value = value.replace(mark," ")
	return " ".join(value.split(" ",false))

func _denial(text: String) -> bool:
	var value := _fold(text)
	for prefix in ["no es verdad","no es cierto","no dije","no dijo","no me dijo","no me conto","nunca dije","eso es falso","no creo que"]:
		if value.contains(prefix): return true
	return false

func _matches(topic: Dictionary, text: String) -> bool:
	var folded := _fold(text)
	if folded.contains(_fold(str(topic.text))): return true
	if folded.contains(_fold(_own_line(str(topic.id),str(topic.text)))) or folded.contains(_fold(_heard_detail(str(topic.id),str(topic.text)))): return true
	for version: String in topic.get("variants",[]):
		if folded.contains(_fold(version)): return true
	# Recognize the distinctive private detail even when the speaker changes pronouns.
	match str(topic.id):
		"lupita_meal_worry":
			if folded.contains("miedo") and (folded.contains("nadie vaya") or folded.contains("comida")): return true
		"cesar_asking_help":
			if (folded.contains("pena") and folded.contains("ayuda")) or folded.contains("parecer una carga"): return true
		"ines_saved_postcards":
			if folded.contains("postal") and folded.contains("sin enviar"): return true
	for alias: String in topic.aliases:
		var needle := _fold(alias)
		# Two generic nouns ("comida vecinal", "su bicicleta") are not a secret disclosure.
		if needle.length() >= 15 and needle.split(" ",false).size() >= 3 and folded.contains(needle): return true
	return false

func _subject_bound(topic: Dictionary, text: String, speaker: String, listener: String) -> bool:
	if speaker.is_empty() or listener.is_empty(): return true
	var subject: String = str(topic.subjects[0])
	var folded: String = " " + _fold(text) + " "
	if speaker == topic.owner_id and folded.contains(_fold(_own_line(str(topic.id),str(topic.text)))): return true
	if folded.contains(" "+_fold(_name(subject))+" ") or folded.contains(" "+subject+" "): return true
	var pronouns: Array = [" yo "," me da "," me preocupa "," me inquieta "," me abruma", " mi comida", " mi bicicleta", " mi postal"] if speaker == subject else ([" te da "," te preocupa "," te inquieta "," te abruma", " tu comida", " tu bicicleta", " tu postal"] if listener == subject else [])
	for pronoun: String in pronouns:
		if folded.contains(pronoun): return true
	return false

func matched_claims(owner: String, text: String, speaker_id: String = "", listener_id: String = "") -> Array[String]:
	var result: Array[String] = []
	if _denial(text): return result
	for id: String in _state.get("knowledge",{}).get(owner,{}):
		if _matches(_state.topics[id],text) and _subject_bound(_state.topics[id],text,speaker_id,listener_id): result.append(id)
	return result

func note_exchange(a: String, b: String, a_text: String, b_text: String, event_id: String) -> void:
	if not _physical(a,b) or event_id.is_empty(): return
	if not _receipt("exchange:"+event_id.left(120)+":"+a+":"+b): return
	for pair in [[a,b,a_text],[b,a,b_text]]:
		var speaker: String = pair[0]
		var listener: String = pair[1]
		var text: String = pair[2]
		if _denial(text):
			_disagreement(listener,speaker,text,event_id)
		for id: String in matched_claims(speaker,text,speaker,listener):
			var variant := ""
			for version: String in _state.topics[id].get("variants",[]):
				if _fold(text).contains(_fold(version)): variant = version; break
			transfer(speaker,listener,id,variant,event_id)
		# A subject can recognize their own private detail without granting the speaker knowledge.
		for id: String in matched_claims(listener,text,speaker,listener): _notice(listener,speaker,id,event_id)

func _disagreement(listener: String, speaker: String, text: String, event: String) -> void:
	for id: String in _state.knowledge.get(listener,{}):
		if not _matches(_state.topics[id],text) or not _subject_bound(_state.topics[id],text,speaker,listener): continue
		var entry: Dictionary = _state.knowledge[listener][id]
		if entry.certainty == "observed": continue
		if not _receipt("disagree:"+event+":"+listener+":"+id): continue
		entry.versions.append({"text":_clean(text).left(240),"source_id":speaker,"confidence":0,"minute":_minute(),"event_id":event,"kind":"disagreement"})
		while entry.versions.size() > 3: entry.versions.pop_front()
		entry.certainty = "uncertain"
		entry.confidence = maxi(10,int(entry.confidence)-10)

func _notice(owner: String, partner: String, id: String, event: String) -> void:
	var topic: Dictionary = _state.topics.get(id,{})
	if topic.is_empty() or topic.owner_id != owner or topic.privacy != "secret" or _authorized(owner,partner,id): return
	var key := "case:"+owner+":"+partner+":"+id
	if _state.cases.has(key): return
	var suspects: Array[String] = []
	for record: Dictionary in _state.disclosures:
		if record.claim_id == id and record.speaker == owner and record.authorized and record.listener != partner and record.listener not in suspects: suspects.append(record.listener)
	_state.cases[key] = {"id":key,"owner_id":owner,"subject_id":owner,"partner_id":partner,"claim_id":id,"heard_from":partner,
		"stance":"suspicion","status":"open","suspects":suspects,"reported_source":"","minute":_minute(),"event_id":event.left(120),
		"confrontation":false,"asked":false,"effects":[],"breached_at":0}
	_trim_cases()

func _trim_cases() -> void:
	while _state.cases.size() > MAX_CASES:
		var victim: String = str(_state.cases.keys()[0])
		for id: String in _state.cases:
			if _state.cases[id].status == "resolved": victim = id; break
		_state.cases.erase(victim)

func noticed_before(owner: String, partner: String, claim_id: String) -> bool:
	return _state.get("cases",{}).has("case:"+owner+":"+partner+":"+claim_id)

func pending_case(owner: String, partner: String) -> Dictionary:
	var cases: Array = _state.get("cases",{}).values()
	cases.reverse()
	for value: Dictionary in cases:
		if value.owner_id == owner and value.partner_id == partner and value.status == "open": return value.duplicate(true)
	return {}

func _effect(incident: Dictionary, label: String, partner: String, trust: float, affection: float, frustration: float) -> void:
	if label in incident.effects or not _pair(str(incident.owner_id),partner): return
	incident.effects.append(label)
	var person: Dictionary = _world.get_ref().get_resident(str(incident.owner_id))
	if not person.get("relationships",{}).has(partner): return
	var relationship: Dictionary = person.relationships[partner]
	# Apply to the current projected state, so old recovery isn't lost or double counted.
	var projected: Dictionary = _world.get_ref().relationship_for(str(incident.owner_id),partner)
	for key in ["trust","affection","tolerance","frustration"]: relationship[key] = projected[key]
	relationship.trust = clampf(float(relationship.trust)+trust,0,100)
	relationship.affection = clampf(float(relationship.affection)+affection,0,100)
	relationship.frustration = clampf(float(relationship.frustration)+frustration,0,100)
	relationship.updated_at = _minute()

func respond_case(owner: String, partner: String, intent: String, source_id: String = "", event_id: String = "") -> bool:
	if not _physical(owner,partner) or intent not in ["admit","deny","avoid","change","apology"]: return false
	var found := pending_case(owner,partner)
	if found.is_empty() or (not source_id.is_empty() and source_id not in Registry.ids()): return false
	if not _receipt("response:"+_event(event_id)+":"+found.id+":"+intent): return false
	var incident: Dictionary = _state.cases[found.id]
	match intent:
		"admit":
			if source_id.is_empty() or source_id == partner:
				incident.stance = "confirmed"
				if "admission" not in incident.effects: incident.breached_at = _minute()
				_effect(incident,"admission",partner,-10,-5,12)
			else:
				# The reported source is testimony. It creates a question, never a guilt verdict.
				incident.reported_source = source_id
				if source_id != owner:
					var key := "case:"+owner+":"+source_id+":"+str(incident.claim_id)
					if not _state.cases.has(key):
						var question: Dictionary = incident.duplicate(true)
						question.id = key; question.partner_id = source_id; question.heard_from = partner
						question.stance = "suspicion"; question.confrontation = true; question.effects = []
						_state.cases[key] = question
				incident.status = "resolved"
		"deny": incident.status = "resolved"
		"avoid": _effect(incident,"avoidance",partner,0,0,2)
		"change": incident.status = "resolved"
		"apology":
			if incident.stance == "confirmed": _effect(incident,"apology",partner,2,1,-5)
			incident.status = "resolved"
	_trim_cases()
	return true

func pending_confrontation(a: String, b: String) -> Dictionary:
	var value := pending_case(a,b)
	if value.is_empty() or not value.confrontation or value.asked: return {}
	value.claimant = a
	value.accused = b
	return value

func resolve_confrontation(a: String, b: String, event_id: String) -> bool:
	if not _physical(a,b): return false
	var found := pending_confrontation(a,b)
	if found.is_empty() or not _receipt("confront:"+event_id.left(120)+":"+found.id): return false
	var incident: Dictionary = _state.cases[found.id]
	incident.asked = true
	# This method records the question. Admission/denial and penalties require respond_case.
	return true

func hear_statement(listener: String, speaker: String, text: String, privacy: String = "personal", subject_id: String = "") -> String:
	text = _clean(text)
	if speaker != "player" or not _physical(speaker,listener) or privacy not in PRIVACY or text.length() < 12 or text.length() > 240: return ""
	if subject_id.is_empty(): subject_id = speaker
	if subject_id not in Registry.ids(): return ""
	var id := "statement:"+speaker+":"+str(_stable(_fold(text)))
	if not _can_record_disclosure(speaker,listener,id): return ""
	if not _state.knowledge[listener].has(id) and not _make_room(listener,not _state.topics.has(id)): return ""
	if not _state.topics.has(id):
		if not _make_room(speaker) or not _make_room(listener): return ""
		var topic := {"id":id,"owner_id":speaker,"subjects":[subject_id],"kind":"rumor","privacy":privacy,"text":text.strip_edges(),"aliases":[],
			"seed_holders":[],"origin_label":"Testimonio literal del jugador; no verificado por el mundo.","require_trust":70 if privacy == "secret" else 45,"leakable":privacy != "public"}
		_state.topics[id] = topic
		_state.knowledge[speaker][id] = _entry(topic,speaker,speaker,"observed",100,_minute(),"statement:self")
	# The sender explicitly chose this listener; it does not need an automatic trust gate.
	_add_disclosure(speaker,listener,id,_event(""),true,_minute())
	if not _state.knowledge[listener].has(id): _state.knowledge[listener][id] = _entry(_state.topics[id],listener,speaker,"heard",60,_minute(),"statement:heard")
	return id

func find_opinion(owner: String, subject: String, tag: String) -> Dictionary:
	return knowledge_for(owner,"opinion:"+owner+":"+subject+":"+str(_stable(tag)))

func _make_room(owner: String, new_topic: bool = true) -> bool:
	while (_state.topics.size() >= MAX_TOPICS and new_topic) or _state.knowledge[owner].size() >= MAX_KNOWN:
		var victim := ""
		var oldest := 9000000000000
		for id: String in _state.topics:
			var topic: Dictionary = _state.topics[id]
			if _catalog.has(id) or topic.privacy != "public": continue
			if _state.knowledge[owner].size() >= MAX_KNOWN and not _state.knowledge[owner].has(id): continue
			var protected := false
			for incident: Dictionary in _state.cases.values():
				if incident.claim_id == id and incident.status == "open": protected = true; break
			if protected: continue
			var newest := 0
			for entries: Dictionary in _state.knowledge.values():
				if entries.has(id): newest = maxi(newest,int(entries[id].minute))
			if newest < oldest: oldest = newest; victim = id
		if victim.is_empty(): return false
		_state.topics.erase(victim)
		for entries: Dictionary in _state.knowledge.values(): entries.erase(victim)
		for index in range(_state.disclosures.size()-1,-1,-1):
			if _state.disclosures[index].claim_id == victim: _state.disclosures.remove_at(index)
		for id: String in _state.cases.keys():
			if _state.cases[id].claim_id == victim: _state.cases.erase(id)
	return true

func note_opinion(owner: String, subject: String, text: String, privacy: String = "personal", tag: String = "") -> String:
	text = _clean(text)
	if not _ready_world() or owner not in Registry.ids() or subject not in Registry.ids() or owner == subject or privacy not in PRIVACY or text.length() < 12 or text.length() > 240: return ""
	if not _world.get_ref().is_present(owner): return ""
	var id := "opinion:"+owner+":"+subject+":"+str(_stable(tag if not tag.is_empty() else text))
	if _state.topics.has(id): return id
	if not _make_room(owner): return ""
	var topic := {"id":id,"owner_id":owner,"subjects":[subject,owner],"kind":"opinion","privacy":privacy,"text":text,"aliases":[],
		"seed_holders":[],"origin_label":"Impresión personal tras una experiencia; no demuestra los sentimientos ni intenciones de la otra persona.","require_trust":70 if privacy == "secret" else (0 if privacy == "public" else 45),"leakable":privacy != "secret"}
	_state.topics[id] = topic
	_state.knowledge[owner][id] = _entry(topic,owner,owner,"observed",100,_minute(),"opinion:self")
	return id

func note_world_memory(owner: String, memory: Dictionary) -> void:
	if not _ready_world() or owner not in Registry.ids(): return
	if memory.get("kind","") not in ["trabajo","comunidad","ayuda","llegada","exploracion","practica","enseñanza","objeto"]: return
	if owner not in memory.get("participants",[]) or not memory.get("id") is String or not memory.get("content") is String: return
	# Called only at the engine's observation commit, never while replaying old transcripts.
	if int(memory.get("minute",-1)) != _minute() or not _world.get_ref().is_present(owner): return
	var id := "world:"+str(memory.id)
	if id.length() > 80 or (not _state.knowledge[owner].has(id) and not _make_room(owner,not _state.topics.has(id))): return
	var source: String = str(memory.get("heard_from",owner))
	if source not in Registry.ids(): return
	for authored: Dictionary in _catalog.values():
		if authored.privacy != "public" and _matches(authored,str(memory.content)): return
	var heard: bool = source != owner
	if not _state.topics.has(id):
		_state.topics[id] = {"id":id,"owner_id":source,"subjects":[str(memory.participants[0])],"kind":"fact","privacy":"public","text":_clean(str(memory.content)).left(240),
			"aliases":[],"seed_holders":[],"origin_label":_clean(str(memory.get("origin","Observación directa"))).left(300),"require_trust":0,"leakable":false}
	if not _state.knowledge[owner].has(id):
		_state.knowledge[owner][id] = _entry(_state.topics[id],owner,source,"heard" if heard else "observed",75 if heard else 100,_minute(),str(memory.id))

func context_for(owner: String, listener: String, query: String = "") -> Dictionary:
	var output := {"claims":[],"case":{},"policy":"Sólo se incluyen temas que este personaje puede compartir aquí; lo escuchado no está comprobado."}
	if not _pair(owner,listener): return output
	var candidates := candidates_for(owner,listener)
	var words := _fold(query).split(" ",false)
	candidates.sort_custom(func(a,b): return _score(str(_state.topics[a].text),words) > _score(str(_state.topics[b].text),words))
	for id in candidates:
		var known := knowledge_for(owner,id)
		var topic := {"id":id,"subject_id":known.subject_id,"text":(("He oído versiones distintas. " if known.certainty == "uncertain" else "")+str(known.text)).left(240),"kind":known.kind,"certainty":known.certainty,
			"source_id":known.source_id,"privacy":known.privacy,"confidence":int(known.confidence)}
		output.claims.append(topic)
		if output.claims.size() >= 4: break
	var incident := pending_case(owner,listener)
	if not incident.is_empty(): output.case = {"id":incident.id,"subject_id":owner,"partner_id":listener,"stance":incident.stance,"prompt":"Algo privado llegó a esta persona sin que yo se lo contara. Quiero preguntar cómo lo supo, sin dar por culpable a nadie."}
	while JSON.stringify(output).length() > 2400 and not output.claims.is_empty(): output.claims.pop_back()
	return output

func _score(text: String, words: PackedStringArray) -> int:
	var score := 0
	for word in words:
		if word.length() >= 4 and _fold(text).contains(word): score += 1
	return score

func filter_text(owner: String, listener: String, text: String) -> String:
	if listener.is_empty() or listener == owner: return text
	var explicit_private := false
	for marker in ["no se lo digas","entre nosotros","es un secreto","en confianza"]:
		if _fold(text).contains(marker): explicit_private = true
	var permitted := false
	for id: String in _state.get("topics",{}):
		var topic: Dictionary = _state.topics[id]
		if topic.privacy != "public" and _matches(topic,text):
			if not can_share(owner,listener,id): return "[Detalle privado reservado por este personaje.]"
			permitted = true
	if explicit_private and not permitted: return "[Detalle privado reservado por este personaje.]"
	return text

func filter_memory(owner: String, listener: String, memory: Dictionary) -> Dictionary:
	var copy: Dictionary = memory.duplicate(true)
	for key in ["content","heard_text"]:
		if copy.get(key) is String: copy[key] = filter_text(owner,listener,copy[key])
	for turn in copy.get("turns",[]):
		if turn is Dictionary and turn.get("text") is String: turn.text = filter_text(owner,listener,turn.text)
	return copy

func _keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size(): return false
	for key in keys:
		if not value.has(key): return false
	return true

func _integer(value, low: int, high: int = 9000000000000) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= low and value <= high

func _text(value, limit: int, empty: bool = false) -> bool:
	return value is String and value.length() <= limit and (empty or not value.is_empty()) and _clean(value) == value

func validate(value, minute: int = -1) -> bool:
	if not value is Dictionary or not _keys(value,["version","serial","topics","knowledge","disclosures","cases","receipts"]): return false
	if value.version != 1 or not _integer(value.serial,0): return false
	if not value.topics is Dictionary or value.topics.size() > MAX_TOPICS or not value.knowledge is Dictionary or value.knowledge.size() != Registry.ids().size(): return false
	for id in value.topics:
		var topic = value.topics[id]
		if not _text(id,80) or not topic is Dictionary or not _keys(topic,["id","owner_id","subjects","kind","privacy","text","aliases","seed_holders","origin_label","require_trust","leakable"] + (["variants"] if topic.has("variants") else [])): return false
		if topic.id != id or topic.owner_id not in Registry.ids() or topic.kind not in KINDS or topic.privacy not in PRIVACY or not _text(topic.text,240) or not _text(topic.origin_label,300): return false
		if not topic.subjects is Array or topic.subjects.is_empty() or topic.subjects.size() > 6 or not topic.aliases is Array or topic.aliases.size() > 8 or not topic.seed_holders is Array: return false
		for person in topic.subjects + topic.seed_holders:
			if person not in Registry.ids(): return false
		for alias in topic.aliases:
			if not _text(alias,100): return false
		if not topic.get("variants",[]) is Array or topic.get("variants",[]).size() > 3: return false
		for version in topic.get("variants",[]):
			if not _text(version,240): return false
		if not _integer(topic.require_trust,0,100) or not topic.leakable is bool: return false
		if _catalog.has(id):
			if topic != _catalog[id]: return false
		elif not (str(id).begins_with("world:") or str(id).begins_with("statement:") or str(id).begins_with("opinion:")) or not topic.seed_holders.is_empty() or not topic.aliases.is_empty(): return false
	for id in _catalog:
		if not value.topics.has(id): return false
	for owner in Registry.ids():
		if not value.knowledge.get(owner) is Dictionary or value.knowledge[owner].size() > MAX_KNOWN: return false
		for id in value.knowledge[owner]:
			var entry = value.knowledge[owner][id]
			if not value.topics.has(id) or not entry is Dictionary or not _keys(entry,["claim_id","text","certainty","source_id","confidence","minute","authorized_by","authorized_recipient","path","evidence","versions"]): return false
			if _catalog.has(id) and entry.certainty == "observed" and owner != value.topics[id].owner_id: return false
			if entry.claim_id != id or entry.text not in [value.topics[id].text]+value.topics[id].get("variants",[]) or entry.certainty not in CERTAINTY or entry.source_id not in Registry.ids(): return false
			if (entry.certainty == "observed") != (entry.source_id == owner) or not _integer(entry.confidence,0,100) or not _integer(entry.minute,0): return false
			if entry.authorized_by != value.topics[id].owner_id or entry.authorized_recipient not in ["",owner]: return false
			if not entry.path is Array or entry.path.is_empty() or entry.path.size() > 8 or entry.path.back() != owner or not entry.evidence is Array or entry.evidence.is_empty() or entry.evidence.size() > 4: return false
			for person in entry.path:
				if person not in Registry.ids(): return false
			for evidence in entry.evidence:
				if not _text(evidence,120): return false
			if not entry.versions is Array or entry.versions.is_empty() or entry.versions.size() > 3: return false
			for version in entry.versions:
				if not version is Dictionary or not _keys(version,["text","source_id","confidence","minute","event_id","kind"]): return false
				if not _text(version.text,240) or version.source_id not in Registry.ids() or not _integer(version.confidence,0,100) or not _integer(version.minute,0) or not _text(version.event_id,120) or version.kind not in ["statement","disagreement"]: return false
				if version.kind == "statement" and version.text not in [value.topics[id].text]+value.topics[id].get("variants",[]): return false
	if not value.disclosures is Array or value.disclosures.size() > MAX_DISCLOSURES: return false
	var unique := {}
	for record in value.disclosures:
		if not record is Dictionary or not _keys(record,["speaker","listener","claim_id","minute","authorized","event_id"]): return false
		if record.speaker not in Registry.ids() or record.listener not in Registry.ids() or record.speaker == record.listener or not value.topics.has(record.claim_id): return false
		if not value.knowledge[record.speaker].has(record.claim_id) or not value.knowledge[record.listener].has(record.claim_id): return false
		if not _integer(record.minute,0) or not record.authorized is bool or not _text(record.event_id,120): return false
		if record.authorized and value.topics[record.claim_id].privacy == "secret" and record.speaker != value.topics[record.claim_id].owner_id: return false
		var key: String = record.speaker+":"+record.listener+":"+record.claim_id
		if unique.has(key): return false
		unique[key] = true
	if not value.cases is Dictionary or value.cases.size() > MAX_CASES: return false
	for id in value.cases:
		var incident = value.cases[id]
		if not _text(id,80) or not incident is Dictionary or not _keys(incident,["id","owner_id","subject_id","partner_id","claim_id","heard_from","stance","status","suspects","reported_source","minute","event_id","confrontation","asked","effects","breached_at"]): return false
		if incident.id != "case:"+str(incident.owner_id)+":"+str(incident.partner_id)+":"+str(incident.claim_id): return false
		if incident.id != id or incident.owner_id not in Registry.ids() or incident.subject_id != incident.owner_id or incident.partner_id not in Registry.ids() or incident.partner_id == incident.owner_id or not value.topics.has(incident.claim_id): return false
		if value.topics[incident.claim_id].owner_id != incident.owner_id or value.topics[incident.claim_id].privacy != "secret" or incident.heard_from not in Registry.ids(): return false
		if incident.stance not in ["suspicion","confirmed"] or incident.status not in ["open","resolved"] or incident.reported_source not in Registry.ids()+[""] or not _integer(incident.minute,0) or not _text(incident.event_id,120): return false
		if not _integer(incident.breached_at,0) or not incident.confrontation is bool or not incident.asked is bool or not incident.suspects is Array or incident.suspects.size() > Registry.ids().size() or not incident.effects is Array or incident.effects.size() > 3: return false
		for suspect in incident.suspects:
			if suspect not in Registry.ids(): return false
			var remembered := false
			for record: Dictionary in value.disclosures:
				if record.speaker == incident.owner_id and record.listener == suspect and record.claim_id == incident.claim_id and record.authorized: remembered = true; break
			if not remembered: return false
		for effect in incident.effects:
			if effect not in ["admission","apology","avoidance"]: return false
	if not value.receipts is Dictionary or value.receipts.size() > MAX_RECEIPTS: return false
	for id in value.receipts:
		if not _text(id,300) or not _integer(value.receipts[id],0): return false
	if minute >= 0:
		for entries: Dictionary in value.knowledge.values():
			for entry: Dictionary in entries.values():
				if entry.minute > minute: return false
				for version: Dictionary in entry.versions:
					if version.minute > minute: return false
		for record: Dictionary in value.disclosures:
			if record.minute > minute: return false
		for incident: Dictionary in value.cases.values():
			if incident.minute > minute or incident.breached_at > minute: return false
		for receipt_minute in value.receipts.values():
			if receipt_minute > minute: return false
	return true
