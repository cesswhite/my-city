extends SceneTree
## The same valid, synthetic progression states before and after a journal change.
## Graphical Godot --script res://tests/journal_capture.gd -- --ui-test --phase before|after
const Main = preload("res://scenes/main.tscn")
const Layout = preload("res://scripts/world_layout.gd")
const Seats = preload("res://scripts/seating.gd")
const QUEST := "bicicleta_de_mateo"
var output_dir: String
var failures: Array[String] = []
var captures := 0
var records: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")

func fail(message: String) -> void:
	failures.append(message)
	push_error(message)

func settle() -> void:
	for _frame in range(4): await process_frame
	await RenderingServer.frame_post_draw

func position(scene, id: String, point: Vector2, room: String = "street") -> void:
	var person: Dictionary = scene.colony.get_resident(id)
	person.room = room
	person.pos = [point.x,point.y]
	person.target = person.pos.duplicate()
	person.travel_intent = ""
	scene.paths.erase(id)

func act(result: Dictionary) -> bool:
	if not result.get("ok",false):
		fail("Fixture world action failed: " + str(result.get("message","")))
		return false
	return true

func beside(scene, id: String) -> void:
	position(scene,"player",Vector2(310,200))
	position(scene,id,Vector2(328,200))

func screenshot(viewport: SubViewport, scene, name: String) -> void:
	await settle()
	var image: Image = viewport.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != viewport.size or image.save_png(output_dir.path_join(name + ".png")) != OK:
		fail("Could not capture " + name)
		return
	captures += 1
	print("CAPTURE: " + output_dir.path_join(name + ".png"))
	records.append({"file":name + ".png", "viewport":[viewport.size.x,viewport.size.y],
		"quest":scene.colony.quest_status(QUEST),"inventory":scene.colony.progression_state().inventory})

func capture_state(viewport: SubViewport, scene, state_name: String, message: String = "") -> void:
	if not scene.colony._progression.validate(scene.colony.progression_state()):
		fail("Invalid synthetic progression state: " + state_name)
	scene.update_room()
	scene.learning.last_message = message
	var before: String = JSON.stringify(scene.colony.progression_state())
	for size: Vector2i in [Vector2i(768,432),Vector2i(960,540)]:
		viewport.size = size
		await settle()
		scene.learning.show_journal(QUEST)
		var name := "%dx%d-%s" % [size.x,size.y,state_name]
		await screenshot(viewport,scene,name)
		if "--include-scroll" in OS.get_cmdline_user_args():
			var changed := false
			for scroll in scene.learning.panel.find_children("*","ScrollContainer",true,false):
				var bar: VScrollBar = scroll.get_v_scroll_bar()
				if bar.max_value > bar.page + 0.1:
					scroll.scroll_vertical = int(bar.max_value)
					changed = true
			if changed: await screenshot(viewport,scene,name + "-fin")
		scene.learning.close()
	if JSON.stringify(scene.colony.progression_state()) != before:
		fail("Reading the journal mutated progression: " + state_name)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--ui-test" not in args or DisplayServer.get_name() == "headless":
		push_error("Use a graphical renderer and -- --ui-test --phase before|after.")
		quit(1)
		return
	var phase := "before"
	for index in range(args.size()-1):
		if args[index] == "--phase": phase = args[index+1]
	if phase not in ["before","after"]:
		quit(1)
		return
	output_dir = ProjectSettings.globalize_path("res://../artifacts/journal/" + phase)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(768,432)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene = Main.instantiate()
	scene.managed_by_shell = true
	scene.start_new_game = true
	scene.colony.save_path = "user://test_journal_capture_%d.json" % OS.get_process_id()
	viewport.add_child(scene)
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_token = ""
	scene.service_url = ""
	scene.paused = true
	if not scene.preview_mode:
		fail("Refusing to capture a nonisolated world.")
		scene.free()
		viewport.free()
		quit(1)
		return
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	beside(scene,"mateo")
	await capture_state(viewport,scene,"available")
	act(scene.colony.start_apprenticeship(QUEST))
	await capture_state(viewport,scene,"accepted-missing")
	position(scene,"player",Layout.stand_at("shop","street"))
	act(scene.colony.buy_item("aceite"))
	beside(scene,"mateo")
	await capture_state(viewport,scene,"accepted-ready")
	act(scene.colony.deliver_apprenticeship(QUEST))
	await capture_state(viewport,scene,"learned")
	position(scene,"player",Layout.stand_at("bicycle","player"),"player")
	act(scene.colony.perform_procedure("reparar_bicicleta"))
	await capture_state(viewport,scene,"empty-backpack")
	for _step in range(3): act(scene.colony.perform_procedure("reparar_bicicleta"))
	await capture_state(viewport,scene,"completed-4-of-4")
	# Carry the legitimately earned bicycle, two teaching kits and a bought coffee.
	for entry: Array in [["alma","jardin_de_alma","semillas"],["ines","te_de_ines","hojas_te"]]:
		beside(scene,entry[0])
		act(scene.colony.start_apprenticeship(entry[1]))
		position(scene,"player",Layout.stand_at("shop","street"))
		act(scene.colony.buy_item(entry[2]))
		beside(scene,entry[0])
		act(scene.colony.deliver_apprenticeship(entry[1]))
	for seat: Dictionary in Seats.seats():
		if seat.prop_key != "cafe_table_left": continue
		position(scene,"player",seat.stand_at)
		act(scene.colony._progression.order_coffee(str(seat.id)))
		break
	await capture_state(viewport,scene,"long-backpack","Conservas la bicicleta reparada, los materiales de tus próximos proyectos y una taza de café. Cada aprendizaje se demuestra mediante sus pasos, a tu ritmo.")
	if not scene.dialogue_job.is_empty() or not scene.visit_job.is_empty() or scene.decision_pending:
		fail("Capture unexpectedly created provider work.")
	var file := FileAccess.open(output_dir.path_join("captures.json"),FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"synthetic":true,"captures":records,"failures":failures},"\t"))
		file.close()
	else: fail("Could not write capture metadata.")
	scene.free()
	viewport.free()
	await process_frame
	print("JOURNAL CAPTURE: %d images; %d failures" % [captures,failures.size()])
	quit(0 if failures.is_empty() else 1)
