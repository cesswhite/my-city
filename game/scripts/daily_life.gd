extends RefCounted
## Small physical activities between schedule changes. Runtime state only; no experience spam.
const Navigation = preload("res://scripts/navigation.gd")
const Layout = preload("res://scripts/world_layout.gd")
const SharedDestinations = preload("res://scripts/shared_destinations.gd")
const PRIORITY_MINUTES := 45
const SOCIAL_COOLDOWN := 60
const SPEAKING_MINUTES := 5
var _world: WeakRef
var _states: Dictionary = {}
var _speaking: Dictionary = {}

func setup(world) -> void:
	_world = weakref(world)
	_states.clear()
	_speaking.clear()

func forget(id: String) -> void:
	_states.erase(id)
	_speaking.erase(id)

func _key(id: String) -> String:
	return str(_world.get_ref()._routine_keys.get(id, ""))

func _point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

func _at_target(resident: Dictionary) -> bool:
	return _point(resident.pos).distance_to(_point(resident.target)) <= 2.0

func _public(kind: String, action: String, label: String, until: int = 0, source: String = "routine") -> Dictionary:
	var busy: bool = kind in ["working", "eating", "speaking", "sleeping"]
	return {"action": action, "kind": kind, "label": label, "until": until, "source": source,
		"busy": busy, "interruptible": kind not in ["speaking", "sleeping"], "social_ready": kind in ["idle", "leisure"]}

func state_for(id: String) -> Dictionary:
	var world = _world.get_ref()
	var resident: Dictionary = world.get_resident(id)
	if resident.is_empty() or not world.is_present(id): return {}
	if world.is_sleeping(id):
		if id == "player" and world.is_exhausted(): return _public("sleeping", "exhaustion", "Durmiendo por agotamiento", 0, "exhaustion")
		return _public("sleeping", "sleep", "Durmiendo", int(resident.sleep.until), "rest")
	if id in world.conversation_holds or _speaking.get(id, {}).get("until", 0) > world.minute:
		return _public("speaking", "conversation", str(_speaking.get(id, {}).get("label", "Conversando")), int(_speaking.get(id, {}).get("until", 0)), "conversation")
	if world.settlement_jobs.busy(id): return world.settlement_jobs.daily_state(id)
	if id == "player" and not world.player_autonomy: return _public("manual", "manual", "Bajo tu control", 0, "player")
	var state: Dictionary = _states.get(id, {})
	if state.is_empty():
		return _public("idle" if _at_target(resident) else "walking", "routine", str(resident.get("routine", "Comenzando el día")))
	if state.phase != "active":
		return _public("walking", "walk", "Caminando a " + _place_name(str(state.place)), 0, state.source)
	var task: Dictionary = state.task
	var result: Dictionary = _public(str(task.kind), str(task.action), str(task.label), int(state.until), str(state.source))
	result["duration"] = int(task.duration)
	result["started"] = int(state.until) - int(task.duration)
	return result

func social_available(id: String) -> bool:
	var world = _world.get_ref()
	var resident: Dictionary = world.get_resident(id)
	if resident.is_empty() or (id == "player" and not world.player_autonomy) or not _at_target(resident) or resident.has("travel_route"): return false
	if world.minute - int(world._local_chat_times.get(id, -SOCIAL_COOLDOWN)) < SOCIAL_COOLDOWN: return false
	return bool(state_for(id).get("social_ready", false)) and resident.get("routine_place", "") not in ["casa", "descansar"]

func decision_ready(id: String) -> bool:
	var world = _world.get_ref()
	if not world.is_present(id) or world.settlement_jobs.busy(id): return false
	var state: Dictionary = _states.get(id, {})
	if state.is_empty(): return true
	if int(state.get("priority_until", 0)) > world.minute: return false
	return not bool(state_for(id).get("busy", false))

func prioritize(id: String, action: String) -> void:
	var world = _world.get_ref()
	if not world.is_present(id) or world.settlement_jobs.busy(id): return
	if action not in world.PLACES and action != "descansar": return
	var resident: Dictionary = world.get_resident(id)
	_states[id] = _new_state(resident, action)
	_states[id].source = "decision"
	_states[id].priority_until = world.minute + PRIORITY_MINUTES
	_speaking.erase(id)

func note_dialogue(a_id: String, b_id: String, freeze: bool = false) -> void:
	var world = _world.get_ref()
	for pair in [[a_id, b_id], [b_id, a_id]]:
		var id: String = pair[0]
		var resident: Dictionary = world.get_resident(id)
		var speech: Dictionary = _speaking.get(id, {})
		var extension: int = maxi(0, world.minute + SPEAKING_MINUTES - int(speech.get("until", world.minute)))
		if freeze and speech.is_empty() and id not in world.conversation_holds:
			speech["goal"] = {"target": resident.target.duplicate(), "room": resident.room, "intent": resident.get("travel_intent", ""), "key": _key(id)}
			resident.target = resident.pos.duplicate()
			resident.travel_intent = ""
		speech["until"] = world.minute + SPEAKING_MINUTES
		speech["label"] = "Conversando con " + str(world.get_resident(pair[1]).name)
		_speaking[id] = speech
		if _states.has(id) and int(_states[id].until) > 0: _states[id].until += extension
		world._local_chat_times[id] = world.minute
		resident.activity = speech.label

func local_line(id: String, partner_id: String, reply: bool = false) -> String:
	var world = _world.get_ref()
	var resident: Dictionary = world.get_resident(id)
	var state: Dictionary = state_for(id)
	var count: int = int(world._memory_index.get(id, {}).get("completed_by_partner", {}).get(partner_id, 0))
	var lines: Array = []
	if state.kind == "working":
		lines = [str(state.label) + ". En un momento puedo hacer una pausa.", "Me entretiene esta tarea. ¿Qué estás haciendo tú?"]
	elif state.kind == "walking":
		lines = [str(state.label) + ". Podemos hablar un momento aquí.", "Voy a seguir mi recorrido después de esta charla."]
	elif resident.room == Layout.place_area("huerto") and _point(resident.pos).distance_to(_point(world.PLACES.huerto)) < 45:
		lines = ["Me gusta mirar las plantas desde este sendero. ¿A ti también?", "Este rincón me da ideas para lo que quiero aprender."]
	elif resident.room == Layout.place_area("cafe") and _point(resident.pos).distance_to(_point(world.PLACES.cafe)) < 45:
		lines = ["Me gusta hacer una pausa en el café. ¿Cómo va tu día?", "Aquí siempre encuentro un momento para escuchar a mis vecinos."]
	else:
		var by_role: Dictionary = {
			"cesar": ["Me gusta mirar cómo cambian las plantas cada día.", "Las plantas necesitan tiempo y un poco de atención."],
			"lupita": ["Estoy pensando en una comida vecinal. ¿Qué te gustaría llevar?", "Me gusta que cada vecino encuentre su lugar aquí."],
			"mateo": ["Me gusta cuidar las herramientas para que duren.", "En el taller siempre hay algo que revisar."],
			"ines": ["Disfruto escuchar a los vecinos en el café.", "Podemos compartir una receta cuando estemos en el café."],
			"alma": ["Me gusta dibujar estos rincones.", "Hay muchos detalles bonitos por la colonia."],
			"player": ["Todavía estoy conociendo la colonia. ¿Qué lugar te gusta?", "Me gustaría aprender algo que luego pueda compartir."]}
		lines = by_role.get(id, ["Me alegra encontrar un momento para conversar."])
	return str(lines[(count + (1 if reply else 0)) % lines.size()])

func tick() -> void:
	var world = _world.get_ref()
	for resident: Dictionary in world.residents:
		var id: String = resident.id
		if not world.is_present(id):
			forget(id)
			continue
		if world.is_sleeping(id):
			resident.activity = "Durmiendo por agotamiento" if id == "player" and world.is_exhausted() else "Durmiendo"
			continue
		_expire_speech(resident)
		if world.settlement_jobs.busy(id):
			resident.activity = str(state_for(id).get("label", "Trabajo del barrio"))
			continue
		if id == "player" and not world.player_autonomy:
			_states.erase(id)
			continue
		var place: String = resident.get("routine_place", "")
		if place.is_empty(): continue
		var state: Dictionary = _states.get(id, {})
		if state.is_empty() or state.key != _key(id):
			state = _new_state(resident, place)
			_states[id] = state
		elif int(state.get("priority_until", 0)) > 0 and world.minute >= int(state.priority_until):
			world._set_destination(resident, place)
			state = _new_state(resident, place)
			_states[id] = state
		if id in world.conversation_holds:
			if int(state.until) > 0: state.until += 5
			if int(state.priority_until) > 0: state.priority_until += 5
			continue
		if _speaking.get(id, {}).get("until", 0) > world.minute: continue
		if state.place in ["casa", "descansar"]:
			_rest(resident, state)
			continue
		if resident.room != Layout.place_area(str(state.place)) or not _at_target(resident) or resident.has("travel_route"):
			resident.activity = "Caminando a " + _place_name(str(state.place))
			continue
		if state.phase == "task_travel":
			state.phase = "active"
			state.until = world.minute + int(state.task.duration)
		elif state.phase == "arriving" or world.minute >= int(state.until):
			_next_task(resident, state)
		resident.activity = str(state_for(id).label)

func _expire_speech(resident: Dictionary) -> void:
	var world = _world.get_ref()
	var id: String = resident.id
	var speech: Dictionary = _speaking.get(id, {})
	if speech.is_empty() or int(speech.until) > world.minute or id in world.conversation_holds: return
	var goal: Dictionary = speech.get("goal", {})
	if not goal.is_empty() and goal.key == _key(id) and resident.room == goal.room and _at_target(resident) and str(resident.get("travel_intent", "")).is_empty():
		resident.target = goal.target.duplicate()
		resident.travel_intent = goal.intent
	_speaking.erase(id)
	resident.activity = str(resident.get("routine", "Bajo tu control"))

func _new_state(resident: Dictionary, place: String) -> Dictionary:
	return {"key": _key(resident.id), "place": place, "source": "routine", "priority_until": 0,
		"phase": "arriving", "sequence": -1, "task": {}, "until": 0}

func _rest(resident: Dictionary, state: Dictionary) -> void:
	var world = _world.get_ref()
	if resident.room != resident.home_id:
		resident.activity = "Volviendo a casa"
		return
	var bed: Vector2 = Layout.stand_at("bed", resident.id)
	if _point(resident.pos).distance_to(bed) > 2.0 or not _at_target(resident):
		resident.target = [bed.x, bed.y]
		resident.travel_intent = "casa"
		resident.activity = "Preparándose para dormir"
		return
	var duration: int = 30 if state.place == "descansar" else _night_remaining(resident)
	if world.start_sleep(resident.id, duration):
		if state.place == "descansar": state.priority_until = world.minute + duration
		resident.activity = "Durmiendo"

func _night_remaining(resident: Dictionary) -> int:
	var world = _world.get_ref()
	# Find the first future non-rest block, including the next day's schedule offset.
	for delta in range(5, 901, 5):
		var future: int = world.minute + delta
		var offset: int = ((world._day_seed(int(future / 1440), resident.id) % 7) - 3) * 5
		var local: int = posmod(future - offset, 1440)
		for entry in resident.get("schedule", []):
			if local >= int(entry.start) and local < int(entry.end) and entry.place not in ["casa", "descansar"]: return delta
	return 900

func _next_task(resident: Dictionary, state: Dictionary) -> void:
	var world = _world.get_ref()
	state.sequence = (int(state.sequence) + 1) % 3
	state.task = _task_for(resident.id, str(state.place), int(state.sequence))
	var chosen: Vector2 = SharedDestinations.choose(world, resident, str(state.place), int(state.sequence) + 1)
	if Navigation.route(_point(resident.pos), chosen, resident.room).is_empty(): return
	resident.target = [chosen.x, chosen.y]
	resident.travel_intent = str(state.place)
	state.phase = "active" if _at_target(resident) else "task_travel"
	state.until = world.minute + int(state.task.duration) if state.phase == "active" else 0
	world._decision_dirty[resident.id] = true

func _task_for(id: String, place: String, sequence: int) -> Dictionary:
	if sequence == 2: return {"action": "social_break", "kind": "leisure", "label": "Tomando una pausa para convivir", "duration": 10}
	var choices: Array = []
	match place:
		"cafe":
			choices = [["drink", "eating", "Disfrutando una bebida"], ["listen", "leisure", "Escuchando el ambiente del café"]]
			if id == "ines": choices = [["serve", "working", "Atendiendo el café"], ["tidy_cups", "working", "Ordenando las tazas"]]
			elif id == "alma": choices[1] = ["sketch", "working", "Dibujando en su libreta"]
		"taller":
			choices = [["observe_tools", "leisure", "Observando el trabajo del taller"], ["inspect_bicycle", "leisure", "Mirando una bicicleta"]]
			if id == "mateo": choices = [["repair", "working", "Revisando una reparación"], ["sort_tools", "working", "Ordenando herramientas"]]
			elif id == "alma": choices = [["sketch", "working", "Dibujando el taller"], ["observe_tools", "leisure", "Observando sus detalles"]]
		"huerto":
			choices = [["observe_plants", "leisure", "Observando las plantas"], ["check_soil", "working", "Revisando la tierra junto al sendero"]]
			if id == "cesar": choices[0] = ["water", "working", "Regando junto al sendero"]
			elif id == "alma": choices[0] = ["sketch", "working", "Dibujando las plantas"]
		"plaza":
			choices = [["look_around", "leisure", "Observando la plaza"], ["take_break", "leisure", "Disfrutando una pausa"]]
			if id == "lupita": choices[0] = ["plan_meeting", "working", "Preparando una reunión vecinal"]
			elif id == "alma": choices[0] = ["sketch", "working", "Dibujando la plaza"]
	if choices.is_empty(): choices = [["take_break", "leisure", "Disfrutando una pausa"]]
	var selected: Array = choices[sequence % choices.size()]
	var duration: int = 10 + (_world.get_ref()._day_seed(sequence, id + place) % 4) * 5
	return {"action": selected[0], "kind": selected[1], "label": selected[2], "duration": duration}

func _place_name(place: String) -> String:
	return {"plaza": "la plaza", "cafe": "el café", "taller": "el taller", "huerto": "el huerto", "casa": "casa", "descansar": "casa"}.get(place, place)
