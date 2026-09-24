extends RefCounted
## Directed social state. Local rules, bounded ledgers, no model or XP.
const Layout = preload("res://scripts/world_layout.gd")
const Residents = preload("res://scripts/resident_catalog.gd")
static var IDS: Array = Residents.ids()
const METRICS := ["trust","affection","tolerance","frustration"]
const STAMPS := ["updated_at","cooldown_until","last_contact","last_finish","last_pressure","last_credit","last_greeting"]
const KEYS := ["trust","affection","tolerance","frustration","updated_at","cooldown_until","last_contact","last_finish","last_pressure","credit_day","credits","last_credit","topics","recent_events","greeting_day","greeting_count","last_greeting"]
const PUBLIC_BIO := {
	"cesar":"Es vecino de la colonia y cuida plantas.",
	"lupita":"Organiza actividades para reunir a los vecinos.",
	"mateo":"Trabaja en el taller y repara bicicletas.",
	"ines":"Atiende el café y prepara té para sus visitantes.",
	"alma":"Dibuja y fotografía los espacios de la colonia.",
	"player":"Es un nuevo habitante de la colonia."
}
const PERSONAL_BIO := {
	"cesar":"Acaba de mudarse a la colonia y suele cuidar las plantas al amanecer.",
	"lupita":"Creció en la ciudad. Disfruta reunir a sus vecinos y también sus momentos tranquilos.",
	"mateo":"Aprendió a reparar bicicletas en un taller familiar. Practica cómo explicar su trabajo con paciencia.",
	"ines":"Vivió en varias ciudades antes de abrir el café. Disfruta escuchar historias de sus visitantes.",
	"alma":"Siempre ha vivido en la colonia. Guarda fotografías de sus cambios y dibuja lugares que quiere conservar.",
	"player":"Está conociendo a sus vecinos y construyendo una vida en la colonia."
}
var _world: WeakRef
var _sessions: Dictionary = {}
var _pending_greetings: Dictionary = {}
const QUIET_MINUTES := 45
const OPEN_MINUTES := 60
const QUIET_LINES := [
	"Ahora prefiero un rato a solas. Luego hablamos.",
	"Ahorita no tengo ganas de platicar. Hablamos luego.",
	"Me gustaría estar un rato por mi cuenta. Luego platicamos.",
	"Ahora necesito despejarme un poco. Nos vemos al rato."
]
var _willingness_roll: Callable

static func initial_availability() -> Dictionary:
	return {"until":0,"declined":false,"notified":[],"line":0}

func setup(world, migrating: bool = false) -> void:
	_world = weakref(world)
	_sessions.clear()
	_pending_greetings.clear()
	for owner: Dictionary in world.residents:
		if not owner.has("chat_availability"): owner["chat_availability"] = initial_availability()
		if not owner.has("relationships"): owner["relationships"] = {}
		for partner: String in IDS:
			if partner == owner.id or owner.relationships.has(partner): continue
			var state: Dictionary = _baseline(owner)
			if migrating:
				var days := {}
				for memory: Dictionary in owner.memories:
					if memory.kind == "conversacion" and partner in memory.participants:
						days[int(memory.day)] = true
					if days.size() >= 6: break
				state.trust += days.size() * 2.0
				state.affection += days.size()
			owner.relationships[partner] = state

func _key(owner: String, partner: String) -> String:
	return owner + ">" + partner

func _valid_pair(owner: String, partner: String) -> bool:
	return owner in IDS and partner in IDS and owner != partner and not _world.get_ref().get_resident(owner).is_empty() and not _world.get_ref().get_resident(partner).is_empty()

func _baseline(owner: Dictionary) -> Dictionary:
	var traits: String = _fold(" ".join(owner.personality))
	var trust := 26.0
	var affection := 20.0
	var tolerance := 78.0
	if traits.contains("reservado"): trust -= 6; tolerance -= 6
	if traits.contains("independiente"): trust -= 3; tolerance -= 6
	if traits.contains("sociable"): trust += 5; affection += 5; tolerance += 8
	if traits.contains("paciente"): tolerance += 12
	if traits.contains("atenta") or traits.contains("considerada"): tolerance += 6; affection += 3
	if traits.contains("directa"): tolerance -= 4
	var world = _world.get_ref()
	return {"trust":trust,"affection":affection,"tolerance":tolerance,"frustration":0.0,
		"updated_at":world.minute,"cooldown_until":0,"last_contact":0,"last_finish":0,"last_pressure":0,
		"credit_day":int(world.minute/1440),"credits":0,"last_credit":0,"topics":[],"recent_events":[],
		"greeting_day":int(world.minute/1440),"greeting_count":0,"last_greeting":0}

func _resting(owner: Dictionary) -> bool:
	var world = _world.get_ref()
	if world.is_sleeping(owner.id): return true
	if owner.get("room", "street") != owner.id: return false
	var point: Vector2 = Layout.point(owner.pos)
	return point.distance_to(Layout.point(owner.target)) < 0.5 and (point.distance_to(Layout.point(Layout.data().home_rest)) <= 12 or point.distance_to(Layout.stand_at("bed",owner.id)) <= 12)

func _recover(state: Dictionary, owner: Dictionary, partner: String) -> void:
	var world = _world.get_ref()
	if not world.is_present(owner.id): return
	var arrival: int = int(world.settlement.state.inhabitants.get(owner.id, {}).get("arrived_at", 0))
	var elapsed: int = maxi(0,world.minute-maxi(int(state.updated_at), arrival))
	state.updated_at = world.minute
	if elapsed == 0 or (owner.id in world.conversation_holds and partner in world.conversation_holds): return
	var resting := _resting(owner)
	var baseline: Dictionary = _baseline(owner)
	state.tolerance = minf(maxf(float(state.tolerance),float(baseline.tolerance)),float(state.tolerance)+elapsed*(0.08 if resting else 0.025))
	state.frustration = maxf(0.0,float(state.frustration)-elapsed*(0.12 if resting else 0.04))

func tick() -> void:
	var world = _world.get_ref()
	for owner: Dictionary in world.residents:
		if not world.is_present(owner.id): continue
		for partner: String in owner.relationships:
			_recover(owner.relationships[partner],owner,partner)

func _project(owner: String, partner: String) -> Dictionary:
	if not _valid_pair(owner,partner): return {}
	var resident: Dictionary = _world.get_ref().get_resident(owner)
	var state: Dictionary = resident.relationships[partner].duplicate(true)
	_recover(state,resident,partner)
	return state

func relationship_for(owner: String, partner: String) -> Dictionary:
	var state := _project(owner,partner)
	if state.is_empty(): return {}
	var disclosure := "public"
	if state.trust >= 45 and state.frustration < 40: disclosure = "personal"
	if state.trust >= 70 and state.affection >= 50 and state.frustration < 25: disclosure = "intimate"
	var mood := "calm"
	if state.trust < 25: mood = "guarded"
	if state.trust >= 60 and state.affection >= 40: mood = "warm"
	if state.tolerance <= 30 or state.frustration >= 40: mood = "tired"
	if state.frustration >= 65: mood = "irritated"
	return {"trust":state.trust,"affection":state.affection,"tolerance":state.tolerance,"frustration":state.frustration,
		"mood":mood,"disclosure":disclosure,"cooldown_until":int(state.cooldown_until)}

func visible_profile_for(owner: String, viewer: String) -> Dictionary:
	var world = _world.get_ref()
	var resident: Dictionary = world.get_resident(owner)
	if resident.is_empty(): return {}
	var level: String = "intimate" if owner == viewer else str(relationship_for(owner,viewer).get("disclosure","public"))
	var biography: String = str(resident.biography) if level == "intimate" else str(PERSONAL_BIO.get(owner,PUBLIC_BIO.player) if level == "personal" else PUBLIC_BIO.get(owner,PUBLIC_BIO.player))
	return {"biography":biography.left(1000),"personality":resident.personality.duplicate(),"goal":str(resident.goal).left(300) if level != "public" else ""}

func _session(owner: String, partner: String) -> Dictionary:
	return _sessions.get(_key(owner,partner),{"turns":0,"questions":0,"private_requests":0,"last_heard":"","repeat_count":0})

func _address(partner: String) -> String:
	var name: String = str(_world.get_ref().get_resident(partner).name).strip_edges().left(24)
	return "" if name == "Tú" or name.is_empty() else ", " + name

func _space_reply(owner: String, partner: String, repeat_contact: bool = false) -> String:
	var variant: int = int(_world.get_ref().get_resident(owner).relationships[partner].get("greeting_count",0)) + int(_session(owner,partner).turns)
	for character in owner.to_utf8_buffer(): variant += character
	if repeat_contact:
		return ("Ya hablamos%s. Necesito un rato." if variant % 2 == 0 else "Ahora necesito espacio%s. Hablemos después.") % _address(partner)
	return ("Sí%s, tengo que seguir. Hablamos después." if variant % 2 == 0 else "Voy a tomarme un rato%s. Seguimos otro día.") % _address(partner)

func available(owner: String) -> bool:
	# Selection and UI reads never roll a mood or count as unwanted contact.
	var world = _world.get_ref()
	var person: Dictionary = world.get_resident(owner)
	if person.is_empty(): return false
	var state: Dictionary = person.get("chat_availability", initial_availability())
	return not state.declined or world.minute >= int(state.until)

func _decline_chance(person: Dictionary) -> float:
	var traits := _fold(" ".join(person.personality))
	var chance := 0.18
	if traits.contains("reservado") or traits.contains("independiente"): chance += 0.07
	if traits.contains("sociable"): chance -= 0.07
	var kind: String = str(_world.get_ref().daily_state(person.id).get("kind", ""))
	if kind in ["working", "eating"]: chance += 0.08
	return clampf(chance, 0.08, 0.35)

func _pressure(owner: String, partner: String) -> void:
	var world = _world.get_ref()
	var person: Dictionary = world.get_resident(owner)
	var state: Dictionary = person.relationships[partner]
	_recover(state,person,partner)
	if int(state.last_pressure) == world.minute and int(state.cooldown_until) > world.minute: return
	state.last_pressure = world.minute
	state.frustration = minf(100,state.frustration+8)
	state.tolerance = maxf(0,state.tolerance-6)
	state.cooldown_until = maxi(int(state.cooldown_until),world.minute+30)

func _availability_reply(person: Dictionary, partner: String) -> Dictionary:
	var world = _world.get_ref()
	var state: Dictionary = person.chat_availability
	if world.minute >= int(state.until):
		# After a respected pause, offer a real opportunity to reconnect rather
		# than repeatedly rolling another refusal. Existing personal limits win.
		var was_quiet: bool = state.declined
		var roll := 1.0
		if not was_quiet: roll = float(_willingness_roll.call()) if _willingness_roll.is_valid() else randf()
		state.declined = not was_quiet and roll < _decline_chance(person)
		state.until = world.minute + (QUIET_MINUTES if state.declined else OPEN_MINUTES)
		state.notified.clear()
		state.line = int(abs(hash("%s:%d" % [person.id, world.minute]))) % QUIET_LINES.size()
	if not state.declined: return {}
	if partner not in state.notified:
		state.notified.append(partner)
		return {"allowed":false,"reply":QUIET_LINES[int(state.line)],"end":true,"reason":"unavailable"}
	_pressure(person.id,partner)
	var frustration: float = float(person.relationships[partner].frustration)
	var reply: String = ("Te pedí un rato%s. Por favor, no insistas." if frustration < 24 else "Basta%s. Ya te dije que ahora no quiero hablar.") % _address(partner)
	return {"allowed":false,"reply":reply,"end":true,"reason":"availability_pressure"}

func start(owner: String, partner: String) -> Dictionary:
	var world = _world.get_ref()
	if not _valid_pair(owner,partner): return {"allowed":false,"reply":"No podemos conversar ahora.","end":true}
	var person: Dictionary = world.get_resident(owner)
	var other: Dictionary = world.get_resident(partner)
	if world.is_sleeping(owner) or world.is_sleeping(partner) or world._distance(person,other) >= world.MAX_DISTANCE:
		return {"allowed":false,"reply":"Ahora no puedo conversar contigo.","end":true}
	if _sessions.has(_key(owner,partner)): return {"allowed":true,"reply":"","end":false}
	# An announced temporary no stays a no, even if another invitation arrives
	# before the clock advances. The first request never changes relationships.
	if owner != "player" and not available(owner):
		return _availability_reply(person,partner)
	var snapshot := _project(owner,partner)
	if world.minute < int(snapshot.cooldown_until) or snapshot.frustration >= 75 or snapshot.tolerance <= 12:
		_pressure(owner,partner)
		return {"allowed":false,"reply":_space_reply(owner,partner,true),"end":true}
	if owner != "player":
		var availability := _availability_reply(person,partner)
		if not availability.is_empty(): return availability
	_sessions[_key(owner,partner)] = _session(owner,partner)
	return {"allowed":true,"reply":"","end":false}

func _limits(owner: String) -> Dictionary:
	var traits: String = _fold(" ".join(_world.get_ref().get_resident(owner).personality))
	return {"turns":12 if traits.contains("sociable") else 8 if traits.contains("reservado") or traits.contains("independiente") else 10,
		"questions":7 if traits.contains("sociable") or traits.contains("paciente") else 5}

func _fold(text: String) -> String:
	return text.to_lower().replace("á","a").replace("é","e").replace("í","i").replace("ó","o").replace("ú","u").strip_edges()

func _insult(text: String) -> bool:
	var folded := _fold(text)
	for negation in ["no eres","no sos","no te digo","me dijeron","me llamaron"]:
		if folded.contains(negation): return false
	for phrase in ["eres idiota","eres un idiota","eres una idiota","eres estupido","eres una estupida","eres un estupido","eres inutil","callate","vete a la mierda","chingas a tu madre","chinga tu madre","te odio"]:
		if folded.contains(phrase): return true
	return folded in ["idiota","estupido","estupida","imbecil","inutil"]

func _private_level(text: String) -> String:
	var folded := _fold(text)
	if not (folded.contains("?") or folded.begins_with("cuentame") or folded.begins_with("dime") or folded.begins_with("hablame")): return ""
	for term in ["tu papa","tu mama","tus padres","tu familia","tus abuelos","secretos","trauma","intimidad","vida amorosa","pareja","por que murio","tu dolor"]:
		if folded.contains(term): return "intimate"
	for term in ["donde creciste","donde naciste","de donde vienes","de donde eres","tu infancia","tu pasado","tu historia personal","quien te enseño","quien te enseno"]:
		if folded.contains(term): return "personal"
	return ""

func _farewell(text: String) -> bool:
	var folded := _fold(text)
	for phrase in ["adios","hasta luego","hasta pronto","nos vemos","te dejo descansar","ya me voy","eso era todo"]:
		if folded.contains(phrase): return true
	return false

func _trivial(text: String) -> bool:
	var folded := _fold(text).replace("¿", "").replace("¡", "")
	var words: PackedStringArray = folded.replace("¿","").replace("?","").replace("!","").replace("¡","").replace(",","").replace(".","").split(" ",false)
	if words.size() < 4: return true
	# Gratitude and greetings never grant trust, even with ornamental extra words.
	if folded.begins_with("gracias") or folded.begins_with("muchas gracias") or folded.begins_with("muchisimas gracias"): return true
	for phrase in ["buenos dias","buenas tardes","buenas noches","hola","como estas","que tal"]:
		if folded.begins_with(phrase) and words.size() <= 8: return true
	return _farewell(text)

func turn(owner: String, partner: String, text: String, session_exchanges: int) -> Dictionary:
	if not _valid_pair(owner,partner) or text.strip_edges().is_empty() or text.length() > 1500:
		return {"reply":"No entendí ese mensaje.","end":false,"reason":"invalid"}
	var world = _world.get_ref()
	var state := _project(owner,partner)
	var session := _session(owner,partner)
	if _insult(text): return {"reply":"Así no quiero seguir hablando. Necesito espacio.","end":true,"reason":"insult"}
	if _farewell(text): return {"reply":"Nos vemos. Que estés bien.","end":true,"reason":"farewell"}
	if world.minute < int(state.cooldown_until) or state.frustration >= 75 or state.tolerance <= 12:
		return {"reply":_space_reply(owner,partner,true),"end":true,"reason":"space"}
	var requested: String = _private_level(text)
	var disclosed: String = relationship_for(owner,partner).disclosure
	if not requested.is_empty() and (disclosed == "public" or requested == "intimate" and disclosed != "intimate"):
		if int(session.private_requests) >= 2: return {"reply":"Ya te dije que prefiero guardar ese tema. Necesito una pausa.","end":true,"reason":"privacy_pressure"}
		return {"reply":"Prefiero conocerte mejor antes de hablar de eso." if int(session.private_requests) == 0 else "Prefiero dejar ese tema. Podemos hablar de otra cosa.","end":false,"reason":"privacy"}
	if _fold(text) == session.last_heard and (text.contains("?") or not _trivial(text)):
		if int(session.repeat_count) >= 2: return {"reply":_space_reply(owner,partner),"end":true,"reason":"repeat_pressure"}
		return {"reply":"Ya te respondí%s. Podemos cambiar de tema." % _address(partner),"end":false,"reason":"repeat"}
	var limits := _limits(owner)
	if maxi(session_exchanges,int(session.turns)) >= int(limits.turns) or text.contains("?") and int(session.questions) >= int(limits.questions):
		return {"reply":_space_reply(owner,partner),"end":true,"reason":"fatigue"}
	return {"reply":"","end":false,"reason":""}

func _note_encounter(state: Dictionary) -> void:
	var world = _world.get_ref()
	if int(state.greeting_day) != int(world.minute/1440):
		state.greeting_day = int(world.minute/1440)
		state.greeting_count = 0
	state.greeting_count = mini(24,int(state.greeting_count)+1)
	state.last_greeting = world.minute

func _note_side(owner: String, partner: String, heard: String, own_text: String, fingerprint: String, greeting: bool) -> void:
	var world = _world.get_ref()
	var person: Dictionary = world.get_resident(owner)
	var state: Dictionary = person.relationships[partner]
	if fingerprint in state.recent_events: return
	var preflight: Dictionary = turn(owner,partner,heard,int(_session(owner,partner).turns))
	_recover(state,person,partner)
	state.recent_events.append(fingerprint)
	if state.recent_events.size() > 8: state.recent_events.pop_front()
	state.last_contact = world.minute
	if greeting:
		_note_encounter(state)
		return
	var session: Dictionary = _session(owner,partner)
	_sessions[_key(owner,partner)] = session
	# A conversation counts as meeting today once, on its first completed exchange.
	# Merely starting, preparing a reply or cancelling never reaches this point.
	if int(session.turns) == 0: _note_encounter(state)
	session.turns += 1
	session.questions = int(session.questions)+1 if heard.contains("?") else 0
	session.repeat_count = int(session.repeat_count)+1 if session.last_heard == _fold(heard) else 1
	session.last_heard = _fold(heard)
	match str(preflight.reason):
		"insult":
			state.trust = maxf(0,state.trust-8)
			state.affection = maxf(0,state.affection-6)
			state.tolerance = maxf(0,state.tolerance-24)
			state.frustration = minf(100,state.frustration+26)
		"privacy", "privacy_pressure":
			if int(session.private_requests) > 0:
				state.tolerance = maxf(0,state.tolerance-8)
				state.frustration = minf(100,state.frustration+10)
				state.trust = maxf(0,state.trust-2)
			session.private_requests += 1
		"space", "fatigue":
			state.tolerance = maxf(0,state.tolerance-5)
			state.frustration = minf(100,state.frustration+6)
		"repeat", "repeat_pressure":
			state.tolerance = maxf(0,state.tolerance-(10 if preflight.end else 5))
			state.frustration = minf(100,state.frustration+(10 if preflight.end else 5))
		"farewell": pass
		_:
			state.tolerance = maxf(0,state.tolerance-(3 if heard.contains("?") else 2))
			var topic: String = _fold(heard).sha256_text()
			var day: int = int(world.minute/1440)
			if int(state.credit_day) != day: state.credit_day = day; state.credits = 0
			if not _trivial(heard) and not _trivial(own_text) and not _insult(own_text) and topic not in state.topics and int(state.credits) < 2 and (int(state.last_credit) == 0 or world.minute-int(state.last_credit) >= 180):
				state.trust = minf(100,state.trust+4)
				state.affection = minf(100,state.affection+3)
				state.last_credit = world.minute
				state.credits += 1
				state.topics.append(topic)
				if state.topics.size() > 12: state.topics.pop_front()
	if preflight.end and preflight.reason != "farewell": state.cooldown_until = maxi(int(state.cooldown_until),world.minute+90)

func note_exchange(a: String, b: String, a_text: String, b_text: String, source: String, exchange_id: String) -> void:
	if not _valid_pair(a,b): return
	# An actual committed memory is unique, even when both texts repeat in the same minute.
	var fingerprint: String = exchange_id.sha256_text()
	var greeting: bool = source.begins_with("Saludo local")
	_note_side(a,b,b_text,a_text,fingerprint,greeting)
	_note_side(b,a,a_text,b_text,fingerprint,greeting)
	if greeting: _pending_greetings.erase(_pair_key(a,b))

func finish(owner: String, partner: String, respectful: bool = true) -> void:
	if not _valid_pair(owner,partner): return
	var world = _world.get_ref()
	var person: Dictionary = world.get_resident(owner)
	var state: Dictionary = person.relationships[partner]
	var active: bool = _sessions.has(_key(owner,partner)) or _sessions.has(_key(partner,owner))
	_sessions.erase(_key(owner,partner))
	_sessions.erase(_key(partner,owner))
	if not active and respectful: return
	state.last_finish = world.minute
	if not respectful: state.cooldown_until = maxi(int(state.cooldown_until),world.minute+45)

func _pair_key(a: String, b: String) -> String:
	return a+":"+b if a < b else b+":"+a

func greeting_pair(a: String, b: String) -> Dictionary:
	var empty := {"first":"","reply":""}
	if not _valid_pair(a,b): return empty
	if not available(a) or not available(b): return empty
	var world = _world.get_ref()
	var first: Dictionary = world.get_resident(a)
	var second: Dictionary = world.get_resident(b)
	if world._distance(first,second) >= world.MAX_DISTANCE or world.is_sleeping(a) or world.is_sleeping(b) or a in world.conversation_holds or b in world.conversation_holds: return empty
	var key := _pair_key(a,b)
	if int(_pending_greetings.get(key,0)) > world.minute: return empty
	for pair in [[a,b],[b,a]]:
		var state: Dictionary = _project(pair[0],pair[1])
		if int(state.cooldown_until) > world.minute or state.frustration >= 65 or (int(state.greeting_count) > 0 and world.minute-int(state.last_greeting) < 60): return empty
	var state: Dictionary = first.relationships[b]
	var count: int = int(state.greeting_count) if int(state.greeting_day) == int(world.minute/1440) else 0
	var hour: int = int(world.minute/60)%24
	var salutation := "Buenos días" if hour >= 6 and hour < 12 else "Buenas tardes" if hour >= 12 and hour < 19 else "Buenas noches"
	var name_b := "" if second.name == "Tú" else ", "+str(second.name)
	var name_a := "" if first.name == "Tú" else ", "+str(first.name)
	var lines := [
		{"first":salutation+name_b+".","reply":salutation+name_a+"."},
		{"first":"Hola de nuevo"+name_b+".","reply":"Hola"+name_a+"."},
		{"first":"Nos volvemos a encontrar.","reply":"Que vaya bien tu día."},
		{"first":"¿Qué tal va el día?","reply":"Aquí, siguiendo con mis cosas."}
	]
	_pending_greetings[key] = world.minute+10
	return lines[0 if count == 0 else 1+(count-1)%3].duplicate()

static func validate_availability(value: Variant, owner: String, minute: int) -> bool:
	if not value is Dictionary or value.size() != 4: return false
	if not value.get("declined") is bool or not value.get("notified") is Array: return false
	for key in ["until", "line"]:
		var number = value.get(key)
		if not (number is int or number is float) or not is_finite(float(number)) or number < 0 or float(number) != floor(float(number)): return false
	if value.until > minute + OPEN_MINUTES or value.line >= QUIET_LINES.size() or value.notified.size() > IDS.size()-1: return false
	if not value.declined and not value.notified.is_empty(): return false
	if owner == "player" and value.declined: return false
	var seen := {}
	for partner in value.notified:
		if not partner is String or partner not in IDS or partner == owner or seen.has(partner): return false
		seen[partner] = true
	return true

static func validate(value: Variant, owner: String, minute: int) -> bool:
	if not value is Dictionary or value.size() > IDS.size() - 1: return false
	for partner in value:
		if partner not in IDS or partner == owner: return false
		var state = value[partner]
		if not state is Dictionary or state.size() != KEYS.size(): return false
		for key in KEYS:
			if not state.has(key): return false
		for key in METRICS:
			var number = state[key]
			if not (number is int or number is float) or not is_finite(float(number)) or number < 0 or number > 100: return false
		for key in STAMPS + ["credit_day","credits","greeting_day","greeting_count"]:
			var number = state[key]
			if not (number is int or number is float) or not is_finite(float(number)) or number < 0 or float(number) != floor(float(number)) or number > 9007199254740991.0: return false
		if state.cooldown_until > minute+10080 or state.updated_at > minute or state.credits > 2 or state.greeting_count > 24: return false
		for key in ["topics","recent_events"]:
			if not state[key] is Array or state[key].size() > (12 if key == "topics" else 8): return false
			var seen := {}
			for text in state[key]:
				if not text is String or text.length() != 64 or seen.has(text): return false
				for index in range(text.length()):
					if not "0123456789abcdef".contains(text[index]): return false
				seen[text] = true
	return true
