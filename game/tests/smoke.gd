extends SceneTree
const Colony = preload("res://scripts/colony.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Layout = preload("res://scripts/world_layout.gd")
var failed: int = 0
var checks: int = 0
var test_path: String = "user://test_colony_%d.json" % OS.get_process_id()

func _init():
	call_deferred("_run")

func _check(condition: bool, label: String):
	checks += 1
	if condition:
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)

func _run():
	var colony = Colony.new()
	colony.save_path = test_path
	_clean()
	colony.setup(false, true)
	_check(colony.residents.size() == 6, "cinco vecinos y jugador")
	_check(not colony.apply_decision("player", "borrar_mundo"), "rechaza acciones fuera de contrato")
	var original_position: Array = colony.get_resident("player").pos.duplicate()
	_check(colony.apply_decision("player", "cafe"), "puede proponer un destino")
	_check(colony.get_resident("player").pos == original_position, "decidir no teletransporta al personaje")
	colony.practice("player")
	_check(not colony.last_error.is_empty(), "sin instrucciones no conoce la receta")
	colony.teach("ines", "player")
	_check(not colony.last_error.is_empty(), "no enseña a distancia")
	colony.converse("player", "ines")
	_check(not colony.last_error.is_empty(), "no conversa a distancia")
	colony.get_resident("player").pos = [100.0, 190.0]
	colony.get_resident("player").room = Layout.place_area("cafe")
	colony.get_resident("player").erase("travel_route")
	var first_dialogue: String = colony.converse("player", "ines")
	_check(colony.last_error.is_empty(), "conversación presencial")
	_check(not first_dialogue.contains("recuerdo") and not first_dialogue.contains("me acuerdo") and not first_dialogue.contains("habíamos"), "el primer encuentro no inventa recuerdos compartidos")
	_check(colony.get_resident("player").known_people.has("ines"), "registra identidad conocida")
	_check(colony.get_resident("cesar").memories.is_empty(), "César no recibe conversaciones ajenas")
	_check(colony.record_dialogue("player", "ines", "Crecí en un pueblo.", "Me gustaría conocer ese lugar.", "Jev: prueba local sin red"), "registra diálogo externo presencial")
	var external_memory: Dictionary = colony.get_resident("player").memories.back()
	_check(external_memory.epistemic_status == "testimonio_no_verificado", "diálogo externo conserva testimonio, no verdad confirmada")
	_check(colony.get_resident("cesar").memories.is_empty(), "diálogo externo no da recuerdos a terceros")
	_check(not colony.record_dialogue("player", "cesar", "Hola", "Hola", "Prueba"), "rechaza diálogo externo a distancia")
	_check(not colony.record_dialogue("player", "ines", "a".repeat(1501), "Hola", "Prueba"), "rechaza diálogo externo demasiado largo")
	_check(not colony.record_dialogue("player", "ines", " ", "Hola", "Prueba"), "rechaza diálogo externo vacío")
	var private_context: Dictionary = colony.context_for("cesar")
	_check(private_context.memories.is_empty() and private_context.known_people.is_empty(), "contexto sin recuerdos privados ajenos")
	var player_context: Dictionary = colony.context_for("player")
	player_context.memories.clear()
	_check(not colony.get_resident("player").memories.is_empty(), "contexto es una copia, no modifica recuerdos")
	colony.teach("ines", "player")
	_check(colony.last_error.is_empty(), "recibe receta presencialmente")
	_check(colony.get_resident("player").skills.preparar_te.status == "instrucciones", "enseñar no cuenta como ejecutar")
	colony.get_resident("player").pos = [236.0, 210.0]
	colony.practice("player")
	_check(not colony.last_error.is_empty(), "práctica necesita instalaciones del café")
	colony.get_resident("player").pos = [100.0, 190.0]
	colony.supplies.te = 0
	colony.practice("player")
	_check(not colony.last_error.is_empty(), "práctica comprueba ingredientes disponibles")
	colony.supplies.te = 3
	colony.practice("player")
	_check(colony.last_error.is_empty(), "ejecución completa de la receta")
	_check(colony.get_resident("player").skills.preparar_te.status == "demostrada", "habilidad demostrada por ejecución")
	_check(colony.supplies.te == 2, "preparar consume ingredientes reales")
	_check(colony.save_game(), "guarda JSON válido")
	var restored = Colony.new()
	restored.save_path = test_path
	restored.setup(false, true)
	_check(restored.load_game(), "carga partida")
	_check(restored.get_resident("player").skills.preparar_te.practice_runs == 1, "persiste aprendizaje ejecutado")
	restored.minute += 1440
	var remembered: Dictionary = restored.get_resident("player").known_people.ines.duplicate(true)
	var dialogue: String = restored.converse("player", "ines")
	_check(dialogue.contains("Sí, me acuerdo de eso.") and not dialogue.contains("día 1") and not dialogue.contains("08:00"), "reconoce encuentro anterior tras reiniciar con una frase natural sin fecha ni hora")
	_check(remembered.last_time == 480 and restored.get_resident("player").memories[0].time == "día 1 a las 08:00", "conserva fecha y hora en la procedencia interna del recuerdo")
	var next_dialogue: String = restored.converse("player", "ines")
	_check(next_dialogue.contains("Cierto, ya habíamos hablado de eso.") and next_dialogue != dialogue, "varía la frase del recuerdo entre encuentros")
	_check(restored.context_for("cesar").memories.is_empty(), "aislamiento de recuerdos tras cargar")
	restored.practice("player")
	_check(restored.last_error.is_empty() and restored.get_resident("player").skills.preparar_te.practice_runs == 2, "repite receta tras reiniciar sin volver a enseñar")
	_check(restored.save_game() and FileAccess.file_exists(test_path + ".bak"), "conserva copia previa al reemplazar")
	var valid_save: String = FileAccess.get_file_as_string(test_path)
	var payload = JSON.parse_string(valid_save)
	payload.residents[0].memories.append(restored.get_resident("player").memories[0])
	_write(JSON.stringify(payload))
	_check(not restored.load_game(), "rechaza memoria que no pertenece al personaje")
	_write("{PARTIDA ROTA")
	var minute_before: int = restored.minute
	_check(not restored.load_game() and restored.minute == minute_before, "carga dañada no altera estado en memoria")
	_check(not restored.save_game(), "no sobrescribe partida dañada")
	_check(FileAccess.get_file_as_string(test_path) == "{PARTIDA ROTA", "conserva bytes de archivo dañado")
	_write(valid_save)
	_check(restored.load_game(), "puede recuperar partida válida")
	for index in range(30): restored.tick()
	_check(restored.minute == minute_before + 150, "avance local de tiempo sin errores")
	var busy = Colony.new()
	busy.save_path = test_path
	busy.setup(false, true)
	busy.get_resident("player").pos = [100.0, 190.0]
	busy.get_resident("player").room = Layout.place_area("cafe")
	busy.record_dialogue("player", "ines", "Mi primer recuerdo es la jacaranda de mi abuela.", "Guardaremos la historia de tu jacaranda.", "Prueba")
	var anchor_id: String = busy.get_resident("player").memories[0].id
	busy.teach("ines", "player")
	for index in range(360):
		busy.minute += 1
		var topic: String = "Hoy tenemos pan dulce y café. " + "Texto cotidiano. ".repeat(50)
		if index == 110: topic = "Aprendí compostaje con hojas secas y tierra."
		busy.record_dialogue("player", "ines", topic, "Recuerdo esta visita número %d. " % index + "Una conversación tranquila. ".repeat(35), "Prueba")
	var history_size: int = busy.get_resident("player").memories.size()
	var compact: Dictionary = busy.context_for("player", "ines", "jacaranda compostaje")
	_check(JSON.stringify(compact).length() <= 12000, "contexto máximo 12000 caracteres con cientos de recuerdos")
	_check(compact.recent_conversation.size() == 4 and JSON.stringify(compact.recent_conversation).length() <= 4000, "solo cuatro intercambios recientes acotados")
	_check(compact.memories.size() <= 4 and JSON.stringify(compact.memories).length() <= 2500, "recuerdos recuperados acotados")
	var has_anchor: bool = false
	var has_teaching: bool = false
	var has_lexical: bool = false
	for memory in compact.memories:
		if memory.id == anchor_id: has_anchor = true
		if memory.kind == "enseñanza": has_teaching = true
		if str(memory.content).contains("compostaje"): has_lexical = true
	_check(has_anchor, "recupera primer encuentro fuera de las últimas 300 memorias")
	_check(has_teaching, "recupera enseñanza antigua fuera de ventana")
	_check(has_lexical, "recupera recuerdo pertinente por consulta léxica")
	_check(busy.get_resident("player").memories.size() == history_size, "compactar contexto conserva todo el historial")
	_check(compact.pair_id == busy.context_for("ines", "player").pair_id, "identificador estable y simétrico para cada pareja")
	_check(busy.context_for("cesar", "ines").recent_conversation.is_empty() and busy.context_for("cesar", "ines").memories.is_empty(), "contexto pareja no lee memorias privadas ajenas")
	compact.recent_conversation[0].content = "MODIFICADO"
	_check(not JSON.stringify(busy.get_resident("player").memories).contains("MODIFICADO"), "contexto acotado no comparte estructuras mutables")
	_check(busy.save_game(), "historial extenso sigue guardándose completo")
	var reopened = Colony.new()
	reopened.save_path = test_path
	reopened.setup(true)
	_check(reopened.get_resident("player").memories.size() == history_size, "recupera historial completo de disco")
	var reopened_context: Dictionary = reopened.context_for("player", "ines", "jacaranda")
	_check(JSON.stringify(reopened_context.memories).contains("jacaranda"), "reconstruye ancla antigua después de cargar")
	var scheduled = Colony.new()
	scheduled.setup(false, true)
	var player_target: Array = scheduled.get_resident("player").target.duplicate()
	scheduled.tick(false)
	_check(scheduled.get_resident("cesar").memories.is_empty(), "tick con IA no genera conversación plantilla")
	_check(scheduled.get_resident("player").target == player_target, "horarios no controlan al jugador")
	_check(scheduled.get_resident("cesar").routine == "Cuidar las plantas", "agenda diaria define la actividad actual")
	_check(not scheduled.decision_due("player"), "jugador excluido del planificador IA")
	_check(not scheduled.decision_due("cesar"), "no pide decisión IA mientras camina")
	scheduled.get_resident("cesar").pos = scheduled.get_resident("cesar").target.duplicate()
	scheduled.on_arrival("cesar")
	_check(scheduled.decision_due("cesar"), "pide decisión al llegar tras cambio de rutina")
	scheduled.apply_decision("cesar", "plaza")
	var ai_target: Array = scheduled.get_resident("cesar").target.duplicate()
	scheduled.tick(false)
	_check(scheduled.get_resident("cesar").target == ai_target, "misma franja no sobrescribe decisión IA")
	scheduled.get_resident("cesar").pos = ai_target.duplicate()
	_check(not scheduled.decision_due("cesar"), "enfría peticiones IA tras acción válida")
	var duplicate_schedule = Colony.new()
	duplicate_schedule.setup(false, true)
	duplicate_schedule.tick(false)
	_check(duplicate_schedule.get_resident("ines").target == scheduled.get_resident("ines").target, "horarios deterministas con igual día y personaje")
	for index in range(220): scheduled.tick(false)
	var initiatives: int = 0
	for resident in scheduled.residents:
		for memory in resident.memories:
			if memory.kind == "iniciativa": initiatives += 1
	_check(initiatives == 1, "una iniciativa propia por día sin diálogos inventados")
	var neighborhood = Colony.new()
	neighborhood.setup(false, true)
	neighborhood.get_resident("cesar").room = "street"
	neighborhood.get_resident("cesar").pos = [236.0, 210.0]
	neighborhood.get_resident("lupita").room = "street"
	neighborhood.get_resident("lupita").pos = [264.0, 215.0]
	neighborhood.record_dialogue("cesar", "lupita", "¿Qué vas a preparar?", "Voy a preparar comida con flores de calabaza.", "OpenAI: testimonio presencial")
	var reported: Dictionary = neighborhood.context_for("cesar", "player", "¿Qué te dijo Lupita sobre la comida?")
	_check(JSON.stringify(reported.memories).contains("calabaza"), "César puede contar al jugador lo que él escuchó de Lupita")
	_check(JSON.stringify(reported.memories).contains("testimonio_no_verificado") and JSON.stringify(reported.memories).contains("OpenAI: testimonio presencial") and JSON.stringify(reported.memories).contains("08:00"), "lo escuchado conserva fuente, fecha y condición de testimonio")
	var unwitnessed: Dictionary = neighborhood.context_for("mateo", "player", "¿Qué te dijo Lupita sobre la comida?")
	_check(not JSON.stringify(unwitnessed).contains("calabaza"), "Mateo no conoce conversación que no presenció")
	var resting = Colony.new()
	resting.setup(false, true)
	resting.minute = 60
	for index in range(12): resting.tick(true)
	var sleeping_conversations: int = 0
	for resident in resting.residents:
		for memory in resident.memories:
			if memory.kind == "conversacion": sleeping_conversations += 1
	_check(sleeping_conversations == 0, "vecinos descansando no generan conversaciones espontáneas")
	var homes = Colony.new()
	homes.save_path = test_path
	homes.setup(false, true)
	var guest: Dictionary = homes.get_resident("player")
	var host: Dictionary = homes.get_resident("lupita")
	guest.pos = Colony.HOME_DOORS.lupita.duplicate()
	guest.room = Layout.home_area("lupita")
	var before_visit: int = guest.memories.size()
	var empty_visit: Dictionary = homes.visit_context("player", "lupita")
	_check(empty_visit.valid and not empty_visit.occupied and guest.memories.size() == before_visit, "contexto de puerta es lectura sin inventar encuentros")
	_check(not homes.enter_home("player", "lupita"), "entrada exige permiso incluso con puerta abierta")
	_check(homes.request_home_visit("player", "lupita").allowed, "casa vacía permite explorar con solicitud local")
	_check(host.memories.is_empty(), "dueño ausente no recuerda una visita que no presenció")
	_check(homes.enter_home("player", "lupita") and guest.room == "lupita", "permiso permite cruzar a habitación correcta")
	homes.on_arrival("player")
	_check(guest.room == "lupita", "llegada jugador no cambia automáticamente de habitación")
	guest.pos = [240.0, 190.0]
	_check(not homes.leave_home("player"), "salida exige alcanzar puerta interior")
	guest.pos = Colony.ROOM_EXIT.duplicate()
	_check(homes.leave_home("player") and guest.room == Layout.home_area("lupita"), "salir regresa a puerta correspondiente de su área")
	_check(not homes.enter_home("player", "lupita"), "permiso de entrada se consume una sola vez")
	guest.pos[0] -= 20 # Keep knocking distance without occupying the host's exit.
	guest.target = guest.pos.duplicate()
	host.pos = Colony.HOME_DOORS.lupita.duplicate()
	host.room = Layout.home_area("lupita")
	_check(homes.enter_home("lupita", "lupita"), "dueño entra libremente a su casa")
	_check(not homes.request_home_visit("player", "lupita").allowed, "dueño desconocido niega visita según política local")
	homes.request_home_visit("player", "lupita")
	_check(homes.visit_context("player", "lupita").encounters == 0 and not host.known_people.has("player"), "repetir golpes a la puerta no fabrica confianza")
	host.pos = Colony.ROOM_EXIT.duplicate()
	homes.leave_home("lupita")
	homes.record_dialogue("player", "lupita", "Me da gusto conocerte.", "Podemos conversar en la plaza.", "Testimonio presencial de prueba")
	homes.enter_home("lupita", "lupita")
	_check(homes.request_home_visit("player", "lupita").allowed, "habitante sociable recibe conocido tras encuentro real")
	host.pos = Colony.ROOM_EXIT.duplicate()
	homes.leave_home("lupita")
	_check(not homes.enter_home("player", "lupita"), "permiso caduca si dueño cambia habitación")
	homes.enter_home("lupita", "lupita")
	host.pos = Colony.HOME_REST.duplicate()
	host.target = host.pos.duplicate()
	homes.request_home_visit("player", "lupita")
	homes.minute += 20
	_check(not homes.enter_home("player", "lupita"), "permiso de puerta caduca con tiempo")
	homes.request_home_visit("player", "lupita")
	homes.enter_home("player", "lupita")
	guest.pos = [110.0, 178.0]
	_check(not homes.record_dialogue("player", "ines", "Hola", "Hola", "Prueba"), "no conversa entre habitación y calle aunque coordenadas coincidan")
	homes.teach("ines", "player")
	_check(not homes.last_error.is_empty(), "no enseña una receta a través de habitaciones")
	guest.skills = homes.get_resident("ines").skills.duplicate(true)
	homes.practice("player")
	_check(not homes.last_error.is_empty(), "casa no equivale al café aunque coordenadas coincidan")
	_check(not JSON.stringify(homes.context_for("player").observations).contains("ines"), "percepción no ve personajes de otra habitación")
	guest.pos = Colony.ROOM_EXIT.duplicate()
	homes.leave_home("player")
	guest.pos = Colony.HOME_DOORS.mateo.duplicate()
	guest.room = Layout.home_area("mateo")
	var mateo: Dictionary = homes.get_resident("mateo")
	mateo.pos = Colony.HOME_DOORS.mateo.duplicate()
	mateo.room = Layout.home_area("mateo")
	homes.enter_home("mateo", "mateo")
	mateo.pos = Colony.HOME_REST.duplicate()
	mateo.target = mateo.pos.duplicate()
	_check(not homes.request_home_visit("player", "mateo").allowed, "política local protege relación todavía desconocida")
	var online_visit: Dictionary = homes.apply_visit_decision("player", "mateo", true, "jev")
	_check(online_visit.allowed and online_visit.decision_source == "jev", "decisión externa puede invitar con fuente explícita")
	_check(homes.enter_home("player", "mateo"), "invitación externa obtiene permiso físico válido")
	_check(homes.save_game(), "guarda habitaciones y estados de visita")
	var loaded_homes = Colony.new()
	loaded_homes.save_path = test_path
	loaded_homes.setup(true)
	_check(loaded_homes.get_resident("player").room == "mateo", "posición y habitación persisten tras recarga")
	var night = Colony.new()
	night.setup(false, true)
	night.minute = 1380
	night.tick(false)
	var returning: Dictionary = night.get_resident("cesar")
	_check(returning.target == Colony.HOME_DOORS.cesar, "agenda nocturna envía dueño hacia su puerta")
	returning.pos = returning.target.duplicate()
	night.on_arrival("cesar")
	_check(returning.room == "cesar" and returning.target == Colony.HOME_REST, "dueño entra solo y se dirige a descansar dentro")
	night.apply_decision("cesar", "plaza")
	_check(returning.target == Colony.ROOM_EXIT, "destino calle desde casa primero requiere salida interior")
	returning.pos = returning.target.duplicate()
	night.on_arrival("cesar")
	var assigned_plaza := Vector2(float(returning.target[0]), float(returning.target[1]))
	var next_street: Dictionary = Layout.next_exit(Layout.home_area("cesar"), Layout.place_area("plaza"))
	_check(returning.room == Layout.home_area("cesar") and returning.travel_intent == "plaza" and returning.travel_route.room == Layout.place_area("plaza") and assigned_plaza.is_equal_approx(next_street.at) and Navigation.is_walkable(assigned_plaza, returning.room), "al salir continúa por el paso de su área hacia la plaza")
	var hosted = Colony.new()
	hosted.save_path = test_path
	hosted.setup(false, true)
	var visiting_npc: Dictionary = hosted.get_resident("lupita")
	visiting_npc.pos = Colony.HOME_DOORS.cesar.duplicate()
	visiting_npc.room = Layout.home_area("cesar")
	hosted.request_home_visit("lupita", "cesar")
	hosted.enter_home("lupita", "cesar")
	hosted.get_resident("player").pos = Colony.HOME_DOORS.cesar.duplicate()
	hosted.get_resident("player").room = Layout.home_area("cesar")
	hosted.get_resident("player").pos[0] -= 20 # Leave the exit free while awaiting a reply.
	hosted.get_resident("player").target = hosted.get_resident("player").pos.duplicate()
	var occupied_by_guest: Dictionary = hosted.visit_context("player", "cesar")
	_check(occupied_by_guest.occupied and occupied_by_guest.resident_id == "lupita", "invitado presente responde cuando propietario está ausente")
	var absent_owner_memories: int = hosted.get_resident("cesar").memories.size()
	hosted.request_home_visit("player", "cesar")
	_check(hosted.get_resident("cesar").memories.size() == absent_owner_memories, "propietario ausente no recibe recuerdos de respuesta del invitado")
	_check(not visiting_npc.memories.is_empty(), "ocupante que contesta conserva experiencia de puerta")
	var pending_signature: String = occupied_by_guest.occupant_signature
	visiting_npc.pos = Colony.ROOM_EXIT.duplicate()
	hosted.leave_home("lupita")
	var stale_response: Dictionary = hosted.apply_visit_decision("player", "cesar", true, "jev", pending_signature)
	_check(not stale_response.valid and not stale_response.allowed, "respuesta de IA tardía se rechaza si cambió quien estaba dentro")
	_check(not hosted.observe_house_item("player", "cesar", "Semillas", "Semillas del campo."), "observar objeto requiere estar dentro de la casa")
	hosted.request_home_visit("player", "cesar")
	hosted.enter_home("player", "cesar")
	_check(hosted.observe_house_item("player", "cesar", "Semillas", "Semillas del campo que César conserva de su papá."), "objeto inspeccionado se convierte en observación personal")
	var observed_count: int = hosted.get_resident("player").memories.size()
	hosted.observe_house_item("player", "cesar", "Semillas", "Semillas del campo que César conserva de su papá.")
	_check(hosted.get_resident("player").memories.size() == observed_count, "inspección repetida no duplica recuerdo del objeto")
	_check(hosted.get_resident("cesar").memories.size() == absent_owner_memories, "observar objeto no escribe recuerdos en otros habitantes")
	_check(hosted.save_game(), "guarda observaciones de objetos")
	var observed_reload = Colony.new()
	observed_reload.save_path = test_path
	observed_reload.setup(true)
	observed_reload.observe_house_item("player", "cesar", "Semillas", "Semillas del campo que César conserva de su papá.")
	_check(observed_reload.get_resident("player").memories.size() == observed_count, "deduplicación de objeto persiste tras cargar")
	_check(JSON.stringify(observed_reload.context_for("player", "cesar", "semillas").memories).contains("Semillas"), "recuerdo del objeto se recupera para conversar")
	_test_conversation_holds()
	_test_dialogue_continuity()
	_clean()
	print("RESULT: %d/%d comprobaciones correctas" % [checks - failed, checks])
	quit(0 if failed == 0 else 1)

func _conversation_count(resident: Dictionary) -> int:
	var total: int = 0
	for memory in resident.memories:
		if memory.kind == "conversacion": total += 1
	return total

func _test_conversation_holds():
	var colony = Colony.new()
	colony.save_path = test_path
	colony.setup(false, true)
	colony.set_player_autonomy(true)
	colony.minute = 600
	for resident in colony.residents:
		resident.room = "street"
		resident.pos = [236.0, 210.0]
		resident.target = resident.pos.duplicate()
		resident.erase("travel_route")
	for id in ["player", "ines"]:
		colony.get_resident(id).pos = [110.0, 178.0]
		colony.get_resident(id).target = [110.0, 178.0]
	colony.conversation_holds.assign(["player", "ines"])
	_check(not colony.decision_due("player") and not colony.decision_due("ines"), "participantes retenidos no solicitan decisiones IA")
	_check(colony.decision_due("mateo"), "retener una pareja no detiene decisiones de otros vecinos")
	var held_target: Array = colony.get_resident("ines").target.duplicate()
	_check(not colony.apply_decision("ines", "huerto") and colony.get_resident("ines").target == held_target, "decisión tardía no desplaza a participante retenido")
	colony.converse("player", "ines")
	_check(not colony.last_error.is_empty() and colony.get_resident("player").memories.is_empty(), "diálogo plantilla no interrumpe conversación retenida")
	colony.get_resident("mateo").pos = [112.0, 178.0]
	_check(colony._nearest(colony.get_resident("mateo"), true).is_empty(), "buscar interlocutor omite pareja retenida aunque sea la más cercana")
	_check(colony._nearest(colony.get_resident("ines")).is_empty(), "participante retenido no busca otra conversación")
	colony.get_resident("mateo").pos = [236.0, 210.0]
	_check(colony.apply_decision("mateo", "conversar"), "otro vecino puede conversar durante la retención")
	_check(colony.record_dialogue("player", "ines", "Estoy terminando de contarte mi historia.", "Te escucho, ¿qué ocurrió después?", "Prueba manual"), "retención permite registrar el diálogo manual completo")
	var player_before: int = _conversation_count(colony.get_resident("player"))
	var ines_before: int = _conversation_count(colony.get_resident("ines"))
	var free_before: int = _conversation_count(colony.get_resident("cesar"))
	for index in range(72):
		# An available encounter now requires arrival and a short activity pause.
		# Advance real routes instead of asking residents still walking to chat.
		for resident in colony.residents:
			if resident.id in colony.conversation_holds or colony.is_sleeping(resident.id): continue
			var point := Vector2(resident.pos[0], resident.pos[1])
			var goal := Vector2(resident.target[0], resident.target[1])
			var budget := 120.0
			for waypoint in Navigation.route(point, goal, resident.room):
				var distance: float = minf(point.distance_to(waypoint), budget)
				point = point.move_toward(waypoint, distance)
				budget -= distance
				if budget <= 0.0: break
			resident.pos = [point.x, point.y]
			if point.distance_to(goal) <= 0.1: colony.on_arrival(resident.id)
		colony.tick(true)
	_check(_conversation_count(colony.get_resident("player")) == player_before and _conversation_count(colony.get_resident("ines")) == ines_before, "ticks locales no crean charlas paralelas de participantes retenidos")
	_check(_conversation_count(colony.get_resident("cesar")) > free_before, "los demás habitantes mantienen conversaciones espontáneas")
	_check(colony.get_resident("player").target != colony.get_resident("player").pos and not colony.get_resident("player").routine.is_empty(), "agenda retenida puede actualizar el destino que host reanudará")
	_check(colony.save_game() and not JSON.parse_string(FileAccess.get_file_as_string(test_path)).has("conversation_holds"), "retenciones no se escriben en la partida")
	_check(colony.load_game() and colony.conversation_holds.is_empty(), "cargar limpia retenciones de la sesión")
	colony.conversation_holds.assign(["ines"])
	colony.setup(false, true)
	_check(colony.conversation_holds.is_empty(), "setup reinicia retenciones")
	colony.get_resident("ines").target = colony.get_resident("ines").pos.duplicate()
	_check(colony.decision_due("ines") and colony.apply_decision("ines", "plaza"), "al liberar retención vuelven las decisiones habituales")

func _test_dialogue_continuity():
	var colony = Colony.new()
	colony.save_path = test_path
	colony.setup(false, true)
	colony.get_resident("player").pos = colony.get_resident("ines").pos.duplicate()
	colony.get_resident("player").room = colony.get_resident("ines").room
	for index in range(6):
		var opening: String = ("INICIO_JUGADOR_%d " % index + "Un detalle largo con comillas \" y barra \\. ".repeat(55)).left(1400) + " FIN_JUGADOR_%d" % index
		var reply: String = ("INICIO_INES_%d " % index + "Te escuché y recuerdo otra historia. ".repeat(50)).left(1370) + " ¿Volverás mañana a contarme el final %d?" % index
		_check(colony.record_dialogue("player", "ines", opening, reply, "Prueba de continuidad"), "registra intercambio largo %d" % index)
		colony.minute += 5
	var context: Dictionary = colony.context_for("ines", "player")
	_check(context.recent_conversation.size() == 4 and JSON.stringify(context.recent_conversation).length() <= 4000, "contexto conserva cuatro intercambios con presupuesto total acotado")
	var both_voices: bool = true
	var all_budgeted: bool = true
	var closing_questions: bool = true
	for index in range(context.recent_conversation.size()):
		var memory: Dictionary = context.recent_conversation[index]
		var turn_index: int = index + 2
		both_voices = both_voices and memory.content.contains("Tú: INICIO_JUGADOR_%d" % turn_index) and memory.content.contains("Inés: INICIO_INES_%d" % turn_index) and memory.content.contains("FIN_JUGADOR_%d" % turn_index)
		closing_questions = closing_questions and memory.content.contains("¿Volverás mañana a contarme el final %d?" % turn_index)
		all_budgeted = all_budgeted and JSON.stringify(memory).length() <= 975 and memory.heard_from == "player" and memory.origin == "Prueba de continuidad" and memory.epistemic_status == "testimonio_no_verificado" and not memory.time.is_empty()
	_check(both_voices, "mensajes largos conservan inicio y final de ambas voces")
	_check(closing_questions, "las preguntas finales del NPC sobreviven a la compactación")
	_check(all_budgeted and JSON.stringify(context).length() <= 12000, "cada intercambio respeta 975 caracteres con fuente y contexto total 12000")
	_check(not JSON.stringify(colony.context_for("cesar", "player")).contains("INICIO_INES"), "continuidad de pareja no filtra una conversación a terceros")
	var saved_turns: Array = colony.get_resident("ines").memories.back().turns.duplicate(true)
	context.recent_conversation.back().content = "CONTEXTO ALTERADO"
	_check(colony.get_resident("ines").memories.back().turns == saved_turns, "compactación no comparte turnos mutables con el historial")
	_check(colony.save_game(), "guarda episodios con turnos estructurados")
	var restored = Colony.new()
	restored.save_path = test_path
	restored.setup(true)
	_check(restored.get_resident("ines").memories.back().turns == saved_turns, "voces completas sobreviven al reinicio")
	_check(restored.context_for("ines", "player").recent_conversation.back().content.contains("el final 5?"), "el siguiente turno recupera la última pregunta tras cargar")
	var valid_save: String = FileAccess.get_file_as_string(test_path)
	var invalid = JSON.parse_string(valid_save)
	for resident in invalid.residents:
		if resident.id == "ines": resident.memories.back().turns[0].speaker_id = "mateo"
	_write(JSON.stringify(invalid))
	_check(not restored.load_game(), "rechaza turnos que atribuyen la voz a un tercero ajeno")
	var legacy = JSON.parse_string(valid_save)
	for resident in legacy.residents:
		for memory in resident.memories: memory.erase("turns")
	_write(JSON.stringify(legacy))
	_check(restored.load_game(), "partidas antiguas sin turnos estructurados siguen cargando")
	var legacy_recent: Array = restored.context_for("ines", "player").recent_conversation
	_check(legacy_recent.size() == 4 and legacy_recent.back().content.contains("Tú: INICIO_JUGADOR_5") and legacy_recent.back().content.contains("Inés: INICIO_INES_5") and legacy_recent.back().content.contains("el final 5?"), "transcripción antigua también conserva dos voces y última pregunta")
	restored.get_resident("ines").name = "Noemí"
	_check(restored.context_for("ines", "player").recent_conversation.back().content.contains("el final 5?"), "recuerdo antiguo conserva el cierre incluso si cambió el nombre del personaje")

func _write(content: String):
	var file = FileAccess.open(test_path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func _clean():
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(test_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path + suffix))
