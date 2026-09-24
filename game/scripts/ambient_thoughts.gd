extends RefCounted
## Fleeting presentation, separate from dialogue, memories and world decisions.
const Layout = preload("res://scripts/world_layout.gd")
const VISIBLE_SECONDS := 4.0
const FADE_SECONDS := 0.25
const RESIDENT_COOLDOWN := 44.0
const INITIAL_DELAY := 4.5
var _world: WeakRef
var _clock := 0.0
var _next_at := INITIAL_DELAY
var _active: Dictionary = {}
var _last_at: Dictionary = {}
var _recent: Dictionary = {}
var _sequence := 0
var _room := ""

func _init(world) -> void:
	_world = weakref(world)

func _eligible(resident: Dictionary, room: String) -> bool:
	var world = _world.get_ref()
	if resident.is_empty() or resident.get("room", "street") != room: return false
	if resident.id == "player" and not world.player_autonomy: return false
	if resident.id in world.conversation_holds or world.is_sleeping(resident.id): return false
	return world.daily_state(resident.id).get("kind", "") not in ["speaking", "sleeping"]

func _signature(resident: Dictionary) -> String:
	var world = _world.get_ref()
	var state: Dictionary = world.daily_state(resident.id)
	var weather: Dictionary = world.weather_state()
	return "%s/%s/%s/%s/%s" % [resident.room, state.get("kind", ""), state.get("action", ""), weather.period, weather.feeling]

func silence() -> void:
	_active.clear()
	_next_at = maxf(_next_at, _clock + INITIAL_DELAY)

func advance(real_delta: float, room: String, suppressed: bool = false) -> void:
	if not is_finite(real_delta) or real_delta <= 0.0: return
	_clock += real_delta
	if _room != room:
		_room = room
		silence()
	if suppressed:
		silence()
		return
	var world = _world.get_ref()
	if world == null: return
	if not _active.is_empty():
		var resident: Dictionary = world.get_resident(_active.id)
		if _clock >= float(_active.until) or not _eligible(resident, room) or _signature(resident) != _active.context:
			_active.clear()
		else: return
	if _clock < _next_at: return
	var eligible: Array[Dictionary] = []
	for resident: Dictionary in world.active_residents():
		if _eligible(resident, room) and _clock - float(_last_at.get(resident.id, -RESIDENT_COOLDOWN)) >= RESIDENT_COOLDOWN:
			eligible.append(resident)
	if eligible.is_empty():
		_next_at = _clock + 2.0
		return
	# Give the quietest neighbor a turn; tie order varies with the in-game day.
	eligible.sort_custom(func(a, b):
		var a_last: float = _last_at.get(a.id, -RESIDENT_COOLDOWN)
		var b_last: float = _last_at.get(b.id, -RESIDENT_COOLDOWN)
		if a_last != b_last: return a_last < b_last
		return world._day_seed(world.minute / 1440, a.id) < world._day_seed(world.minute / 1440, b.id))
	var person: Dictionary = eligible.front()
	var choices: Array[Dictionary] = candidates(person.id)
	var recent: Array = _recent.get(person.id, [])
	var fresh: Array[Dictionary] = choices.filter(func(item): return item.text not in recent)
	if not fresh.is_empty(): choices = fresh
	if choices.is_empty(): return
	var index: int = world._day_seed(world.minute / 1440, person.id + str(_sequence)) % choices.size()
	_active = choices[index].duplicate()
	_active.merge({"id": person.id, "started": _clock, "until": _clock + VISIBLE_SECONDS, "context": _signature(person)})
	_last_at[person.id] = _clock
	recent.append(_active.text)
	if recent.size() > 3: recent.pop_front()
	_recent[person.id] = recent
	_sequence += 1
	# Ten to sixteen seconds of quiet after this four-second appearance.
	_next_at = _clock + VISIBLE_SECONDS + 10.0 + (_sequence * 3 % 7)

func visible_for(id: String) -> Dictionary:
	if _active.is_empty() or _active.id != id: return {}
	var world = _world.get_ref()
	if world == null: return {}
	var person: Dictionary = world.get_resident(id)
	if not _eligible(person, _room) or _signature(person) != _active.context: return {}
	var result: Dictionary = _active.duplicate()
	result.alpha = clampf(minf((_clock - float(_active.started)) / FADE_SECONDS, (float(_active.until) - _clock) / FADE_SECONDS), 0.0, 1.0)
	return result if result.alpha > 0.0 else {}

func _line(text: String, emoji: String = "") -> Dictionary:
	return {"text": text, "emoji": emoji}

func candidates(id: String) -> Array[Dictionary]:
	var world = _world.get_ref()
	var resident: Dictionary = world.get_resident(id)
	if resident.is_empty(): return []
	var state: Dictionary = world.daily_state(id)
	var weather: Dictionary = world.weather_state()
	var options: Array[Dictionary] = [
		_line("Mmm, ¿olvidaba algo?"), _line("Una cosa a la vez."),
		_line("Qué bien un respiro."), _line("Hoy voy con calma."),
		_line("Me gustaría un perrito.", "🐶❤️")]
	var by_role: Dictionary = {
		"cesar": ["Ojalá broten pronto.", "Un huertito en casa...", "Extraño el campo."],
		"lupita": ["Una comida entre todos...", "¿A quién invitaría?", "Me gusta este barrio."],
		"mateo": ["Todo tiene su arreglo.", "Paso a paso sale mejor.", "Me gusta enseñar."],
		"ines": ["Se me antoja un té.", "¿Canela o hierbabuena?", "Qué gusto compartir."],
		"alma": ["Eso quedaría en un dibujo.", "Tengo una idea...", "Qué colores tan bonitos."]}
	for thought: String in by_role.get(id, []): options.append(_line(thought))
	var personality: Array = resident.get("personality", [])
	if "curiosa" in personality or "curioso" in personality: options.append(_line("¿Y si pruebo algo nuevo?", "✨"))
	if "sociable" in personality: options.append(_line("Qué ganas de ver amigos.", "❤️"))
	if "paciente" in personality: options.append(_line("Sin prisa sale mejor."))
	var task_lines: Dictionary = {
		"water": "Un poquito de agua...", "check_soil": "A ver esta tierrita...",
		"repair": "A ver si ahora gira.", "sort_tools": "Cada cosa en su lugar.",
		"serve": "Con cariño sabe mejor.", "tidy_cups": "Que todo quede listo.",
		"sketch": "Le falta un detalle...", "plan_meeting": "¿Y si comemos juntos?",
		"drink": "Justo lo que quería."}
	if state.get("kind", "") in ["working", "eating"] and task_lines.has(state.get("action", "")):
		options.append(_line(task_lines[state.action]))
	if Layout.is_outdoor(str(resident.room)):
		if weather.feeling == "calor" and weather.daylight: options.append(_line("Qué calor hace hoy.", "☀️"))
		elif weather.feeling == "fresco": options.append(_line("Está fresco afuera."))
		if weather.period == "mañana": options.append(_line("Todavía es temprano."))
		elif weather.period == "tarde": options.append(_line("Ya cae la tarde."))
		elif weather.period == "noche": options.append(_line("Qué tranquila la noche.", "🌙"))
		var point := Vector2(resident.pos[0], resident.pos[1])
		if Layout.place_area("huerto") == resident.room and point.distance_to(Vector2(world.PLACES.huerto[0], world.PLACES.huerto[1])) < 40:
			options.append(_line("Me alegra ver las plantas.", "🌱"))
		if Layout.place_area("cafe") == resident.room and point.distance_to(Vector2(world.PLACES.cafe[0], world.PLACES.cafe[1])) < 40:
			options.append(_line("Se me antoja un cafecito.", "☕"))
	elif resident.room == resident.home_id:
		options.append(_line("Qué a gusto en casa."))
	return options
