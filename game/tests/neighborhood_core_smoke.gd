extends SceneTree
const Colony = preload("res://scripts/colony.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Destinations = preload("res://scripts/shared_destinations.gd")
var checks := 0
var failures := 0
var path := "user://test_neighborhood_core_%d.json" % OS.get_process_id()

func _init(): call_deferred("run")

func check(ok: bool, message: String):
	checks += 1
	if ok: print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func fresh():
	var world = Colony.new()
	world.save_path = path
	world.setup(false, true)
	return world

func isolate(world, except_id: String = "player"):
	for resident in world.residents:
		if resident.id == except_id: continue
		resident.room = resident.id
		resident.pos = Colony.HOME_REST.duplicate()
		resident.target = resident.pos.duplicate()
		world.cancel_travel(resident.id)

func place(resident: Dictionary, room: String, at: Vector2):
	resident.room = room
	resident.pos = [at.x, at.y]
	resident.target = resident.pos.duplicate()
	resident.erase("travel_route")
	resident.travel_intent = ""

func walk(world, id: String, max_legs: int = 16) -> Dictionary:
	var actor: Dictionary = world.get_resident(id)
	var transitions: Array[String] = [actor.room]
	var distance := 0.0
	for _leg in range(max_legs):
		var room: String = actor.room
		var from: Vector2 = Layout.point(actor.pos)
		var target: Vector2 = Layout.point(actor.target)
		var points: Array[Vector2] = Navigation.route(from, target, room)
		if points.is_empty() or points.back().distance_to(target) > 0.01:
			return {"ok": false, "reason": "No route %s %s -> %s" % [room, from, target], "areas": transitions}
		for node in points:
			while Layout.point(actor.pos).distance_to(node) > 0.0001:
				var previous: Vector2 = Layout.point(actor.pos)
				var next: Vector2 = Navigation.move_direction(previous, node - previous, minf(1.0, previous.distance_to(node)), room)
				if previous.distance_to(next) < 0.00001 or not Navigation.is_walkable(next, room):
					return {"ok": false, "reason": "Blocked legal step in " + room, "areas": transitions}
				distance += previous.distance_to(next)
				actor.pos = [next.x, next.y]
		world.on_arrival(id)
		if actor.room != room: transitions.append(actor.room)
		if not actor.has("travel_route") and Layout.point(actor.pos).distance_to(Layout.point(actor.target)) <= 0.001:
			return {"ok": true, "areas": transitions, "distance": distance}
	return {"ok": false, "reason": "Too many route legs", "areas": transitions}

func run():
	clean()
	var world = fresh()
	check(Layout.outdoor_ids().size() == 6, "seis áreas exteriores registradas")
	for resident in world.residents:
		check(Navigation.is_walkable(Layout.point(resident.pos), resident.room), "spawn transitable de " + resident.id)
	for area: String in Layout.outdoor_ids():
		for edge: Dictionary in Layout.exits(area):
			check(Navigation.is_walkable(edge.at, area) and Navigation.is_walkable(edge.spawn, edge.to), "paso y llegada físicos " + area + " a " + str(edge.to))
		for other: String in Layout.outdoor_ids():
			check(not Layout.area_route(area, other).is_empty(), "grafo conecta " + area + " y " + other)
	for home: String in Colony.RESIDENT_IDS:
		var area: String = Layout.home_area(home)
		var door: Vector2 = Layout.point(Colony.HOME_DOORS[home])
		var connected := Navigation.is_walkable(door, area)
		for edge: Dictionary in Layout.exits(area):
			var route: Array[Vector2] = Navigation.route(door, edge.at, area)
			connected = connected and not route.is_empty() and route.back().is_equal_approx(edge.at)
		check(connected, "puerta " + home + " conectada a su calle y pasos")
	for venue: String in Colony.PLACES:
		var area: String = Layout.place_area(venue)
		var candidates: Array[Vector2] = Destinations.candidates(venue)
		var valid := not candidates.is_empty()
		for candidate in candidates: valid = valid and Navigation.is_walkable(candidate, area)
		check(valid, "destinos compartidos usan el área de " + venue)

	isolate(world)
	var player: Dictionary = world.get_resident("player")
	place(player, "player", Layout.point(Colony.ROOM_ENTRY))
	check(world.travel_to("player", "workshops", Layout.point(Colony.PLACES.taller)), "ordena viaje desde casa a otra zona")
	check(player.room == "player" and player.target == Colony.ROOM_EXIT, "primero camina a salida interior sin teletransportarse")
	var journey := walk(world, "player")
	check(journey.ok and player.room == "workshops" and Layout.point(player.pos).is_equal_approx(Layout.point(Colony.PLACES.taller)), "recorre casa, homes, plaza y taller: " + str(journey))
	check(journey.areas == ["player", "homes", "street", "workshops"], "viaje utiliza sólo enlaces contiguos")
	check(not player.has("travel_route"), "destino completado limpia el plan temporal")
	check(not world.travel_to("player", "mateo", Layout.point(Colony.ROOM_ENTRY)), "viaje no omite permiso de casa ajena")

	var cesar: Dictionary = world.get_resident("cesar")
	place(cesar, "workshops", Layout.point(Colony.PLACES.taller))
	world._set_destination(cesar, "casa")
	var home_journey := walk(world, "cesar")
	check(home_journey.ok and cesar.room == "cesar", "vecino atraviesa calles y entra físicamente a su casa: " + str(home_journey))
	check(world.apply_decision("cesar", "cafe"), "decisión del vecino apunta a café de otra área")
	var cafe_journey := walk(world, "cesar")
	check(cafe_journey.ok and cesar.room == Layout.place_area("cafe"), "sale en gardens y continúa hasta café: " + str(cafe_journey))

	place(player, "street", Vector2(300, 190))
	var edge: Dictionary = Layout.next_exit("street", "gardens")
	check(not world.cross_exit("player", edge.id), "no cambia de área desde lejos")
	place(player, "street", edge.at)
	place(cesar, edge.to, edge.spawn)
	check(not world.cross_exit("player", edge.id) and player.room == "street", "spawn ocupado retiene posición y área")
	place(cesar, "cesar", Layout.point(Colony.HOME_REST))
	world.conversation_holds.assign(["player"])
	check(not world.cross_exit("player", edge.id), "conversación retenida no cruza un paso")
	world.conversation_holds.clear()
	check(world.cross_exit("player", edge.id) and player.room == edge.to, "paso liberado permite continuar")
	for area: String in Layout.outdoor_ids():
		for portal: Dictionary in Layout.exits(area):
			var reverse: Dictionary = Layout.next_exit(portal.to, area)
			var delta: Vector2 = (portal.spawn - reverse.at) / Vector2(16, 14)
			check(delta.length_squared() >= 1.0, "llegada no bloquea vecino que sale en sentido opuesto " + area + "->" + str(portal.to))

	place(player, "gardens", Vector2(192, 230))
	place(cesar, "street", Vector2(192, 230))
	check(not world.record_dialogue("player", "cesar", "Hola", "Hola", "Prueba aislada"), "coordenadas iguales entre áreas no son cercanía")
	check(world.context_for("player").observations.is_empty(), "percepción no revela vecinos de otras áreas")
	check(world.observe_area_item("player", "gardens", "Semillero", "Semillas esperando su temporada."), "inspección exterior registra experiencia propia")
	var memories: int = player.memories.size()
	world.observe_area_item("player", "gardens", "Semillero", "Semillas esperando su temporada.")
	check(player.memories.size() == memories and cesar.memories.is_empty(), "inspección exterior no duplica ni informa a terceros")
	check(not world.observe_area_item("player", "atelier", "Cuadro", "Un cuadro."), "no observa objetos de otra área")

	check(world.travel_to("player", "workshops", Layout.point(Colony.PLACES.taller)), "prepara viaje persistente a mitad de camino")
	world._set_destination(cesar, "taller")
	var npc_destination: Dictionary = cesar.travel_route.duplicate(true)
	var current_target: Array = player.target.duplicate()
	check(world.save_game(), "guarda áreas y ruta final con copia atómica")
	var restored = fresh()
	check(restored.load_game(), "recupera áreas y ruta final")
	var restored_player: Dictionary = restored.get_resident("player")
	check(restored_player.room == "gardens" and restored_player.travel_route.room == "workshops" and restored_player.target == current_target and not restored.player_autonomy, "recargar conserva tramo local sin activar autonomía")
	var restored_npc: Dictionary = restored.get_resident("cesar")
	check(restored_npc.room == "street" and restored_npc.travel_intent == "taller" and restored_npc.travel_route == npc_destination and not restored.decision_due("cesar"), "ruta autónoma NPC conserva destino y no pide otra decisión en tránsito")
	var npc_trip := walk(restored, "cesar")
	check(npc_trip.ok and restored_npc.room == "workshops" and restored_npc.target == npc_destination.position, "NPC reanuda y completa la ruta persistida sin perder intención")
	var restored_trip := walk(restored, "player")
	check(restored_trip.ok and restored_player.room == "workshops", "viaje guardado puede terminar por caminos reales")
	check(restored_player.memories.size() == memories, "memoria no se pierde al cargar ni cruzar")

	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("world_revision")
	for actor in legacy.residents:
		actor.erase("travel_route")
		if actor.id == "cesar":
			actor.room = "street"
			actor.pos = [192.0, 230.0]
			actor.target = Colony.PLACES.huerto.duplicate()
			actor.travel_intent = "huerto"
	write_payload(legacy)
	check(restored.load_game(), "migra partida anterior sin versión de barrio")
	var migrated: Dictionary = restored.get_resident("cesar")
	check(migrated.room == "street" and migrated.pos == [192.0, 230.0] and migrated.travel_route.room == "gardens", "migración conserva ubicación real y reencamina intención original")
	check(migrated.target == [edge.at.x, edge.at.y], "target migrado es paso local, no coordenadas remotas")
	for bad in [{"room": "inexistente", "position": [200, 200]}, {"room": "gardens", "position": [200, 50]}, {"room": "mateo", "position": [236, 252]}, {"room": "gardens", "position": [200, 200], "extra": true}]:
		var corrupt: Dictionary = saved.duplicate(true)
		corrupt.residents[5].travel_route = bad
		write_payload(corrupt)
		var before: String = JSON.stringify(restored.residents)
		check(not restored.load_game() and JSON.stringify(restored.residents) == before, "rechaza ruta corrupta sin mutar mundo " + str(bad))
	write_payload(saved)
	clean()
	print("RESULT: %d/%d comprobaciones correctas" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)

func write_payload(payload: Dictionary):
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()

func clean():
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
