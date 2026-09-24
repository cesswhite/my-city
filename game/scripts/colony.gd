extends RefCounted
## Local, deterministic simulation. No LLM or model training is claimed here.
const VERSION: int = 1
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
const WORLD_REVISION := 2
const Settlement = preload("res://scripts/settlement.gd")
const SettlementJobs = preload("res://scripts/settlement_jobs.gd")
const EnvironmentState = preload("res://scripts/environment_state.gd")
const Progression = preload("res://scripts/progression.gd")
const COFFEE_PRICE := Progression.COFFEE_PRICE
const DailyLife = preload("res://scripts/daily_life.gd")
const Rest = preload("res://scripts/rest_state.gd")
const Weather = preload("res://scripts/colony_weather.gd")
const ConversationScene = preload("res://scripts/conversation_scene.gd")
const SharedDestinations = preload("res://scripts/shared_destinations.gd")
const SocialRelationships = preload("res://scripts/social_relationships.gd")
const SocialKnowledge = preload("res://scripts/social_knowledge.gd")
const SocialDialogue = preload("res://scripts/social_dialogue.gd")
const SocialDynamics = preload("res://scripts/social_dynamics.gd")
static var RESIDENT_IDS: Array = preload("res://scripts/resident_catalog.gd").ids()
static var PLACES: Dictionary = Layout.data().places.duplicate(true)
const ACTIONS = ["colaborar", "plaza", "cafe", "taller", "huerto", "descansar", "conversar", "practicar"]
const RECIPE_STEPS = ["llenar_tetera", "calentar_agua", "agregar_te", "servir"]
const RECIPE_INGREDIENTS = {"agua": 1, "te": 1}
const MAX_DISTANCE: float = 45.0
const ENERGY_AWAKE_PER_MINUTE: float = 0.025
const ENERGY_REST_PER_MINUTE: float = 0.10
const ENERGY_SLEEP_PER_MINUTE: float = 0.25
const ENERGY_REST_DISTANCE: float = 12.0
const RECALL_PHRASES = [
	"Sí, recuerdo que me habías comentado algo.",
	"Sí, me acuerdo de eso.",
	"Cierto, ya habíamos hablado de eso.",
	"Sí, me habías contado algo."
]
static var HOME_DOORS: Dictionary = Layout.data().doors.duplicate(true)
static var ROOM_ENTRY: Array = Layout.data().entry.duplicate()
static var ROOM_EXIT: Array = Layout.data().exit.duplicate()
static var HOME_REST: Array = Layout.data().home_rest.duplicate()
const PLAYER_SCHEDULE = [
	{"start": 0, "end": 420, "place": "casa", "label": "Descansar en casa"},
	{"start": 420, "end": 600, "place": "cafe", "label": "Desayunar y conocer vecinos"},
	{"start": 600, "end": 780, "place": "plaza", "label": "Pasear por la plaza"},
	{"start": 780, "end": 900, "place": "cafe", "label": "Comer y conversar"},
	{"start": 900, "end": 1080, "place": "taller", "label": "Visitar el taller y observar"},
	{"start": 1080, "end": 1200, "place": "huerto", "label": "Visitar el huerto"},
	{"start": 1200, "end": 1320, "place": "plaza", "label": "Compartir la tarde con vecinos"},
	{"start": 1320, "end": 1440, "place": "casa", "label": "Volver a casa a descansar"}
]
var residents: Array[Dictionary] = []
var events: Array[String] = []
var minute: int = 480
var last_error: String = ""
var save_path: String = "user://colony.json"
var supplies: Dictionary = {"agua": 30, "te": 30}
## Opt-in for this session only; never restored from a save.
var player_autonomy: bool = false
## Participants reserved by the host for a live conversation; session state only.
var conversation_holds: Array[String] = []
var _turn: int = 0
var _serial: int = 0
var _memory_index: Dictionary = {}
var _default_schedules: Dictionary = {}
var _routine_keys: Dictionary = {}
var _decision_marks: Dictionary = {}
var _decision_dirty: Dictionary = {}
var _last_event_day: int = -1
var _local_chat_times: Dictionary = {}
var _visit_permissions: Dictionary = {}
var _room_revisions: Dictionary = {}
var _progression = Progression.new()
var settlement = Settlement.new()
var settlement_jobs = SettlementJobs.new()
var environment = EnvironmentState.new()
var _daily_life = DailyLife.new()
var _social = SocialRelationships.new()
var social_knowledge = SocialKnowledge.new()
var social_dialogue = SocialDialogue.new()
var social_dynamics = SocialDynamics.new()
var _energy_previous_position: Array = []
var _energy_previous_room: String = ""

func setup(load_existing: bool = true, developed: bool = false):
	player_autonomy = false
	conversation_holds.clear()
	residents.clear()
	events.clear()
	minute = 480
	_turn = 0
	_serial = 0
	_memory_index.clear()
	_default_schedules.clear()
	_routine_keys.clear()
	_decision_marks.clear()
	_decision_dirty.clear()
	_last_event_day = -1
	_local_chat_times.clear()
	_visit_permissions.clear()
	_room_revisions.clear()
	_energy_previous_position.clear()
	_energy_previous_room = ""
	supplies = {"agua": 30, "te": 30}
	last_error = ""
	var raw = _parse_json(FileAccess.get_file_as_string("res://data/residents.json"))
	if not raw is Array:
		last_error = "No se pudieron leer los habitantes iniciales."
		return
	for item in raw:
		var resident: Dictionary = item.duplicate(true)
		var spawn: Dictionary = Layout.resident_spawn(str(resident.id))
		if not spawn.is_empty(): resident.pos = [spawn.position.x, spawn.position.y]
		resident["target"] = resident.pos.duplicate()
		resident["activity"] = "Conociendo la colonia"
		resident["memories"] = []
		resident["known_people"] = {}
		resident["skills"] = {}
		resident["room"] = str(spawn.get("room", "street"))
		resident["home_id"] = resident.id
		resident["travel_intent"] = ""
		resident["routine"] = "Explorar libremente" if resident.id == "player" else "Comenzando el día"
		if resident.id == "player": resident["energy"] = 100.0
		if resident.id == "player" and resident.get("schedule", []).is_empty():
			resident["schedule"] = PLAYER_SCHEDULE.duplicate(true)
		_default_schedules[resident.id] = resident.get("schedule", []).duplicate(true)
		residents.append(resident)
	get_resident("ines").skills["preparar_te"] = {
		"name": "Preparar té", "status": "demostrada", "steps": RECIPE_STEPS.duplicate(),
		"ingredients": RECIPE_INGREDIENTS.duplicate(), "source": "Historia inicial de Inés",
		"learned_at": 480, "practice_runs": 1, "last_result": "Receta inicial conocida"
	}
	_progression.setup(self)
	_daily_life.setup(self)
	_social.setup(self)
	settlement.setup(self, developed)
	environment.setup(self)
	settlement_jobs.setup(self)
	settlement_jobs.autonomous_enabled = not developed
	social_knowledge.setup(self)
	social_dialogue.setup(self)
	social_dynamics.setup(self)
	if load_existing and FileAccess.file_exists(save_path):
		if load_game():
			_log("La colonia recuerda su última visita.")
		else:
			_log("Partida conservada sin modificar: " + last_error)
	else:
		_log("Un pequeño barrio y una historia por construir.")
	ensure_exhaustion()

func get_resident(id: String) -> Dictionary:
	for resident in residents:
		if resident.id == id:
			return resident
	return {}

func is_present(id: String) -> bool:
	return settlement.is_present(id)

func active_residents(include_player: bool = true) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for resident in residents:
		if is_present(resident.id) and (include_player or resident.id != "player"): result.append(resident)
	return result

func area_open(id: String) -> bool:
	return settlement.area_open(id)

func home_available(id: String) -> bool:
	return is_present(id) and settlement.building_ready(str(settlement.catalog.home_buildings.get(id,"")))

func open_area_route(from: String, to: String) -> Array[String]:
	var result: Array[String] = []
	if not area_open(from) or not area_open(to): return result
	var queue: Array[String] = [from]
	var parent: Dictionary = {from:""}
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == to:
			while not current.is_empty():
				result.push_front(current)
				current = parent[current]
			return result
		for link in Layout.exits(current):
			if area_open(link.to) and not parent.has(link.to):
				parent[link.to] = current
				queue.append(link.to)
	return result

func next_open_exit(from: String, to: String) -> Dictionary:
	var route: Array[String] = open_area_route(from,to)
	if route.size() < 2: return {}
	for link in Layout.exits(from):
		if link.to == route[1]: return link
	return {}

func allowed_actions_for(id: String) -> Array:
	var allowed: Array = ACTIONS.duplicate()
	for action in ["taller","huerto"]:
		if not area_open(Layout.place_area(action)): allowed.erase(action)
	if settlement_jobs.autonomous_offer(id).is_empty(): allowed.erase("colaborar")
	return allowed

func player_energy() -> float:
	var value = get_resident("player").get("energy", 100.0)
	return float(value) if _valid_energy(value) else 100.0

func daily_state(id: String) -> Dictionary:
	return _daily_life.state_for(id)

func weather_state() -> Dictionary:
	return Weather.at_minute(minute)

func conversation_scene_for(id: String) -> Dictionary:
	return ConversationScene.capture(self, id)

func social_available(id: String) -> bool:
	return is_present(id) and not settlement_jobs.busy(id) and _daily_life.social_available(id) and _social.available(id)

func relationship_for(owner: String, partner: String) -> Dictionary:
	return _social.relationship_for(owner, partner)

func visible_profile_for(owner: String, viewer: String) -> Dictionary:
	return _social.visible_profile_for(owner, viewer)

func social_start(owner: String, partner: String) -> Dictionary:
	if not is_present(owner) or not is_present(partner): return {"ok":false,"allowed":false,"message":"Ese vecino todavía no está aquí."}
	return _social.start(owner, partner)

func social_turn(owner: String, partner: String, text: String, session_exchanges: int = 0) -> Dictionary:
	return _social.turn(owner, partner, text, session_exchanges)

func social_finish(owner: String, partner: String, respectful: bool = true) -> void:
	_social.finish(owner, partner, respectful)

func greeting_pair(a: String, b: String) -> Dictionary:
	return _social.greeting_pair(a, b)

func is_sleeping(id: String) -> bool:
	return Rest.is_sleeping(self, id)

func is_exhausted() -> bool:
	return Rest.is_exhausted(self)

func ensure_exhaustion() -> bool:
	if not Rest.ensure_exhaustion(self): return false
	_daily_life.forget("player")
	_energy_previous_position = get_resident("player").pos.duplicate()
	_energy_previous_room = get_resident("player").get("room", "street")
	return true

func advance_exhaustion(real_seconds: float) -> bool:
	if not Rest.advance_exhaustion(self, real_seconds): return false
	_daily_life.forget("player")
	return true

func start_sleep(id: String, duration_minutes: int = 480) -> bool:
	if id == "player" and ensure_exhaustion():
		last_error = "Necesitas recuperarte del agotamiento."
		return false
	return Rest.begin(self, id, duration_minutes)

func wake_resident(id: String) -> bool:
	return Rest.wake(self, id)

func _update_player_energy(elapsed_minutes: float) -> void:
	var player: Dictionary = get_resident("player")
	if player.is_empty(): return
	if is_exhausted() or ensure_exhaustion(): return
	var room: String = player.get("room", "street")
	var stationary: bool = _point_distance(player.pos, player.target) <= 2.0
	if not _energy_previous_position.is_empty():
		stationary = stationary and room == _energy_previous_room and _point_distance(player.pos, _energy_previous_position) <= 2.0
	var bed: Vector2 = Layout.stand_at("bed", "player")
	var near_bed: bool = _point_distance(player.pos, HOME_REST) <= ENERGY_REST_DISTANCE or Vector2(player.pos[0], player.pos[1]).distance_to(bed) <= ENERGY_REST_DISTANCE
	var scheduled_rest: bool = player_autonomy and player.get("routine_place", "") in ["casa", "descansar"]
	var resting: bool = room == "player" and player.get("home_id", "") == "player" and stationary and "player" not in conversation_holds and (near_bed or scheduled_rest)
	var sleeping_here: bool = is_sleeping("player") and Rest.at_bed(player) and "player" not in conversation_holds
	var rate: float = ENERGY_SLEEP_PER_MINUTE if sleeping_here else ENERGY_REST_PER_MINUTE if resting else -ENERGY_AWAKE_PER_MINUTE
	player["energy"] = clampf(player_energy() + rate * elapsed_minutes, 0.0, 100.0)
	_energy_previous_position = player.pos.duplicate()
	_energy_previous_room = room
	ensure_exhaustion()

func set_player_autonomy(enabled: bool):
	if enabled and player_autonomy: return
	player_autonomy = enabled
	var player: Dictionary = get_resident("player")
	if player.is_empty(): return
	_routine_keys.erase("player")
	_decision_marks.erase("player")
	_decision_dirty.erase("player")
	if enabled:
		if player.get("schedule", []).is_empty(): player["schedule"] = PLAYER_SCHEDULE.duplicate(true)
		_update_routines()
	else:
		_daily_life.forget("player")
		player.erase("travel_route")
		player.target = player.pos.duplicate()
		player.travel_intent = ""
		player.routine = "Explorar libremente"
		player["routine_place"] = ""
		player.activity = "Durmiendo por agotamiento" if is_exhausted() else "Durmiendo" if is_sleeping("player") else "Bajo tu control"

func progression_state() -> Dictionary:
	return _progression.snapshot()

func available_apprenticeships() -> Array[Dictionary]:
	return _progression.available()

func shop_catalog() -> Array[Dictionary]:
	return _progression.shop_catalog()

func progression_item_name(item_id: String) -> String:
	return _progression.item_name(item_id)

func quest_status(quest_id: String) -> Dictionary:
	return _progression.status_for(quest_id)

func start_apprenticeship(quest_id: String) -> Dictionary:
	if is_exhausted(): return {"ok":false,"message":"Primero necesitas recuperarte del agotamiento."}
	return _progression.start(quest_id)

func buy_item(item_id: String, quantity: int = 1) -> Dictionary:
	if is_exhausted(): return {"ok":false,"message":"Primero necesitas recuperarte del agotamiento."}
	return _progression.buy(item_id, quantity)

func coffee_offer(seat_id: String) -> Dictionary:
	return _progression.coffee_offer(seat_id)

func order_coffee(seat_id: String) -> Dictionary:
	return _progression.order_coffee(seat_id)

func drink_coffee(seat_id: String) -> Dictionary:
	return _progression.drink_coffee(seat_id)

func deliver_apprenticeship(quest_id: String) -> Dictionary:
	if is_exhausted(): return {"ok":false,"message":"Primero necesitas recuperarte del agotamiento."}
	return _progression.deliver(quest_id)

func perform_procedure(procedure_id: String, step_id: String = "") -> Dictionary:
	if is_exhausted(): return {"ok":false,"message":"Primero necesitas recuperarte del agotamiento."}
	return _progression.perform(procedure_id, step_id)

func can_ride_bicycle() -> bool:
	return _progression.state.procedures.get("reparar_bicicleta", {}).get("world_verified", false) and int(_progression.state.inventory.get("bicicleta", 0)) > 0 and "montar_bicicleta" in _progression.state.unlocks

func tick(use_local_decisions: bool = true):
	_update_player_energy(5.0)
	minute += 5
	environment.tick()
	Rest.tick(self, 5.0)
	_social.tick()
	settlement_jobs.tick(5.0)
	_update_routines()
	_daily_life.tick()
	var actors: Array[Dictionary] = active_residents(player_autonomy)
	if actors.is_empty(): return
	var actor: Dictionary = actors[_turn % actors.size()]
	var can_chat: bool = social_available(actor.id)
	if use_local_decisions and can_chat and _day_seed(minute, actor.id) % 3 == 0:
		var nearby: Dictionary = _nearest(actor, true, true)
		if not nearby.is_empty() and social_available(nearby.id):
			converse(actor.id, nearby.id)
	_turn += 1

func decision_due(id: String) -> bool:
	var resident: Dictionary = get_resident(id)
	if not is_present(id) or settlement_jobs.busy(id) or resident.is_empty() or is_sleeping(id) or id in conversation_holds or (id == "player" and not player_autonomy): return false
	if resident.has("travel_route"): return false
	if resident.get("room", "street") == resident.get("home_id", "") and resident.get("routine_place", "") in ["casa", "descansar"]: return false
	if _point_distance(resident.pos, resident.target) > 8.0: return false
	if not _daily_life.decision_ready(id): return false
	return bool(_decision_dirty.get(id, true)) or minute - int(_decision_marks.get(id, -60)) >= 60

func _day_seed(day: int, id: String) -> int:
	var result: int = day * 7919 + 137
	for character in id.to_utf8_buffer(): result = (result * 31 + character) % 1000003
	return result

func _update_routines():
	var day: int = int(minute / 1440)
	var daily_seed: int = _day_seed(day, "colonia")
	var actors: Array[Dictionary] = active_residents(player_autonomy)
	if actors.is_empty(): return
	var event_id: String = actors[daily_seed % actors.size()].id
	var event_start: int = 900 + (daily_seed % 13) * 15
	var local_minute: int = minute % 1440
	if local_minute >= event_start and local_minute < event_start + 30 and _last_event_day != day:
		var organizer: Dictionary = get_resident(event_id)
		var actor_name: String = "Tu personaje" if organizer.id == "player" and organizer.name == "Tú" else str(organizer.name)
		var invitation: String = actor_name + " decide llevar una historia a la plaza y buscar con quién compartirla."
		_remember(organizer, _memory("iniciativa", [event_id], invitation, "intención propia; encuentro aún no ocurrido"))
		_log(invitation)
		_last_event_day = day
	for resident in active_residents():
		if settlement_jobs.busy(resident.id): continue
		if resident.id == "player" and not player_autonomy: continue
		if is_sleeping(resident.id): continue
		var schedule: Array = resident.get("schedule", [])
		var offset: int = ((_day_seed(day, resident.id) % 7) - 3) * 5
		var schedule_minute: int = posmod(local_minute - offset, 1440)
		for entry in schedule:
			if schedule_minute < int(entry.start) or schedule_minute >= int(entry.end): continue
			var place: String = entry.place
			var label: String = entry.label
			if PLACES.has(place) and not area_open(Layout.place_area(place)):
				place = "plaza"
				label = "Cuidar el barrio"
			var routine_key: String = "%d:%d" % [day, int(entry.start)]
			if resident.id == event_id and local_minute >= event_start and local_minute < event_start + 30:
				place = "plaza"
				label = "Compartir una historia espontánea"
				routine_key += ":iniciativa"
			resident.routine = label
			resident["routine_place"] = place
			if _routine_keys.get(resident.id, "") != routine_key:
				_routine_keys[resident.id] = routine_key
				_decision_dirty[resident.id] = true
				_set_destination(resident, place)
				resident.activity = label
			break

func _set_destination(resident: Dictionary, place: String):
	if not is_present(resident.id): return
	if PLACES.has(place) and not area_open(Layout.place_area(place)): place = "plaza"
	var home: String = resident.get("home_id", "")
	if place in ["descansar", "casa"] and HOME_DOORS.has(home):
		resident.travel_intent = "casa"
		if resident.get("room", "street") == home:
			resident.erase("travel_route")
			resident.target = HOME_REST.duplicate()
		else:
			_assign_travel(resident, Layout.home_area(home), Layout.point(HOME_DOORS[home]))
	elif PLACES.has(place):
		resident.travel_intent = place
		var destination: Vector2 = SharedDestinations.choose(self, resident, place)
		_assign_travel(resident, Layout.place_area(place), destination)
	else:
		resident.erase("travel_route")
		resident.travel_intent = ""
		resident.target = resident.pos.duplicate()

func travel_to(id: String, target_room: String, target: Vector2) -> bool:
	last_error = ""
	var resident: Dictionary = get_resident(id)
	if not is_present(id) or resident.is_empty() or is_sleeping(id) or id in conversation_holds:
		return _save_failure("Termina lo que estás haciendo antes de caminar.")
	if not area_open(_outdoor_for(target_room)): return _save_failure("Ese camino todavía está cerrado. Revisa las obras del Diario.")
	# Entering a different house is a separate, permission-checked interaction.
	if not Layout.is_outdoor(target_room) and target_room != resident.get("room", "street"):
		return _save_failure("Camina primero a la puerta de esa casa.")
	if not Navigation.is_walkable(target, target_room):
		return _save_failure("Ese destino no tiene un camino transitable.")
	var source_area: String = _outdoor_for(str(resident.get("room", "street")))
	if Layout.is_outdoor(target_room) and source_area != target_room and next_open_exit(source_area, target_room).is_empty():
		return _save_failure("No hay un camino hacia esa calle.")
	if not _assign_travel(resident, target_room, target): return false
	resident.travel_intent = ""
	return true

func cancel_travel(id: String) -> void:
	var resident: Dictionary = get_resident(id)
	if resident.is_empty(): return
	resident.erase("travel_route")
	resident.travel_intent = ""
	resident.target = resident.pos.duplicate()

func _outdoor_for(room: String) -> String:
	return room if Layout.is_outdoor(room) else Layout.home_area(room)

func _assign_travel(resident: Dictionary, target_room: String, target: Vector2) -> bool:
	if not is_present(resident.id) or not area_open(_outdoor_for(target_room)): return false
	resident["travel_route"] = {"room": target_room, "position": [target.x, target.y]}
	return _route_leg(resident)

func _route_leg(resident: Dictionary) -> bool:
	var journey: Dictionary = resident.get("travel_route", {})
	if journey.is_empty(): return true
	var room: String = resident.get("room", "street")
	if room == journey.room:
		resident.target = journey.position.duplicate()
	elif not Layout.is_outdoor(room):
		resident.target = ROOM_EXIT.duplicate()
	else:
		var link: Dictionary = next_open_exit(room, journey.room)
		if link.is_empty(): return _save_failure("No hay un camino hacia esa calle.")
		resident.target = [link.at.x, link.at.y]
	return true

func cross_exit(id: String, exit_id: String) -> bool:
	last_error = ""
	var resident: Dictionary = get_resident(id)
	if not is_present(id) or resident.is_empty() or is_sleeping(id) or id in conversation_holds:
		return _save_failure("Termina lo que estás haciendo antes de cambiar de calle.")
	var room: String = resident.get("room", "street")
	var link: Dictionary = {}
	for candidate: Dictionary in Layout.exits(room):
		if candidate.id == exit_id:
			link = candidate
			break
	if link.is_empty() or Layout.edge_exit(room, Layout.point(resident.pos), link.direction).get("id", "") != exit_id:
		return _save_failure("Acércate al paso que conecta las calles.")
	if not area_open(link.to): return _save_failure("Este paso aún está cerrado. Explóralo y prepara la obra desde el Diario.")
	var spawn: Array = [link.spawn.x, link.spawn.y]
	if not Navigation.is_walkable(link.spawn, link.to) or not _entry_clear(spawn, link.to, id):
		return _save_failure("Espera a que quede libre el paso de la otra calle.")
	resident.room = link.to
	resident.pos = spawn
	resident.target = spawn.duplicate()
	_room_revisions[id] = int(_room_revisions.get(id, 0)) + 1
	_route_leg(resident)
	return true

func on_arrival(id: String):
	var resident: Dictionary = get_resident(id)
	if not is_present(id) or resident.is_empty() or is_sleeping(id) or id in conversation_holds: return
	if _point_distance(resident.pos, resident.target) > 2.0: return
	var journey: Dictionary = resident.get("travel_route", {})
	if not journey.is_empty():
		if resident.room == journey.room:
			# Frozen conversation goals cannot complete an unrelated final destination.
			if _point_distance(resident.pos, journey.position) > 2.0: return
			resident.erase("travel_route")
		elif not Layout.is_outdoor(resident.room):
			leave_home(id)
			return
		else:
			var link: Dictionary = next_open_exit(resident.room, journey.room)
			if not link.is_empty(): cross_exit(id, link.id)
			return
	if id == "player" and not player_autonomy: return
	var intent: String = resident.get("travel_intent", "")
	var room: String = resident.get("room", "street")
	var home: String = resident.get("home_id", "")
	if intent == "casa" and HOME_DOORS.has(home):
		if room == Layout.home_area(home) and _point_distance(resident.pos, HOME_DOORS[home]) <= 12.0:
			if enter_home(id, home): resident.activity = "Descansando en casa"
		elif not Layout.is_outdoor(room) and room != home and _point_distance(resident.pos, ROOM_EXIT) <= 16.0:
			leave_home(id)
	elif PLACES.has(intent) and not Layout.is_outdoor(room) and _point_distance(resident.pos, ROOM_EXIT) <= 16.0:
		leave_home(id)

func visit_context(visitor_id: String, home_id: String) -> Dictionary:
	var visitor: Dictionary = get_resident(visitor_id)
	var owner: Dictionary = get_resident(home_id)
	var result: Dictionary = {"valid": false, "allowed": false, "occupied": false, "resident_id": home_id,
		"home_id": home_id, "reason": "Esta casa no existe.", "known": false, "encounters": 0, "routine": "", "awake": false}
	if visitor.is_empty() or owner.is_empty() or not HOME_DOORS.has(home_id): return result
	if not is_present(visitor_id) or not home_available(home_id):
		result.reason = "Esta vivienda todavía necesita ser habilitada."
		return result
	var occupants: Array[Dictionary] = []
	var signature: Array[String] = []
	for candidate in active_residents():
		if candidate.id == visitor_id or (candidate.id == "player" and not player_autonomy) or candidate.get("room", "street") != home_id: continue
		occupants.append(candidate)
		signature.append(str(candidate.id) + ":" + str(_room_revisions.get(candidate.id, 0)))
	signature.sort()
	result["occupant_signature"] = ";".join(signature)
	result.occupied = not occupants.is_empty()
	var respondent: Dictionary = owner
	if result.occupied:
		respondent = owner if owner.get("room", "street") == home_id and owner.id != visitor_id else occupants[0]
	result.resident_id = respondent.id
	result.known = respondent.known_people.has(visitor_id)
	result.encounters = mini(1000000, int(_memory_index.get(respondent.id, {}).get("completed_by_partner", {}).get(visitor_id, 0)))
	result.routine = respondent.get("routine", "")
	result.awake = not is_sleeping(respondent.id) and minute % 1440 >= 420 and minute % 1440 < 1320
	if visitor.get("room", "street") != Layout.home_area(home_id) or _point_distance(visitor.pos, HOME_DOORS[home_id]) > 25.0:
		result.reason = "Acércate a la puerta de la casa desde la calle."
		return result
	result.valid = true
	result.reason = "La puerta está abierta." if not result.occupied else "Toca y espera la respuesta de " + str(respondent.name) + "."
	return result

func request_home_visit(visitor_id: String, home_id: String) -> Dictionary:
	var state: Dictionary = visit_context(visitor_id, home_id)
	if not state.valid:
		last_error = state.reason
		return state
	var respondent: Dictionary = get_resident(state.resident_id)
	var threshold: int = 2 if "reservado" in respondent.personality or "independiente" in respondent.personality or "protectora" in respondent.personality else 1
	var allowed: bool = visitor_id == home_id or not state.occupied or (state.awake and state.known and state.encounters >= threshold)
	if state.occupied and visitor_id != home_id:
		var relation: Dictionary = relationship_for(state.resident_id, visitor_id)
		if not relation.is_empty() and (relation.cooldown_until > minute or relation.frustration >= 65): allowed = false
	return apply_visit_decision(visitor_id, home_id, allowed, "Regla local de convivencia")

func apply_visit_decision(visitor_id: String, home_id: String, allowed: bool, source: String, expected_signature: String = "") -> Dictionary:
	last_error = ""
	var state: Dictionary = visit_context(visitor_id, home_id)
	state["decision_source"] = source.left(120)
	if not state.valid or source.strip_edges().is_empty():
		last_error = state.reason
		return state
	var visitor: Dictionary = get_resident(visitor_id)
	var owner: Dictionary = get_resident(home_id)
	var respondent: Dictionary = get_resident(state.resident_id)
	if not expected_signature.is_empty() and expected_signature != state.occupant_signature:
		state.valid = false
		state.reason = "Cambió quien está en casa; vuelve a tocar."
		last_error = state.reason
		return state
	var own_home: bool = visitor_id == home_id
	if own_home or not state.occupied: allowed = true
	if state.occupied and not state.awake and not own_home: allowed = false
	var needs_space: bool = false
	if state.occupied and not own_home:
		var relation: Dictionary = relationship_for(state.resident_id, visitor_id)
		needs_space = not relation.is_empty() and (relation.cooldown_until > minute or relation.frustration >= 65)
		if needs_space: allowed = false
	state.allowed = allowed
	if own_home:
		state.reason = "Es tu casa."
	elif not state.occupied:
		state.reason = "No hay nadie; la puerta está abierta."
	elif not state.awake:
		state.reason = str(respondent.name) + " está descansando; vuelve durante el día."
	elif needs_space:
		state.reason = str(respondent.name) + " necesita un poco de espacio; vuelve más tarde."
	elif allowed:
		state.reason = str(respondent.name) + " te invita a entrar."
	else:
		state.reason = str(respondent.name) + " prefiere no recibir visitas en este momento."
	var key: String = visitor_id + ":" + home_id
	_visit_permissions.erase(key)
	if allowed:
		_visit_permissions[key] = {"expires": minute + 15, "signature": state.occupant_signature}
	if not own_home:
		var content: String = str(visitor.name) + " se acercó a la casa de " + str(owner.name) + ". " + str(state.reason)
		if state.occupied and state.awake:
			for observer in [visitor, respondent]:
				_remember(observer, _memory("visita", [visitor_id, respondent.id], content, source.left(120) + "; respuesta a la puerta"))
		else:
			_remember(visitor, _memory("visita", [visitor_id], content, "observación propia en la puerta"))
		_log(content)
	return state

func enter_home(id: String, home_id: String) -> bool:
	if not is_present(id) or not home_available(home_id): return _save_failure("Esta casa todavía no está habilitada.")
	last_error = ""
	if is_sleeping(id): return _save_failure("Despierta antes de entrar.")
	if id in conversation_holds: return _save_failure("Termina la conversación antes de entrar.")
	var state: Dictionary = visit_context(id, home_id)
	if not state.valid: return _save_failure(state.reason)
	var key: String = id + ":" + home_id
	if id != home_id:
		var permission: Dictionary = _visit_permissions.get(key, {})
		if permission.is_empty() or minute > int(permission.get("expires", -1)) or permission.get("signature", "") != state.occupant_signature:
			return _save_failure("Toca la puerta o solicita entrar antes de cruzarla.")
	if not _entry_clear(ROOM_ENTRY, home_id, id):
		return _save_failure("Espera a que quede libre la entrada.")
	_visit_permissions.erase(key)
	var resident: Dictionary = get_resident(id)
	resident.room = home_id
	resident.erase("travel_route")
	resident.pos = ROOM_ENTRY.duplicate()
	resident.target = HOME_REST.duplicate() if id == home_id and (id != "player" or player_autonomy) else ROOM_ENTRY.duplicate()
	if id != home_id: resident.travel_intent = ""
	resident.activity = "En casa de " + str(get_resident(home_id).name)
	_room_revisions[id] = int(_room_revisions.get(id, 0)) + 1
	return true

func _entry_clear(point: Array, room: String, id: String) -> bool:
	# Crossing a portal must obey the same personal space as walking. This is a
	# read-only check: a blocked visitor keeps the original permission and expiry.
	for other: Dictionary in active_residents():
		if other.id == id or other.get("room", "street") != room: continue
		var dx: float = (float(other.pos[0]) - float(point[0])) / 16.0
		var dy: float = (float(other.pos[1]) - float(point[1])) / 14.0
		if dx * dx + dy * dy < 1.0: return false
	return true

func observe_house_item(id: String, home_id: String, title: String, description: String) -> bool:
	last_error = ""
	var resident: Dictionary = get_resident(id)
	if resident.is_empty() or not HOME_DOORS.has(home_id) or resident.get("room", "street") != home_id:
		return _save_failure("Debes estar dentro de esa casa para observar el objeto.")
	title = title.strip_edges()
	description = description.strip_edges()
	if title.is_empty() or description.is_empty() or title.length() > 80 or description.length() > 1000:
		return _save_failure("El objeto necesita un título y una descripción breves.")
	var key: String = "objeto:" + home_id + ":" + title
	if _memory_index.get(id, {}).get("observed_items", {}).has(key): return true
	var memory: Dictionary = _memory("objeto", [id], title + ": " + description, "observación directa en casa de " + str(get_resident(home_id).name))
	memory["object_key"] = key
	memory["home_id"] = home_id
	_remember(resident, memory)
	return true

func observe_area_item(id: String, area: String, title: String, description: String) -> bool:
	last_error = ""
	var resident: Dictionary = get_resident(id)
	if resident.is_empty() or not Layout.is_outdoor(area) or resident.get("room", "street") != area:
		return _save_failure("Debes estar en esa calle para observar el objeto.")
	title = title.strip_edges()
	description = description.strip_edges()
	if title.is_empty() or description.is_empty() or title.length() > 80 or description.length() > 1000:
		return _save_failure("El objeto necesita un título y una descripción breves.")
	var key: String = "objeto:" + area + ":" + title
	if _memory_index.get(id, {}).get("observed_items", {}).has(key): return true
	var memory: Dictionary = _memory("objeto", [id], title + ": " + description, "observación directa en " + Layout.area_title(area))
	memory["object_key"] = key
	memory["room"] = area
	_remember(resident, memory)
	return true

func leave_home(id: String) -> bool:
	last_error = ""
	if is_sleeping(id): return _save_failure("Despierta antes de salir.")
	if id in conversation_holds: return _save_failure("Termina la conversación antes de salir.")
	var resident: Dictionary = get_resident(id)
	if resident.is_empty(): return _save_failure("No existe este habitante.")
	var room: String = resident.get("room", "street")
	if not HOME_DOORS.has(room) or _point_distance(resident.pos, ROOM_EXIT) > 16.0:
		return _save_failure("Acércate a la salida de la casa para volver a la calle.")
	var area: String = Layout.home_area(room)
	if not _entry_clear(HOME_DOORS[room], area, id):
		return _save_failure("Espera a que quede libre la puerta en la calle.")
	resident.room = area
	resident.pos = HOME_DOORS[room].duplicate()
	resident.target = resident.pos.duplicate()
	_room_revisions[id] = int(_room_revisions.get(id, 0)) + 1
	resident.activity = "De nuevo en la calle"
	var intent: String = resident.get("travel_intent", "")
	if resident.has("travel_route"): _route_leg(resident)
	elif not intent.is_empty(): _set_destination(resident, intent)
	return true

func converse(a_id: String, b_id: String) -> String:
	last_error = ""
	var a: Dictionary = get_resident(a_id)
	var b: Dictionary = get_resident(b_id)
	if a.is_empty() or b.is_empty() or a_id == b_id:
		return _failure("El encuentro necesita dos habitantes distintos.")
	if is_sleeping(a_id) or is_sleeping(b_id): return _failure("Espera a que despierte para conversar.")
	if a_id in conversation_holds or b_id in conversation_holds:
		return _failure("Uno de los habitantes ya está participando en otra conversación.")
	if _distance(a, b) >= MAX_DISTANCE:
		return _failure("Acércate a " + str(b.name) + " para conversar.")
	if not is_present(a_id) or not is_present(b_id) or not Navigation._clear_segment(Layout.point(a.pos),Layout.point(b.pos),a.room):
		return _failure("Necesitan poder verse para conversar.")
	if not _social.available(a_id) or not _social.available(b_id):
		return _failure("Ahora prefiere un rato a solas. Podrán conversar después.")
	if relationship_for(a_id, b_id).cooldown_until > minute or relationship_for(b_id, a_id).cooldown_until > minute:
		return _failure("Dale un poco de espacio; podrán conversar más tarde.")
	var recall: String = ""
	if a.known_people.has(b_id):
		var encounters: int = int(_memory_index.get(a_id, {}).get("completed_by_partner", {}).get(b_id, 1))
		recall = RECALL_PHRASES[maxi(0, encounters - 1) % RECALL_PHRASES.size()] + " "
	var a_line: String = recall + _daily_life.local_line(a_id, b_id)
	var b_line: String = _daily_life.local_line(b_id, a_id, true)
	var social_lines: Dictionary = social_dialogue.encounter_pair(a_id,b_id)
	if not social_lines.is_empty():
		a_line = social_lines.first
		b_line = social_lines.reply
	var dialogue: String = "%s: %s\n%s: %s" % [a.name, a_line, b.name, b_line]
	for pair in [[a, b, b_line], [b, a, a_line]]:
		var listener: Dictionary = pair[0]
		var speaker: Dictionary = pair[1]
		var memory: Dictionary = _memory("conversacion", [a_id, b_id], dialogue, "conversación local predeterminada")
		memory["heard_from"] = speaker.id
		memory["heard_text"] = pair[2]
		memory["epistemic_status"] = "testimonio_no_verificado"
		_remember(listener, memory)
		listener.known_people[speaker.id] = {
			"name": speaker.name, "last_topic": pair[2], "last_time": minute,
			"source": "conversación local predeterminada", "memory_id": memory.id
		}
		listener.activity = "Conversando con " + str(speaker.name)
	_log(dialogue)
	_social.note_exchange(a_id, b_id, a_line, b_line, "conversación local predeterminada", "exchange_%d" % _serial)
	social_dialogue.on_exchange(a_id,b_id,a_line,b_line,"exchange_%d" % _serial)
	social_dynamics.note_exchange(a_id,b_id,a_line,b_line,"exchange_%d" % _serial)
	_social.finish(a_id, b_id)
	_daily_life.note_dialogue(a_id, b_id, true)
	return dialogue

func record_dialogue(a_id: String, b_id: String, a_text: String, b_text: String, source: String) -> bool:
	last_error = ""
	var a: Dictionary = get_resident(a_id)
	var b: Dictionary = get_resident(b_id)
	if a.is_empty() or b.is_empty() or a_id == b_id:
		return _save_failure("El diálogo necesita dos habitantes distintos.")
	if is_sleeping(a_id) or is_sleeping(b_id): return _save_failure("Una persona dormida no puede escuchar este diálogo.")
	if _distance(a, b) >= MAX_DISTANCE:
		return _save_failure("Los habitantes deben estar cerca para escuchar el diálogo.")
	if not is_present(a_id) or not is_present(b_id) or not Navigation._clear_segment(Layout.point(a.pos),Layout.point(b.pos),a.room):
		return _save_failure("No pueden escucharse a través de un obstáculo.")
	a_text = a_text.strip_edges()
	b_text = b_text.strip_edges()
	source = source.strip_edges()
	if a_text.is_empty() or b_text.is_empty() or a_text.length() > 1500 or b_text.length() > 1500 or source.is_empty() or source.length() > 120:
		return _save_failure("Diálogo rechazado: faltan textos o superan el límite permitido.")
	var dialogue: String = "%s: %s\n%s: %s" % [a.name, a_text, b.name, b_text]
	var turns: Array[Dictionary] = [
		{"speaker_id": a_id, "name": str(a.name), "text": a_text},
		{"speaker_id": b_id, "name": str(b.name), "text": b_text}
	]
	for pair in [[a, b, b_text], [b, a, a_text]]:
		var listener: Dictionary = pair[0]
		var speaker: Dictionary = pair[1]
		var heard: String = pair[2]
		var memory: Dictionary = _memory("conversacion", [a_id, b_id], dialogue, source)
		memory["turns"] = turns.duplicate(true)
		memory["heard_from"] = speaker.id
		memory["heard_text"] = heard
		memory["epistemic_status"] = "testimonio_no_verificado"
		_remember(listener, memory)
		listener.known_people[speaker.id] = {
			"name": speaker.name, "last_topic": heard, "last_time": minute,
			"source": source, "memory_id": memory.id, "epistemic_status": "testimonio_no_verificado"
		}
		listener.activity = "Conversando con " + str(speaker.name)
	_log(dialogue)
	_social.note_exchange(a_id, b_id, a_text, b_text, source, "exchange_%d" % _serial)
	social_dialogue.on_exchange(a_id,b_id,a_text,b_text,"exchange_%d" % _serial)
	social_dynamics.note_exchange(a_id,b_id,a_text,b_text,"exchange_%d" % _serial)
	_daily_life.note_dialogue(a_id, b_id)
	return true

func teach(teacher_id: String, learner_id: String) -> String:
	last_error = ""
	var teacher: Dictionary = get_resident(teacher_id)
	var learner: Dictionary = get_resident(learner_id)
	if teacher.is_empty() or learner.is_empty() or teacher_id == learner_id:
		return _failure("Elige a quien enseña y a quien aprende.")
	if is_sleeping(teacher_id) or is_sleeping(learner_id): return _failure("Deben estar despiertos para compartir una receta.")
	if _distance(teacher, learner) >= MAX_DISTANCE:
		return _failure("Deben estar cerca para compartir la receta.")
	if teacher.get("room", "street") != Layout.place_area("cafe") or learner.get("room", "street") != Layout.place_area("cafe") or _point_distance(teacher.pos, PLACES.cafe) >= MAX_DISTANCE or _point_distance(learner.pos, PLACES.cafe) >= MAX_DISTANCE:
		return _failure("Ambos deben estar en el café para enseñar la receta con la tetera.")
	if not teacher.skills.has("preparar_te") or teacher.skills.preparar_te.status != "demostrada":
		return _failure(str(teacher.name) + " todavía no ha demostrado esta receta.")
	if learner.skills.has("preparar_te"):
		return _failure(str(learner.name) + " ya conserva la receta; puede practicarla en el café.")
	var recipe: Dictionary = teacher.skills.preparar_te.duplicate(true)
	recipe["status"] = "instrucciones"
	recipe["source"] = "Enseñanza presencial de " + str(teacher.name)
	recipe["learned_at"] = minute
	recipe["practice_runs"] = 0
	recipe["last_result"] = "Instrucciones recibidas; aún no se ha practicado"
	learner.skills["preparar_te"] = recipe
	var result: String = "%s enseñó a %s a preparar té: llenar tetera, calentar agua, agregar té y servir. Falta practicar en el café." % [teacher.name, learner.name]
	for resident in [teacher, learner]:
		_remember(resident, _memory("enseñanza", [teacher_id, learner_id], result, "enseñanza presencial"))
		resident.activity = "Compartiendo una receta"
	_log(result)
	return result

func practice(id: String) -> String:
	last_error = ""
	var resident: Dictionary = get_resident(id)
	if resident.is_empty():
		return _failure("No existe este habitante.")
	if is_sleeping(id): return _failure("Despierta antes de practicar.")
	if not resident.skills.has("preparar_te"):
		return _failure(str(resident.name) + " necesita aprender la receta con Inés.")
	if resident.get("room", "street") != Layout.place_area("cafe") or _point_distance(resident.pos, PLACES.cafe) >= MAX_DISTANCE:
		return _failure("Ve al café para usar la tetera y los ingredientes.")
	var recipe: Dictionary = resident.skills.preparar_te
	if not _valid_recipe(recipe):
		return _failure("La receta no contiene los pasos e ingredientes correctos.")
	for ingredient in RECIPE_INGREDIENTS:
		if supplies.get(ingredient, 0) < RECIPE_INGREDIENTS[ingredient]:
			return _failure("Falta " + ingredient + " en el café.")
	# Execute the allowed recipe in order; its preconditions and effects belong to the world.
	var state: Dictionary = {"water": false, "hot": false, "infused": false, "served": false}
	for step in recipe.steps:
		match step:
			"llenar_tetera": state.water = true
			"calentar_agua": state.hot = state.water
			"agregar_te": state.infused = state.hot
			"servir": state.served = state.infused
	if not state.served:
		return _failure("La práctica no completó los pasos necesarios.")
	for ingredient in RECIPE_INGREDIENTS:
		supplies[ingredient] -= RECIPE_INGREDIENTS[ingredient]
	recipe.status = "demostrada"
	recipe.practice_runs = int(recipe.get("practice_runs", 0)) + 1
	recipe.last_result = "Cuatro pasos verificados; una taza preparada"
	var result: String = "%s preparó té: 4 pasos verificados. La receta queda guardada (práctica %d)." % [resident.name, recipe.practice_runs]
	var memory: Dictionary = _memory("practica", [id], result, "ejecución verificada por el mundo")
	memory["steps_completed"] = RECIPE_STEPS.duplicate()
	memory["ingredients_consumed"] = RECIPE_INGREDIENTS.duplicate()
	_remember(resident, memory)
	resident.activity = "Preparó una taza de té"
	_log(result)
	return result

func context_for(id: String, partner_id: String = "", query: String = "", scene_override: Dictionary = {}) -> Dictionary:
	var resident: Dictionary = get_resident(id)
	if resident.is_empty() or not is_present(id):
		return {}
	if partner_id == id or (not partner_id.is_empty() and (get_resident(partner_id).is_empty() or not is_present(partner_id))):
		return {}
	var terms: Array[String] = _query_terms(query)
	var mentioned: Array[String] = []
	var folded_query: String = _fold_text(query.left(1000))
	for other in active_residents():
		if other.id != id and (folded_query.contains(_fold_text(str(other.name))) or other.id in terms): mentioned.append(other.id)
	var recent: Array[Dictionary] = []
	var recent_ids: Dictionary = {}
	var candidates: Array[Dictionary] = []
	var history: Array = resident.memories
	var index_data: Dictionary = _memory_index.get(id, {})
	if not partner_id.is_empty():
		for memory in index_data.get("recent_by_partner", {}).get(partner_id, []):
			if id not in memory.get("participants", []): continue
			recent.append(_compact_memory(social_knowledge.filter_memory(id,partner_id,memory), [], 975))
			recent_ids[memory.id] = true
	# Conversation input cost is independent of the total persisted history.
	for index in range(history.size() - 1, maxi(-1, history.size() - 301), -1):
		var memory: Dictionary = history[index]
		if id not in memory.get("participants", []): continue
		var same_pair: bool = partner_id.is_empty() or partner_id in memory.participants
		if same_pair and memory.kind == "conversacion" and recent.size() < 4 and not recent_ids.has(memory.id):
			recent.push_front(_compact_memory(social_knowledge.filter_memory(id,partner_id,memory), [], 975))
			recent_ids[memory.id] = true
			continue
		var useful: bool = memory.kind in ["enseñanza", "practica"]
		var text_to_match: String = _fold_text(str(memory.get("content", "")) + " " + str(memory.get("heard_text", "")) + " " + str(memory.get("heard_from", "")))
		var lexical_score: int = 0
		for term in terms:
			if text_to_match.contains(term): lexical_score += 20
		for person_id in mentioned:
			if person_id in memory.participants: lexical_score += 30
		if not same_pair and not useful and lexical_score == 0: continue
		var score: int = (5 if same_pair else 0) + (4 if useful else 0) + lexical_score
		candidates.append({"memory": memory, "score": score, "order": index})
	candidates.sort_custom(func(a, b): return a.score > b.score if a.score != b.score else a.order > b.order)
	var relevant: Array[Dictionary] = []
	var selected: Dictionary = recent_ids.duplicate()
	# Anchors survive a full recent window without sending old transcripts wholesale.
	for person_id in mentioned:
		var mentioned_anchor: Dictionary = index_data.get("first_by_partner", {}).get(person_id, {})
		_add_context_memory(relevant, selected, mentioned_anchor, terms, id, partner_id)
	if not partner_id.is_empty():
		var anchor: Dictionary = index_data.get("first_by_partner", {}).get(partner_id, {})
		_add_context_memory(relevant, selected, anchor, terms, id, partner_id)
	var latest_teaching: Dictionary = index_data.get("latest_teaching", {})
	_add_context_memory(relevant, selected, latest_teaching, terms, id, partner_id)
	for candidate in candidates:
		if relevant.size() == 4: break
		_add_context_memory(relevant, selected, candidate.memory, terms, id, partner_id)
	var known: Dictionary = {}
	for person_id in resident.known_people:
		if not partner_id.is_empty() and person_id != partner_id: continue
		if known.size() == 5: break
		var person: Dictionary = resident.known_people[person_id]
		known[person_id] = {"name": str(person.get("name", "")).left(80),
			"last_topic": social_knowledge.filter_text(id,partner_id,str(person.get("last_topic", ""))).left(240), "last_time": person.get("last_time", 0),
			"source": str(person.get("source", "")).left(80), "memory_id": str(person.get("memory_id", "")).left(80)}
	var compact_skills: Dictionary = {}
	for skill_id in resident.skills:
		if compact_skills.size() == 5: break
		var skill: Dictionary = resident.skills[skill_id]
		compact_skills[str(skill_id).left(80)] = {"status": str(skill.get("status", "")).left(40),
			"steps": skill.get("steps", []).slice(0, 8), "source": str(skill.get("source", "")).left(100),
			"practice_runs": skill.get("practice_runs", 0)}
	var observations: Array[Dictionary] = []
	for other in active_residents():
		if other.id != id and _distance(resident, other) < MAX_DISTANCE:
			observations.append({"id": other.id, "name": str(other.name).left(80), "room": other.get("room", "street"), "pos": other.pos.duplicate(), "activity": str(other.activity).left(100)})
	observations.sort_custom(func(a,b): return _point_distance(resident.pos,a.pos) < _point_distance(resident.pos,b.pos) if _point_distance(resident.pos,a.pos) != _point_distance(resident.pos,b.pos) else str(a.id) < str(b.id))
	observations = observations.slice(0,5)
	var personality: Array[String] = []
	for item in resident.personality.slice(0, 8): personality.append(str(item).left(48))
	var pair_members: Array[String] = [id, partner_id]
	pair_members.sort()
	var scene: Dictionary = conversation_scene_for(id) if scene_override.is_empty() else ConversationScene.compact(scene_override)
	# A private decision keeps its own history; disclosure applies only to a listener.
	var profile: Dictionary = visible_profile_for(id, id if partner_id.is_empty() else partner_id)
	var context: Dictionary = {
		"mode": "local", "minute": minute, "partner_id": partner_id,
		"pair_id": ":".join(pair_members) if not partner_id.is_empty() else "",
		"identity": {"id": resident.id, "name": str(resident.name).left(80),
			"role": str(resident.get("role", "")).left(80), "biography": profile.biography, "personality": personality, "goal": profile.goal},
		"pos": resident.pos.duplicate(), "activity": str(resident.activity).left(100),
		"room": resident.get("room", "street"), "home_id": resident.get("home_id", ""),
		"routine": str(resident.get("routine", "")).left(100), "routine_place": str(resident.get("routine_place", "")).left(40),
		"conversation_scene": scene,
		"recent_conversation": recent, "memories": relevant, "known_people": known,
		"skills": compact_skills, "observations": observations, "allowed_actions": allowed_actions_for(id),
		"memory_policy": "Solo experiencias propias; los testimonios no son hechos verificados."
	}
	context["social_context"] = social_knowledge.context_for(id,partner_id,query)
	context["settlement"] = settlement.context_for(id)
	context.settlement.cooperation_available = "colaborar" in context.allowed_actions
	var relationship: Dictionary = relationship_for(id, partner_id)
	if not relationship.is_empty(): context["relationship"] = relationship
	if id == "player": context["progression"] = _progression.compact_context()
	# Enforce the transport budget even for escaped or unusually long user text.
	while JSON.stringify(context).length() > 12000:
		if relevant.size() > 1: relevant.pop_back()
		elif not observations.is_empty(): observations.pop_back()
		elif known.size() > 1: known.erase(known.keys().back())
		elif compact_skills.size() > 1: compact_skills.erase(compact_skills.keys().back())
		elif str(context.identity.biography).length() > 300 or str(context.identity.goal).length() > 100:
			context.identity.biography = _head_tail(str(context.identity.biography), 300)
			context.identity.goal = _head_tail(str(context.identity.goal), 100)
		elif recent.size() > 1: recent.pop_front()
		elif not context.social_context.get("claims",[]).is_empty(): context.social_context.claims.pop_back()
		else:
			break
	return context

func _query_terms(query: String) -> Array[String]:
	var normalized: String = _fold_text(query.left(1000))
	for punctuation in [".", ",", ":", ";", "¿", "?", "¡", "!", "\n", "\t", "(", ")", "\"", "'"]:
		normalized = normalized.replace(punctuation, " ")
	var terms: Array[String] = []
	for term in normalized.split(" ", false):
		if term.length() >= 4 and term not in terms: terms.append(term)
		if terms.size() == 16: break
	return terms

func _fold_text(value: String) -> String:
	return value.to_lower().replace("á", "a").replace("é", "e").replace("í", "i").replace("ó", "o").replace("ú", "u").replace("ü", "u")

func _excerpt(value: String, terms: Array[String], limit: int) -> String:
	var start: int = 0
	for term in terms:
		var found: int = _fold_text(value).find(term)
		if found >= 0:
			start = maxi(0, found - 40)
			break
	return ("…" if start > 0 else "") + value.substr(start, limit)

func _compact_memory(memory: Dictionary, terms: Array[String], budget: int) -> Dictionary:
	var result: Dictionary = {"id": str(memory.get("id", "")).left(80), "kind": str(memory.get("kind", "")).left(40),
		"origin": str(memory.get("origin", "")).left(80), "participants": memory.get("participants", []).slice(0, 6),
		"minute": memory.get("minute", 0), "time": str(memory.get("time", "")).left(60),
		"epistemic_status": str(memory.get("epistemic_status", "experiencia_propia")).left(40)}
	var turns: Array[Dictionary] = []
	if memory.get("kind") == "conversacion": turns = _conversation_turns(memory)
	var limit: int = 240 if budget > 700 else 100
	while true:
		if turns.size() == 2:
			# Preserve each speaker and the closing question, even after a long opening.
			var voices: Array[String] = []
			for turn in turns:
				var excerpt: String = _excerpt(str(turn.text), terms, limit) if budget <= 700 and not terms.is_empty() else _head_tail(str(turn.text), limit)
				voices.append(str(turn.name).left(40) + ": " + excerpt)
			result["content"] = "\n".join(voices)
			result["heard_text"] = _head_tail(str(memory.get("heard_text", "")), mini(limit, 80))
		else:
			var recent_dialogue: bool = budget > 700 and memory.get("kind") == "conversacion"
			result["content"] = _head_tail(str(memory.get("content", "")), limit * 2) if recent_dialogue else _excerpt(str(memory.get("content", "")), terms, limit)
			result["heard_text"] = _head_tail(str(memory.get("heard_text", "")), mini(limit, 80)) if recent_dialogue else _excerpt(str(memory.get("heard_text", "")), terms, limit)
		result["heard_from"] = str(memory.get("heard_from", "")).left(40)
		if JSON.stringify(result).length() <= budget or limit <= 10: break
		limit = maxi(10, limit - 20)
	return result

func _head_tail(value: String, limit: int) -> String:
	if value.length() <= limit: return value
	var head_size: int = maxi(0, int((limit - 1) / 2))
	return value.left(head_size) + "…" + value.right(maxi(0, limit - head_size - 1))

func _conversation_turns(memory: Dictionary) -> Array[Dictionary]:
	var turns: Array[Dictionary] = []
	if memory.get("turns") is Array and memory.turns.size() == 2:
		for turn in memory.turns:
			if not turn is Dictionary or not turn.get("name") is String or not turn.get("text") is String: return []
			turns.append(turn)
		return turns
	# Existing saves keep their original transcript. Recover its two speaker labels
	# without changing the saved memory or granting anyone a new experience.
	var participants: Array = memory.get("participants", [])
	if participants.size() != 2: return turns
	var content: String = str(memory.get("content", ""))
	var partner: Dictionary = get_resident(str(participants[1]))
	var delimiter: String = "\n" + str(partner.get("name", "")) + ": "
	var split: int = content.find(delimiter)
	var first_label: int = content.find(": ")
	if split < 0 or first_label < 0 or first_label >= split: return turns
	turns.append({"speaker_id": participants[0], "name": content.left(first_label), "text": content.substr(first_label + 2, split - first_label - 2)})
	turns.append({"speaker_id": participants[1], "name": partner.name, "text": content.substr(split + delimiter.length())})
	return turns

func _add_context_memory(output: Array[Dictionary], selected: Dictionary, memory: Dictionary, terms: Array[String], owner_id: String, listener_id: String = ""):
	if memory.is_empty() or output.size() == 4 or selected.has(memory.get("id")): return
	if owner_id not in memory.get("participants", []): return
	output.append(_compact_memory(social_knowledge.filter_memory(owner_id,listener_id,memory), terms, 610))
	selected[memory.id] = true

func _remember(resident: Dictionary, memory: Dictionary):
	resident.memories.append(memory)
	_index_memory(resident.id, memory)
	social_knowledge.note_world_memory(str(resident.id),memory)
	social_dynamics.note_world_memory(str(resident.id),memory)

func _index_memory(owner_id: String, memory: Dictionary):
	if owner_id not in memory.get("participants", []): return
	if memory.get("kind") == "conversacion": _local_chat_times[owner_id] = maxi(int(_local_chat_times.get(owner_id, 0)), int(memory.get("minute", 0)))
	if not _memory_index.has(owner_id): _memory_index[owner_id] = {"first_by_partner": {}, "latest_teaching": {}, "recent_by_partner": {}, "completed_by_partner": {}, "observed_items": {}}
	var index: Dictionary = _memory_index[owner_id]
	if memory.get("kind") == "objeto" and memory.has("object_key"): index.observed_items[memory.object_key] = true
	for participant in memory.participants:
		if participant != owner_id and not index.first_by_partner.has(participant):
			index.first_by_partner[participant] = memory
		if participant != owner_id and memory.get("kind") == "conversacion":
			if memory.get("social_outcome", "completed") != "rejected":
				index.completed_by_partner[participant] = int(index.completed_by_partner.get(participant, 0)) + 1
			if not index.recent_by_partner.has(participant): index.recent_by_partner[participant] = []
			index.recent_by_partner[participant].append(memory)
			if index.recent_by_partner[participant].size() > 4: index.recent_by_partner[participant].pop_front()
	if memory.get("kind") == "enseñanza": index.latest_teaching = memory

func apply_decision(id: String, action: String) -> bool:
	last_error = ""
	var resident: Dictionary = get_resident(id)
	if not is_present(id) or resident.is_empty() or action not in ACTIONS:
		_failure("Acción o habitante no permitido.")
		return false
	if id in conversation_holds:
		return _save_failure("Este habitante está reservado para una conversación en curso.")
	if is_sleeping(id): return _save_failure("Este habitante está durmiendo.")
	if settlement_jobs.busy(id): return _save_failure("Este habitante está atendiendo un compromiso.")
	if action == "colaborar":
		var task_id: String = settlement_jobs.autonomous_offer(id)
		if task_id.is_empty(): return false
		return bool(settlement_jobs.request(id,task_id).ok)
	if PLACES.has(action):
		if not area_open(Layout.place_area(action)): return _save_failure("Ese camino todavía está cerrado.")
		_decision_marks[id] = minute
		_decision_dirty[id] = false
		_set_destination(resident, action)
		resident.activity = "Camino a " + {"plaza": "la plaza", "cafe": "el café", "taller": "el taller", "huerto": "el huerto"}[action]
		_daily_life.prioritize(id, action)
		return true
	match action:
		"descansar":
			_set_destination(resident, "descansar")
			resident.activity = "Volviendo a casa" if resident.get("home_id", "") != "" else "Descansando"
		"conversar":
			var nearby: Dictionary = _nearest(resident, id != "player")
			if nearby.is_empty():
				_failure("No hay nadie lo bastante cerca para conversar.")
				return false
			converse(id, nearby.id)
		"practicar": practice(id)
	if last_error.is_empty():
		_decision_marks[id] = minute
		_decision_dirty[id] = false
		_daily_life.prioritize(id, action)
	return last_error.is_empty()

func save_game() -> bool:
	last_error = ""
	var payload: Dictionary = {"version": VERSION, "world_revision": WORLD_REVISION, "minute": minute, "turn": _turn, "serial": _serial,
		"residents": residents, "events": events, "supplies": supplies, "event_day": _last_event_day + 1, "progression": _progression.snapshot(), "settlement":settlement.snapshot(), "social_knowledge":social_knowledge.snapshot(), "environment":environment.snapshot()}
	if not _valid_save(payload):
		return _save_failure("El estado actual no es válido para guardar.")
	# A failed load must never allow autosave to silently replace the original file.
	if FileAccess.file_exists(save_path):
		var old = _parse_json(FileAccess.get_file_as_string(save_path))
		if not _valid_save(old):
			return _save_failure("Guardado rechazado: existe una partida dañada; se conserva intacta.")
	var temporary: String = save_path + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _save_failure("No se pudo escribir el archivo temporal.")
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return _save_failure("No se pudo completar el guardado temporal.")
	if FileAccess.file_exists(save_path):
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(save_path + ".bak")) != OK:
			return _save_failure("No se pudo conservar la copia de seguridad.")
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(save_path)) != OK:
		return _save_failure("No se pudo reemplazar la partida de forma atómica.")
	return true

func load_game() -> bool:
	last_error = ""
	conversation_holds.clear()
	if not FileAccess.file_exists(save_path):
		return _save_failure("No hay una partida guardada.")
	var file = FileAccess.open(save_path, FileAccess.READ)
	if file == null or file.get_length() > 16 * 1024 * 1024:
		return _save_failure("La partida no se puede leer o es demasiado grande.")
	var payload = _parse_json(file.get_as_text())
	file.close()
	if not _valid_save(payload):
		return _save_failure("La partida está dañada o usa una versión incompatible.")
	residents.assign(payload.residents)
	minute = int(payload.minute)
	if payload.has("settlement"): settlement.restore(payload.settlement)
	else: settlement.setup(self,true)
	_memory_index.clear()
	_local_chat_times.clear()
	_visit_permissions.clear()
	_room_revisions.clear()
	_routine_keys.clear()
	_decision_marks.clear()
	_decision_dirty.clear()
	_energy_previous_position.clear()
	_energy_previous_room = ""
	for resident in residents:
		if not resident.has("room"): resident["room"] = "street"
		if not resident.has("home_id") or resident.id == "player": resident["home_id"] = resident.id
		if not resident.has("travel_intent"): resident["travel_intent"] = ""
		if not resident.has("schedule"): resident["schedule"] = _default_schedules.get(resident.id, []).duplicate(true)
		if resident.id == "player" and resident.schedule.is_empty(): resident.schedule = PLAYER_SCHEDULE.duplicate(true)
		if not resident.has("routine"): resident["routine"] = "Comenzando el día"
		if resident.id == "player": resident["energy"] = float(resident.get("energy", 100.0))
		# Old saves retain their real location; only blocked ground is recovered.
		var recovered: Vector2 = Navigation.recover_position(Layout.point(resident.pos), resident.room)
		if recovered != Layout.point(resident.pos):
			resident.pos = [recovered.x, recovered.y]
			if is_sleeping(resident.id): resident.target = resident.pos.duplicate()
		if int(payload.get("world_revision", 1)) < WORLD_REVISION:
			resident.erase("travel_route")
			if not is_sleeping(resident.id) and resident.id != "player" and not str(resident.travel_intent).is_empty():
				_set_destination(resident, resident.travel_intent)
			elif not Navigation.is_walkable(Layout.point(resident.target), resident.room):
				resident.target = resident.pos.duplicate()
		elif resident.has("travel_route"):
			_route_leg(resident)
		for memory in resident.memories: _index_memory(resident.id, memory)
		for key in resident.appearance:
			resident.appearance[key] = int(resident.appearance[key])
	events.assign(payload.events)
	minute = int(payload.minute)
	_turn = int(payload.turn)
	_serial = int(payload.serial)
	_last_event_day = int(payload.get("event_day", 0)) - 1
	supplies = payload.supplies.duplicate(true)
	if payload.has("progression"):
		_progression.restore(payload.progression)
	else:
		_progression.reset()
	var player_journey: Dictionary = get_resident("player").get("travel_route", {}).duplicate(true) if str(get_resident("player").get("travel_intent", "")).is_empty() else {}
	set_player_autonomy(false)
	# Manual click travel is distinct from opting into autonomous decisions.
	if not player_journey.is_empty() and not is_sleeping("player"):
		get_resident("player")["travel_route"] = player_journey
		_route_leg(get_resident("player"))
	environment.setup(self)
	if payload.has("environment"): environment.restore(payload.environment)
	_daily_life.setup(self)
	_social.setup(self, true)
	settlement_jobs.setup(self)
	social_knowledge.setup(self)
	if payload.has("social_knowledge"): social_knowledge.restore(payload.social_knowledge)
	social_dialogue.setup(self)
	social_dynamics.setup(self)
	ensure_exhaustion()
	return true

func _parse_json(content: String) -> Variant:
	var parser = JSON.new()
	if parser.parse(content) != OK:
		return null
	return parser.data

func _valid_save(payload: Variant) -> bool:
	if not payload is Dictionary or payload.get("version") != VERSION:
		return false
	for key in ["minute", "turn", "serial"]:
		if not _whole_number(payload.get(key)):
			return false
	if payload.has("event_day") and not _whole_number(payload.event_day): return false
	if payload.has("world_revision") and (not _whole_number(payload.world_revision) or payload.world_revision < 1 or payload.world_revision > WORLD_REVISION): return false
	if payload.has("progression") and not _progression.validate(payload.progression): return false
	if payload.has("settlement") and not settlement.validate(payload.settlement): return false
	if payload.has("social_knowledge") and not social_knowledge.validate(payload.social_knowledge,int(payload.minute)): return false
	if payload.has("environment") and not environment.validate(payload.environment,int(payload.minute),payload.get("settlement",{})): return false
	if not payload.get("residents") is Array or payload.residents.size() != RESIDENT_IDS.size():
		return false
	if not payload.get("events") is Array or payload.events.size() > 500:
		return false
	for event in payload.events:
		if not event is String: return false
	if not payload.get("supplies") is Dictionary: return false
	for ingredient in RECIPE_INGREDIENTS:
		if not _whole_number(payload.supplies.get(ingredient)): return false
	var seen: Array[String] = []
	for resident in payload.residents:
		if not resident is Dictionary or resident.get("id") not in RESIDENT_IDS or resident.id in seen: return false
		seen.append(resident.id)
		for key in ["name", "role", "biography", "goal", "activity"]:
			if not resident.get(key) is String: return false
		if not resident.get("personality") is Array: return false
		for personality_item in resident.personality:
			if not personality_item is String: return false
		for key in ["pos", "target"]:
			if not _valid_point(resident.get(key)): return false
		if resident.has("room") and (not resident.room is String or (not Layout.is_outdoor(resident.room) and resident.room not in RESIDENT_IDS)): return false
		if payload.has("settlement") and payload.settlement.inhabitants[resident.id].present:
			var physical_room: String = str(resident.get("room","street"))
			if _outdoor_for(physical_room) not in payload.settlement.areas: return false
			if not Layout.is_outdoor(physical_room) and str(settlement.catalog.home_buildings.get(physical_room,"")) not in payload.settlement.buildings: return false
		if resident.has("travel_route"):
			var journey = resident.travel_route
			if not journey is Dictionary or journey.size() != 2 or not journey.get("room") is String or not _valid_point(journey.get("position")): return false
			if not Layout.is_outdoor(journey.room) and journey.room != resident.get("room", "street"): return false
			if not Navigation.is_walkable(Layout.point(journey.position), journey.room): return false
			if not resident.get("sleep", {}) is Dictionary or not resident.get("sleep", {}).is_empty(): return false
		if resident.has("home_id") and resident.home_id != resident.id and not (resident.id == "player" and resident.home_id == ""): return false
		if resident.has("travel_intent") and resident.travel_intent not in ["", "casa", "plaza", "cafe", "taller", "huerto", "descansar"]: return false
		if resident.has("schedule"):
			if not resident.schedule is Array or resident.schedule.size() > 12: return false
			for entry in resident.schedule:
				if not entry is Dictionary or not _whole_number(entry.get("start")) or not _whole_number(entry.get("end")): return false
				if entry.start >= entry.end or entry.end > 1440 or entry.get("place") not in ["plaza", "cafe", "taller", "huerto", "descansar", "casa"] or not entry.get("label") is String: return false
		if resident.has("routine") and not resident.routine is String: return false
		if resident.has("energy") and (resident.id != "player" or not _valid_energy(resident.energy)): return false
		if not Rest.valid_state(resident, int(payload.minute)): return false
		if resident.has("relationships") and not SocialRelationships.validate(resident.relationships, resident.id, int(payload.minute)): return false
		if resident.has("chat_availability") and not SocialRelationships.validate_availability(resident.chat_availability, resident.id, int(payload.minute)): return false
		if not resident.get("appearance") is Dictionary: return false
		for key in ["skin", "hair", "hair_style", "eyes", "beard", "hat", "shirt", "pants"]:
			if not _whole_number(resident.appearance.get(key)) or resident.appearance[key] > 32: return false
		if not resident.get("memories") is Array: return false
		for memory in resident.memories:
			if not memory is Dictionary: return false
			for key in ["id", "kind", "origin", "content", "time"]:
				if not memory.get(key) is String: return false
			if not memory.get("participants") is Array or resident.id not in memory.participants: return false
			for participant in memory.participants:
				if participant not in RESIDENT_IDS: return false
			if not _whole_number(memory.get("minute")) or not _whole_number(memory.get("day")): return false
			if memory.has("turns"):
				if memory.kind != "conversacion" or not memory.turns is Array or memory.turns.size() != 2 or memory.participants.size() != 2: return false
				for turn_index in range(2):
					var turn = memory.turns[turn_index]
					if not turn is Dictionary or turn.get("speaker_id") != memory.participants[turn_index]: return false
					if not turn.get("name") is String or not turn.get("text") is String: return false
					if turn.text.strip_edges().is_empty() or turn.text.length() > 1500: return false
		if not resident.get("known_people") is Dictionary or not resident.get("skills") is Dictionary: return false
		for person in resident.known_people:
			if person not in RESIDENT_IDS: return false
			var known = resident.known_people[person]
			if not known is Dictionary or not _whole_number(known.get("last_time")): return false
			for key in ["name", "last_topic", "source", "memory_id"]:
				if not known.get(key) is String: return false
		for skill_id in resident.skills:
			var skill = resident.skills[skill_id]
			if not skill is Dictionary or skill.get("status") not in ["instrucciones", "demostrada"]: return false
			if skill_id == "preparar_te":
				if not _valid_recipe(skill): return false
			elif not _progression.valid_skill(skill_id, skill): return false
			if not _whole_number(skill.get("practice_runs")) or not _whole_number(skill.get("learned_at")): return false
			for key in ["source", "name", "last_result"]:
				if not skill.get(key) is String: return false
	return true

func _valid_recipe(recipe: Dictionary) -> bool:
	var steps = recipe.get("steps")
	var ingredients = recipe.get("ingredients")
	if not steps is Array or steps.size() != RECIPE_STEPS.size(): return false
	for index in range(RECIPE_STEPS.size()):
		if not steps[index] is String or steps[index] != RECIPE_STEPS[index]: return false
	if not ingredients is Dictionary or ingredients.size() != RECIPE_INGREDIENTS.size(): return false
	for item in RECIPE_INGREDIENTS:
		if not _whole_number(ingredients.get(item)) or int(ingredients[item]) != RECIPE_INGREDIENTS[item]: return false
	return true

func _whole_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) == floor(float(value))

func _valid_energy(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= 100.0

func _valid_point(point: Variant) -> bool:
	if not point is Array or point.size() != 2: return false
	for value in point:
		if not (value is int or value is float) or not is_finite(float(value)): return false
	return point[0] >= 20 and point[0] <= 472 and point[1] >= 76 and point[1] <= 292

func _memory(kind: String, participants: Array, content: String, origin: String) -> Dictionary:
	_serial += 1
	return {"id": "memory_%d" % _serial, "kind": kind, "origin": origin, "participants": participants.duplicate(),
		"minute": minute, "day": int(minute / 1440) + 1, "time": _time_label(minute), "content": content}

func _time_label(value: int) -> String:
	return "día %d a las %02d:%02d" % [int(value / 1440) + 1, int(value / 60) % 24, value % 60]

func _nearest(resident: Dictionary, autonomous_only: bool = false, available_only: bool = false) -> Dictionary:
	var nearest: Dictionary = {}
	if resident.get("id", "") in conversation_holds or is_sleeping(resident.get("id", "")): return nearest
	var distance: float = MAX_DISTANCE
	for other in active_residents():
		if other.id == resident.id or other.id in conversation_holds: continue
		if is_sleeping(other.id): continue
		if autonomous_only and other.id == "player" and not player_autonomy: continue
		if available_only and not social_available(other.id): continue
		if relationship_for(resident.id, other.id).cooldown_until > minute or relationship_for(other.id, resident.id).cooldown_until > minute: continue
		var current: float = _distance(resident, other)
		if current < distance:
			distance = current
			nearest = other
	return nearest

func _point_distance(a: Array, b: Array) -> float:
	return Vector2(float(a[0]), float(a[1])).distance_to(Vector2(float(b[0]), float(b[1])))

func _distance(a: Dictionary, b: Dictionary) -> float:
	if not is_present(str(a.get("id",""))) or not is_present(str(b.get("id",""))): return INF
	if a.get("room", "street") != b.get("room", "street"): return INF
	return _point_distance(a.pos, b.pos)

func _log(message: String):
	events.append("[%s] %s" % [_time_label(minute), message])
	if events.size() > 120: events.pop_front()

func _failure(message: String) -> String:
	last_error = message
	return message

func _save_failure(message: String) -> bool:
	last_error = message
	return false
