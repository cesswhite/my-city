extends SceneTree
const Suggestions = preload("res://scripts/chat_suggestions.gd")
const Colony = preload("res://scripts/colony.gd")
class SceneWorld extends "res://scripts/colony.gd":
	var scenes: Dictionary = {}
	func conversation_scene_for(id: String) -> Dictionary:
		return scenes[id].duplicate(true) if scenes.has(id) else super.conversation_scene_for(id)
var world
var checks := 0
var failures := 0

func _initialize():
	call_deferred("run")

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func texts(id: String, reply: String, previous: String = "", exchanges: int = 1) -> Array[String]:
	var options: Array[Dictionary] = Suggestions.suggest(world, id, reply, previous, exchanges)
	var result: Array[String] = []
	check(options.size() == 2, "dos respuestas útiles para " + id + ": " + reply)
	for option in options:
		var text: String = option.text
		check(option.label == text, "la etiqueta envía exactamente su texto")
		check(text.length() <= 45 and text.split(" ", false).size() <= 8, "opción breve: " + text)
		check(not text.contains("\n") and not text.contains("\r") and not text.contains("\t") and not text.contains("—") and not text.contains("–") and not text.contains("  "), "una frase compacta")
		check(not Suggestions._any(text.to_lower(), ["cuéntame más", "quiero aprender", "tus planes", "qué estás haciendo hoy", "world_verified", "jev", "openai", "2026"]), "sin relleno, apertura artificial ni detalles técnicos")
		check(text not in result, "opciones distintas")
		result.append(text)
	return result

func memory(id: String, spoken: String, reply: String = "Te escucho.") -> Dictionary:
	return {"kind": "conversacion", "participants": ["player", id], "turns": [{"speaker_id": "player", "name": "Tú", "text": spoken}, {"speaker_id": id, "name": id, "text": reply}]}

func run():
	world = SceneWorld.new()
	world.save_path = "user://unused_chat_suggestions_%d.json" % OS.get_process_id()
	world.setup(false, true)
	for id in ["cesar", "lupita", "mateo", "ines", "alma"]:
		var person: Dictionary = world.get_resident(id)
		world.scenes[id] = {"phase": "idle", "ongoing_action": "", "place": "calle"}
		var hello: Array[String] = texts(id, "¿Ya tienes aceite?", "Hola.", 0)
		check(hello[0] == "Hola, %s. ¿Cómo estás?" % person.name and hello[1] == "¿Qué tal va todo?", "nueva sesión saluda sin heredar preguntas viejas ni inventar trabajo")
		check(not Suggestions._any(" ".join(hello), ["papá", "abuelos", "oficio", "ciudad", "campo", "exposición", "receta"]), "apertura no revela la biografía privada de " + id)
		var daily: Array[String] = texts(id, "Estoy escuchando música.")
		check(daily == ["¿Qué te gusta de esa música?", "¿Me recomiendas una canción?"], "música no cambia a oficio o huerto por identidad de " + id)
		var open_question: Array[String] = texts(id, "¿Qué te gustaría saber?")
		check(open_question == ["¿Qué lugar me recomiendas conocer?", "¿Hace mucho que vives aquí?"], "pregunta abierta no adelanta historias privadas")
		var story: Array[String] = texts(id, "Crecí con mi tía cerca de un río.")
		check(not Suggestions._any(" ".join(story), ["papá", "mamá", "abuelos", "taller", "huerto"]), "sigue la historia contada sin sustituirla por biografía interna")
	for row in [["working", "repair", "¿Cómo va esa reparación?"], ["working", "sort_tools", "¿Ordenando las herramientas?"], ["working", "serve", "¿Está tranquilo el café?"], ["working", "tidy_cups", "¿Ya casi terminas de ordenar?"], ["working", "water", "¿Cómo van las plantas?"], ["working", "check_soil", "¿Cómo está la tierra?"], ["working", "sketch", "¿Me enseñas tu dibujo?"], ["working", "plan_meeting", "¿Cómo va la reunión?"], ["eating", "drink", "¿Qué estás tomando?"], ["walking", "repair", "¿Hacia dónde vas?"], ["resting", "", "¿Te acompaño un rato?"], ["leisure", "", "¿Te acompaño un rato?"], ["idle", "repair", "¿Qué tal va todo?"]]:
		world.scenes.mateo = {"phase": row[0], "ongoing_action": row[1], "place": "plaza", "routine": "Reparar bicicletas", "intent": "taller", "next_plan": "Reparar"}
		check(texts("mateo", "", "", 0)[1] == row[2], "apertura depende de acción observable: " + str(row[0]) + "/" + str(row[1]))
	world.scenes.mateo = {"phase": "idle", "ongoing_action": "", "paused_for_chat": true}
	var before_chat: Dictionary = {"phase": "working", "ongoing_action": "repair", "place": "taller", "activity_before_chat": "Revisando una reparación"}
	var snapshot_text: String = JSON.stringify(before_chat)
	check(Suggestions.suggest(world, "mateo", "", "", 0, before_chat)[1].text == "¿Cómo va esa reparación?", "snapshot anterior al hold conserva actividad observable en apertura")
	check(JSON.stringify(before_chat) == snapshot_text, "sugerir no modifica el snapshot de la conversación")
	check(Suggestions.suggest(world, "mateo", "", "", 0, {"phase": false, "ongoing_action": 2})[1].text == "¿Qué tal va todo?", "snapshot malformado vuelve a la escena pública segura")
	check(Suggestions.suggest(world, "mateo", "Estoy escuchando música.", "", 1, before_chat)[0].text == "¿Qué te gusta de esa música?", "después de la apertura manda el tema actual y no el trabajo anterior")
	world.scenes.clear()
	check(texts("mateo", "Estaba ordenando herramientas aquí en el taller.") == ["¿Cómo las organizas?", "¿Te falta mucho por ordenar?"], "ordenar herramientas recibe seguimiento específico")
	var still_working: Array[String] = texts("mateo", "Todavía estoy ordenando las herramientas.")
	check(still_working[0] == "¿Cómo las organizas?" and not " ".join(still_working).contains("terminaste"), "actividad en curso no se da por terminada")
	var walk_plan: Array[String] = texts("mateo", "Después pensaba dar una vuelta por el huerto.")
	check(walk_plan[0] == "¿Te acompaño a dar una vuelta?" and not Suggestions._any(" ".join(walk_plan), ["semilla", "agua", "plantar", "bici"]), "paseo por el huerto no se convierte en cultivo")
	var cafe_break: Array[String] = texts("ines", "Iba al café a tomar un descanso.")
	check(cafe_break[0] == "Que disfrutes el descanso." and not Suggestions._any(" ".join(cafe_break), ["receta", "ingredientes", "tazas", "té"]), "descanso en café no fuerza receta ni trabajo")
	var oil: String = "Mateo puede ayudarte con la bici. Necesitas aceite para la cadena."
	check(texts("cesar", oil) == ["¿Dónde consigo aceite?", "¿Mateo está en el taller?"], "aceite y Mateo conservan el asunto exacto")
	check("¿Mateo está en el taller?" not in texts("mateo", oil), "a Mateo no se le pregunta dónde está Mateo")
	var store_options: Array[String] = texts("cesar", "El aceite lo venden en la tienda. Mateo está en el taller.")
	check(store_options[0] == "Gracias, pasaré por la tienda." and "¿Dónde consigo aceite?" not in store_options and "¿Mateo está en el taller?" not in store_options, "no vuelve a preguntar ubicaciones ya respondidas")
	check("¿Dónde consigo aceite?" in texts("mateo", "La tienda no vende aceite."), "una negación no se convierte en sitio confirmado")
	check(texts("cesar", "Necesitas aceite. ¿Quieres que te enseñe a revisar la bici?")[0] == "Sí, explícame el primer paso.", "responde la última invitación antes de buscar aceite")
	check(texts("ines", "No tengo aceite. ¿Me ayudas a buscarlo?")[0] == "Sí, ¿por dónde empezamos?", "negación ajena no inventa inventario del jugador")
	check(texts("mateo", "¿No quieres que te enseñe a reparar la bici?")[0] == "Sí, explícame el primer paso.", "invitación negativa no invierte la respuesta")
	check(texts("ines", "¿Quieres té?")[0] == "Sí, me apetece una bebida.", "invitación a beber")
	check(texts("ines", "¿Qué te gustaría tomar?")[0] == "Me apetece un té.", "pregunta abierta de bebida no cambia a paseo")
	check(texts("mateo", "Estaba ordenando herramientas. ¿Y tú?")[0] == "Me apetece dar una vuelta.", "pregunta abreviada de actividad no responde estado de ánimo")
	check(texts("alma", "¿Quieres conocer mi historia?")[0] == "Sí, ¿cómo empezó tu historia?", "historia no se interpreta como bebida")
	check(texts("lupita", "¿Qué te gustaría llevar a la comida?")[0] == "Me gustaría preparar algo.", "pregunta abierta sobre comida no propone bicicletas")
	check(texts("cesar", "¿Prefieres ir al taller o al huerto?") == ["Prefiero ir al taller.", "Prefiero ir al huerto."], "alternativas contestan lugares ofrecidos")
	check(texts("cesar", "¿Quieres reparar la bici? ¿Cómo estás?")[0] == "Bien, gracias.", "sólo la última pregunta gobierna la respuesta")
	check(texts("cesar", "Crecí en el campo. ¿Y tú?")[0] == "Prefiero contártelo después.", "no inventa infancia del jugador ante pregunta abreviada")
	check(texts("cesar", "¿De dónde eres?")[0] == "Prefiero contártelo después.", "no inventa lugar de origen")
	check(texts("mateo", "No necesitas aceite para revisar los frenos.")[0] == "¿Cómo reviso los frenos?", "negación de requisito evita buscar aceite innecesario")
	check(texts("mateo", "Prefiero no hablar de la bicicleta.")[0] == "¿De qué te apetece hablar?", "respeta el cambio de tema explícito")
	check(texts("mateo", "Tienes aceite?")[0] == "Aún no tengo aceite.", "pregunta sin apertura invertida reconoce inventario vacío")
	world._progression.state.inventory.aceite = 1
	check(texts("mateo", "¿Ya tienes aceite?")[0] == "Ya tengo el aceite.", "aceite afirmado sólo con posesión real")
	check(texts("cesar", oil)[0] == "Ya tengo el aceite.", "contexto de aceite cambia después de conseguirlo")
	world._progression.state.inventory.erase("aceite")
	check(texts("cesar", oil)[0] == "¿Dónde consigo aceite?", "consumir el objeto elimina la afirmación")
	for pair in [["reparar_bicicleta", "¿Ya sabes reparar la bicicleta?"], ["plantar_jardin", "¿Ya sabes plantar el jardín?"], ["preparar_te", "¿Ya sabes preparar té?"]]:
		world.get_resident("player").skills[pair[0]] = {"status": "demostrada"}
		world._progression.state.procedures[pair[0]] = {"status": "demostrada", "world_verified": false}
		check(texts("mateo", pair[1])[0] == "Aún necesito practicar.", "atributo de habilidad solo no acredita ejecución real")
		world._progression.state.procedures[pair[0]].world_verified = true
		check(texts("mateo", pair[1])[0] == "Ya lo practiqué en casa.", "ejecución verificada permite responder que se practicó")
	world._progression.state.procedures.clear()
	var memories: Array = world.get_resident("player").memories
	memories.append(memory("cesar", "¿Dónde consigo aceite?"))
	memories.append(memory("alma", "¿Cuánto aceite necesito?"))
	memories.append(memory("cesar", "¿Mateo está en el taller?"))
	var fresh: Array[String] = texts("cesar", oil, "¿Mateo está en el taller?", 2)
	check("¿Dónde consigo aceite?" not in fresh and "¿Mateo está en el taller?" not in fresh, "evita ambos últimos mensajes del jugador con ese vecino")
	check(fresh[0] == "¿Cuánto aceite necesito?", "memoria de otra pareja no elimina una opción contextual")
	check(texts("cesar", oil, "¿DÓNDE CONSIGO ACEITE?", 1)[0] != "¿Dónde consigo aceite?", "suprime repetición con mayúsculas y puntuación")
	memories.clear()
	memories.append(memory("mateo", "La cadena está seca.", "El aceite se consigue en la tienda."))
	memories.append(memory("mateo", "¿Cuánto aceite necesito?", "Basta poco aceite para la cadena."))
	var followup: Array[String] = texts("mateo", "Basta poco aceite para la cadena.", "¿Cuánto aceite necesito?", 2)
	check("¿Dónde consigo aceite?" not in followup and "¿Cuánto aceite necesito?" not in followup, "en varios turnos conserva respuesta de lugar y cantidad")
	check(followup[0] == "Gracias, pasaré por la tienda.", "seguimiento reconoce la indicación dada en el turno anterior")
	memories.clear()
	memories.append(memory("alma", "Busco aceite.", "El aceite se consigue en la tienda."))
	check(texts("mateo", "Necesitas aceite.", "", 1)[0] == "¿Dónde consigo aceite?", "no importa respuestas privadas de otra conversación")
	memories.clear()
	memories.append(memory("mateo", "Quiero sembrar.", "En la tienda venden semillas."))
	check(texts("mateo", "Necesitas aceite.", "", 1)[0] == "¿Dónde consigo aceite?", "saber dónde venden semillas no inventa dónde venden aceite")
	memories.clear()
	var before: String = JSON.stringify(Suggestions.OPENING_ACTIONS)
	for iteration in range(12): texts("alma", "Te escucho. ¿Qué te gustaría saber?")
	check(JSON.stringify(Suggestions.OPENING_ACTIONS) == before, "sugerir repetidamente no muta ni aumenta las plantillas")
	check(Suggestions.suggest(world, "player", "", "", 0).is_empty() and Suggestions.suggest(world, "missing", "", "", 1).is_empty(), "sin sugerencias para jugador o vecino desconocido")
	check(Suggestions.suggest(null, "mateo", "", "", 0).is_empty(), "sin mundo devuelve vacío con seguridad")
	print("CHAT SUGGESTIONS: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
