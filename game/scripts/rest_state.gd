extends RefCounted
## Sleep is physical, persistent simulation state; closing the app advances no time.
const Layout = preload("res://scripts/world_layout.gd")
const MAX_MINUTES := 900
const BED_DISTANCE := 12.0
const EXHAUSTION_SECONDS := 8.0
const EXHAUSTION_RECOVERY := 5.0

static func is_sleeping(world, id: String) -> bool:
	var resident: Dictionary = world.get_resident(id)
	return not resident.is_empty() and resident.get("sleep", {}) is Dictionary and not resident.get("sleep", {}).is_empty()

static func is_exhausted(world) -> bool:
	var player: Dictionary = world.get_resident("player")
	var state = player.get("sleep", {})
	return state is Dictionary and state.get("kind", "") == "exhaustion"

static func ensure_exhaustion(world) -> bool:
	var player: Dictionary = world.get_resident("player")
	if player.is_empty() or is_sleeping(world, "player") or world.player_energy() > 0.0: return false
	player["sleep"] = {"kind":"exhaustion", "remaining":EXHAUSTION_SECONDS}
	player.erase("travel_route")
	player.energy = 0.0
	player.target = player.pos.duplicate()
	player.travel_intent = ""
	player.activity = "Durmiendo por agotamiento"
	return true

static func advance_exhaustion(world, real_seconds: float) -> bool:
	if not is_exhausted(world) or not is_finite(real_seconds) or real_seconds <= 0.0: return false
	var player: Dictionary = world.get_resident("player")
	var remaining: float = maxf(0.0, float(player.sleep.remaining) - minf(EXHAUSTION_SECONDS, real_seconds))
	# Bound floating-point residue without adding an extra frame to eight seconds.
	if remaining > 0.000001:
		player.sleep.remaining = remaining
		return false
	player.erase("sleep")
	player.erase("travel_route")
	player.energy = EXHAUSTION_RECOVERY
	player.target = player.pos.duplicate()
	player.travel_intent = ""
	player.activity = "Recién despierto"
	return true

static func at_bed(resident: Dictionary) -> bool:
	if resident.get("room", "street") != resident.get("id", "") or resident.get("home_id", "") != resident.get("id", ""): return false
	var pos := Layout.point(resident.pos)
	return pos.distance_to(Layout.stand_at("bed", resident.id)) <= BED_DISTANCE and pos.distance_to(Layout.point(resident.target)) <= 2.0

static func begin(world, id: String, duration_minutes: int = 480) -> bool:
	world.last_error = ""
	var resident: Dictionary = world.get_resident(id)
	if resident.is_empty() or not world.is_present(id) or not at_bed(resident):
		world.last_error = "Acércate a tu cama para dormir."
		return false
	if id in world.conversation_holds or is_sleeping(world, id):
		world.last_error = "Termina lo que estás haciendo antes de dormir."
		return false
	if duration_minutes < 5 or duration_minutes > MAX_MINUTES:
		world.last_error = "Elige un descanso de entre cinco minutos y quince horas."
		return false
	resident["sleep"] = {"started": world.minute, "until": world.minute + duration_minutes}
	resident.erase("travel_route")
	resident.target = resident.pos.duplicate()
	resident.travel_intent = ""
	resident.activity = "Durmiendo"
	return true

static func wake(world, id: String) -> bool:
	if not is_sleeping(world, id): return false
	if id == "player" and is_exhausted(world): return false
	var resident: Dictionary = world.get_resident(id)
	resident.erase("sleep")
	resident.erase("travel_route")
	resident.target = resident.pos.duplicate()
	resident.travel_intent = ""
	resident.activity = "Recién despierto"
	return true

static func tick(world, _elapsed: float = 5.0) -> void:
	for resident: Dictionary in world.residents:
		if not world.is_present(resident.id): continue
		if not is_sleeping(world, resident.id): continue
		if resident.id == "player" and is_exhausted(world):
			resident.activity = "Durmiendo por agotamiento"
			continue
		if world.minute >= int(resident.sleep.until) or not at_bed(resident) or resident.id in world.conversation_holds:
			wake(world, resident.id)
		else:
			resident.activity = "Durmiendo"

static func valid_state(resident: Dictionary, minute: int) -> bool:
	if not resident.has("sleep"): return true
	var state = resident.sleep
	if not state is Dictionary: return false
	if state.is_empty(): return true
	if state.size() != 2: return false
	if state.get("kind", "") == "exhaustion":
		var remaining = state.get("remaining")
		var energy = resident.get("energy")
		if resident.get("id", "") != "player" or not (remaining is int or remaining is float) or not is_finite(float(remaining)) or remaining <= 0 or remaining > EXHAUSTION_SECONDS: return false
		if not (energy is int or energy is float) or not is_finite(float(energy)) or energy != 0: return false
		if not resident.get("pos") is Array or not resident.get("target") is Array or resident.pos.size() != 2 or resident.target.size() != 2: return false
		for value in resident.pos + resident.target:
			if not (value is int or value is float) or not is_finite(float(value)): return false
		return resident.pos == resident.target and resident.get("travel_intent", "") == ""
	for key in ["started", "until"]:
		var value = state.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floorf(float(value)) or value < 0: return false
	return state.started <= minute and state.until > minute and state.until - state.started >= 5 and state.until - state.started <= MAX_MINUTES and at_bed(resident)
