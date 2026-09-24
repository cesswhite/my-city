extends RefCounted
## Authoritative town transactions. Text generation never writes this state.
const Catalog = preload("res://scripts/settlement_catalog.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
var catalog: Dictionary = Catalog.data()
var state: Dictionary = {}
var _world: WeakRef

func setup(world, developed: bool = false) -> void:
	_world = weakref(world)
	state = {"version":1,"revision":0,"areas":catalog.initial.areas.duplicate(),"buildings":catalog.initial.buildings.duplicate(),
		"inhabitants":{},"projects":{},"nodes":{},"plots":{},"discoveries":[],"jobs":{},"receipts":{},"orders":{},"sales":{},"serial":0}
	for resident in world.residents:
		state.inhabitants[resident.id] = {"present":resident.id in catalog.initial.residents,"arrived_at":world.minute,"energy":100.0,"requests":{}}
	if developed:
		for id in state.inhabitants: state.inhabitants[id].present = true
		for id in catalog.projects:
			if id in ["forest_path","storage_upgrade","garden_upgrade","community_hall"]: continue
			var data: Dictionary = catalog.projects[id]
			state.projects[id] = {"status":"completed","progress":float(data.minutes)}
			if not str(data.building).is_empty() and data.building not in state.buildings: state.buildings.append(data.building)
			if not str(data.opens).is_empty() and data.opens not in state.areas: state.areas.append(data.opens)
			if not str(data.discovery).is_empty() and data.discovery not in state.discoveries: state.discoveries.append(data.discovery)
	else:
		world._progression.state.coins = int(catalog.initial.coins)
		# Existing personal learning items are retained; community materials start empty.
		for id in catalog.resources: world._progression.state.inventory.erase(id)
		world._progression._add_items(catalog.initial.items)
		for resident in world.residents:
			if not is_present(resident.id): continue
			if not area_open(world._outdoor_for(resident.room)):
				resident.room = Layout.home_area(resident.id)
				resident.pos = Layout.data().doors[resident.id].duplicate()
				resident.target = resident.pos.duplicate()

func snapshot() -> Dictionary:
	return state.duplicate(true)

func view() -> Dictionary:
	var result: Dictionary = snapshot()
	result["minute"] = _world.get_ref().minute
	return result

func restore(value: Dictionary) -> void:
	state = value.duplicate(true)

func is_present(id: String) -> bool:
	return bool(state.get("inhabitants", {}).get(id, {}).get("present", false))

func area_open(id: String) -> bool:
	return id in state.get("areas", [])

func building_ready(id: String) -> bool:
	return id in state.get("buildings", [])

func _done(id: String) -> bool:
	return id.is_empty() or state.projects.get(id, {}).get("status", "") == "completed"

func _requirements(data: Dictionary) -> String:
	var required = data.get("requires", [])
	if required is String: required = [] if required.is_empty() else [required]
	for id in required:
		if not _done(id): return "Primero: %s." % catalog.projects[id].title
	var discovery: String = str(data.get("discovery", ""))
	if not discovery.is_empty() and discovery not in state.discoveries: return "Explora primero este camino."
	if data.has("relationship"):
		var relation: Dictionary = data.relationship
		var current: Dictionary = _world.get_ref().relationship_for(relation.id, "player")
		if float(current.get("trust",0)) < float(relation.trust): return "Gana la confianza de %s (%d)." % [_world.get_ref().get_resident(relation.id).name, relation.trust]
	return ""

func task_spec(task_id: String, _worker: String = "player") -> Dictionary:
	var parts: PackedStringArray = task_id.split(":", false, 1)
	if parts.size() != 2: return {}
	var verb: String = parts[0]
	var key: String = parts[1]
	var table: String = {"gather":"nodes","produce":"recipes","build":"projects","explore":"explorations","plant":"plots","tend":"plots","harvest":"plots"}.get(verb, "")
	if table.is_empty() or not catalog[table].has(key): return {}
	var data: Dictionary = catalog[table][key].duplicate(true)
	data["key"] = key
	data["id"] = task_id
	data["verb"] = verb
	data["room"] = data.area
	data["kind"] = "build" if verb == "build" else "farm" if verb in ["plant","tend","harvest"] else str(data.get("kind", verb))
	data["energy"] = float(data.get("energy", 5.0))
	data["inputs"] = data.get("inputs", {}).duplicate(true)
	data["outputs"] = data.get("outputs", {}).duplicate(true)
	if verb == "gather": data.outputs = {data.resource:int(data.quantity)}
	if verb == "plant":
		data.inputs = data.seed.duplicate(true)
		data.outputs = {}
		data.title = "Sembrar · " + str(data.title)
	if verb == "tend":
		data.minutes = 10
		data.outputs = {}
		data.title = "Regar · " + str(data.title)
	if verb == "harvest":
		data.minutes = 10
		data.title = "Cosechar · " + str(data.title)
		if building_ready("garden_upgrade"):
			for id in data.outputs: data.outputs[id] = int(data.outputs[id]) + 1
	return data

func _node_state(key: String) -> Dictionary:
	var data: Dictionary = catalog.nodes[key]
	var period: int = int(_world.get_ref().minute / int(data.period))
	var saved: Dictionary = state.nodes.get(key, {})
	if int(saved.get("period", -1)) != period: return {"period":period,"remaining":int(data.stock)}
	return saved.duplicate(true)

func offer(task_id: String, worker: String = "player") -> Dictionary:
	var spec: Dictionary = task_spec(task_id, worker)
	if spec.is_empty(): return _result(false, "Esa actividad no existe.")
	var reason := ""
	if not is_present(worker): reason = "Ese habitante todavía no vive aquí."
	elif not area_open(spec.room): reason = "Ese camino sigue cerrado."
	else: reason = _requirements(spec)
	if reason.is_empty():
		for job in state.jobs.values():
			if job.task_id == task_id or (spec.verb in ["plant","tend","harvest"] and str(job.task_id).get_slice(":",1) == spec.key):
				reason = "Alguien ya está atendiendo este lugar."
				break
	if reason.is_empty():
		match spec.verb:
			"build":
				if _done(spec.key): reason = "Esta obra ya está terminada."
				elif not state.projects.has(spec.key): reason = _cost_error(spec.cost.items, int(spec.cost.coins))
			"gather":
				if int(_node_state(spec.key).remaining) < int(spec.quantity): reason = "Aquí ya recogimos suficiente. Volverá a haber mañana."
			"explore":
				if spec.key in state.discoveries: reason = "Este camino ya está explorado."
			"plant":
				if state.plots.get(spec.key, {}).get("status", "empty") != "empty": reason = "Este bancal ya está sembrado."
			"tend":
				var plot: Dictionary = state.plots.get(spec.key, {})
				if plot.get("status", "empty") != "growing": reason = "Siembra primero el bancal."
				elif plot.get("tended", false): reason = "La tierra sigue húmeda."
			"harvest":
				var plot: Dictionary = state.plots.get(spec.key, {})
				if plot.get("status", "empty") != "growing": reason = "Todavía no hay nada sembrado."
				elif not plot.get("tended", false): reason = "Hace falta regar este cultivo."
				elif _world.get_ref().minute - int(plot.planted_at) < int(spec.growth_minutes): reason = "El cultivo todavía está creciendo."
				elif _world.get_ref().environment.harvest_outputs(spec.key,spec.outputs).is_empty(): reason = "Las plantas necesitan recuperarse antes de cosechar."
	if reason.is_empty(): reason = _cost_error(spec.inputs, 0)
	return {"ok":reason.is_empty(),"message":reason if not reason.is_empty() else "Todo listo.","spec":spec}

func _cost_error(items: Dictionary, coins: int) -> String:
	var wallet: Dictionary = _world.get_ref()._progression.state
	var missing: Array[String] = []
	if int(wallet.coins) < coins: missing.append("%d monedas" % (coins-int(wallet.coins)))
	for id in items:
		var needed: int = int(items[id]) - int(wallet.inventory.get(id, 0))
		if needed > 0: missing.append("%d %s" % [needed,catalog.resources.get(id, {}).get("name",id)])
	return "Falta: " + ", ".join(missing) + "." if not missing.is_empty() else ""

func tasks(worker: String = "player") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for pair in [["gather","nodes"],["produce","recipes"],["build","projects"],["explore","explorations"],["plant","plots"],["tend","plots"],["harvest","plots"]]:
		for id in catalog[pair[1]]:
			var task_id: String = str(pair[0])+":"+str(id)
			var spec: Dictionary = task_spec(task_id,worker)
			if not area_open(spec.room): continue
			# Show the next physical frontier, without presenting every future responsibility.
			var required = spec.get("requires", [])
			if required is String: required = [] if required.is_empty() else [required]
			var known: bool = true
			for dependency in required:
				if not _done(dependency): known = false
			if not known: continue
			if spec.verb == "build" and _done(id): continue
			if spec.verb == "explore" and id in state.discoveries: continue
			var plot: Dictionary = state.plots.get(id,{})
			if spec.verb == "plant" and plot.get("status","empty") != "empty": continue
			if spec.verb in ["tend","harvest"] and plot.get("status","empty") != "growing": continue
			if spec.verb == "tend" and plot.get("tended",false): continue
			var proposal: Dictionary = offer(task_id,worker)
			spec["ok"] = proposal.ok
			spec["message"] = proposal.message
			result.append(spec)
	return result

func prepare_task(task_id: String, worker: String) -> Dictionary:
	var proposal: Dictionary = offer(task_id,worker)
	if not proposal.ok: return proposal
	var spec: Dictionary = proposal.spec
	var wallet = _world.get_ref()._progression
	var escrow: Dictionary = {"items":spec.inputs.duplicate(true)}
	if spec.verb == "build" and not state.projects.has(spec.key):
		wallet.state.coins = int(wallet.state.coins) - int(spec.cost.coins)
		wallet._consume(spec.cost.items)
		state.projects[spec.key] = {"status":"building","progress":0.0}
	wallet._consume(spec.inputs)
	if spec.verb == "gather":
		var node: Dictionary = _node_state(spec.key)
		node.remaining = int(node.remaining) - int(spec.quantity)
		state.nodes[spec.key] = node
		escrow["node"] = spec.key
		escrow["period"] = node.period
		escrow["quantity"] = int(spec.quantity)
	state.serial = int(state.serial) + 1
	_changed()
	return {"ok":true,"message":"Actividad preparada.","spec":spec,"escrow":escrow}

func complete_task(job: Dictionary) -> Dictionary:
	var worker: String = str(job.get("worker",""))
	if not state.jobs.has(worker) or state.jobs[worker].get("id","") != job.get("id", "") or state.receipts.has(job.get("id","")):
		return _result(false,"Esta actividad ya terminó o no está asignada.")
	job = state.jobs[worker]
	var spec: Dictionary = task_spec(str(job.task_id),worker)
	var world = _world.get_ref()
	if spec.is_empty() or not is_present(worker) or not area_open(spec.room): return _result(false,"La actividad ya no está disponible.")
	if world.is_sleeping(worker) or worker in world.conversation_holds or not bool(job.get("worked",false)) or float(job.get("progress",0)) < float(spec.minutes):
		return _result(false,"Todavía falta terminar el trabajo presencial.")
	var returning: bool = worker != "player" and spec.verb in ["gather","explore"]
	var expected: Dictionary = catalog.board if returning else spec
	var room: String = str(expected.get("room",expected.get("area","")))
	var resident: Dictionary = world.get_resident(worker)
	if resident.room != room or world._point_distance(resident.pos, expected.at) > 12.0:
		return _result(false,"Llega al punto de entrega para terminar.")
	if returning and job.get("phase", "") != "returning": return _result(false,"Lleva primero los hallazgos al tablón.")
	var wallet = world._progression
	var text: String = str(resident.name) + " terminó: " + str(spec.title) + "."
	match spec.verb:
		"gather", "produce": wallet._add_items(spec.outputs)
		"plant":
			state.plots[spec.key] = {"status":"growing","planted_at":world.minute,"tended":false}
			world.environment.reset_plot(spec.key)
		"tend": state.plots[spec.key].tended = true
		"harvest":
			var harvested: Dictionary = world.environment.harvest_outputs(spec.key,spec.outputs)
			if harvested.is_empty(): return _result(false,"Las plantas todavía necesitan recuperarse.")
			wallet._add_items(harvested)
			state.plots[spec.key] = {"status":"empty","planted_at":0,"tended":false}
			world.environment.reset_plot(spec.key)
		"explore":
			if spec.key in state.discoveries: return _result(false,"Ese descubrimiento ya está registrado.")
			state.discoveries.append(spec.key)
			var seed_value: int = world._day_seed(int(job.started / 1440),worker+spec.key)
			var outcome: Dictionary = spec.rewards[seed_value % spec.rewards.size()]
			wallet._add_items(outcome.items)
			text = str(resident.name) + ": " + str(outcome.text)
		"build":
			state.projects[spec.key] = {"status":"completed","progress":float(spec.minutes)}
			if not str(spec.building).is_empty() and spec.building not in state.buildings: state.buildings.append(spec.building)
			if not str(spec.opens).is_empty() and spec.opens not in state.areas: state.areas.append(spec.opens)
			if not str(spec.arrival).is_empty(): _arrive(spec.arrival)
	state.receipts[job.id] = world.minute
	# Only active job IDs may settle. Old receipts can be bounded without replay risk.
	while state.receipts.size() > 512: state.receipts.erase(state.receipts.keys()[0])
	_changed()
	note_event(worker,text,"exploracion" if spec.verb == "explore" else "comunidad")
	return _result(true,text)

func cancel_task(job: Dictionary) -> void:
	var worker: String = str(job.get("worker",""))
	if not state.jobs.has(worker) or state.jobs[worker].get("id","") != job.get("id", "") or state.receipts.has(job.get("id","")): return
	job = state.jobs[worker]
	state.receipts[job.id] = _world.get_ref().minute
	while state.receipts.size() > 512: state.receipts.erase(state.receipts.keys()[0])
	var escrow: Dictionary = job.get("escrow",{})
	_world.get_ref()._progression._add_items(escrow.get("items",{}))
	if escrow.has("node"):
		var node: Dictionary = _node_state(escrow.node)
		if int(node.period) == int(escrow.period):
			node.remaining = mini(int(catalog.nodes[escrow.node].stock),int(node.remaining)+int(escrow.quantity))
			state.nodes[escrow.node] = node
	_changed()

func _arrive(id: String) -> void:
	if is_present(id): return
	var world = _world.get_ref()
	state.inhabitants[id].present = true
	state.inhabitants[id].arrived_at = world.minute
	var resident: Dictionary = world.get_resident(id)
	var area: String = Layout.home_area(id)
	var start: Vector2 = Layout.point(Layout.data().doors[id])
	var exits: Array = Layout.exits(area)
	if not exits.is_empty(): start = exits[0].at - exits[0].direction * 20.0
	start = Navigation.recover_position(start,area)
	if not world._entry_clear([start.x,start.y],area,id):
		var clear := false
		for radius in [20.0,36.0,52.0,72.0]:
			for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN,Vector2(1,-1),Vector2(-1,1)]:
				var candidate: Vector2 = start + direction.normalized()*radius
				if Navigation.is_walkable(candidate,area) and world._entry_clear([candidate.x,candidate.y],area,id):
					start = candidate
					clear = true
					break
			if clear: break
	resident.room = area
	resident.pos = [start.x,start.y]
	resident.target = resident.pos.duplicate()
	resident.activity = "Conociendo a sus vecinos" if id == "cesar" else "De vuelta en casa"
	resident.travel_intent = ""
	resident.erase("travel_route")
	world._routine_keys.erase(id)
	world._decision_dirty[id] = true
	note_event(id,str(resident.name)+(" llegó al barrio." if id == "cesar" else " regresó a su casa."),"llegada")

func project_status(id: String) -> Dictionary:
	if not catalog.projects.has(id): return {}
	var result: Dictionary = catalog.projects[id].duplicate(true)
	var progress: Dictionary = state.projects.get(id,{})
	result["id"] = id
	result["status"] = str(progress.get("status","planned"))
	result["progress"] = float(progress.get("progress",0))
	var proposal: Dictionary = offer("build:"+id)
	result["ok"] = proposal.ok
	result["message"] = proposal.message
	return result

func stage() -> Dictionary:
	var index: int = 0
	for i in range(catalog.stages.size()):
		var unlocked: bool = true
		for id in catalog.stages[i].get("requires",[]):
			if not _done(id): unlocked = false
		if unlocked: index = i
	var next: String = "El barrio sigue creciendo a tu ritmo."
	for id in catalog.projects:
		if not _done(id) and area_open(catalog.projects[id].area):
			next = str(catalog.projects[id].title)
			break
	return {"index":index,"title":catalog.stages[index].name,"next":next}

func market() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var wallet: Dictionary = _world.get_ref()._progression.state
	var day: int = int(_world.get_ref().minute / 1440)
	for id in catalog.resources:
		var data: Dictionary = catalog.resources[id]
		var sale: Dictionary = state.sales.get(id,{})
		var used: int = int(sale.get("quantity",0)) if int(sale.get("day",-1)) == day else 0
		result.append({"id":id,"name":data.name,"price":int(data.sell),"remaining":maxi(0,int(data.daily_demand)+(2 if building_ready("storage_upgrade") else 0)-used),"owned":int(wallet.inventory.get(id,0))})
	return result

func sell(id: String, quantity: int = 1) -> Dictionary:
	if not catalog.resources.has(id) or quantity <= 0 or quantity > 99: return _result(false,"Elige una cantidad válida.")
	var world = _world.get_ref()
	var player: Dictionary = world.get_resident("player")
	var shop: Dictionary = world._progression.catalog.shop
	if world.is_sleeping("player") or player.room != shop.room or world._point_distance(player.pos,shop.pos) > float(shop.radius): return _result(false,"Acércate a la tienda para vender.")
	var row: Dictionary = {}
	for item in market():
		if item.id == id: row = item
	if quantity > int(row.owned): return _result(false,"No llevas esa cantidad.")
	if quantity > int(row.remaining): return _result(false,"La tienda ya tiene suficiente por hoy.")
	var day: int = int(world.minute / 1440)
	var previous: Dictionary = state.sales.get(id,{})
	var used: int = int(previous.get("quantity",0)) if int(previous.get("day",-1)) == day else 0
	world._progression._consume({id:quantity})
	world._progression.state.coins = int(world._progression.state.coins) + quantity * int(row.price)
	state.sales[id] = {"day":day,"quantity":used+quantity}
	_changed()
	return _result(true,"Vendiste %d %s por %d monedas." % [quantity,row.name,quantity*int(row.price)])

func orders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in catalog.orders:
		var data: Dictionary = catalog.orders[id].duplicate(true)
		if not is_present(data.requester) or not _requirements(data).is_empty(): continue
		data["id"] = id
		var day: int = int(_world.get_ref().minute / 1440)
		var saved: Dictionary = state.orders.get(id,{})
		var used: int = int(saved.get("count",0)) if int(saved.get("day",-1)) == day else 0
		var reason: String = "Pedido entregado por hoy." if used >= int(data.daily_limit) else _cost_error(data.items,0)
		data["ok"] = reason.is_empty()
		data["message"] = reason if not reason.is_empty() else "Llévaselo a " + str(_world.get_ref().get_resident(data.requester).name) + "."
		result.append(data)
	return result

func deliver_order(id: String) -> Dictionary:
	var selected: Dictionary = {}
	for data in orders():
		if data.id == id: selected = data
	if selected.is_empty(): return _result(false,"Ese pedido todavía no está disponible.")
	if not selected.ok: return _result(false,selected.message)
	var world = _world.get_ref()
	if world.is_sleeping(selected.requester): return _result(false,"Espera a que despierte para entregarle el pedido.")
	if world.is_sleeping("player") or world._distance(world.get_resident("player"),world.get_resident(selected.requester)) >= world.MAX_DISTANCE: return _result(false,"Entrega el pedido en persona a %s." % world.get_resident(selected.requester).name)
	var day: int = int(world.minute / 1440)
	var saved: Dictionary = state.orders.get(id,{})
	var used: int = int(saved.get("count",0)) if int(saved.get("day",-1)) == day else 0
	world._progression._consume(selected.items)
	world._progression.state.coins = int(world._progression.state.coins)+int(selected.coins)
	state.orders[id] = {"day":day,"count":used+1}
	var relation: Dictionary = world.get_resident(selected.requester).relationships.player
	relation.trust = minf(100.0,float(relation.trust)+2.0)
	relation.affection = minf(100.0,float(relation.affection)+1.0)
	note_event("player","%s entregó %s a %s." % [world.get_resident("player").name,selected.title,world.get_resident(selected.requester).name],"ayuda")
	_changed()
	return _result(true,"Pedido entregado. Recibiste %d monedas." % selected.coins)

func context_for(id: String) -> Dictionary:
	var job: Dictionary = state.jobs.get(id,{})
	var summary: Dictionary = {"stage":stage().title,"own_job":"","cooperation_available":false}
	if not job.is_empty(): summary.own_job = task_spec(job.task_id,id).get("title", "")
	summary.cooperation_available = is_present(id) and job.is_empty()
	return summary

func note_event(worker: String, text: String, kind: String = "trabajo") -> void:
	var world = _world.get_ref()
	var actor: Dictionary = world.get_resident(worker)
	if actor.is_empty() or not is_present(worker): return
	var participants: Array = [worker]
	for witness in world.active_residents():
		if witness.id == worker or world.is_sleeping(witness.id): continue
		if world._distance(actor,witness) <= 52.0 and Navigation._clear_segment(Layout.point(actor.pos),Layout.point(witness.pos),actor.room): participants.append(witness.id)
	var memory: Dictionary = world._memory(kind,participants,text.left(360),"actividad presencial verificada")
	for id in participants:
		var personal: Dictionary = memory.duplicate(true)
		if kind == "exploracion" and id != worker:
			personal.origin = "informe escuchado de " + str(actor.name)
			personal["heard_from"] = worker
			personal["heard_text"] = text.left(360)
			personal["epistemic_status"] = "testimonio_no_verificado"
		world._remember(world.get_resident(id),personal)
	world._log(text)

func _changed() -> void:
	state.revision = int(state.revision) + 1

func _result(ok: bool, message: String) -> Dictionary:
	return {"ok":ok,"message":message}

func validate(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1: return false
	for key in ["revision","serial"]:
		if not _integer(value.get(key),2147483647): return false
	for key in ["inhabitants","projects","nodes","plots","jobs","receipts","orders","sales"]:
		if not value.get(key) is Dictionary: return false
	for pair in [["areas",Layout.outdoor_ids()],["buildings",_building_ids()],["discoveries",catalog.explorations.keys()]]:
		if not value.get(pair[0]) is Array: return false
		var seen: Array = []
		for id in value[pair[0]]:
			if id not in pair[1] or id in seen: return false
			seen.append(id)
	for id in catalog.initial.areas:
		if id not in value.areas: return false
	for id in catalog.initial.buildings:
		if id not in value.buildings: return false
	if value.inhabitants.size() != _world.get_ref().residents.size(): return false
	for resident in _world.get_ref().residents:
		var inhabitant = value.inhabitants.get(resident.id)
		if not inhabitant is Dictionary or not inhabitant.get("present") is bool or not _number(inhabitant.get("energy"),100) or not _integer(inhabitant.get("arrived_at"),2147483647) or not inhabitant.get("requests") is Dictionary: return false
		if resident.id in catalog.initial.residents and not inhabitant.present: return false
	# Unlocks are consequences of completed projects, never independent flags.
	for area in value.areas:
		if area in catalog.initial.areas: continue
		var justified := false
		for id in catalog.projects:
			if catalog.projects[id].opens == area and value.projects.get(id,{}).get("status","") == "completed": justified = true
		if not justified: return false
	for building in value.buildings:
		if building in catalog.initial.buildings: continue
		var justified := false
		for id in catalog.projects:
			if catalog.projects[id].building == building and value.projects.get(id,{}).get("status","") == "completed": justified = true
		if not justified: return false
	for resident_id in value.inhabitants:
		var requests: Dictionary = value.inhabitants[resident_id].requests
		if not requests.is_empty():
			if requests.size() != 3 or not requests.get("task_id") is String or task_spec(requests.task_id).is_empty() or not _integer(requests.get("minute"),2147483647) or not _integer(requests.get("count"),3) or requests.count < 1: return false
		if value.inhabitants[resident_id].present and str(catalog.home_buildings.get(resident_id,"")) not in value.buildings: return false
	for id in value.projects:
		if not catalog.projects.has(id): return false
		var project = value.projects[id]
		if not project is Dictionary or project.get("status") not in ["building","completed"] or not _number(project.get("progress"),float(catalog.projects[id].minutes)): return false
		if project.status == "completed" and float(project.progress) != float(catalog.projects[id].minutes): return false
		var definition: Dictionary = catalog.projects[id]
		for prerequisite in definition.requires:
			if value.projects.get(prerequisite,{}).get("status","") != "completed": return false
		if not str(definition.discovery).is_empty() and definition.discovery not in value.discoveries: return false
		if definition.area not in value.areas: return false
		if project.status == "completed":
			if not str(definition.opens).is_empty() and definition.opens not in value.areas: return false
			if not str(definition.building).is_empty() and definition.building not in value.buildings: return false
			if not str(definition.arrival).is_empty() and not value.inhabitants.get(definition.arrival,{}).get("present",false): return false
	for id in value.nodes:
		if not catalog.nodes.has(id): return false
		var node = value.nodes[id]
		if not node is Dictionary or not _integer(node.get("period"),2147483647) or not _integer(node.get("remaining"),int(catalog.nodes[id].stock)): return false
	for id in value.plots:
		if not catalog.plots.has(id): return false
		var plot = value.plots[id]
		if not plot is Dictionary or plot.get("status") not in ["empty","growing"] or not _integer(plot.get("planted_at"),2147483647) or not plot.get("tended") is bool: return false
	for pair in [["orders",catalog.orders,"count"],["sales",catalog.resources,"quantity"]]:
		for id in value[pair[0]]:
			if not pair[1].has(id): return false
			var record = value[pair[0]][id]
			if not record is Dictionary or not _integer(record.get("day"),2147483647) or not _integer(record.get(pair[2]),999): return false
	for id in value.discoveries:
		var exploration: Dictionary = catalog.explorations[id]
		if exploration.area not in value.areas: return false
		if not str(exploration.requires).is_empty() and value.projects.get(exploration.requires,{}).get("status","") != "completed": return false
	for id in value.plots:
		if value.projects.get(catalog.plots[id].requires,{}).get("status","") != "completed": return false
	if value.jobs.size() > value.inhabitants.size() or value.receipts.size() > 512: return false
	for receipt in value.receipts:
		if not receipt is String or receipt.length() > 128 or not _integer(value.receipts[receipt],2147483647): return false
	var unique_jobs: Array = []
	var unique_targets: Array = []
	for worker in value.jobs:
		var job = value.jobs[worker]
		if not value.inhabitants.has(worker) or not value.inhabitants[worker].present or not job is Dictionary or job.get("worker") != worker: return false
		if not job.get("id") is String or not job.id.begins_with("work-") or job.id.length() > 128 or value.receipts.has(job.id) or job.id in unique_jobs: return false
		var serial: String = job.id.trim_prefix("work-")
		if not serial.is_valid_int() or int(serial) <= 0 or int(serial) > int(value.serial): return false
		unique_jobs.append(job.id)
		var spec: Dictionary = task_spec(str(job.get("task_id","")),worker)
		if spec.is_empty() or job.get("kind") != spec.kind or job.get("target_room") != spec.room or not _world.get_ref()._valid_point(job.get("target")): return false
		if Layout.point(job.target).distance_to(Layout.point(spec.at)) > 0.01 or job.get("phase") not in ["travelling","working","returning","paused"]: return false
		if not _number(job.get("progress"),float(spec.minutes)) or job.get("required") != spec.minutes or not _integer(job.get("started"),2147483647) or not job.get("worked") is bool or not _number(job.get("energy"),100): return false
		if not job.get("escrow") is Dictionary or not _valid_items(job.escrow.get("items",{})): return false
		if not _same_items(job.escrow.get("items",{}),spec.inputs) or float(job.energy) != float(spec.energy): return false
		if job.target_room not in value.areas: return false
		var requirements = spec.get("requires",[])
		if requirements is String: requirements = [] if requirements.is_empty() else [requirements]
		for required in requirements:
			if value.projects.get(required,{}).get("status","") != "completed": return false
		if not str(spec.get("discovery", "")).is_empty() and spec.discovery not in value.discoveries: return false
		var target_key: String = ("plot:" if spec.verb in ["plant","tend","harvest"] else str(spec.verb)+":") + str(spec.key)
		if target_key in unique_targets: return false
		unique_targets.append(target_key)
		if job.phase == "returning" and (worker == "player" or spec.verb not in ["gather","explore"] or float(job.progress) != float(spec.minutes) or not job.worked): return false
		if float(job.progress) > 0 and not job.worked: return false
		if spec.verb == "gather":
			if job.escrow.size() != 4 or job.escrow.get("node") != spec.key or job.escrow.get("quantity") != spec.quantity or not _integer(job.escrow.get("period"),2147483647): return false
			if not value.nodes.has(spec.key): return false
			if int(job.escrow.period) != int(float(job.started) / float(spec.period)): return false
			var node: Dictionary = value.nodes[spec.key]
			if int(node.period) < int(job.escrow.period): return false
			if int(node.period) == int(job.escrow.period) and int(node.remaining) > int(spec.stock)-int(spec.quantity): return false
		elif job.escrow.size() != 1: return false
		if spec.verb == "build":
			if value.projects.get(spec.key,{}).get("status","") != "building" or value.projects[spec.key].progress != job.progress: return false
		if spec.verb == "explore" and spec.key in value.discoveries: return false
	return true

func _building_ids() -> Array:
	var ids: Array = catalog.initial.buildings.duplicate()
	for data in catalog.projects.values():
		if not str(data.building).is_empty() and data.building not in ids: ids.append(data.building)
	return ids

func _valid_items(items: Variant) -> bool:
	if not items is Dictionary: return false
	for id in items:
		if not catalog.resources.has(id) or not _integer(items[id],999): return false
	return true

func _same_items(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size(): return false
	for id in a:
		if not b.has(id) or float(a[id]) != float(b[id]): return false
	return true

func _integer(value: Variant, maximum: int) -> bool:
	return _number(value,maximum) and float(value) == floorf(float(value))

func _number(value: Variant, maximum: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= 0 and float(value) <= maximum
