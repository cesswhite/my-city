extends RefCounted
## Progress is caused only by validated world actions, never by dialogue text.
const Layout = preload("res://scripts/world_layout.gd")
const Seats = preload("res://scripts/seating.gd")
const COFFEE_PRICE := 3
const COFFEE_ENERGY := 5.0
const COFFEE_ITEM := "taza_cafe"
const COFFEE_TABLES := ["cafe_table_left", "cafe_table_right"]
var catalog: Dictionary = {}
var state: Dictionary = {}
var _world: WeakRef

func setup(world):
	_world = weakref(world)
	var parser = JSON.new()
	if parser.parse(FileAccess.get_file_as_string("res://data/apprenticeships.json")) != OK:
		push_error("No se pudo leer el catálogo de aprendizajes.")
		return
	catalog = parser.data
	var resources: Dictionary = preload("res://scripts/settlement_catalog.gd").data().resources
	for id in resources: catalog.items[id] = {"name":resources[id].name}
	# Resolve semantic locations once from the same geometry used by walking and art.
	catalog.shop["room"] = Layout.place_area("shop")
	catalog.shop["pos"] = _interaction_position(str(catalog.shop.id), str(catalog.shop.room))
	for apprenticeship in catalog.apprenticeships:
		var station: Dictionary = apprenticeship.practice_station
		station["pos"] = _interaction_position(str(station.id), str(station.room))
	reset()

func _interaction_position(id: String, room: String) -> Array:
	var position: Vector2 = Layout.stand_at(id, room)
	return [position.x, position.y]

func reset():
	state = {"version": 2, "coins": int(catalog.get("initial_coins", 20)), "inventory": catalog.get("initial_inventory", {}).duplicate(true), "quests": {}, "procedures": {}, "unlocks": []}

func item_name(item_id: String) -> String:
	return str(catalog.items.get(item_id, {}).get("name", item_id))

func snapshot() -> Dictionary:
	return state.duplicate(true)

func entry(quest_id: String) -> Dictionary:
	for item in catalog.get("apprenticeships", []):
		if item.id == quest_id: return item
	return {}

func procedure_entry(procedure_id: String) -> Dictionary:
	for item in catalog.get("apprenticeships", []):
		if item.procedure_id == procedure_id: return item
	return {}

func available() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var world = _world.get_ref()
	for item in catalog.apprenticeships:
		if not world.is_present(item.mentor_id): continue
		var copy: Dictionary = item.duplicate(true)
		copy["mentor_name"] = world.get_resident(item.mentor_id).name
		copy["status"] = status_for(item.id).status
		copy["next_hint"] = status_for(item.id).next_hint
		result.append(copy)
	return result

func status_for(quest_id: String) -> Dictionary:
	var data: Dictionary = entry(quest_id)
	if data.is_empty(): return {}
	var progress: Dictionary = state.quests.get(quest_id, {})
	var status: String = progress.get("status", "available")
	var procedure: Dictionary = state.procedures.get(data.procedure_id, {})
	var next: int = int(procedure.get("step_index", 0))
	var hint: String
	match status:
		"available": hint = "Habla con %s para pedir este encargo." % _world.get_ref().get_resident(data.mentor_id).name
		"accepted":
			hint = "Entrega los materiales a %s donde esté." % _world.get_ref().get_resident(data.mentor_id).name if _has_items(data.materials) else "Compra los materiales del encargo en la tienda."
		"learned": hint = "Practica en tu casa: " + str(data.steps[next].label) if next < data.steps.size() else "Procedimiento completo."
		_: hint = "Aprendizaje demostrado y guardado."
	return {"id": quest_id, "status": status, "next_hint": hint.left(240), "procedure_id": data.procedure_id,
		"next_step_id": data.steps[next].id if next < data.steps.size() else "",
		"next_step_label": data.steps[next].label if next < data.steps.size() else "",
		"step_index": next, "step_count": data.steps.size(), "has_materials": _has_items(data.materials)}

func shop_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item_id in catalog.items:
		var item: Dictionary = catalog.items[item_id]
		if not item.has("price"): continue
		var quest: Dictionary = entry(item.quest_id)
		var remaining: int = 0
		if state.quests.get(item.quest_id, {}).get("status", "") == "accepted":
			remaining = maxi(0, int(quest.materials[item_id]) - int(state.inventory.get(item_id, 0)))
		result.append({"id": item_id, "name": item.name, "price": int(item.price), "quest_id": item.quest_id, "available_quantity": remaining})
	return result

func _coffee_seat_error(seat_id: String) -> String:
	var seat: Dictionary = Seats.get_seat(seat_id)
	if seat.is_empty() or seat.prop_key not in COFFEE_TABLES:
		return "Siéntate en un banquito del café para pedir o beber."
	var world = _world.get_ref()
	var player: Dictionary = world.get_resident("player")
	if world.player_autonomy or world.is_sleeping("player") or world.player_energy() <= 0.0 or "player" in world.conversation_holds:
		return "Toma el control y termina lo que estás haciendo para disfrutar el café."
	var position: Vector2 = Layout.point(player.pos)
	var target: Vector2 = Layout.point(player.target)
	if player.get("room", "street") != Layout.place_area("cafe") or not position.is_finite() or not target.is_finite() or position.distance_to(seat.stand_at) > 0.75 or target.distance_to(seat.stand_at) > 0.75:
		return "Espera a estar sentado en el café."
	return ""

func coffee_offer(seat_id: String) -> Dictionary:
	# Posture is owned by PlayerSeating; the host passes its active ID. This layer
	# independently checks the real seat, room, approach and current intention.
	var has_coffee: bool = int(state.inventory.get(COFFEE_ITEM, 0)) > 0
	var coins: int = int(state.coins)
	var message: String = _coffee_seat_error(seat_id)
	var ok: bool = message.is_empty()
	if ok:
		if has_coffee: message = "Tu taza está lista para beber."
		elif coins < COFFEE_PRICE:
			ok = false
			message = "Necesitas %d monedas para pedir café." % COFFEE_PRICE
		else: message = "Una taza de café cuesta %d monedas." % COFFEE_PRICE
	return {"ok": ok, "message": message, "price": COFFEE_PRICE, "has_coffee": has_coffee, "coins": coins, "energy_gain": COFFEE_ENERGY}

func order_coffee(seat_id: String) -> Dictionary:
	var offer: Dictionary = coffee_offer(seat_id)
	if not offer.ok: return _result(false, offer.message)
	if offer.has_coffee: return _result(false, "Termina tu taza antes de pedir otra.")
	# All preconditions precede both writes, so a rejected order never charges.
	state.coins = int(state.coins) - COFFEE_PRICE
	state.inventory[COFFEE_ITEM] = 1
	var message := "Pediste una taza de café por %d monedas." % COFFEE_PRICE
	_note("compra", ["player"], message, {"item_id": COFFEE_ITEM, "quantity": 1, "coins_spent": COFFEE_PRICE, "seat_id": seat_id})
	return _result(true, message)

func drink_coffee(seat_id: String) -> Dictionary:
	var error: String = _coffee_seat_error(seat_id)
	if not error.is_empty(): return _result(false, error)
	if int(state.inventory.get(COFFEE_ITEM, 0)) != 1: return _result(false, "Primero pide una taza de café.")
	var world = _world.get_ref()
	var before: float = world.player_energy()
	state.inventory.erase(COFFEE_ITEM)
	var energy: float = minf(100.0, before + COFFEE_ENERGY)
	world.get_resident("player")["energy"] = energy
	var restored: float = energy - before
	var message: String = "Bebiste tu café. Recuperaste %s%% de energía." % String.num(restored, 2).trim_suffix("00").trim_suffix("0").trim_suffix(".") if restored > 0.0 else "Bebiste tu café con la energía al máximo."
	_note("consumo", ["player"], message, {"item_id": COFFEE_ITEM, "quantity": 1, "seat_id": seat_id})
	var result: Dictionary = _result(true, message)
	result["energy_gained"] = restored
	return result

func start(quest_id: String) -> Dictionary:
	var data: Dictionary = entry(quest_id)
	if data.is_empty(): return _result(false, "Este encargo no existe.")
	if state.quests.has(quest_id): return _result(false, "Este encargo ya está en tu diario.")
	var world = _world.get_ref()
	var player: Dictionary = world.get_resident("player")
	var mentor: Dictionary = world.get_resident(data.mentor_id)
	if not world.is_present(data.mentor_id): return _result(false,"Ese vecino llegará cuando prepares su hogar.")
	if world._distance(player, mentor) >= world.MAX_DISTANCE:
		return _result(false, "Acércate a %s para recibir el encargo." % mentor.name)
	state.quests[quest_id] = {"status": "accepted", "accepted_at": world.minute, "delivered_at": 0, "completed_at": 0}
	var message: String = "%s te pidió materiales para «%s». %s" % [mentor.name, data.title, data.lore]
	_note("encargo", ["player", data.mentor_id], message)
	return _result(true, message)

func buy(item_id: String, quantity: int = 1) -> Dictionary:
	if quantity <= 0 or quantity > 99: return _result(false, "Elige una cantidad válida.")
	var selected: Dictionary = {}
	for item in shop_catalog():
		if item.id == item_id: selected = item
	if selected.is_empty(): return _result(false, "Ese artículo no se vende en la tienda.")
	if quantity > int(selected.available_quantity):
		return _result(false, "Compra solamente el material pendiente de un encargo aceptado.")
	var world = _world.get_ref()
	var player: Dictionary = world.get_resident("player")
	if player.room != catalog.shop.room or world._point_distance(player.pos, catalog.shop.pos) > float(catalog.shop.radius):
		return _result(false, "Acércate al mostrador de la tienda para comprar.")
	var cost: int = int(selected.price) * quantity
	if int(state.coins) < cost: return _result(false, "No tienes suficientes monedas.")
	state.coins = int(state.coins) - cost
	state.inventory[item_id] = int(state.inventory.get(item_id, 0)) + quantity
	var message: String = "Compraste %d × %s por %d monedas." % [quantity, selected.name, cost]
	_note("compra", ["player"], message)
	return _result(true, message)

func deliver(quest_id: String) -> Dictionary:
	var data: Dictionary = entry(quest_id)
	if data.is_empty() or state.quests.get(quest_id, {}).get("status", "") != "accepted":
		return _result(false, "Primero acepta el encargo; cada entrega se realiza una sola vez.")
	var world = _world.get_ref()
	var player: Dictionary = world.get_resident("player")
	var mentor: Dictionary = world.get_resident(data.mentor_id)
	if not world.is_present(data.mentor_id): return _result(false,"Ese vecino llegará cuando prepares su hogar.")
	# The lesson follows its mentor, independently of their routine or workplace.
	# _distance also checks the room, so materials still change hands in person.
	if world._distance(player, mentor) >= world.MAX_DISTANCE:
		return _result(false, "Acércate a %s para entregar los materiales." % mentor.name)
	if not _has_items(data.materials): return _result(false, "Todavía falta el material del encargo.")
	_consume(data.materials)
	_add_items(data.kit)
	state.quests[quest_id].status = "learned"
	state.quests[quest_id].delivered_at = world.minute
	state.procedures[data.procedure_id] = {"quest_id": quest_id, "status": "instrucciones", "step_index": 0,
		"executed_steps": [], "learned_at": world.minute, "started_at": 0, "completed_at": 0, "world_verified": false, "practice_runs": 0}
	_grant_skill(data, false)
	var message: String = "%s recibió el material y te enseñó «%s». Llevas el kit para practicar, paso a paso, en tu casa." % [mentor.name, data.procedure_name]
	_note("enseñanza", ["player", data.mentor_id], message)
	return _result(true, message)

func perform(procedure_id: String, step_id: String = "") -> Dictionary:
	var data: Dictionary = procedure_entry(procedure_id)
	if data.is_empty() or not state.procedures.has(procedure_id): return _result(false, "Aprende primero este procedimiento con tu mentor.")
	var procedure: Dictionary = state.procedures[procedure_id]
	if procedure.world_verified: return _result(false, "Este proyecto ya está completado; el aprendizaje sigue guardado.")
	var world = _world.get_ref()
	var player: Dictionary = world.get_resident("player")
	var station: Dictionary = data.practice_station
	if player.room != station.room or world._point_distance(player.pos, station.pos) > float(station.radius):
		return _result(false, "Acércate a la estación correspondiente dentro de tu casa.")
	var next: int = int(procedure.step_index)
	var expected: Dictionary = data.steps[next]
	if not step_id.is_empty() and step_id != expected.id:
		return _result(false, "Ese paso todavía no corresponde. Sigue: " + str(expected.label) + ".")
	if next == 0:
		if not _has_items(data.consumes): return _result(false, "Falta el kit de práctica que te entregó tu mentor.")
		_consume(data.consumes)
		procedure.started_at = world.minute
	procedure.status = "practicando"
	procedure.executed_steps.append(expected.id)
	procedure.step_index = next + 1
	var message: String = "Paso verificado: " + str(expected.label) + "."
	if int(procedure.step_index) == data.steps.size():
		procedure.status = "demostrada"
		procedure.world_verified = true
		procedure.completed_at = world.minute
		procedure.practice_runs = 1
		state.quests[data.id].status = "completed"
		state.quests[data.id].completed_at = world.minute
		_add_items(data.produces)
		if data.unlock not in state.unlocks: state.unlocks.append(data.unlock)
		_grant_skill(data, true)
		message += " «%s» completado; conservas este conocimiento." % data.procedure_name
	_note("practica", ["player"], message, {"procedure_id": procedure_id, "step_id": expected.id, "step_index": procedure.step_index, "world_verified": procedure.world_verified})
	return _result(true, message)

func compact_context() -> Dictionary:
	var context: Dictionary = {"coins": int(state.coins), "inventory": state.inventory.duplicate(), "quests": {}, "procedures": {}, "unlocks": state.unlocks.duplicate()}
	for quest_id in state.quests:
		var status: Dictionary = status_for(quest_id)
		context.quests[quest_id] = {"status": status.status, "next_hint": status.next_hint}
	for procedure_id in state.procedures:
		var procedure: Dictionary = state.procedures[procedure_id]
		var status: Dictionary = status_for(procedure.quest_id)
		context.procedures[procedure_id] = {"status": procedure.status, "next_step_id": status.next_step_id,
			"executed_steps": procedure.executed_steps.duplicate(), "world_verified": procedure.world_verified}
	return context

func _grant_skill(data: Dictionary, demonstrated: bool):
	var world = _world.get_ref()
	var player: Dictionary = world.get_resident("player")
	if player.skills.get(data.procedure_id, {}).get("status", "") == "demostrada" and not demonstrated: return
	var steps: Array[String] = []
	for step in data.steps: steps.append(step.id)
	player.skills[data.procedure_id] = {"name": data.procedure_name, "status": "demostrada" if demonstrated else "instrucciones",
		"steps": steps, "ingredients": {"agua": 1, "te": 1} if data.procedure_id == "preparar_te" else {},
		"source": "Enseñanza presencial de " + str(world.get_resident(data.mentor_id).name), "learned_at": world.minute,
		"practice_runs": 1 if demonstrated else 0, "last_result": "Procedimiento ejecutado en casa" if demonstrated else "Instrucciones y kit recibidos"}

func valid_skill(skill_id: String, skill: Variant) -> bool:
	var data: Dictionary = procedure_entry(skill_id)
	if data.is_empty() or not skill is Dictionary: return false
	if skill.get("status") not in ["instrucciones", "demostrada"] or not skill.get("steps") is Array or skill.steps.size() != data.steps.size(): return false
	for index in range(data.steps.size()):
		if skill.steps[index] != data.steps[index].id: return false
	if not skill.get("ingredients") is Dictionary: return false
	return true

func validate(value: Variant) -> bool:
	if not value is Dictionary or not _integer(value.get("version"), 2) or int(value.version) not in [1, 2]: return false
	value = _migrate(value)
	if not _integer(value.get("coins"), 1000000): return false
	for field in ["inventory", "quests", "procedures"]:
		if not value.get(field) is Dictionary: return false
	if not value.get("unlocks") is Array or value.unlocks.size() > catalog.apprenticeships.size(): return false
	for item_id in value.inventory:
		if not catalog.items.has(item_id) or not _integer(value.inventory[item_id], 999): return false
		if item_id == COFFEE_ITEM and int(value.inventory[item_id]) > 1: return false
	for quest_id in value.quests:
		var data: Dictionary = entry(quest_id)
		var quest = value.quests[quest_id]
		if data.is_empty() or not quest is Dictionary or quest.get("status") not in ["accepted", "learned", "completed"]: return false
		for time_key in ["accepted_at", "delivered_at", "completed_at"]:
			if not _integer(quest.get(time_key), 2147483647): return false
		if quest.status != "accepted" and not value.procedures.has(data.procedure_id): return false
		if quest.status == "accepted" and value.procedures.has(data.procedure_id): return false
	for procedure_id in value.procedures:
		var data: Dictionary = procedure_entry(procedure_id)
		var procedure = value.procedures[procedure_id]
		if data.is_empty() or not procedure is Dictionary or procedure.get("quest_id") != data.id or not value.quests.has(data.id): return false
		if procedure.get("status") not in ["instrucciones", "practicando", "demostrada"] or not procedure.get("world_verified") is bool: return false
		if not _integer(procedure.get("step_index"), data.steps.size()) or not procedure.get("executed_steps") is Array: return false
		if int(procedure.step_index) != procedure.executed_steps.size(): return false
		for index in range(procedure.executed_steps.size()):
			if procedure.executed_steps[index] != data.steps[index].id: return false
		var finished: bool = int(procedure.step_index) == data.steps.size()
		if procedure.world_verified != finished or (procedure.status == "demostrada") != finished: return false
		if procedure.status == "instrucciones" and int(procedure.step_index) != 0: return false
		if procedure.status == "practicando" and (int(procedure.step_index) == 0 or finished): return false
		if int(procedure.step_index) == 0 and not _contains_items(value.inventory, data.consumes): return false
		if int(procedure.step_index) > 0:
			for consumed_item in data.consumes:
				if int(value.inventory.get(consumed_item, 0)) != 0: return false
		if (value.quests[data.id].status == "completed") != finished: return false
		if finished and (data.unlock not in value.unlocks or not _contains_items(value.inventory, data.produces)): return false
		for time_key in ["learned_at", "started_at", "completed_at", "practice_runs"]:
			if not _integer(procedure.get(time_key), 2147483647): return false
		if int(procedure.practice_runs) != (1 if finished else 0): return false
	var unique: Array = []
	for unlock in value.unlocks:
		if unlock in unique: return false
		unique.append(unlock)
		var valid_unlock: bool = false
		for data in catalog.apprenticeships:
			if unlock == data.unlock and value.procedures.get(data.procedure_id, {}).get("world_verified", false): valid_unlock = true
		if not valid_unlock: return false
	return true

func restore(value: Dictionary):
	state = _migrate(value)
	state.coins = int(state.coins)
	for item_id in state.inventory: state.inventory[item_id] = int(state.inventory[item_id])

func _migrate(value: Dictionary) -> Dictionary:
	var migrated: Dictionary = value.duplicate(true)
	if migrated.get("version") == 1:
		if migrated.get("inventory") is Dictionary and migrated.get("procedures") is Dictionary and not migrated.procedures.has("reparar_bicicleta"):
			migrated.inventory["bicicleta_averiada"] = 1
		migrated.version = 2
	return migrated

func _integer(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) <= maximum and float(value) == floor(float(value))

func _contains_items(inventory: Dictionary, needed: Dictionary) -> bool:
	for item_id in needed:
		if int(inventory.get(item_id, 0)) < int(needed[item_id]): return false
	return true

func _has_items(needed: Dictionary) -> bool:
	return _contains_items(state.inventory, needed)

func _consume(items: Dictionary):
	for item_id in items:
		state.inventory[item_id] = int(state.inventory.get(item_id, 0)) - int(items[item_id])
		if state.inventory[item_id] == 0: state.inventory.erase(item_id)

func _add_items(items: Dictionary):
	for item_id in items: state.inventory[item_id] = int(state.inventory.get(item_id, 0)) + int(items[item_id])

func _note(kind: String, participants: Array, text: String, extra: Dictionary = {}):
	var world = _world.get_ref()
	for participant in participants:
		var memory: Dictionary = world._memory(kind, participants, text, "acción verificada por las reglas del mundo")
		memory.merge(extra)
		world._remember(world.get_resident(participant), memory)
	world._log(text)

func _result(ok: bool, message: String) -> Dictionary:
	_world.get_ref().last_error = "" if ok else message
	return {"ok": ok, "message": message}
