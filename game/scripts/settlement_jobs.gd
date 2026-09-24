extends RefCounted
## Physical, resumable commitments. Settlement alone owns materials and rewards.
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Residents = preload("res://scripts/resident_catalog.gd")
const OFFER_INTERVAL := 120
const WORK_DISTANCE := 2.0
var _world: WeakRef
var _next_offer: Dictionary = {}
var _offer_cursor := 0
var autonomous_enabled := true

func setup(world) -> void:
	_world = weakref(world)
	_next_offer.clear()
	_offer_cursor = 0
	for resident: Dictionary in world.residents: Residents.merge_work_profile(resident)

func busy(id: String) -> bool:
	var world = _world.get_ref()
	return world != null and world.settlement.state.get("jobs", {}).has(id)

func _result(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}

func _profile(id: String) -> Dictionary:
	return Residents.work_profile(id)

func _energy(id: String) -> float:
	var world = _world.get_ref()
	return world.player_energy() if id == "player" else float(world.settlement.state.inhabitants.get(id, {}).get("energy", 100.0))

func _category(spec: Dictionary) -> String:
	var world = _world.get_ref()
	var parts: PackedStringArray = str(spec.id).split(":", true, 1)
	match parts[0]:
		"produce": return str(world.settlement.catalog.recipes.get(parts[1], {}).get("kind", "craft"))
		"plant", "tend", "harvest": return "farm"
		"gather": return str(world.settlement.catalog.nodes.get(parts[1], {}).get("kind", "gather"))
	return parts[0]

func _schedule_place(resident: Dictionary, minute: int) -> String:
	var world = _world.get_ref()
	var offset: int = ((world._day_seed(int(minute / 1440), resident.id) % 7) - 3) * 5
	var local: int = posmod(minute - offset, 1440)
	for entry: Dictionary in resident.get("schedule", []):
		if local >= int(entry.start) and local < int(entry.end): return str(entry.place)
	return ""

func _responsibility(resident: Dictionary, spec: Dictionary) -> String:
	var world = _world.get_ref()
	var local: int = posmod(world.minute, 1440)
	for duty: Dictionary in _profile(resident.id).get("responsibilities", []):
		if local < int(duty.start) or local >= int(duty.end): continue
		if str(spec.room) != Layout.place_area(str(duty.place)) or _category(spec) not in duty.get("compatible", []):
			return str(duty.label)
	return ""

func preview(worker: String, task_id: String) -> Dictionary:
	var world = _world.get_ref()
	if world == null or not world.is_present(worker): return _result(false, "Ese vecino todavía no está en el pueblo.")
	var resident: Dictionary = world.get_resident(worker)
	if busy(worker): return _result(false, "Primero hay que terminar o cancelar el trabajo actual.")
	if world.is_sleeping(worker): return _result(false, "Ahora está descansando.")
	if worker in world.conversation_holds or world._daily_life.state_for(worker).get("kind", "") == "speaking": return _result(false, "Terminen la conversación antes de empezar.")
	var offer: Dictionary = world.settlement.offer(task_id, worker)
	if not bool(offer.get("ok", false)): return offer
	var spec: Dictionary = offer.spec
	if not Navigation.is_walkable(Layout.point(spec.at), str(spec.room)): return _result(false, "El lugar de trabajo no tiene un acceso libre.")
	if _energy(worker) < float(spec.get("energy", 0.0)) + (0.01 if worker == "player" else float(_profile(worker).get("reserve_energy", 20.0))):
		return _result(false, "Necesito descansar antes de hacer ese trabajo." if worker != "player" else "Descansa un poco antes de empezar.")
	if worker == "player": return offer
	var profile: Dictionary = _profile(worker)
	if _category(spec) not in profile.get("capabilities", []): return _result(false, "No sé hacer ese trabajo; puedo ayudarte con otra cosa.")
	if _schedule_place(resident, world.minute) in ["casa", "descansar"]: return _result(false, "Ahora necesito mi descanso. Lo vemos más tarde.")
	var duty: String = _responsibility(resident, spec)
	if not duty.is_empty(): return _result(false, "Ahora me toca " + duty + ". Puedo ayudar después.")
	if float(spec.minutes) > float(profile.get("max_minutes", 60)): return _result(false, "Hoy prefiero un trabajo más corto.")
	var relationship: Dictionary = world.relationship_for(worker, "player")
	if float(relationship.get("frustration", 0)) >= 55 or float(relationship.get("tolerance", 100)) < 25 or int(relationship.get("cooldown_until", 0)) > world.minute:
		return _result(false, "Necesito un poco de espacio antes de colaborar.")
	if _category(spec) not in profile.get("interests", []) and float(relationship.get("trust", 0)) < 40:
		return _result(false, "Prefiero ayudar con algo que me interese más.")
	return offer

func request(worker: String, task_id: String) -> Dictionary:
	return _request(worker, task_id, false)

func _request(worker: String, task_id: String, autonomous: bool) -> Dictionary:
	var world = _world.get_ref()
	var offer: Dictionary = preview(worker, task_id)
	if not offer.get("ok", false):
		if not autonomous and worker != "player" and world.is_present(worker) and not busy(worker) and not world.is_sleeping(worker) and worker not in world.conversation_holds and world.settlement.offer(task_id, worker).get("ok", false): _note_refusal(worker, task_id)
		return offer
	var prepared: Dictionary = world.settlement.prepare_task(task_id, worker)
	if not prepared.get("ok", false): return prepared
	var spec: Dictionary = prepared.spec
	var existing_progress: float = float(world.settlement.state.projects.get(task_id.get_slice(":", 1), {}).get("progress", 0.0)) if task_id.begins_with("build:") else 0.0
	var job := {"id": "work-%d" % int(world.settlement.state.serial), "worker": worker, "task_id": task_id,
		"kind": str(spec.kind), "target_room": str(spec.room), "target": spec.at.duplicate(),
		"phase": "travelling", "progress": existing_progress, "required": float(spec.minutes), "started": int(world.minute),
		"escrow": prepared.get("escrow", {}).duplicate(true), "worked": existing_progress > 0.0, "energy": float(spec.get("energy", 0.0))}
	world.settlement.state.jobs[worker] = job
	if not world.travel_to(worker, job.target_room, Layout.point(job.target)):
		world.settlement.cancel_task(job)
		world.settlement.state.jobs.erase(worker)
		return _result(false, "No hay un camino libre hasta ese trabajo.")
	world._daily_life.forget(worker)
	_next_offer[worker] = world.minute + OFFER_INTERVAL
	world.settlement.note_event(worker, str(world.get_resident(worker).name) + " aceptó: " + str(spec.title) + ".")
	_update_label(worker)
	return _result(true, "En camino: " + str(spec.title) + ".")

func _note_refusal(worker: String, task_id: String) -> void:
	var world = _world.get_ref()
	# Only repeated real invitations to the same task exert pressure. Browsing never does.
	var inhabitant: Dictionary = world.settlement.state.inhabitants[worker]
	var request_state: Dictionary = inhabitant.get("requests", {})
	var same: bool = request_state.get("task_id", "") == task_id and world.minute - int(request_state.get("minute", -10000)) < 60
	if same and int(request_state.get("minute", -1)) == world.minute: return
	var count: int = mini(3, int(request_state.get("count", 0)) + 1) if same else 1
	inhabitant.requests = {"task_id": task_id, "minute": int(world.minute), "count": count}
	if count < 3: return
	# Respect the existing directed relationship: no trust reward or invented exchange.
	var relation: Dictionary = world.get_resident(worker).relationships.get("player", {})
	if relation.is_empty(): return
	relation.frustration = minf(100.0, float(relation.frustration) + 4.0)
	relation.tolerance = maxf(0.0, float(relation.tolerance) - 3.0)

func cancel(worker: String) -> Dictionary:
	var world = _world.get_ref()
	if not busy(worker): return _result(false, "No hay un trabajo pendiente.")
	var job: Dictionary = world.settlement.state.jobs[worker]
	world.settlement.cancel_task(job)
	world.settlement.state.jobs.erase(worker)
	world.cancel_travel(worker)
	world._daily_life.forget(worker)
	world._routine_keys.erase(worker)
	world._decision_dirty[worker] = true
	_next_offer[worker] = world.minute + OFFER_INTERVAL
	world.settlement.note_event(worker, str(world.get_resident(worker).name) + " dejó el trabajo para otra ocasión.", "trabajo_cancelado")
	return _result(true, "Trabajo cancelado; los materiales sin usar vuelven al almacén.")

func _returning(job: Dictionary) -> bool:
	return job.worker != "player" and str(job.task_id).get_slice(":", 0) in ["gather", "explore"] and float(job.progress) >= float(job.required) and bool(job.worked)

func _destination(job: Dictionary) -> Dictionary:
	var board: Dictionary = _world.get_ref().settlement.catalog.board
	return {"room": board.area, "at": board.at} if _returning(job) else {"room": job.target_room, "at": job.target}

func _at(resident: Dictionary, destination: Dictionary) -> bool:
	return resident.room == destination.room and Layout.point(resident.pos).distance_to(Layout.point(destination.at)) <= WORK_DISTANCE and Layout.point(resident.pos).distance_to(Layout.point(resident.target)) <= WORK_DISTANCE and not resident.has("travel_route")

func _route(worker: String, destination: Dictionary) -> bool:
	var world = _world.get_ref()
	var person: Dictionary = world.get_resident(worker)
	var journey: Dictionary = person.get("travel_route", {})
	if journey.get("room", "") == destination.room and journey.get("position", []) == destination.at: return true
	return world.travel_to(worker, str(destination.room), Layout.point(destination.at))

func _spend_energy(worker: String, amount: float) -> void:
	var world = _world.get_ref()
	if worker == "player": world.get_resident(worker).energy = maxf(0.0, world.player_energy() - amount)
	else: world.settlement.state.inhabitants[worker].energy = maxf(0.0, _energy(worker) - amount)

func _pause_for_rest(resident: Dictionary) -> void:
	var world = _world.get_ref()
	if resident.room != resident.home_id:
		if resident.get("travel_intent", "") != "casa": world._set_destination(resident, "casa")
		return
	var bed := Layout.stand_at("bed", resident.id)
	if Layout.point(resident.pos).distance_to(bed) > WORK_DISTANCE:
		if not resident.has("travel_route"): world.travel_to(resident.id, resident.home_id, bed)
		return
	var duration := 30
	while duration < 900 and _schedule_place(resident, world.minute + duration) in ["casa", "descansar"]: duration += 5
	world.start_sleep(resident.id, duration)

func tick(elapsed_minutes: float = 5.0) -> void:
	var world = _world.get_ref()
	if world == null or not is_finite(elapsed_minutes) or elapsed_minutes <= 0: return
	for resident: Dictionary in world.active_residents():
		var worker: String = resident.id
		if not busy(worker):
			if worker != "player":
				var resting: bool = world._daily_life.state_for(worker).get("kind", "") in ["idle", "leisure"]
				var rate := 0.25 if world.is_sleeping(worker) else (0.08 if resting else 0.0)
				world.settlement.state.inhabitants[worker].energy = minf(100, _energy(worker) + elapsed_minutes * rate)
			continue
		var job: Dictionary = world.settlement.state.jobs[worker]
		if world.is_sleeping(worker) or worker in world.conversation_holds or world._daily_life.state_for(worker).get("kind", "") == "speaking":
			job.phase = "paused"
			if worker != "player" and world.is_sleeping(worker): world.settlement.state.inhabitants[worker].energy = minf(100, _energy(worker) + elapsed_minutes * 0.25)
			continue
		if worker != "player" and (_schedule_place(resident, world.minute) in ["casa", "descansar"] or _energy(worker) < 10.0):
			job.phase = "paused"
			_pause_for_rest(resident)
			continue
		var destination: Dictionary = _destination(job)
		if not _at(resident, destination):
			job.phase = "returning" if _returning(job) else "travelling"
			_route(worker, destination)
			_update_label(worker)
			continue
		if _returning(job):
			job.phase = "returning"
			_complete(worker, job)
			continue
		if job.phase != "working":
			job.phase = "working"
			_update_label(worker)
			continue
		var remaining: float = maxf(0.0, float(job.required) - float(job.progress))
		var work: float = minf(elapsed_minutes, remaining)
		var cost: float = float(job.energy) * work / maxf(1.0, float(job.required))
		if cost > _energy(worker):
			job.phase = "paused"
			continue
		job.progress = minf(float(job.required), float(job.progress) + work)
		job.worked = bool(job.worked) or work > 0
		_spend_energy(worker, cost)
		if str(job.task_id).begins_with("build:"):
			world.settlement.state.projects[str(job.task_id).get_slice(":", 1)].progress = float(job.progress)
		if float(job.progress) >= float(job.required):
			if _returning(job):
				job.phase = "returning"
				_route(worker, _destination(job))
			else: _complete(worker, job)
		if busy(worker): _update_label(worker)
	if autonomous_enabled: _offer_one()

func _offer_one() -> void:
	var world = _world.get_ref()
	var people: Array = world.active_residents()
	if people.is_empty(): return
	var worker: String = str(people[_offer_cursor % people.size()].id)
	_offer_cursor += 1
	if int(_next_offer.get(worker, 0)) > world.minute: return
	var task_id := autonomous_offer(worker)
	_next_offer[worker] = world.minute + OFFER_INTERVAL
	if not task_id.is_empty(): _request(worker, task_id, true)

func _complete(worker: String, job: Dictionary) -> void:
	var world = _world.get_ref()
	var result: Dictionary = world.settlement.complete_task(job)
	if not result.get("ok", false):
		job.phase = "paused"
		return
	world.settlement.state.jobs.erase(worker)
	world.cancel_travel(worker)
	world._daily_life.forget(worker)
	world._routine_keys.erase(worker)
	world._decision_dirty[worker] = true
	_next_offer[worker] = world.minute + OFFER_INTERVAL

func _update_label(worker: String) -> void:
	var world = _world.get_ref()
	world.get_resident(worker).activity = str(daily_state(worker).get("label", ""))

func daily_state(worker: String) -> Dictionary:
	if not busy(worker): return {}
	var world = _world.get_ref()
	var job: Dictionary = world.settlement.state.jobs[worker]
	var spec: Dictionary = world.settlement.task_spec(job.task_id, worker)
	var title: String = str(spec.get("title", "Trabajo del barrio"))
	var kind: String = "working" if job.phase == "working" else ("leisure" if job.phase == "paused" else "walking")
	var label := title
	if job.phase == "travelling": label = "En camino: " + title
	elif job.phase == "returning": label = "Llevando lo recogido al tablón"
	elif job.phase == "paused": label = "En pausa: " + title
	return {"kind": kind, "action": str(job.kind), "label": label, "source": "settlement", "busy": true,
		"interruptible": true, "social_ready": false, "until": 0, "duration": float(job.required), "progress": float(job.progress), "phase": str(job.phase)}

func autonomous_offer(worker: String) -> String:
	var world = _world.get_ref()
	if worker == "player" or not world.is_present(worker) or busy(worker) or int(_next_offer.get(worker, 0)) > world.minute: return ""
	var state: Dictionary = world._daily_life.state_for(worker)
	if state.get("kind", "") not in ["idle", "leisure"]: return ""
	var candidates: Array[String] = []
	for spec: Dictionary in world.settlement.tasks(worker):
		if not spec.get("ok", false) or not spec.get("inputs", {}).is_empty(): continue
		if str(spec.id).begins_with("build:"):
			var project: Dictionary = world.settlement.state.projects.get(str(spec.id).get_slice(":", 1), {})
			if project.get("status", "") not in ["funded", "building", "in_progress"]: continue
		if _category(spec) not in _profile(worker).get("interests", []): continue
		if preview(worker, spec.id).get("ok", false): candidates.append(spec.id)
	if candidates.is_empty(): return ""
	candidates.sort()
	return candidates[posmod(world._day_seed(int(world.minute / OFFER_INTERVAL), worker), candidates.size())]
