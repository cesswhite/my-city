extends SceneTree
const Colony = preload("res://scripts/colony.gd")
const Social = preload("res://scripts/social_relationships.gd")
var checks := 0
var failed := 0
var path := "user://test_social_relationships_%d.json" % OS.get_process_id()

func _init(): call_deferred("run")

func check(value: bool, description: String) -> void:
	checks += 1
	if value: print("PASS: " + description)
	else:
		failed += 1
		push_error("FAIL: " + description)

func fresh():
	var world = Colony.new()
	world.save_path = path
	world.setup(false, true)
	world._social._willingness_roll = func(): return 1.0 # Keep relationship cases independent of random availability.
	for id in ["cesar", "player", "lupita", "mateo"]:
		world.get_resident(id).room = "street"
		world.get_resident(id).pos = [310.0,200.0] if id == "player" else [328.0,200.0]
		world.get_resident(id).target = world.get_resident(id).pos.duplicate()
	return world

func commit(world, text: String, reply: String = "Escucho lo que cuentas y comparto contigo este momento.", owner: String = "cesar") -> bool:
	return world.record_dialogue("player",owner,text,reply,"Prueba local sin proveedor")

func state(world, owner: String = "cesar", partner: String = "player") -> Dictionary:
	return world.get_resident(owner).relationships[partner]

func clean() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))

func run() -> void:
	clean()
	var world = fresh()
	var original: Dictionary = world.relationship_for("cesar","player")
	check(original.size() == 7 and original.disclosure == "public", "snapshot dirigido exacto y relación nueva pública")
	check(original.trust < world.relationship_for("lupita","player").trust, "personalidad reservada y sociable parten diferente")
	check(world.relationship_for("cesar","cesar").is_empty() and world.relationship_for("cesar","nadie").is_empty(), "rechaza relación propia e identidad desconocida")
	var copied: Dictionary = world.relationship_for("cesar","player")
	copied.trust = 99
	check(world.relationship_for("cesar","player").trust == original.trust, "lectura no comparte estado mutable")
	var raw: String = JSON.stringify(state(world))
	check(world.social_start("cesar","player").allowed, "puede iniciar charla presencial")
	check(world.social_start("cesar","player").allowed and JSON.stringify(state(world)) == raw, "inicio idempotente no regala confianza ni fatiga")
	check(world.social_turn("cesar","player","¿Cómo van las plantas?",0).reply.is_empty(), "pregunta cotidiana permite respuesta normal")
	check(JSON.stringify(state(world)) == raw, "preflight no muta aunque transporte pueda fallar")
	check(world.social_turn("cesar","player","¿Cómo era tu papá?",0).reason == "privacy", "tema íntimo requiere confianza")
	check(JSON.stringify(state(world)) == raw, "pregunta privada sin intercambio confirmado no penaliza")
	var context: Dictionary = world.context_for("cesar","player","¿Cómo era tu papá?")
	check(not context.identity.biography.contains("papá") and context.identity.goal.is_empty(), "contexto público retira biografía familiar y deseos privados")
	check(context.relationship == original and not world.context_for("cesar").has("relationship"), "relación acompaña sólo contexto con interlocutor válido")
	check(world.context_for("cesar").identity.biography == world.get_resident("cesar").biography and world.context_for("cesar").identity.goal == world.get_resident("cesar").goal, "decisión privada sin interlocutor conserva objetivos e historia propios")
	check(world.visible_profile_for("cesar","cesar").biography.contains("papá"), "perfil propio conserva historia completa")
	state(world).trust = 48
	check(world.visible_profile_for("cesar","player").biography.contains("mudarse") and not world.visible_profile_for("cesar","player").biography.contains("papá"), "confianza personal abre contexto general sin intimidad familiar")
	state(world).trust = 80
	state(world).affection = 70
	check(world.visible_profile_for("cesar","player").biography.contains("papá") and world.social_turn("cesar","player","¿Cómo era tu papá?",0).reply.is_empty(), "intimidad permite historia familiar sin inventarla")
	state(world).frustration = 70
	check(world.relationship_for("cesar","player").disclosure == "public" and world.relationship_for("cesar","player").mood == "irritated", "malestar retira permiso actual sin borrar recuerdos")
	check(world.relationship_for("player","cesar").trust != 80, "dirección inversa no hereda emociones")

	world = fresh()
	var untouched: Dictionary = world.relationship_for("mateo","player")
	world.social_start("cesar","player")
	check(commit(world,"Hoy observé nuevos brotes en las plantas del barrio."), "intercambio completo crea experiencia real")
	var credited: float = state(world).trust
	check(credited == original.trust+4 and state(world).affection == original.affection+3, "contenido sustancial aporta un ajuste limitado")
	check(world.relationship_for("mateo","player") == untouched, "tercero no recibe emociones ni experiencia ajena")
	var before_thanks: float = state(world).trust
	for index in range(8):
		world.social_finish("cesar","player")
		world.social_start("cesar","player")
		commit(world,"Muchas gracias por hablar conmigo este día tan agradable %d." % index)
	check(state(world).trust == before_thanks, "ocho agradecimientos adornados no cultivan confianza")
	world.social_finish("cesar","player")
	world.minute += 180
	commit(world,"También encontré una hoja de color distinto junto al sendero.")
	check(state(world).trust == credited+4, "segundo intercambio espaciado puede aportar confianza")
	world.social_finish("cesar","player")
	world.minute += 180
	commit(world,"Esta tarde voy a dibujar el reflejo del agua de la fuente.")
	check(state(world).trust == credited+4, "presupuesto diario limita positivos aunque cambie el texto")
	world.social_finish("cesar","player")
	world.minute += 1440
	commit(world,"Hoy observé nuevos brotes en las plantas del barrio.")
	check(state(world).trust == credited+4, "repetir tema recordado otro día tampoco concede confianza")

	world = fresh()
	world.get_resident("player").name = "Céss"
	world.social_start("cesar","player")
	var repeated := "¿Qué estás haciendo?"
	check(world.social_turn("cesar","player",repeated,0).reply.is_empty(), "primera pregunta no se trata como insistencia")
	commit(world,repeated,"Estoy observando las hojas junto al camino.")
	var warning: Dictionary = world.social_turn("cesar","player",repeated,1)
	check(warning.reason == "repeat" and not warning.end and warning.reply.contains("Céss"), "segunda pregunta igual pide cambiar tema y usa nombre real")
	commit(world,repeated,warning.reply)
	var cutoff: Dictionary = world.social_turn("cesar","player",repeated,2)
	check(cutoff.reason == "repeat_pressure" and cutoff.end, "tercera pregunta idéntica termina incluso en el mismo minuto")
	commit(world,repeated,cutoff.reply)
	check(state(world).frustration >= 15 and state(world).cooldown_until > world.minute, "insistencia confirmada consume tolerancia y deja cooldown")
	world.social_finish("cesar","player",false)
	var irritated: float = state(world).frustration
	check(not world.social_start("cesar","player").allowed and state(world).frustration > irritated, "recontacto durante pausa aumenta presión")
	var pressure: float = state(world).frustration
	world.social_start("cesar","player")
	check(state(world).frustration == pressure, "consultas repetidas del mismo inicio no multiplican presión por frame")

	world = fresh()
	world.social_start("cesar","player")
	var private_text := "¿Cómo era tu papá?"
	var private_reply: Dictionary = world.social_turn("cesar","player",private_text,0)
	commit(world,private_text,private_reply.reply)
	check(state(world).frustration == 0 and state(world).trust == original.trust, "primer límite privado no penaliza confianza")
	for index in range(2):
		private_reply = world.social_turn("cesar","player",private_text,index+1)
		commit(world,private_text,private_reply.reply)
	check(private_reply.end and state(world).frustration == 20, "insistir sobre historia privada después del límite sí tiene efecto")
	world = fresh()
	world.social_start("cesar","player")
	var insult: Dictionary = world.social_turn("cesar","player","Eres un idiota y no sirves para nada.",0)
	check(insult.end and state(world).trust == original.trust, "insulto preflight prepara límite sin escribir emoción todavía")
	commit(world,"Eres un idiota y no sirves para nada.",insult.reply)
	check(state(world).trust == original.trust-8 and state(world).frustration == 26 and state(world).tolerance == original.tolerance-24, "insulto confirmado cambia métricas una sola vez")
	var trust_before: float = state(world).trust
	world.social_finish("cesar","player")
	world.social_finish("player","cesar",false)
	check(state(world,"player","cesar").cooldown_until >= world.minute+45, "segundo cierre de pareja impone pausa aunque primero limpió sesiones")
	check(state(world).trust == trust_before, "finalizar conversación no regala confianza")
	world.minute += 60
	var recovered: Dictionary = world.relationship_for("cesar","player")
	check(recovered.frustration < 26 and recovered.tolerance > original.tolerance-24 and recovered.trust == trust_before, "dar espacio recupera ánimo pero no confianza")
	world._social.tick()
	var start_rest: Dictionary = world.relationship_for("cesar","player")
	world.get_resident("cesar").room = "cesar"
	world.get_resident("cesar").pos = Colony.HOME_REST.duplicate()
	world.get_resident("cesar").target = Colony.HOME_REST.duplicate()
	world.minute += 60
	var rested: Dictionary = world.relationship_for("cesar","player")
	check(start_rest.frustration-rested.frustration > 60*0.04 and rested.trust == trust_before, "reposo real en casa mejora recuperación sin subir confianza")

	world = fresh()
	world.social_start("cesar","player")
	world.social_turn("cesar","player","¿Cómo van las plantas?",0)
	world.social_finish("cesar","player")
	check(state(world).greeting_count == 0 and state(world,"player","cesar").greeting_count == 0, "inicio y preflight cancelados no cuentan como encuentro")
	world.social_start("cesar","player")
	commit(world,"Hoy observé nuevos brotes en las plantas del barrio.","Las hojas cambian de color con el paso de los días.")
	check(state(world).greeting_count == 1 and state(world,"player","cesar").greeting_count == 1, "primer intercambio de charla cuenta un encuentro en ambas direcciones")
	commit(world,"También encontré una hoja distinta junto al sendero.","Me gusta observar esos pequeños detalles entre las plantas.")
	commit(world,"Esta tarde voy a dibujar el reflejo de la fuente.","Me parece una buena manera de conocer nuestro barrio.")
	check(state(world).greeting_count == 1 and state(world,"player","cesar").greeting_count == 1, "dos turnos adicionales no multiplican el encuentro de la sesión")
	world.social_finish("cesar","player")
	world.minute += 65
	var after_conversation: Dictionary = world.greeting_pair("cesar","player")
	check(after_conversation.first.begins_with("Hola de nuevo"), "tras charla real y nuevo cruce recuerda que ya se vieron hoy")
	var before_greeting: float = state(world).trust
	world.record_dialogue("cesar","player",after_conversation.first,after_conversation.reply,"Saludo local")
	check(state(world).greeting_count == 2 and state(world).trust == before_greeting, "saludo posterior confirma segundo encuentro sin bonus social")

	world = fresh()
	world.get_resident("player").name = "Céss"
	var greeting_texts: Array[String] = []
	var greeting_trust: float = state(world).trust
	for index in range(4):
		var greeting: Dictionary = world.greeting_pair("cesar","player")
		greeting_texts.append(greeting.first)
		check(not greeting.first.is_empty() and state(world).greeting_count == index, "saludo %d se propone sin confirmar experiencia" % (index+1))
		check(world.greeting_pair("player","cesar").first.is_empty(), "reserva de saludo bloquea repetición simultánea inversa")
		world.record_dialogue("cesar","player",greeting.first,greeting.reply,"Saludo local")
		world.minute += 65
	check(greeting_texts[0].contains("Buenos días") and greeting_texts[0].contains("Céss") and greeting_texts[1] != greeting_texts[2] and greeting_texts[2] != greeting_texts[3], "cuatro encuentros tienen variación breve según hora y cuenta")
	check(state(world).greeting_count == 4 and state(world).trust == greeting_trust, "sólo saludos completados cuentan y no dan confianza")
	check(world.get_resident("mateo").memories.is_empty(), "saludos sólo pertenecen a testigos directos")
	world.minute = 1440+20*60
	var evening: Dictionary = world.greeting_pair("cesar","player")
	check(evening.first.begins_with("Buenas noches"), "nuevo día reinicia saludo con hora nocturna")
	world.record_dialogue("cesar","player",evening.first,evening.reply,"Saludo local")
	check(state(world).greeting_count == 1, "cuenta diaria nueva se confirma con intercambio")
	world.get_resident("player").room = "player"
	check(world.greeting_pair("cesar","player").first.is_empty(), "no saluda telepáticamente entre habitaciones")
	world.get_resident("player").room = "street"
	world.minute += 60
	world.conversation_holds.assign(["cesar"])
	check(world.greeting_pair("cesar","player").first.is_empty(), "saludo no interrumpe a vecino reservado")
	world.conversation_holds.clear()
	check(world.save_game(), "relaciones y saludos persisten en guardado validado")
	var restored = fresh()
	check(restored.load_game(), "carga estado social sin perder recuerdos")
	check(restored.relationship_for("cesar","player") == world.relationship_for("cesar","player") and state(restored).greeting_count == 1, "métricas dirigidas y cuenta diaria sobreviven a reinicio")
	check(JSON.stringify(restored.get_resident("cesar").memories) == JSON.stringify(JSON.parse_string(JSON.stringify(world.get_resident("cesar").memories))), "historia completa conserva contenido y procedencia")
	var valid_text: String = FileAccess.get_file_as_string(path)
	var valid_payload: Dictionary = JSON.parse_string(valid_text)
	for value in [-1.0,101.0,NAN,INF]:
		state(restored).trust = value
		check(not restored.save_game() and FileAccess.get_file_as_string(path) == valid_text, "métrica fuera de rango o no finita no sobrescribe partida")
	state(restored).trust = greeting_trust
	var invalid: Dictionary = state(restored).duplicate(true)
	invalid.cooldown_until = 0.5
	check(not Social.validate({"player":invalid},"cesar",restored.minute), "cooldown fraccionario inválido")
	check(not Social.validate({"cesar":state(restored)},"cesar",restored.minute), "guardado no acepta relación consigo mismo")
	check(not Social.validate({"intruso":state(restored)},"cesar",restored.minute), "guardado no acepta contraparte desconocida")
	invalid = state(restored).duplicate(true)
	invalid.recent_events.resize(9)
	check(not Social.validate({"player":invalid},"cesar",restored.minute), "bitácora social tiene tamaño acotado")
	for resident: Dictionary in valid_payload.residents: resident.erase("relationships")
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(valid_payload)); file.close()
	var old_memories: String = JSON.stringify(valid_payload.residents[0].memories)
	check(restored.load_game() and restored.get_resident("cesar").relationships.size() == 5, "migra partida anterior sin cambiar versión ni exigir campos nuevos")
	check(JSON.stringify(restored.get_resident("cesar").memories) == old_memories, "migración conserva todas las memorias previas")
	check(restored.context_for("cesar","player").relationship.size() == 7 and JSON.stringify(restored.context_for("cesar","player")).length() <= 12000, "contexto social mantiene presupuesto total")
	world = fresh()
	world.get_resident("cesar").room = "cesar"
	world.get_resident("cesar").pos = Colony.HOME_REST.duplicate()
	world.get_resident("cesar").target = Colony.HOME_REST.duplicate()
	world.get_resident("player").room = "gardens"
	world.get_resident("player").pos = Colony.HOME_DOORS.cesar.duplicate()
	state(world).cooldown_until = world.minute+45
	check(not world.request_home_visit("player","cesar").allowed, "pausa social bloquea visita local al interlocutor ocupado")
	check(not world.apply_visit_decision("player","cesar",true,"Jev: prueba sin red").allowed and not world.enter_home("player","cesar"), "preferencia externa no puede saltarse pausa social ni conceder permiso")
	state(world).cooldown_until = 0
	state(world).frustration = 70
	check(not world.apply_visit_decision("player","cesar",true,"Jev: prueba sin red").allowed, "frustración alta conserva límite de visitas")
	state(world).frustration = 0
	check(world.apply_visit_decision("player","cesar",true,"Jev: prueba sin red").allowed, "habitante tranquilo todavía puede invitar desconocido por decisión externa")
	clean()
	print("RESULT: %d/%d comprobaciones sociales correctas" % [checks-failed,checks])
	quit(0 if failed == 0 else 1)
