extends RefCounted
## Physical greetings and authored social topics. One local pair at a time;
## only completed, audible exchanges enter memory or transmit knowledge.
const Navigation = preload("res://scripts/navigation.gd")
const Layout = preload("res://scripts/world_layout.gd")
const CHECK_INTERVAL := 0.2
const NEAR := 34.0
const APART := 52.0
const TURN_SECONDS := 2.2
var host: Control
var _elapsed := 0.0
var _clock := 0.0
var _next_at := 2.0
var _contacts: Dictionary = {}
var _active: Dictionary = {}

func _init(owner: Control) -> void:
	host = owner

func _eligible(person: Dictionary) -> bool:
	if not host.colony.is_present(person.id) or host.colony.settlement_jobs.busy(person.id): return false
	if person.id == "player" and not host.colony.player_autonomy: return false
	if person.id in host.colony.conversation_holds or host.colony.is_sleeping(person.id): return false
	if not Layout.is_outdoor(str(person.room)): return false
	if not host.dialogue_job.is_empty() and person.id in [host.dialogue_job.a, host.dialogue_job.b]: return false
	if host.decision_pending and person.id == host.deciding_id: return false
	return host.colony.daily_state(person.id).get("kind", "") not in ["speaking", "sleeping"]

func _key(a: String, b: String) -> String:
	var ids := [a, b]
	ids.sort()
	return ":".join(ids)

func advance(delta: float, sleeping: bool = false) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	_clock += delta
	if sleeping:
		cancel()
		return
	if not _active.is_empty():
		var a: Dictionary = host.colony.get_resident(_active.a)
		var b: Dictionary = host.colony.get_resident(_active.b)
		if not _still_present(a,b):
			cancel()
		elif _clock >= float(_active.until):
			var pair: Dictionary = _active.duplicate(true)
			# Both short turns have actually happened before storing the encounter.
			host.colony.record_dialogue(pair.a, pair.b, pair.first, pair.reply, str(pair.source))
			cancel()
		return
	_elapsed += delta
	if _elapsed < CHECK_INTERVAL: return
	_elapsed = 0.0
	var people: Array = host.colony.active_residents()
	for i in range(people.size()):
		var a: Dictionary = people[i]
		for j in range(i + 1, people.size()):
			var b: Dictionary = people[j]
			var key := _key(a.id, b.id)
			var distance: float = host.position_of(a).distance_to(host.position_of(b))
			if a.room != b.room or distance > APART:
				_contacts.erase(key)
				continue
			if distance > NEAR or _contacts.has(key) or _clock < _next_at: continue
			if not _eligible(a) or not _eligible(b): continue
			# A wall, fence or basin between two people is not a face-to-face meeting.
			if not Navigation._clear_segment(host.position_of(a), host.position_of(b), a.room): continue
			var lines: Dictionary = _social_lines(a,b)
			if not _valid_lines(lines): continue
			_contacts[key] = true
			if lines.get("_reverse",false): _begin(b,a,lines)
			else: _begin(a,b,lines)
			return

func _still_present(a: Dictionary,b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty(): return false
	for person: Dictionary in [a,b]:
		if not host.colony.is_present(person.id) or host.colony.is_sleeping(person.id) or host.colony.settlement_jobs.busy(person.id): return false
		if person.id == "player" and not host.colony.player_autonomy: return false
		if str(person.room) != str(_active.room): return false
		if not host.dialogue_job.is_empty() and person.id in [host.dialogue_job.a,host.dialogue_job.b]: return false
	var first: Vector2 = host.position_of(a)
	var second: Vector2 = host.position_of(b)
	return first.distance_to(second)<host.colony.MAX_DISTANCE and Navigation._clear_segment(first,second,a.room)

func _valid_lines(lines: Dictionary) -> bool:
	for key: String in ["first","reply"]:
		if not lines.get(key) is String or str(lines[key]).strip_edges().is_empty() or str(lines[key]).length()>240: return false
	return true

func _social_lines(a: Dictionary,b: Dictionary) -> Dictionary:
	# A substantial exchange waits for a real pause. Passing people may still
	# greet without abandoning their schedule, sleep, work or explicit routes.
	if host.colony.social_available(a.id) and host.colony.social_available(b.id):
		var planner = host.colony.get("social_dialogue")
		if planner != null and planner.has_method("encounter_pair"):
			var plan: Dictionary = planner.encounter_pair(a.id,b.id)
			if _valid_lines(plan): return plan
			var reverse: Dictionary = planner.encounter_pair(b.id,a.id)
			if _valid_lines(reverse):
				reverse = reverse.duplicate(true)
				reverse["_reverse"] = true
				return reverse
	return host.colony.greeting_pair(a.id,b.id)

func _begin(a: Dictionary, b: Dictionary, lines: Dictionary) -> void:
	var kind: String = str(lines.get("kind","greeting"))
	var turn_seconds: float = TURN_SECONDS if kind=="greeting" else clampf(maxi(str(lines.first).length(),str(lines.reply).length())/22.0,3.5,7.5)
	_active = {"a":a.id,"b":b.id,"first":str(lines.first),"reply":str(lines.reply),"room":a.room,"started":_clock,"until":_clock+turn_seconds*2.0,"turn_seconds":turn_seconds,"kind":kind,"source":"Saludo local" if kind=="greeting" else "Conversación local · "+kind,"plan":lines.duplicate(true),"goals":{}}
	for person: Dictionary in [a, b]:
		_active.goals[person.id] = {"room": person.room, "target": person.target.duplicate(), "intent": person.get("travel_intent", ""), "activity": person.activity, "routine_key":str(host.colony._routine_keys.get(person.id,""))}
		host.colony.conversation_holds.append(person.id)
		person.target = person.pos.duplicate()
		person.travel_intent = ""
		person.activity = ("Saludando a " if kind=="greeting" else "Conversando con ") + str(b.name if person.id == a.id else a.name)
		host.paths.erase(person.id)
	var direction: Vector2 = host.position_of(b) - host.position_of(a)
	host.facing[a.id] = direction
	host.facing[b.id] = -direction
	if host.ambient_thoughts != null: host.ambient_thoughts.silence()

func cancel_for(id: String) -> void:
	if not _active.is_empty() and id in [_active.a, _active.b]: cancel()

func cancel() -> void:
	if _active.is_empty(): return
	for id: String in [_active.a, _active.b]:
		var person: Dictionary = host.colony.get_resident(id)
		var goal: Dictionary = _active.goals[id]
		host.colony.conversation_holds.erase(id)
		if person.room == goal.room and person.target == person.pos and str(person.get("travel_intent", "")).is_empty() and str(host.colony._routine_keys.get(id,"")) == str(goal.get("routine_key","")):
			person.target = goal.target.duplicate()
			person.travel_intent = goal.intent
			person.activity = goal.activity
		host.paths.erase(id)
	_active.clear()
	_next_at = _clock + 8.0

func visible_for(id: String) -> Dictionary:
	if _active.is_empty(): return {}
	var first: bool = _clock - float(_active.started) < float(_active.get("turn_seconds",TURN_SECONDS))
	if id != (_active.a if first else _active.b): return {}
	return {"text": str(_active.first if first else _active.reply), "emoji": "", "alpha": 1.0}

func let_leave(id: String, partner: String) -> void:
	## Release is a route change, never a position change or teleport.
	var person: Dictionary = host.colony.get_resident(id)
	var other: Dictionary = host.colony.get_resident(partner)
	if person.is_empty() or other.is_empty() or not host.colony.is_present(id) or not host.colony.is_present(partner) or host.colony.is_sleeping(id): return
	if person.room != other.room: return
	var point: Vector2 = host.position_of(person)
	var away: Vector2 = host.position_of(other)
	var target: Vector2 = Vector2(person.target[0], person.target[1])
	if target.distance_to(point) >= 18 and target.distance_to(away) > point.distance_to(away): return
	var best: Vector2 = point
	var best_score := -INF
	var directions: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP, Vector2(1,1).normalized(), Vector2(-1,1).normalized(), Vector2(1,-1).normalized(), Vector2(-1,-1).normalized()]
	var occupied: Array[Vector2] = host.crowd.people(person)
	for radius: float in [28.0, 44.0, 60.0]:
		for direction: Vector2 in directions:
			var candidate: Vector2 = (point + direction * radius).round()
			if candidate.distance_to(away) < 45.0 or not Navigation.is_walkable(candidate, person.room): continue
			var clear := true
			for neighbor: Vector2 in occupied:
				if ((candidate-neighbor)/host.CrowdMotion.CLEARANCE).length_squared() < 1.2: clear = false
			if not clear: continue
			var path: Array[Vector2] = Navigation.route(point, candidate, person.room)
			if path.is_empty() or path[-1] != candidate: continue
			var score: float = candidate.distance_to(away) - radius * 0.5
			if score > best_score:
				best_score = score
				best = candidate
	if best != point:
		person.target = [best.x, best.y]
		person.travel_intent = ""
		person.activity = "Tomando un poco de espacio"
		host.paths.erase(id)
