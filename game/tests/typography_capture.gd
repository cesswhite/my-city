extends SceneTree
## Repeatable full-UI captures; only synthetic local data and --ui-test are accepted.
const SIZE := Vector2i(768, 432)
var output_dir: String
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for _frame in range(4): await process_frame
	await RenderingServer.frame_post_draw

func capture(viewport: SubViewport, name: String) -> void:
	await settle()
	var image: Image = viewport.get_texture().get_image()
	var path: String = output_dir.path_join(name + ".png")
	if image.is_empty() or image.get_size() != SIZE or image.save_png(path) != OK:
		failures += 1
		push_error("Could not capture native viewport: " + name)
	else: print("CAPTURE: " + path)

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--ui-test" not in args or DisplayServer.get_name() == "headless":
		push_error("Use a graphical renderer and -- --ui-test --phase before|after.")
		quit(1)
		return
	var phase: String = "before"
	for index in range(args.size() - 1):
		if args[index] == "--phase": phase = args[index + 1]
	if phase not in ["before", "after"]:
		push_error("Capture phase must be before or after.")
		quit(1)
		return
	output_dir = ProjectSettings.globalize_path("res://../artifacts/typography/" + phase)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene = load("res://scenes/main.tscn").instantiate()
	viewport.add_child(scene)
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_token = ""
	scene.paused = true
	if not scene.preview_mode:
		push_error("Refusing capture outside isolated preview mode.")
		scene.free()
		quit(1)
		return
	var player: Dictionary = scene.colony.get_resident("player")
	var lupita: Dictionary = scene.colony.get_resident("lupita")
	player.name = "María José"
	player.room = "street"
	player.pos = [264.0, 178.0]
	player.target = player.pos.duplicate()
	lupita.room = "street"
	lupita.pos = [280.0, 178.0]
	lupita.target = lupita.pos.duplicate()
	lupita.biography = "Creció en una ciudad con su mamá y su papá. Le gusta reunir a los vecinos, escuchar sus historias y aprender a cultivar hierbas."
	lupita.goal = "Organizar una comida en el barrio y conocer mejor a sus vecinos."
	scene.message("Una mañana en la colonia: César, Inés y Lupita preparan café. ¿Qué te gustaría aprender hoy?")
	scene.selected_id = "lupita"
	scene.page = "historia"
	scene.build_inspector()
	await capture(viewport, "story")
	for texts in [
		["Hola, Lupita. ¿Cómo estás?", "Hola, María José. Estoy bien, gracias. ¿Y tú?"],
		["Me gustaría conocer mejor el barrio.", "Me gusta reunir a los vecinos y aprender a cultivar hierbas."],
		["¿Cómo puedo participar?", "Podemos empezar por conocer el huerto y saludar a Alma."],
	]: scene.colony.record_dialogue("player", "lupita", texts[0], texts[1], "Fixture local de tipografía")
	scene.start_player_conversation("lupita")
	scene.chat_drafts.lupita = "Sí, me gustaría. ¿Qué necesito llevar?"
	scene.page = "hablar"
	scene.build_inspector()
	await capture(viewport, "chat")
	scene.end_player_conversation()
	scene.show_help()
	await capture(viewport, "help")
	scene.close_help()
	scene.learning.show_journal("bicicleta_de_mateo")
	await capture(viewport, "learning")
	scene.learning.close()
	scene.selected_id = "player"
	scene.page = "aspecto"
	scene.build_inspector()
	await capture(viewport, "appearance")
	if not scene.dialogue_job.is_empty() or scene.decision_pending or not scene.visit_job.is_empty():
		failures += 1
		push_error("Capture unexpectedly scheduled network work.")
	print("TYPOGRAPHY CAPTURE: %s; failures=%d" % [phase, failures])
	scene.free()
	viewport.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
