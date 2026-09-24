extends RefCounted
## Facts for a conversation, captured before its reservation hides the current task.
## A schedule is a plan; only an active physical task is evidence of doing it.
const Layout = preload("res://scripts/world_layout.gd")
const PLACE_NAMES := {"cafe": "el café", "taller": "el taller", "huerto": "el huerto", "plaza": "la plaza", "calle": "la calle", "casa": "casa", "descansar": "casa"}
const LIMITS := {"activity_before_chat": 100, "routine": 100, "place": 80, "place_label": 80, "intent": 80, "ongoing_action": 80, "phase": 32, "next_plan": 100}

static func _point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

static func _name(place: String) -> String:
	if Layout.is_outdoor(place): return str(Layout.area_title(place))
	return str(PLACE_NAMES.get(place, place))

static func _place(world, resident: Dictionary) -> String:
	var room: String = str(resident.get("room", "street"))
	if not Layout.is_outdoor(room): return "casa"
	var nearest: String = "calle" if room == "street" else room
	var distance := 40.0
	for key in ["cafe", "taller", "huerto", "plaza"]:
		if not world.PLACES.has(key) or Layout.place_area(key) != room: continue
		var candidate: float = _point(resident.pos).distance_to(_point(world.PLACES[key]))
		if candidate < distance:
			distance = candidate
			nearest = key
	return nearest

static func _next_plan(world, resident: Dictionary) -> String:
	if world.settlement_jobs.busy(resident.id):
		var job: Dictionary = world.settlement.state.jobs[resident.id]
		var task: Dictionary = world.settlement.task_spec(job.task_id,resident.id)
		return ("Llevar los hallazgos al tablón" if job.phase == "returning" else "Retomar: " + str(task.title)).left(100)
	if resident.id == "player" and not world.player_autonomy: return ""
	var first := 2147483647
	var result := ""
	for day in [int(world.minute / 1440), int(world.minute / 1440) + 1]:
		var offset: int = ((world._day_seed(day, resident.id) % 7) - 3) * 5
		for entry: Dictionary in resident.get("schedule", []):
			var start: int = day * 1440 + int(entry.start) + offset
			if start <= world.minute or start >= first: continue
			first = start
			var planned_place: String = str(entry.get("place", ""))
			result = "Cuidar el barrio" if world.PLACES.has(planned_place) and not world.area_open(Layout.place_area(planned_place)) else str(entry.get("label", "")) + " (" + _name(planned_place) + ")"
	return result.left(100)

static func compact(scene: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for field in LIMITS:
		result[field] = str(scene.get(field, "")).replace("\n", " ").replace("\r", " ").replace("\t", " ").left(int(LIMITS[field]))
	result["paused_for_chat"] = bool(scene.get("paused_for_chat", false))
	return result

static func capture(world, id: String) -> Dictionary:
	var resident: Dictionary = world.get_resident(id)
	if resident.is_empty(): return {}
	var daily: Dictionary = world.daily_state(id)
	var phase: String = str(daily.get("kind", "idle"))
	var action: String = str(daily.get("action", ""))
	var activity: String = str(daily.get("label", ""))
	var place: String = _place(world, resident)
	var intent: String = str(resident.get("travel_intent", ""))
	var paused: bool = phase == "speaking"
	if paused:
		# No snapshot is available when inspecting an already held character.
		# Do not turn "Conversando con…" into a supposed activity before the chat.
		activity = ""
		action = ""
		phase = "idle"
	elif not world.is_sleeping(id) and _point(resident.pos).distance_to(_point(resident.target)) > 2.0:
		phase = "walking"
		action = "walk"
		activity = str(daily.label) if daily.get("source","") == "settlement" else "Caminando a " + _name(intent) if not intent.is_empty() else "Caminando por la colonia"
	elif phase == "idle" or phase == "manual":
		# A routine title such as "Reparar bicicletas" is not a completed/active job.
		activity = ""
		action = ""
		if place == "casa" and resident.get("routine_place", "") in ["casa", "descansar"]:
			phase = "leisure"
			action = "take_break"
			activity = "Descansando en casa"
	var place_label: String = _name(place)
	if place == "casa":
		var room: String = str(resident.get("room", ""))
		var owner: Dictionary = world.get_resident(room)
		place_label = "su casa" if room == resident.get("home_id", "") else "casa de " + str(owner.get("name", "un vecino"))
	return compact({"activity_before_chat": activity, "routine": resident.get("routine", ""),
		"place": place, "place_label": place_label, "intent": intent, "ongoing_action": action,
		"phase": phase, "next_plan": _next_plan(world, resident), "paused_for_chat": paused})
