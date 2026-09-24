extends RefCounted
const Suggestions = preload("res://scripts/chat_suggestions.gd")
## One voluntary player conversation. Completed exchanges live in Colony memories.
var host: Control
var goals: Dictionary = {}
var errors: Dictionary = {}
var error_details: Dictionary = {}
var retry_text: Dictionary = {}
var _session_id: String = ""
var _messages: Array[Dictionary] = []
var _suggested_replies: Array[Dictionary] = []
var _scene: Dictionary = {}
var approach_id: String = ""
var availability: String = ""
var scroll_positions: Dictionary = {}
var scroll_follow: Dictionary = {}
var session_exchanges: int = 0
var _ended_id: String = ""
var _farewell: Array[Dictionary] = []
const MAX_REPLY_CHARS := 180
const MAX_REPLY_WORDS := 30
const MAX_SESSION_MESSAGES := 40
var whitespace := RegEx.new()
var sentence_end := RegEx.new()

func _init(owner: Control) -> void:
	host = owner
	whitespace.compile("[\\s\\p{Z}]+")
	sentence_end.compile("[.!?](?: |$)")

func compact_reply(text: String) -> String:
	# Format the accumulated voice, never individual transport fragments.
	var result: String = whitespace.sub(text.replace("—", ", ").replace("–", ", "), " ", true).strip_edges().replace(" ,", ",")
	var words: PackedStringArray = result.split(" ", false)
	if result.length() <= MAX_REPLY_CHARS and words.size() <= MAX_REPLY_WORDS: return result
	var prefix: String = " ".join(words.slice(0, MAX_REPLY_WORDS)).left(MAX_REPLY_CHARS - 1)
	# Prefer the last complete sentence; never cut a word in half.
	var endings: Array[RegExMatch] = sentence_end.search_all(prefix)
	if not endings.is_empty(): return prefix.left(endings[-1].get_start() + 1)
	var boundary: int = prefix.rfind(" ")
	if boundary >= 0: prefix = prefix.left(boundary)
	return prefix.strip_edges().trim_suffix(",").trim_suffix(";").trim_suffix(":") + "…"

func nearby(id: String) -> bool:
	var player: Dictionary = host.colony.get_resident("player")
	var person: Dictionary = host.colony.get_resident(id)
	return not person.is_empty() and id != "player" and player.room == person.room and host.position_of(player).distance_to(host.position_of(person)) < 45.0

func busy() -> bool:
	return not host.dialogue_job.is_empty() and host.dialogue_job.a == "player" and not host.dialogue_job.get("autonomous", false)

func start(id: String) -> bool:
	if host.sync_exhaustion(): return false
	if id.is_empty() or id == "player" or not host.colony.is_present(id) or host.colony.get_resident(id).is_empty(): return false
	if host.colony.is_sleeping(id):
		_show_error(id, str(host.colony.get_resident(id).name) + " está durmiendo.")
		return false
	if not host.chat_partner_id.is_empty():
		if host.chat_partner_id == id:
			hold()
			return host.chat_partner_id == id
		_show_error(id, "Termina primero tu otra charla.")
		return false
	if not nearby(id):
		_show_error(id, "Acércate para conversar.")
		return false
	var invitation: Dictionary = host.colony.social_start(id, "player")
	if not invitation.get("allowed", true):
		# Refusal happens before this pair reserves anyone. Clear only prepared
		# manual-chat state; background pairs keep their own transport and holds.
		clear_prepared(id)
		_session_id = ""
		_messages.clear()
		_suggested_replies.clear()
		_scene.clear()
		goals.clear()
		session_exchanges = 0
		_ended_id = id
		_farewell.assign([{"speaker_id": id, "name": str(host.colony.get_resident(id).name), "text": compact_reply(str(invitation.get("reply", "Ahora necesito un rato a solas.")))}])
		host.get_viewport().gui_release_focus()
		host.open_inspector(id, "hablar")
		host.refresh_status()
		return false
	host.encounters.cancel_for(id)
	# Manual dialogue takes precedence over the single background transport.
	host.take_control()
	if not host.dialogue_job.is_empty():
		host.dialogue_request.cancel()
		host.release_conversation(false)
		host.dialogue_job.clear()
	if host.decision_pending and host.deciding_id in ["player", id]:
		host.request.cancel_request()
		host.decision_pending = false
	# Preserve the interrupted action, independently from resumable route goals.
	_scene = host.colony.conversation_scene_for(id).duplicate(true)
	_scene.paused_for_chat = true
	host.chat_partner_id = id
	_session_id = id
	_ended_id = ""
	_farewell.clear()
	_messages.clear()
	_suggested_replies.clear()
	errors.erase(id)
	error_details.erase(id)
	retry_text.erase(id)
	scroll_positions.erase(id)
	scroll_follow[id] = true
	session_exchanges = 0
	host.riding_bicycle = false
	host.hud.sync_actions()
	host.selected_id = id
	host.page = "hablar"
	goals.clear()
	hold()
	return true

func hold() -> void:
	if host.chat_partner_id.is_empty(): return
	if not nearby(host.chat_partner_id):
		finish("La charla terminó porque se alejaron.")
		return
	for id in ["player", host.chat_partner_id]:
		# A manual session lasts between replies too. Keep its own two reservations
		# without replacing those held by an independent pair of neighbors.
		if id not in host.colony.conversation_holds: host.colony.conversation_holds.append(id)
		var person: Dictionary = host.colony.get_resident(id)
		if not goals.has(id) or person.target != person.pos or not str(person.get("travel_intent", "")).is_empty():
			goals[id] = {"target": person.target.duplicate(), "room": person.room, "intent": person.get("travel_intent", ""), "activity": person.activity}
		person.target = person.pos.duplicate()
		person.travel_intent = ""
		person.activity = "Conversando con " + str(host.colony.get_resident(host.chat_partner_id if id == "player" else "player").name)
		host.paths.erase(id)
	var direction: Vector2 = host.position_of(host.colony.get_resident(host.chat_partner_id)) - host.position_of(host.colony.get_resident("player"))
	if not direction.is_zero_approx():
		host.facing.player = direction
		host.facing[host.chat_partner_id] = -direction

func clear_prepared(id: String) -> void:
	if id.is_empty(): return
	if _ended_id == id:
		_ended_id = ""
		_farewell.clear()
	# Clear widgets before the next inspector rebuild captures their values.
	if host.inspector_page == "hablar" and host.inspector_resident == id:
		if is_instance_valid(host.chat_input): host.chat_input.text = ""
		if is_instance_valid(host.chat_scroll): host.chat_scroll.scroll_vertical = 0
	host.chat_drafts.erase(id)
	scroll_positions.erase(id)
	scroll_follow.erase(id)
	errors.erase(id)
	error_details.erase(id)
	retry_text.erase(id)
	if approach_id == id:
		approach_id = ""
		if host.pending_mentor == id: host.clear_player_intentions()

func finish(notice: String = "", respectful: bool = true) -> void:
	approach_id = ""
	if host.chat_partner_id.is_empty(): return
	var id: String = host.chat_partner_id
	host.colony.social_finish(id, "player", respectful)
	if busy():
		host.dialogue_request.cancel()
		host.dialogue_job.clear()
		host.dialogue_serial += 1
	# Clear the old widgets first: inspector rebuilding captures their current values.
	if host.inspector_page == "hablar" and host.inspector_resident == id:
		if is_instance_valid(host.chat_input): host.chat_input.text = ""
		if is_instance_valid(host.chat_scroll): host.chat_scroll.scroll_vertical = 0
	host.chat_drafts.erase(id)
	_messages.clear()
	_suggested_replies.clear()
	_session_id = ""
	_scene.clear()
	session_exchanges = 0
	errors.erase(id)
	error_details.erase(id)
	retry_text.erase(id)
	scroll_positions.erase(id)
	scroll_follow.erase(id)
	for participant in goals:
		var person: Dictionary = host.colony.get_resident(participant)
		var goal: Dictionary = goals[participant]
		if participant != "player" and person.room == goal.room and person.target == person.pos:
			person.target = goal.target.duplicate()
			person.travel_intent = goal.intent
			person.activity = goal.activity
		elif participant == "player": person.activity = "Bajo tu control"
		host.paths.erase(participant)
	goals.clear()
	host.colony.conversation_holds.erase("player")
	host.colony.conversation_holds.erase(id)
	host.chat_partner_id = ""
	if host.page == "hablar": host.build_inspector()
	# Do not retain the empty editor/scroll entries that the rebuild may have captured.
	host.chat_drafts.erase(id)
	scroll_positions.erase(id)
	scroll_follow.erase(id)
	if not notice.is_empty(): host.message(notice)

func ended(id: String) -> bool:
	return id == _ended_id and not _farewell.is_empty()

func _departure(text: String) -> bool:
	var folded: String = _fold(text)
	return _mentions(folded, ["me tengo que ir", "tengo que irme", "debo irme", "necesito seguir", "necesito espacio", "quiero estar a solas", "prefiero estar solo", "prefiero estar sola", "no quiero seguir hablando", "no quiero seguir conversando", "prefiero dejar la charla", "dejame en paz", "hasta luego", "nos vemos", "luego hablamos", "ahora voy a", "ahora me voy"])

func _end_from_neighbor(id: String, reply: String, respectful: bool) -> void:
	finish("", respectful)
	_ended_id = id
	_farewell.assign([{"speaker_id": id, "name": str(host.colony.get_resident(id).name), "text": reply}])
	host.encounters.let_leave(id, "player")
	host.get_viewport().gui_release_focus()
	host.build_inspector()
	host.refresh_status()

func send(text: String) -> void:
	var spoken: String = text.strip_edges()
	if spoken.is_empty(): return
	if spoken.length() > 1000:
		_show_error(host.selected_id, "Escribe hasta 1.000 caracteres.")
		return
	if busy():
		_show_error(host.selected_id, "Espera su respuesta para enviar.")
		return
	var id: String = host.selected_id
	if not start(id): return
	if not nearby(id): return
	var social: Dictionary = host.colony.social_turn(id, "player", spoken, session_exchanges)
	var social_reply: String = ""
	if str(social.get("reply","")).is_empty(): social_reply = host.colony.social_dialogue.reply(id,"player",spoken)
	if not host.dialogue_job.is_empty():
		host.dialogue_request.cancel()
		host.release_conversation(false)
		host.dialogue_job.clear()
	errors.erase(id)
	error_details.erase(id)
	retry_text.erase(id)
	if is_instance_valid(host.chat_input) and host.inspector_resident == id and host.chat_input.text.strip_edges() == spoken:
		host.chat_input.text = ""
		host.chat_drafts[id] = ""
	host.dialogue_serial += 1
	host.stream_text = ""
	host.dialogue_job = {"a": "player", "b": id, "first": spoken, "phase": "reply", "manual_session": true, "serial": host.dialogue_serial, "social_end": bool(social.get("end", false)), "social_reason": str(social.get("reason", ""))}
	if not str(social.get("reply", "")).is_empty():
		host.call_deferred("complete_local_chat", host.dialogue_serial, str(social.reply))
	elif not social_reply.is_empty() and (host.service_token.is_empty() or host.colony.social_dialogue.requires_local_reply(id,"player",spoken)):
		# Deterministic evidence and privacy reactions remain consistent offline and online.
		host.call_deferred("complete_local_chat", host.dialogue_serial, social_reply)
	elif host.service_token.is_empty():
		host.call_deferred("complete_local_chat", host.dialogue_serial, local_reply(id, spoken))
	else:
		host.request_dialogue(id, "player", spoken)
	host.build_inspector()
	scroll_follow[id] = true
	host.restore_chat_scroll.call_deferred(id, 0, true)

func completed(job: Dictionary, text: String, source: String, suggested_replies: Array = []) -> void:
	var id: String = str(job.b)
	if id != _session_id or id != host.chat_partner_id or (job.has("serial") and job.serial != host.dialogue_serial): return
	var reply: String = compact_reply(text)
	if host.colony.record_dialogue("player", id, str(job.first), reply, source):
		if not host.colony.events.is_empty(): host.seen_world_events[host.colony.events.back()] = true
		_messages.append({"speaker_id": "player", "name": str(host.colony.get_resident("player").name), "text": str(job.first)})
		_messages.append({"speaker_id": id, "name": str(host.colony.get_resident(id).name), "text": reply})
		if _messages.size() > MAX_SESSION_MESSAGES: _messages.assign(_messages.slice(_messages.size() - MAX_SESSION_MESSAGES))
		_suggested_replies = _validated_suggestions(suggested_replies)
		session_exchanges += 1
		errors.erase(id)
		error_details.erase(id)
		retry_text.erase(id)
		host.dialogue_text = transcript(id)
		if job.get("social_end", false) or _departure(reply) or _departure(str(job.first)):
			var respectful: bool = job.get("social_reason", "") == "farewell" or not job.get("social_end", false) and _departure(str(job.first))
			_end_from_neighbor(id, reply, respectful)
			return
		hold()
	else:
		finish("")
		errors[id] = "La conversación terminó porque se alejaron."
	if host.page == "hablar": host.build_inspector()

func failed(job: Dictionary, reason: String) -> void:
	var id: String = str(job.b)
	if id != _session_id or id != host.chat_partner_id or (job.has("serial") and job.serial != host.dialogue_serial): return
	errors[id] = _failure_notice(str(host.dialogue_request.failure_code))
	error_details[id] = reason.left(240)
	retry_text[id] = str(job.first)
	if str(host.chat_drafts.get(id, "")).is_empty():
		host.chat_drafts[id] = str(job.first)
		if host.inspector_page == "hablar" and host.inspector_resident == id and is_instance_valid(host.chat_input): host.chat_input.text = str(job.first)
	if host.page == "hablar": host.build_inspector()

func _failure_notice(code: String) -> String:
	# Only curated messages reach the game UI; provider details stay diagnostic.
	match code:
		"connection_failed", "upstream_unavailable":
			return "Se perdió la conexión. Comprueba el servicio y reintenta."
		"request_timeout", "upstream_timeout", "http_408", "http_504":
			return "La respuesta tardó demasiado. Puedes reintentar."
		"upstream_busy", "http_429", "http_503":
			return "El servicio está ocupado. Espera un momento y reintenta."
		"upstream_incomplete", "stream_interrupted", "invalid_upstream_response", "invalid_stream":
			return "La respuesta se interrumpió. Puedes reintentar."
		"unauthorized", "upstream_auth", "http_401", "http_403":
			return "No se pudo acceder al servicio. Revisa la conexión del juego."
		_:
			return "No llegó la respuesta. Puedes reintentar."

func _show_error(id: String, text: String) -> void:
	errors[id] = text
	if host.page == "hablar": host.build_inspector()

func messages(id: String) -> Array[Dictionary]:
	if ended(id): return _farewell.duplicate(true)
	if id != _session_id or id != host.chat_partner_id: return []
	var result: Array[Dictionary] = _messages.duplicate(true)
	if busy() and host.dialogue_job.b == id:
		result.append({"speaker_id": "player", "name": str(host.colony.get_resident("player").name), "text": str(host.dialogue_job.first)})
		result.append({"speaker_id": id, "name": str(host.colony.get_resident(id).name), "text": compact_reply(host.stream_text) if not host.stream_text.is_empty() else "…", "pending": true})
	return result

func history(id: String) -> String:
	if id != _session_id or id != host.chat_partner_id: return ""
	var lines: Array[String] = []
	for turn in _messages: lines.append(str(turn.name) + ": " + str(turn.text))
	return "\n".join(lines)

func transcript(id: String) -> String:
	var lines: Array[String] = []
	for turn in messages(id): lines.append(str(turn.name) + ": " + str(turn.text))
	return "\n".join(lines)

func last_reply(id: String) -> String:
	if id != _session_id or id != host.chat_partner_id: return ""
	for index in range(_messages.size() - 1, -1, -1):
		if _messages[index].speaker_id == id: return str(_messages[index].text)
	return ""

func last_player_text(id: String) -> String:
	if id != _session_id or id != host.chat_partner_id: return ""
	for index in range(_messages.size() - 1, -1, -1):
		if _messages[index].speaker_id == "player": return str(_messages[index].text)
	return ""

func scene_for(id: String) -> Dictionary:
	if id != _session_id or id != host.chat_partner_id: return {}
	var result: Dictionary = _scene.duplicate(true)
	var current: Dictionary = host.colony.conversation_scene_for(id)
	result.next_plan = str(current.get("next_plan", ""))
	result.routine = str(current.get("routine", ""))
	return result

func _validated_suggestions(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Array[String] = []
	for value in values.slice(0, 2):
		if not value is String: continue
		var text: String = value.strip_edges()
		if text.is_empty() or text.length() > 45 or text.split(" ", false).size() > 8: continue
		var valid := true
		for index in range(text.length()):
			if text.unicode_at(index) < 32 or text.unicode_at(index) == 127: valid = false
		for marker in ["*", "_", "`", "#", "[", "]", "\\"]:
			if text.contains(marker): valid = false
		if not valid or text.to_lower() in seen: continue
		seen.append(text.to_lower())
		result.append({"label": text, "text": text})
	return result

func suggestion(label: String, text: String) -> Dictionary:
	return {"label": label, "text": text}

func suggestions(id: String) -> Array[Dictionary]:
	var person: Dictionary = host.colony.get_resident(id)
	if person.is_empty() or id == "player": return []
	if ended(id): return []
	if retry_text.has(id): return [{"label": "Reintentar envío", "text": str(retry_text[id]), "action": "retry"}]
	var social_options: Array[Dictionary] = host.colony.social_dialogue.suggestions(id,"player",last_reply(id))
	if not social_options.is_empty(): return social_options
	if _mentions(_fold(last_reply(id)), ["prefiero no", "prefiero conocerte mejor", "prefiero dejar ese tema", "prefiero hablar de otra", "no me siento comodo", "no me siento comoda", "todavia no", "con mas confianza"]):
		return [suggestion("Lo entiendo, cambiemos de tema.", "Lo entiendo, cambiemos de tema."), suggestion("Te dejo seguir. Hasta luego.", "Te dejo seguir. Hasta luego.")]
	var result: Array[Dictionary] = []
	if id == _session_id and host.chat_partner_id == id: result = _suggested_replies.duplicate(true)
	var count: int = session_exchanges if id == _session_id and host.chat_partner_id == id else 0
	for option in Suggestions.suggest(host.colony, id, last_reply(id), last_player_text(id), count, scene_for(id)):
		if result.size() == 2: break
		if result.any(func(value): return str(value.text).to_lower() == str(option.text).to_lower()): continue
		result.append(option.duplicate(true))
	return result

func _fold(text: String) -> String:
	var result: String = whitespace.sub(text.to_lower().replace("á", "a").replace("é", "e").replace("í", "i").replace("ó", "o").replace("ú", "u").replace("ü", "u").replace("ñ", "n"), " ", true)
	for mark in ["¿", "?", "¡", "!", ".", ",", ";", ":"]: result = result.replace(mark, "")
	return result.strip_edges()

func _mentions(text: String, phrases: Array) -> bool:
	for phrase in phrases:
		if text.contains(str(phrase)): return true
	return false

func _last_question(text: String) -> String:
	var end: int = text.rfind("?")
	if end < 0: return ""
	var start: int = text.left(end).rfind("¿")
	return _fold(text.substr(start + 1, end - start - 1)) if start >= 0 else ""

func _activity_reply(id: String) -> String:
	var scene: Dictionary = scene_for(id)
	if scene.is_empty(): scene = host.colony.conversation_scene_for(id)
	var label: String = str(scene.get("activity_before_chat", "")).strip_edges().trim_suffix(".")
	var phase: String = str(scene.get("phase", "idle"))
	var action: String = str(scene.get("ongoing_action", ""))
	var place: String = str(scene.get("place", "calle"))
	if phase == "walking":
		var destination: String = str(scene.get("intent", ""))
		var names: Dictionary = {"casa": "casa", "descansar": "casa", "taller": "el taller", "cafe": "el café", "huerto": "el huerto", "plaza": "la plaza"}
		if names.has(destination): return "Iba hacia " + str(names[destination]) + ". Hice una pausa para saludarte."
		if _fold(label).begins_with("caminando a "): return "Iba " + label.substr(10).to_lower() + ". Hice una pausa para saludarte."
		return "Estaba caminando por aquí. Hice una pausa para saludarte."
	if place == "casa" and phase in ["idle", "leisure", "resting"] and (action in ["rest", "take_break", "routine", ""] or _mentions(_fold(label), ["descans", "dormir"])):
		return "Estaba descansando en casa. Me viene bien este rato tranquilo."
	if label.is_empty() or _mentions(_fold(label), ["conversando", "hablando contigo"]):
		return "Estaba haciendo una pausa aquí."
	var folded: String = _fold(label)
	if folded.begins_with("preparandose para dormir"): return "Me estaba preparando para descansar en casa."
	if phase in ["working", "eating", "leisure"] or _mentions(folded, ["ando ", "iendo "]):
		return compact_reply("Estaba " + label.left(1).to_lower() + label.substr(1).replace(" su libreta", " mi libreta").replace(" sus detalles", " los detalles") + ".")
	return "Estaba haciendo una pausa " + ("en casa." if place == "casa" else "por aquí.")

func _biography_reply(id: String) -> String:
	var text: String = str(host.colony.visible_profile_for(id, "player").get("biography", "Prefiero contártelo cuando nos conozcamos mejor."))
	for pair in [["Es vecino", "Soy vecino"], ["Es un nuevo", "Soy un nuevo"], ["Organiza", "Organizo"], ["Trabaja", "Trabajo"], ["Atiende", "Atiendo"], ["Dibuja y fotografía", "Dibujo y fotografío"], ["y cuida", "y cuido"], ["y repara", "y reparo"], ["y prepara", "y preparo"], ["sus visitantes", "quienes me visitan"], ["suele cuidar", "suelo cuidar"], ["Practica cómo", "Practico cómo"], ["Disfruta", "Disfruto"], [" sus vecinos", " mis vecinos"], [" sus momentos", " mis momentos"], ["y dibuja", "y dibujo"], ["quiere conservar", "quiero conservar"]]:
		text = text.replace(pair[0], pair[1])
	for pair in [["Creció", "Crecí"], ["Siempre ha vivido", "Siempre he vivido"], ["Vivió", "Viví"], ["Aprendió", "Aprendí"], [" aprendió", " aprendí"], ["Acaba de mudarse", "Acabo de mudarme"], ["Está practicando", "Estoy practicando"], ["Le gusta", "Me gusta"], ["Guarda", "Guardo"], [" su papá", " mi papá"], [" su mamá", " mi mamá"], [" sus abuelos", " mis abuelos"], [" su trabajo", " mi trabajo"]]:
		text = text.replace(pair[0], pair[1])
	return compact_reply(text)

func _next_plan_reply(id: String) -> String:
	var scene: Dictionary = scene_for(id)
	if scene.is_empty(): scene = host.colony.conversation_scene_for(id)
	var plan: String = str(scene.get("next_plan", ""))
	for pair in [["(la plaza)", "ir a la plaza"], ["(el café)", "ir al café"], ["(el taller)", "ir al taller"], ["(el huerto)", "ir al huerto"], ["(casa)", "volver a casa"]]:
		if plan.ends_with(pair[0]): return "Después pensaba " + str(pair[1]) + "."
	return "Todavía no tengo decidido qué hacer después."

func _followup_reply(id: String, previous: String) -> String:
	var topic: String = _fold(previous)
	if topic.contains("ordenando herramientas"): return "Así puedo encontrar cada herramienta cuando la necesito."
	if topic.contains("descansando"): return "Me venía bien un rato de calma."
	if topic.contains("dibujando"): return "Estaba fijándome en los detalles de lo que tenía delante."
	if topic.contains("aceite") and topic.contains("tienda"): return "El aceite se usa para lubricar la cadena después de limpiarla."
	if _mentions(topic, ["reparacion", "frenos", "ruedas"]): return "Conviene revisar los frenos y las ruedas antes de montar."
	if topic.contains("tierra") or topic.contains("plantas"): return "Observar la tierra ayuda a decidir cuándo hace falta regar."
	if topic.contains("bebida") or topic.contains("tazas"): return "Me gusta dedicarle un momento tranquilo."
	if _mentions(topic, ["creci", "mis abuelos", "mi papa", "mi infancia"]): return _biography_reply(id)
	return "¿Qué parte te gustaría que te contara?"

func local_reply(id: String, text: String) -> String:
	# Local, predetermined speech. Its memory origin remains explicit.
	return compact_reply(_local_reply(id, text))

func _local_reply(id: String, text: String) -> String:
	var person: Dictionary = host.colony.get_resident(id)
	if person.is_empty(): return "No te escuché bien."
	var social_reply: String = host.colony.social_dialogue.reply(id,"player",text)
	if not social_reply.is_empty(): return social_reply
	var folded: String = _fold(text)
	var previous: String = last_reply(id)
	var question: String = _last_question(previous)
	var previous_player: String = _fold(last_player_text(id))
	if _mentions(folded, ["hasta luego", "nos vemos", "me despido", "me tengo que ir"]) or folded in ["adios", "chau", "chao"]:
		return "Nos vemos. Me dio gusto conversar contigo."
	if _mentions(folded, ["no muy bien", "me siento mal", "estoy triste", "estoy cansado", "estoy cansada"]):
		return "Siento que el día esté pesado. Podemos quedarnos un momento aquí."
	if folded in ["y tu", "y a ti", "y tu que", "tu tambien"]:
		if _mentions(question + " " + previous_player, ["como estas", "como va", "como te sientes"]) or question == "y tu" and _mentions(_fold(previous), ["bien", "gracias"]):
			return "Yo estoy bien, gracias por preguntar. Me alegra tener un rato para conversar."
		if _mentions(question, ["creciste", "de donde eres", "infancia"]): return _biography_reply(id)
		return _activity_reply(id)
	if folded in ["bien", "bien gracias", "muy bien", "todo bien", "con ganas de explorar"]:
		return "Me alegra. Qué bueno encontrarnos un rato."
	if folded in ["si", "claro", "me parece bien", "si me gustaria", "si gracias"]:
		if _mentions(question, ["acompan", "quedamos", "convers", "rato"]): return "Claro, quédate un rato. Me gusta tener compañía."
		if _mentions(question, ["explic", "ensen", "primer paso"]): return "Dime qué parte quieres revisar y la vemos con calma."
		return "De acuerdo."
	if folded in ["no", "ahora no", "prefiero despues", "prefiero dejarlo para despues", "prefiero contartelo despues", "ahora prefiero conversar"]:
		return "Claro, no hay prisa. Podemos simplemente conversar."
	if folded in ["gracias", "muchas gracias", "entiendo", "ya veo", "que bien"]:
		return "De nada." if folded.contains("gracias") else "Sí."
	if folded == "lo entiendo cambiemos de tema": return "Gracias por entender. Podemos hablar de la colonia."
	if _mentions(folded, ["y despues", "y luego", "que planes tienes", "que haras despues", "que piensas hacer despues", "que vas a hacer despues", "tus planes"]): return _next_plan_reply(id)
	if folded in ["y eso", "por que", "como asi", "cuentame mas", "que quieres decir"] and not previous.is_empty(): return _followup_reply(id, previous)
	if _mentions(folded, ["como las organizas", "como organizas las herramientas"]):
		return "Separarlas por tipo ayuda a encontrar cada herramienta: llaves por un lado y piezas pequeñas por otro."
	if folded.contains("te falta mucho por ordenar"):
		return "Estaba ordenando las herramientas cuando llegaste." if str(scene_for(id).get("ongoing_action", "")) == "sort_tools" else _activity_reply(id)
	if _mentions(folded, ["que hacias", "que estabas haciendo", "que estas haciendo", "en que andas", "en que andabas", "que andas haciendo", "que estas reparando", "que estas trabajando", "como va esa reparacion", "ordenando las herramientas", "ya casi terminas de ordenar", "hacia donde vas", "adonde vas", "que estas tomando", "como van las plantas", "como esta la tierra", "me ensenas tu dibujo", "como va la reunion"]):
		return _activity_reply(id)
	if folded.contains("esta tranquilo el cafe"):
		return "Estaba atendiendo el café. Hice una pausa para saludarte." if str(scene_for(id).get("ongoing_action", "")) == "serve" else _activity_reply(id)
	if folded.contains("te acompano"):
		return "Claro, quédate un rato. Me viene bien la compañía."
	if folded.begins_with("hola") or _mentions(folded, ["como estas", "que tal va todo", "como va tu dia"]):
		return "Hola. Me alegra verte. ¿Cómo estás?" if previous.is_empty() and not folded.contains("como estas") else "Bien, gracias. ¿Y tú?"
	if folded.contains("aceite"):
		if _mentions(folded, ["no tengo", "aun no", "todavia no"]): return "Puedes conseguirlo en la tienda. Cuando quieras, revisamos para qué se usa."
		if _mentions(folded, ["ya tengo", "ya compre", "ya consegui"]): return "Puedes dármelo aquí y te explico los pasos." if id == "mateo" else "Dáselo a Mateo cuando lo encuentres."
		if _mentions(folded, ["aplic", "cuanto", "limpiar"]): return "Primero limpia la cadena; después aplica el aceite según los pasos de la reparación."
		return "El aceite se consigue en la tienda." if id == "mateo" else "Puedes buscar aceite en la tienda y preguntarle a Mateo por la reparación."
	if _mentions(folded, ["oficio", "infancia", "quien te enseno", "historia", "creciste", "abuelos", "tu papa", "tu mama", "de donde eres"]):
		return _biography_reply(id)
	if _mentions(folded, ["primer paso", "que reviso primero", "receta", "bicicleta", "semilla", "frenos", "cadena"]):
		var practical: Dictionary = {"mateo": "Primero se revisan los frenos y las ruedas. Después podemos hablar de la cadena y su lubricación.", "alma": "Primero prepara la tierra. Después coloca la semilla y riégala con cuidado.", "ines": "Primero llena la tetera y calienta el agua; luego añade el té y sirve."}
		return str(practical.get(id, "Podemos preguntarle a quien conoce ese oficio. Prefiero no inventarte los pasos."))
	if _mentions(folded, ["aprender", "me ensenas", "ensenarme"]):
		var lessons: Dictionary = {"mateo": "Puedo explicarte cómo revisar una bicicleta. ¿Qué parte te interesa?", "alma": "Podemos hablar de cómo cuidar una jardinera. ¿Qué quieres probar?", "ines": "Puedo explicarte cómo preparo el té. ¿Por dónde quieres empezar?"}
		return str(lessons.get(id, "Podemos compartir lo que sabemos. ¿Qué te interesa?"))
	if _mentions(folded, ["que te gustaria", "que te gusta"]): return str(person.goal)
	if _mentions(folded, ["me gustaria", "me gusta", "prefiero"]): return "Entiendo. Me gusta ir conociendo lo que te interesa."
	return "No estoy seguro de haberte entendido. ¿Puedes decirlo de otra manera?"

func status(id: String) -> String:
	if id == "player": return "Elige a un vecino"
	if not host.chat_partner_id.is_empty() and host.chat_partner_id != id: return "Tienes otra charla abierta"
	if busy() and host.dialogue_job.b == id: return "Está respondiendo…"
	if host.chat_partner_id == id: return "Tu turno · puedes responder"
	return "Puedes saludar" if nearby(id) else "Acércate para conversar"

func update_availability() -> void:
	if host.page != "hablar": return
	var signature: String = "%s:%s:%s:%s" % [host.selected_id, nearby(host.selected_id), host.chat_partner_id, busy()]
	if signature != availability:
		availability = signature
		host.build_inspector()
