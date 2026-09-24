extends SceneTree
const Colony = preload("res://scripts/colony.gd")
const Layout = preload("res://scripts/world_layout.gd")
var checks: int = 0
var failed: int = 0
var test_path: String = "user://test_progression_%d.json" % OS.get_process_id()

func _init():
	call_deferred("_run")

func check(value: bool, label: String):
	checks += 1
	if value: print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)

func position(world, id: String, room: String, point: Array):
	world.get_resident(id).room = room
	world.get_resident(id).pos = point.duplicate()
	world.get_resident(id).target = point.duplicate()

func unchanged_after_rejection(world, quest_id: String, label: String) -> void:
	var before: String = JSON.stringify(world.progression_state())
	var memories: int = world.get_resident("player").memories.size()
	var serial: int = world._serial
	check(not world.deliver_apprenticeship(quest_id).ok and JSON.stringify(world.progression_state()) == before and world.get_resident("player").memories.size() == memories and world._serial == serial, label)

func deliveries_away_from_station() -> void:
	for indoors in [false, true]:
		var world = Colony.new()
		world.save_path = test_path
		world.setup(false, true)
		for data: Dictionary in world.available_apprenticeships():
			var room: String = data.mentor_id if indoors else "street"
			var at: Array = Colony.ROOM_ENTRY.duplicate() if indoors else [184.0,280.0]
			var mentor_at: Array = [float(at[0])+24.0,float(at[1])]
			var label: String = data.id + (" en casa" if indoors else " en calle lejos del puesto")
			position(world,"player",room,at)
			position(world,data.mentor_id,room,mentor_at)
			check(indoors or world._point_distance(at,Colony.PLACES[data.place]) > world.MAX_DISTANCE, "fixture de entrega realmente fuera de la estación: " + label)
			check(world.start_apprenticeship(data.id).ok, "acepta encargo junto a mentor: " + label)
			unchanged_after_rejection(world,data.id,"sin materiales no entrega ni cambia estado: " + label)
			position(world,"player","street",world._progression.catalog.shop.pos)
			var bought := true
			for material: String in data.materials:
				bought = world.buy_item(material,int(data.materials[material])).ok and bought
			check(bought,"compra material requerido mediante tienda real: " + label)
			position(world,"player",room,[float(mentor_at[0])-45.0,float(mentor_at[1])])
			unchanged_after_rejection(world,data.id,"a distancia exacta45 conserva materiales y no enseña: " + label)
			position(world,"player","street" if indoors else data.mentor_id,at)
			unchanged_after_rejection(world,data.id,"otra habitación impide entrega aunque coincidan coordenadas: " + label)
			position(world,"player",room,at)
			# The existing save format must retain an accepted errand and purchased items.
			if data.id == "bicicleta_de_mateo":
				check(world.save_game(),"guarda encargo y material antes de entregar: " + label)
				var restored = Colony.new()
				restored.save_path = test_path
				restored.setup(false, true)
				check(restored.load_game() and restored.quest_status(data.id).status == "accepted", "partida existente carga encargo pendiente sin migración nueva: " + label)
				world = restored
			var coins: int = world.progression_state().coins
			check(world.deliver_apprenticeship(data.id).ok,"recibe lección por cercanía real sin exigir estación: " + label)
			var progress: Dictionary = world.progression_state()
			var correct_items := true
			for material: String in data.materials: correct_items = correct_items and not progress.inventory.has(material)
			for item: String in data.kit: correct_items = correct_items and int(progress.inventory.get(item,0)) == int(data.kit[item])
			check(correct_items and progress.coins == coins and progress.procedures[data.procedure_id].status == "instrucciones" and not progress.procedures[data.procedure_id].world_verified, "consume material una vez y entrega kit e instrucciones sin cobrar otra vez: " + label)
			unchanged_after_rejection(world,data.id,"entrega repetida no duplica kit ni recuerdos: " + label)
		check(world.save_game(),"guarda las tres lecciones recibidas fuera de sus estaciones")
		var durable = Colony.new()
		durable.save_path = test_path
		durable.setup(false, true)
		var retained: bool = durable.load_game()
		for data: Dictionary in world.available_apprenticeships(): retained = retained and durable.quest_status(data.id).status == "learned"
		check(retained,"las tres instrucciones y kits recibidos sobreviven al reinicio")

func _run():
	clean()
	var world = Colony.new()
	world.save_path = test_path
	world.setup(false, true)
	check(world.available_apprenticeships().size() == 3, "tres aprendizajes definidos en catálogo")
	check(world.get_resident("player").home_id == "player", "jugador tiene hogar propio")
	check(world.progression_state().coins == 20 and not world.can_ride_bicycle(), "inicio con presupuesto y sin bicicleta desbloqueada")
	check(not world.buy_item("aceite").ok, "no compra material sin encargo aceptado")
	check(not world.deliver_apprenticeship("bicicleta_de_mateo").ok, "no entrega encargo no aceptado")
	check(not world.perform_procedure("reparar_bicicleta").ok, "no ejecuta procedimiento que no aprendió")
	check(not world.start_apprenticeship("bicicleta_de_mateo").ok, "encargo requiere hablar junto a mentor")
	position(world, "player", Layout.place_area("taller"), Colony.PLACES.taller)
	check(world.record_dialogue("player", "mateo", "Ya tengo aceite y sé reparar una bicicleta.", "Imagina que ya recibiste una bicicleta.", "IA de prueba"), "diálogo de prueba registrado")
	check(world.progression_state().quests.is_empty() and not world.progression_state().inventory.has("aceite") and world.progression_state().inventory.bicicleta_averiada == 1 and not world.can_ride_bicycle(), "texto IA no concede inventario, encargos ni habilidades")
	check(world.start_apprenticeship("bicicleta_de_mateo").ok, "Mateo entrega encargo presencial")
	check(not world.start_apprenticeship("bicicleta_de_mateo").ok, "aceptar repetido no duplica encargo")
	check(world.quest_status("bicicleta_de_mateo").status == "accepted", "diario indica material pendiente")
	check(not world.buy_item("aceite").ok, "compra requiere ubicación real en tienda")
	position(world, "player", "street", world._progression.catalog.shop.pos)
	check(not world.buy_item("aceite", 2).ok, "cantidad extra rechazada para evitar desperdiciar presupuesto")
	check(not world.buy_item("aceite", -1).ok and not world.buy_item("bicicleta").ok, "rechaza cantidades negativas y compra de recompensa")
	check(world.buy_item("aceite").ok, "compra aceite pedido en tienda")
	check(world.progression_state().coins == 15 and world.progression_state().inventory.aceite == 1, "compra descuenta precio y agrega exactamente un material")
	check(not world.buy_item("aceite").ok and world.progression_state().coins == 15, "compras duplicadas no desperdician monedas")
	check(not world.deliver_apprenticeship("bicicleta_de_mateo").ok, "entrega remota desde tienda rechazada")
	position(world, "player", Layout.place_area("taller"), Colony.PLACES.taller)
	position(world, "mateo", "mateo", Colony.PLACES.taller)
	check(not world.deliver_apprenticeship("bicicleta_de_mateo").ok, "no entrega atravesando habitaciones")
	position(world, "mateo", Layout.place_area("taller"), Colony.PLACES.taller)
	check(world.deliver_apprenticeship("bicicleta_de_mateo").ok, "entrega en taller enseña procedimiento y da kit")
	check(not world.progression_state().inventory.has("aceite") and world.progression_state().inventory.kit_bicicleta == 1, "material se entrega físicamente y se recibe kit")
	check(world.progression_state().procedures.reparar_bicicleta.status == "instrucciones" and not world.can_ride_bicycle(), "instrucciones no equivalen a reparación demostrada")
	check(not world.deliver_apprenticeship("bicicleta_de_mateo").ok, "no duplica kit mediante entrega repetida")
	check(world.save_game(), "guarda instrucciones y kit antes de practicar")
	var kit_save: String = FileAccess.get_file_as_string(test_path)
	var missing_kit = JSON.parse_string(kit_save)
	missing_kit.progression.inventory.erase("kit_bicicleta")
	write_save(JSON.stringify(missing_kit))
	check(not world.load_game(), "rechaza partida con procedimiento pendiente sin kit necesario")
	write_save(kit_save)
	check(world.progression_item_name("kit_bicicleta") == "Kit de reparación de Mateo", "inventario usa nombres del catálogo completo")
	position(world, "player", "street", world._progression.entry("bicicleta_de_mateo").practice_station.pos)
	check(not world.perform_procedure("reparar_bicicleta").ok, "coordenadas de estación en calle no bastan")
	position(world, "player", "mateo", world._progression.entry("bicicleta_de_mateo").practice_station.pos)
	check(not world.perform_procedure("reparar_bicicleta").ok, "reparación exige casa propia, no ajena")
	position(world, "player", Layout.home_area("player"), Colony.HOME_DOORS.player)
	check(world.enter_home("player", "player"), "jugador puede entrar a su casa sin permiso ajeno")
	check(not world.perform_procedure("reparar_bicicleta").ok, "entrada de casa no equivale a estación de bicicleta")
	position(world, "player", "player", world._progression.entry("bicicleta_de_mateo").practice_station.pos)
	check(not world.perform_procedure("reparar_bicicleta", "probar_ruedas").ok, "rechaza paso final antes de preparar bicicleta")
	check(world.progression_state().inventory.kit_bicicleta == 1, "paso inválido no consume kit")
	check(world.perform_procedure("reparar_bicicleta", "colocar_bicicleta").ok, "ejecuta primer paso comprobado")
	check(world.progression_state().procedures.reparar_bicicleta.step_index == 1 and not world.can_ride_bicycle(), "un paso no desbloquea montar")
	check(not world.perform_procedure("reparar_bicicleta", "colocar_bicicleta").ok, "rechaza repetir primer paso fuera de orden")
	check(world.save_game(), "guarda práctica parcial e inventario reservado")
	var begun_save: String = FileAccess.get_file_as_string(test_path)
	var duplicate_kit = JSON.parse_string(begun_save)
	duplicate_kit.progression.inventory.kit_bicicleta = 1
	write_save(JSON.stringify(duplicate_kit))
	check(not world.load_game(), "rechaza práctica iniciada con kit ya consumido duplicado")
	write_save(begun_save)
	var restored = Colony.new()
	restored.save_path = test_path
	restored.setup(true)
	check(restored.progression_state().procedures.reparar_bicicleta.step_index == 1, "práctica parcial se conserva tras reiniciar")
	check(restored.quest_status("bicicleta_de_mateo").next_step_id == "lubricar_cadena", "diario recupera el siguiente paso correcto")
	check(restored.perform_procedure("reparar_bicicleta").ok, "continúa siguiente paso sin volver a gastar material")
	check(restored.perform_procedure("reparar_bicicleta", "ajustar_frenos").ok and not restored.can_ride_bicycle(), "comprobar frenos aún no termina proyecto")
	check(restored.perform_procedure("reparar_bicicleta", "probar_ruedas").ok, "prueba final completa reparación")
	check(restored.can_ride_bicycle() and restored.progression_state().inventory.bicicleta == 1, "montar se habilita solo con bicicleta real reparada")
	check(restored.progression_state().procedures.reparar_bicicleta.world_verified and restored.quest_status("bicicleta_de_mateo").status == "completed", "resultado verificado final queda en diario")
	check(not restored.perform_procedure("reparar_bicicleta").ok and restored.progression_state().inventory.bicicleta == 1, "proyecto terminado no duplica recompensas")
	var detached: Dictionary = restored.progression_state()
	detached.inventory.clear()
	check(restored.can_ride_bicycle(), "consulta de progreso no comparte inventario mutable")
	for chain in [["jardin_de_alma", "alma", "semillas", "huerto", "plantar_jardin", restored._progression.entry("jardin_de_alma").practice_station.pos], ["te_de_ines", "ines", "hojas_te", "cafe", "preparar_te", restored._progression.entry("te_de_ines").practice_station.pos]]:
		position(restored, chain[1], "street", [236.0, 210.0])
		position(restored, "player", "street", [240.0, 210.0])
		check(restored.start_apprenticeship(chain[0]).ok, "inicio %s cerca mentor fuera de su estación" % chain[0])
		position(restored, "player", "street", world._progression.catalog.shop.pos)
		check(restored.buy_item(chain[2]).ok, "compra material de " + chain[0])
		position(restored, chain[1], Layout.place_area(chain[3]), Colony.PLACES[chain[3]])
		position(restored, "player", Layout.place_area(chain[3]), Colony.PLACES[chain[3]])
		check(restored.deliver_apprenticeship(chain[0]).ok, "enseñanza y kit de " + chain[0])
		position(restored, "player", "player", chain[5])
		for index in range(4): check(restored.perform_procedure(chain[4]).ok, "paso %d de %s" % [index + 1, chain[4]])
		check(restored.quest_status(chain[0]).status == "completed", "cadena completa " + chain[0])
	check(restored.progression_state().coins == 10, "presupuesto alcanza las tres cadenas sin gasto adicional de práctica")
	check(restored.progression_state().unlocks.size() == 3, "tres capacidades desbloqueadas mediante ejecución")
	var player_context: Dictionary = restored.context_for("player", "mateo", "bicicleta")
	check(JSON.stringify(player_context.progression).length() <= 4000 and JSON.stringify(player_context).length() <= 12000, "progresión cabe en contexto rápido acotado")
	check(not restored.context_for("mateo").has("progression"), "inventario privado del jugador no se comparte con NPC")
	check(restored.save_game(), "guarda tres aprendizajes y recompensas")
	var durable = Colony.new()
	durable.save_path = test_path
	durable.setup(true)
	check(durable.can_ride_bicycle() and durable.progression_state().unlocks.size() == 3, "capacidades reales persisten tras reiniciar")
	var saved_text: String = FileAccess.get_file_as_string(test_path)
	var forged = JSON.parse_string(saved_text)
	forged.progression.procedures.reparar_bicicleta.executed_steps = ["probar_ruedas"]
	write_save(JSON.stringify(forged))
	check(not durable.load_game(), "rechaza save con ejecución de pasos falsificada o inconsistente")
	write_save(saved_text)
	var legacy = Colony.new()
	legacy.save_path = test_path
	legacy.setup(false, true)
	check(legacy.save_game(), "crea base para migración antigua")
	var old = JSON.parse_string(FileAccess.get_file_as_string(test_path))
	old.erase("progression")
	old.residents[5].home_id = ""
	write_save(JSON.stringify(old))
	check(legacy.load_game() and legacy.progression_state().quests.is_empty() and legacy.get_resident("player").home_id == "player", "save anterior migra a hogar e inventario inicial sin perder habitantes")
	deliveries_away_from_station()
	clean()
	print("RESULT PROGRESSION: %d/%d comprobaciones correctas" % [checks - failed, checks])
	quit(0 if failed == 0 else 1)

func write_save(content: String):
	var file = FileAccess.open(test_path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func clean():
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(test_path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path + suffix))
