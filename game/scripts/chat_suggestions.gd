extends RefCounted
## Immediate offline fallback. Questions and intentions never grant items or knowledge.
const MAX_CHARS := 45
const MAX_WORDS := 8
const OPENING_ACTIONS := {
	"repair": "¿Cómo va esa reparación?", "sort_tools": "¿Ordenando las herramientas?",
	"serve": "¿Está tranquilo el café?", "tidy_cups": "¿Ya casi terminas de ordenar?",
	"water": "¿Cómo van las plantas?", "check_soil": "¿Cómo está la tierra?",
	"sketch": "¿Me enseñas tu dibujo?", "plan_meeting": "¿Cómo va la reunión?",
	"drink": "¿Qué estás tomando?"
}
const SAFE_FOLLOWUPS := ["Gracias por contármelo.", "Me ha gustado hablar contigo.", "Te dejo seguir. Hasta luego."]

static func _fold(text: String) -> String:
	return " ".join(text.to_lower().replace("á", "a").replace("é", "e").replace("í", "i").replace("ó", "o").replace("ú", "u").replace("ü", "u").replace("ñ", "n").replace("\n", " ").replace("\r", " ").replace("\t", " ").split(" ", false))

static func _any(text: String, phrases: Array) -> bool:
	for phrase in phrases:
		if text.contains(str(phrase)): return true
	return false

static func _key(text: String) -> String:
	var result: String = _fold(text)
	for symbol in ["¿", "?", "¡", "!", ".", ",", ";", ":"]: result = result.replace(symbol, "")
	return result.strip_edges()

static func _word(text: String, word: String) -> bool:
	return (" " + _key(text) + " ").contains(" " + word + " ")

static func _question(reply: String) -> String:
	var end: int = reply.rfind("?")
	if end < 0: return ""
	var prefix: String = reply.left(end)
	var begin: int = prefix.rfind("¿")
	if begin < 0:
		begin = maxi(prefix.rfind("."), maxi(prefix.rfind("!"), prefix.rfind("?")))
	return _fold(prefix.substr(begin + 1).strip_edges())

static func _snapshot(world) -> Dictionary:
	if world != null and world.has_method("progression_state"):
		var value = world.progression_state()
		if value is Dictionary: return value
	return {}

static func _opening(world, id: String, scene_override: Dictionary = {}) -> String:
	var scene = scene_override
	if not scene.get("phase") is String or not scene.get("ongoing_action") is String:
		if not world.has_method("conversation_scene_for"): return "¿Qué tal va todo?"
		scene = world.conversation_scene_for(id)
	if not scene is Dictionary: return "¿Qué tal va todo?"
	var phase: String = str(scene.get("phase", ""))
	if phase == "walking": return "¿Hacia dónde vas?"
	if phase in ["working", "eating"]:
		return str(OPENING_ACTIONS.get(str(scene.get("ongoing_action", "")), "¿Qué tal va todo?"))
	if phase in ["resting", "leisure"]: return "¿Te acompaño un rato?"
	return "¿Qué tal va todo?"

static func _owns(state: Dictionary, item: String) -> bool:
	var inventory = state.get("inventory", {})
	return inventory is Dictionary and int(inventory.get(item, 0)) > 0

static func _verified(state: Dictionary, procedure: String) -> bool:
	var procedures = state.get("procedures", {})
	return procedures is Dictionary and procedures.get(procedure, {}) is Dictionary and procedures.get(procedure, {}).get("world_verified", false) == true

static func _source_known(known: String, item: String) -> bool:
	for sentence in known.split("."):
		if sentence.contains(item) and sentence.contains("tienda") and not sentence.contains("?") and not _any(sentence, ["no hay", "no vende", "no tiene", "no lo vende", "no se consigue"]): return true
	return false

static func _procedure(text: String) -> String:
	if text.contains("bici") or _word(text, "reparar") or _word(text, "reparaste"): return "reparar_bicicleta"
	if _any(text, ["sembr", "plantar", "jardin"]): return "plantar_jardin"
	if _any(text, ["preparar te", "preparaste el te", "receta"]): return "preparar_te"
	return ""

static func _answer(question: String, state: Dictionary, _id: String, reply: String, known: String) -> Array:
	if question.is_empty(): return []
	if _any(question, ["tienes", "conseguiste", "compraste", "trajiste", "te falta", "necesitas"]):
		if question.contains("aceite"):
			return ["Ya tengo el aceite.", "¿Cómo lo uso?"] if _owns(state, "aceite") else ["Aún no tengo aceite.", "Pasaré por la tienda." if _source_known(known, "aceite") else "¿Dónde consigo aceite?"]
		if question.contains("semillas"):
			return ["Ya tengo las semillas.", "¿Dónde las siembro?"] if _owns(state, "semillas") else ["Aún no tengo semillas.", "Pasaré por la tienda." if _source_known(known, "semillas") else "¿Dónde consigo semillas?"]
	if _any(question, ["ya sabes", "ya aprendiste", "ya reparaste", "ya sembraste", "ya practicaste", "ya preparaste", "has reparado", "has aprendido", "sabes reparar", "sabes preparar", "sabes plantar"]):
		var procedure: String = _procedure(question)
		if not procedure.is_empty():
			return ["Ya lo practiqué en casa.", "¿Cómo puedo hacerlo mejor?"] if _verified(state, procedure) else ["Aún necesito practicar.", "¿Cuál es el primer paso?"]
	if _any(question, ["prefieres", "eliges"]) and question.contains(" o "):
		var choices: Array = []
		for option in [["taller", "Prefiero ir al taller."], ["huerto", "Prefiero ir al huerto."], ["cafe", "Prefiero ir al café."], ["plaza", "Prefiero ir a la plaza."]]:
			if question.contains(option[0]): choices.append(option[1])
		if choices.size() >= 2: return choices.slice(0, 2)
	if _any(question, ["que te gustaria saber", "que quieres saber", "que te interesa saber"]): return ["¿Qué lugar me recomiendas conocer?", "¿Hace mucho que vives aquí?"]
	if _any(question, ["que te gustaria tomar", "que quieres tomar", "que te apetece beber"]): return ["Me apetece un té.", "Prefiero no tomar nada."]
	if _any(question, ["que te gustaria llevar", "que llevarias"]): return ["Me gustaría preparar algo.", "¿Qué hace falta para la comida?"]
	if _any(question, ["que te gusta", "que te interesa", "que quieres hacer", "que estas haciendo", "que te gustaria hacer"]):
		return ["Me apetece dar una vuelta.", "Me gustaría conocer mejor la colonia."]
	if _any(question, ["te animas", "te gustaria", "quieres", "te interesa", "me ayudas", "nos ayudas", "me acompanas", "vamos", "tomamos", "puedes ayudar"]):
		if _any(question, ["explic", "ensen", "mostrar"]): return ["Sí, explícame el primer paso.", "Prefiero intentarlo después."]
		if _any(question, ["ayud", "empez", "repar", "sembr", "cultiv"]): return ["Sí, ¿por dónde empezamos?", "Ahora prefiero conversar."]
		if _any(question, ["ir ", "vamos", "acompan", "pasear"]): return ["Sí, podemos ir juntos.", "Ahora prefiero quedarme aquí."]
		if _any(question, ["historia", "infancia", "familia"]): return ["Sí, ¿cómo empezó tu historia?", "Prefiero escucharla después."]
		if _any(question, ["un te", "tomar te", "cafe", "bebida", "tomamos"]) or question.ends_with(" te"): return ["Sí, me apetece una bebida.", "Ahora prefiero conversar."]
		return ["Sí, me gustaría probar.", "Prefiero dejarlo para después."]
	if question == "y tu" and _any(_fold(reply), ["creci", "familia", "infancia", "ciudad", "campo"]):
		return ["Prefiero contártelo después.", "¿Qué recuerdas de tu infancia?"]
	if question == "y tu" and _any(_fold(reply), ["ordenando", "reparando", "trabajando", "dibujando", "regando", "voy al", "iba al", "dar una vuelta"]):
		return ["Me apetece dar una vuelta.", "Quería pasar a saludarte."]
	if _any(question, ["como estas", "como te sientes", "como va tu dia"]) or question == "y tu":
		return ["Bien, gracias.", "Con ganas de explorar."]
	if _any(question, ["donde creciste", "de donde eres", "tu infancia", "tu familia", "tus padres"]):
		return ["Prefiero contártelo después.", "¿Qué recuerdas de tu infancia?"]
	if _any(question, ["te gusta", "disfrutas"]): return ["Me gustaría probarlo.", "¿Qué es lo que más te gusta?"]
	if _any(question, ["tienes tiempo", "puedes hablar", "podemos hablar", "te quedas"]): return ["Sí, podemos hablar un rato.", "Prefiero hablar después."]
	# A question we cannot safely answer still takes precedence over old topic words.
	return ["¿Puedes aclarar la pregunta?", "Prefiero responderte después."]

static func _context(reply: String, state: Dictionary, id: String, known: String) -> Array:
	var folded: String = _fold(reply)
	if _any(folded, ["no quiero hablar", "prefiero no hablar", "cambiemos de tema"]):
		return ["¿De qué te apetece hablar?", "Podemos hablar de otra cosa."]
	# The purpose of a visit wins over nouns naming a destination or its objects.
	var planned: bool = _any(folded, ["despues", "luego", "pensaba", "planeo", "voy", "iba", "ire", "quiero"])
	if planned and _any(folded, ["descans", "tomar una pausa"]): return ["Que disfrutes el descanso.", "¿Te acompaño un rato?"]
	if planned and _any(folded, ["dar una vuelta", "pasear", "paseo", "caminar", "voy al", "iba al", "ire al", "ir al", "voy a la", "iba a la", "ir a la"]):
		if _any(folded, ["regar", "reparar", "sembrar", "ordenar"]): return ["¿Te vendría bien una mano?", "¿Te llevará mucho rato?"]
		return ["¿Te acompaño a dar una vuelta?", "¿Vas a quedarte un rato?"]
	if folded.contains("herramientas") and _any(folded, ["ordenando", "organizando", "acomodando"]):
		return ["¿Cómo las organizas?", "¿Te falta mucho por ordenar?"]
	if folded.contains("tazas") and _any(folded, ["ordenando", "limpiando", "lavando"]):
		return ["¿Te echo una mano?", "¿Ha habido mucho movimiento?"]
	if folded.contains("aceite") and not _any(folded, ["no necesitas aceite", "no hace falta aceite", "aceite no hace falta", "sin aceite"]):
		var options: Array = ["Ya tengo el aceite." if _owns(state, "aceite") else ("Gracias, pasaré por la tienda." if _source_known(known, "aceite") else "¿Dónde consigo aceite?")]
		if not _any(known, ["gotas", "una botella", "poco aceite", "cantidad"]): options.append("¿Cuánto aceite necesito?")
		if id != "mateo" and folded.contains("mateo") and not _any(known, ["mateo esta en", "mateo en el taller", "encontraras a mateo"]): options.insert(1, "¿Mateo está en el taller?")
		if not _any(known, ["limpia", "limpiar", "aplica", "aplicar", "echa", "echar"]): options.append("¿Cómo lo aplico en la cadena?")
		options.append_array(["¿Cómo sé si quedó bien?", "Gracias, voy a probar."])
		return options
	# Only details spoken in this encounter can shape personal follow-ups.
	if _any(folded, ["abuelo", "papa", "mama", "infancia", "creci"]):
		if folded.contains("abuelo"): return ["¿Qué recuerdas de tus abuelos?", "¿Te gustaba pasar tiempo con ellos?"]
		if folded.contains("papa"): return ["¿Qué te gustaba hacer con tu papá?", "¿Qué recuerdo guardas con más cariño?"]
		if folded.contains("mama"): return ["¿Qué te gustaba hacer con tu mamá?", "¿Qué recuerdo guardas con más cariño?"]
		return ["¿Qué es lo que más recuerdas?", "¿Te gustaba vivir allí?"]
	if _any(folded, ["bici", "freno", "cadena"]) or _word(folded, "reparar"):
		if _verified(state, "reparar_bicicleta"): return ["Ya reparé mi bicicleta.", "¿Cómo cuido la cadena?"]
		if _any(folded, ["limpia", "aplica", "echa", "comprueba", "revisa primero", "unas gotas"]): return ["¿Cómo sé si quedó bien?", "Gracias, voy a probar."]
		return ["¿Cómo reviso los frenos?" if folded.contains("freno") else "¿Qué le pasa a la bici?", "¿Mateo está en el taller?" if id != "mateo" and folded.contains("mateo") and not known.contains("mateo esta en") else "¿Lleva mucho trabajo arreglarla?"]
	if _any(folded, ["semilla", "plant", "huerto", "sembr", "jardin"]):
		if _verified(state, "plantar_jardin"): return ["Ya sembré mi jardinera.", "¿Cada cuánto debo regarla?"]
		if _any(folded, ["riega", "regar", "agua"]): return ["¿Cómo sé si necesitan más agua?", "¿Cuánto tardan en brotar?"]
		if not _any(folded, ["semilla", "sembr", "tierra"]): return ["¿Qué te gusta más de este lugar?", "¿Sueles venir por aquí?"]
		return ["¿Cuánta agua necesitan?", "¿Cuánto tardan en brotar?"]
	if reply.to_lower().contains("té") or _any(folded, ["receta", "bebida", "preparar te"]):
		if _verified(state, "preparar_te"): return ["Ya preparé té en casa.", "¿Cómo puedo mejorar el sabor?"]
		if _any(folded, ["agua", "hojas", "ingredientes"]): return ["¿Cuánto tiempo lo dejo reposar?", "¿Te gusta tomarlo caliente?"]
		return ["¿Qué té te gusta más?", "¿Me recomiendas alguno?"]
	if _any(folded, ["he vivido", "vivi en", "ha vivido", "vivio en", "ciudades", "mudanza"]): return ["¿Qué lugar recuerdas con más cariño?", "¿Qué te hizo quedarte aquí?"]
	if _any(folded, ["reunion", "comida vecinal", "invitar"]): return ["¿Qué podemos preparar para la comida?", "¿Cómo podemos invitar a los vecinos?"]
	if _any(folded, ["dibuj", "exposicion", "ilustra"]): return ["¿Qué dibujo te gustaría mostrar?", "¿Qué te inspira de este lugar?"]
	if _any(folded, ["fotografia", "cambio", "antes la colonia"]): return ["¿Qué ha cambiado más?", "¿Me enseñas alguna foto?"]
	if _any(folded, ["musica", "cancion", "escuchando", "jazz"]): return ["¿Qué te gusta de esa música?", "¿Me recomiendas una canción?"]
	if _any(folded, ["cansad", "descans", "pausa"]): return ["¿Te acompaño un rato?", "Podemos hablar después."]
	if _any(folded, ["triste", "preocupad", "mal dia"]): return ["¿Te apetece hablar de eso?", "Puedo quedarme un rato."]
	if _any(folded, ["bien", "tranquil", "alegr", "buen dia"]): return ["Me alegra.", "¿Te apetece dar una vuelta?"]
	if _any(folded, ["hasta luego", "nos vemos", "adios"]): return ["Hasta luego.", "Que te vaya bien."]
	return ["Te escucho.", "¿Qué te gustaría hacer después?"]

static func _known_answers(world, id: String, reply: String, exchanges: int) -> String:
	var parts: Array[String] = [_fold(reply)]
	if exchanges <= 0 or not world.has_method("_conversation_turns"): return parts[0]
	var memories: Array = world.get_resident("player").get("memories", [])
	var seen := 0
	for index in range(memories.size() - 1, -1, -1):
		var memory: Dictionary = memories[index]
		if memory.get("kind", "") != "conversacion" or id not in memory.get("participants", []) or "player" not in memory.get("participants", []): continue
		for turn: Dictionary in world._conversation_turns(memory):
			if turn.get("speaker_id", "") == id: parts.append(_fold(str(turn.get("text", ""))))
		seen += 1
		if seen >= mini(8, exchanges): break
	return " ".join(parts)

static func _recent(world, id: String, last_player_text: String, exchanges: int) -> Array[String]:
	var result: Array[String] = []
	if not last_player_text.is_empty(): result.append(_key(last_player_text))
	if exchanges <= 0 or not world.has_method("_conversation_turns"): return result
	var memories: Array = world.get_resident("player").get("memories", [])
	var seen := 0
	for index in range(memories.size() - 1, -1, -1):
		var memory: Dictionary = memories[index]
		if memory.get("kind", "") != "conversacion" or id not in memory.get("participants", []) or "player" not in memory.get("participants", []): continue
		for turn: Dictionary in world._conversation_turns(memory):
			if turn.get("speaker_id", "") == "player": result.append(_key(str(turn.get("text", ""))))
		seen += 1
		if seen >= mini(2, exchanges): break
	return result

static func suggest(world, id: String, last_reply: String, last_player_text: String, session_exchanges: int, scene_override: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if world == null or id == "player" or not world.has_method("get_resident"): return result
	var person: Dictionary = world.get_resident(id)
	if person.is_empty(): return result
	var candidates: Array = []
	if session_exchanges <= 0:
		candidates = ["Hola, %s. ¿Cómo estás?" % str(person.get("name", "")), _opening(world, id, scene_override), "Hola, ¿cómo estás?"]
	else:
		var state: Dictionary = _snapshot(world)
		var question: String = _question(last_reply)
		var known: String = _known_answers(world, id, last_reply, session_exchanges)
		candidates = (_answer(question, state, id, last_reply, known) if not question.is_empty() else _context(last_reply, state, id, known)).duplicate()
		# Follow-ups remain questions or wishes; they cannot invent player history.
		candidates.append_array(SAFE_FOLLOWUPS)
	var recent: Array[String] = _recent(world, id, last_player_text if session_exchanges > 0 else "", session_exchanges)
	var used: Array[String] = []
	for candidate in candidates:
		var text: String = str(candidate)
		var key: String = _key(text)
		if text.is_empty() or text.length() > MAX_CHARS or text.split(" ", false).size() > MAX_WORDS: continue
		if _any(text, ["\n", "\r", "\t", "—", "–"]) or key in recent or key in used: continue
		used.append(key)
		result.append({"label": text, "text": text})
		if result.size() == 2: break
	return result
