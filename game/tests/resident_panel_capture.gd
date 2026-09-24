extends SceneTree
## Reusable visual fixture for the real resident panel. Synthetic state only.
## Godot --path game --script res://tests/resident_panel_capture.gd -- --ui-test
## Optional: --phase before|after --include-scroll (captures the end of long pages).
const Main = preload("res://scenes/main.tscn")
const SIZES := [Vector2i(768,432), Vector2i(960,540)]
const PAGES := ["historia", "recuerdos", "aspecto", "agenda"]
var output_dir: String
var captures := 0
var failures: Array[String] = []
var metadata: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func fail(message: String) -> void:
	failures.append(message)
	push_error(message)

func settle() -> void:
	for _frame in range(4): await process_frame
	await RenderingServer.frame_post_draw

func reading_scroll(panel: Control) -> ScrollContainer:
	for node in panel.find_children("*", "ScrollContainer", true, false):
		if node.is_visible_in_tree(): return node
	return null

func capture(viewport: SubViewport, scene: Control, name: String) -> void:
	await settle()
	var image: Image = viewport.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != viewport.size:
		fail("Capture has no image at the requested viewport size: " + name)
		return
	var path: String = output_dir.path_join(name + ".png")
	if image.save_png(path) != OK:
		fail("Could not save capture: " + name)
		return
	captures += 1
	var scroll: ScrollContainer = reading_scroll(scene.inspector)
	metadata.append({"file":name + ".png", "viewport":[viewport.size.x,viewport.size.y],
		"page":scene.page, "resident":scene.selected_id,
		"scroll":scroll.scroll_vertical if is_instance_valid(scroll) else 0})
	print("CAPTURE: " + path)

func world_snapshot(scene: Control) -> String:
	return JSON.stringify({"residents":scene.colony.residents, "events":scene.colony.events,
		"progression":scene.colony.progression_state(), "minute":scene.colony.minute,
		"holds":scene.colony.conversation_holds})

func prepare_fixture(scene: Control) -> void:
	var player: Dictionary = scene.colony.get_resident("player")
	var person: Dictionary = scene.colony.get_resident("lupita")
	player.name = "Íñigo Pérez"
	person.name = "María José Hernández"
	for resident: Dictionary in [player,person]:
		resident.room = "street"
		resident.pos = [270.0,194.0] if resident.id == "player" else [288.0,194.0]
		resident.target = resident.pos.duplicate()
		resident.travel_intent = ""
	person.role = "Organizadora de encuentros y actividades del barrio"
	person.biography = "Creció en una ciudad con su mamá y su papá. Su abuela, Verónica, le enseñó a escuchar con atención y a cuidar un pequeño jardín. Al llegar a la colonia empezó a conocer a César, Inés y Alma, pero también aprendió a reservar momentos tranquilos para sí misma. Le gusta preguntar cómo están sus vecinos, caminar por la plaza y anotar las ideas que surgen al preparar una reunión. ¿Qué historias compartirán mañana? Todavía quiere descubrirlo, sin prisas ni compromisos que los demás no hayan aceptado."
	person.personality = ["sociable", "curiosa", "considerada", "cuidadosa con su tiempo"]
	person.goal = "Organizar una comida sencilla en la colonia y encontrar una forma de que cada vecino participe a su ritmo, después de escuchar qué le gustaría aportar."
	player.biography = "Llegó a la colonia con una libreta llena de ideas y muchas ganas de conocer a sus vecinos. Disfruta caminar sin prisa, preguntar por las plantas y aprender un oficio mediante la práctica."
	for pair: Array in [
		["¿Recuerdas la idea de reunirnos cerca de la plaza? Me gustaría que pudiéramos conversar con calma y que cada persona eligiera cómo participar.", "Sí, recuerdo que lo comentaste. Primero podemos escuchar a los vecinos y luego decidir qué preparar, sin dar por hecho que todos tendrán tiempo."],
		["Ayer vi las flores junto a la fuente. Me fijé en sus colores y pensé que Alma podría disfrutar dibujándolas, aunque no sé si ya tiene otros planes.", "Podrías preguntárselo cuando la encuentres. Me gusta esa idea de invitarla sin asumir qué prefiere hacer."],
		["Hoy traje mi libreta para anotar ideas sobre el jardín, el café y las actividades del barrio. ¿Hay algún detalle que te gustaría que recordara?", "Que podamos hablar con tranquilidad. Cada quien tiene sus propios horarios y a veces necesita un rato a solas; podemos organizarlo poco a poco."],
		["Gracias por explicarlo. Me acordaré de preguntar antes de organizar algo y de respetar el tiempo que cada vecino quiera dedicarle.", "Gracias, Íñigo. Así podemos conocernos mejor y encontrar actividades que disfrutemos sin sentirnos presionados."],
	]:
		if not scene.colony.record_dialogue("player","lupita",pair[0],pair[1],"Datos sintéticos para revisión visual"):
			fail("Could not seed the isolated shared-memory fixture.")
	# The longer biography is visible only in this explicitly trusted fixture.
	var relationship: Dictionary = person.relationships.player
	relationship.trust = 84.0
	relationship.affection = 65.0
	relationship.tolerance = 90.0
	relationship.frustration = 0.0
	relationship.cooldown_until = 0
	person.activity = "Preparando ideas para una reunión tranquila con sus vecinos"
	var labels := [
		"Despertar, desayunar y preparar las actividades de la mañana",
		"Recorrer la plaza y escuchar las ideas de sus vecinos",
		"Conversar en el café y anotar propuestas para la colonia",
		"Tomarse un descanso y leer sus notas con tranquilidad",
		"Compartir un rato al aire libre antes de volver a casa",
		"Ordenar sus cosas y descansar hasta la mañana siguiente",
	]
	for index in range(person.schedule.size()):
		person.schedule[index].label = labels[index % labels.size()]
	scene.update_room()
	scene.overlay.dismiss_toast()
	scene.interaction_hover.clear()

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--ui-test" not in args or DisplayServer.get_name() == "headless":
		push_error("Use a graphical renderer and -- --ui-test; normal player progress is never used.")
		quit(1)
		return
	var phase := "after"
	for index in range(args.size()-1):
		if args[index] == "--phase": phase = args[index+1]
	if phase not in ["before","after"]:
		push_error("Capture phase must be before or after.")
		quit(1)
		return
	output_dir = ProjectSettings.globalize_path("res://../artifacts/resident-panel/" + phase)
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		push_error("Could not create the resident-panel capture directory.")
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = SIZES[0]
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene = Main.instantiate()
	scene.managed_by_shell = true
	scene.start_new_game = true
	scene.colony.save_path = "user://test_resident_panel_capture_%d.json" % OS.get_process_id()
	viewport.add_child(scene)
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_token = ""
	scene.service_url = ""
	scene.paused = true
	if not scene.preview_mode:
		fail("Capture refused outside isolated preview mode.")
		scene.free()
		viewport.free()
		quit(1)
		return
	prepare_fixture(scene)
	var before: String = world_snapshot(scene)
	for dimensions: Vector2i in SIZES:
		viewport.size = dimensions
		await settle()
		for page: String in PAGES:
			scene.get_viewport().gui_release_focus()
			scene.memory_scroll.clear()
			scene.resident_ui.appearance_scroll.clear()
			scene.open_inspector("player" if page == "aspecto" else "lupita",page)
			var name := "%dx%d-%s" % [dimensions.x,dimensions.y,page]
			await capture(viewport,scene,name)
			if "--include-scroll" in args:
				var scroll: ScrollContainer = reading_scroll(scene.inspector)
				if is_instance_valid(scroll) and scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page + 0.1:
					scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
					await capture(viewport,scene,name + "-fin")
	# One representative profile retains all original character data alongside
	# the deliberately long reading fixtures above.
	scene.open_inspector("mateo","historia")
	await capture(viewport,scene,"960x540-mateo-historia")
	if world_snapshot(scene) != before:
		fail("Viewing resident pages unexpectedly changed the synthetic world state.")
	if not scene.dialogue_job.is_empty() or not scene.visit_job.is_empty() or scene.decision_pending or not scene.chat_partner_id.is_empty():
		fail("Viewing resident pages unexpectedly started provider work or a conversation.")
	var file := FileAccess.open(output_dir.path_join("captures.json"),FileAccess.WRITE)
	if file == null:
		fail("Could not save capture metadata.")
	else:
		file.store_string(JSON.stringify({"synthetic":true,"captures":metadata,"failures":failures},"\t"))
		file.close()
	scene.free()
	viewport.free()
	await process_frame
	print("RESIDENT PANEL CAPTURE: %d images; %d failures" % [captures,failures.size()])
	quit(0 if failures.is_empty() else 1)
