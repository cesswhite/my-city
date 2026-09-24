extends SceneTree
## Real home UI with isolated residents, local movement and no saved progress.
## Graphical Godot --script res://tests/home_ui_capture.gd -- --ui-test --phase before|after
const Main = preload("res://scenes/main.tscn")
const Layout = preload("res://scripts/world_layout.gd")
const Targets = preload("res://scripts/world_interactions.gd")
const HOMES := ["cesar","lupita","mateo","ines","alma","player"]
const SIZES := [Vector2i(768,432),Vector2i(960,540)]
var directory: String
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

func fixture(viewport: SubViewport, room: String) -> Control:
	var scene = Main.instantiate()
	scene.managed_by_shell = true
	scene.start_new_game = true
	scene.colony.save_path = "user://test_home_ui_capture_%d.json" % OS.get_process_id()
	viewport.add_child(scene)
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_token = ""
	scene.service_url = ""
	scene.paused = true
	for resident: Dictionary in scene.colony.residents:
		resident.room = resident.id
		resident.pos = Layout.data().home_rest.duplicate()
		resident.target = resident.pos.duplicate()
		resident.travel_intent = ""
	var player: Dictionary = scene.colony.get_resident("player")
	player.room = room
	player.pos = Layout.data().entry.duplicate()
	player.target = player.pos.duplicate()
	scene.paths.clear()
	scene.update_room()
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	scene.interaction_hover.clear()
	scene.refresh_status()
	return scene

func pointer(scene: Control, at: Vector2, pressed: bool = false) -> void:
	if pressed:
		var click := InputEventMouseButton.new()
		click.position = scene.world_to_screen(at)
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		scene.get_viewport().push_input(click,true)
		click = click.duplicate()
		click.pressed = false
		scene.get_viewport().push_input(click,true)
	else:
		var motion := InputEventMouseMotion.new()
		motion.position = scene.world_to_screen(at)
		scene.get_viewport().push_input(motion,true)

func capture(viewport: SubViewport, scene: Control, name: String) -> void:
	scene.actors.queue_redraw()
	await settle()
	var image: Image = viewport.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != viewport.size or image.save_png(directory.path_join(name+".png")) != OK:
		fail("Could not capture " + name)
		return
	captures += 1
	records.append({"file":name+".png","room":scene.current_room,"viewport":[viewport.size.x,viewport.size.y]})
	print("CAPTURE: " + directory.path_join(name+".png"))

func capture_object(viewport: SubViewport, scene: Control, room: String, prefix: String) -> void:
	var semantic_key: String = room + ":item:" + ("postcard" if room == "player" else "project")
	var target := {}
	for item: Dictionary in Targets._targets(room,scene.home_project_state()):
		if item.key == semantic_key:
			target = item
			break
	if target.is_empty():
		fail("The fixture could not find the real home object: " + semantic_key)
		return
	var player: Dictionary = scene.colony.get_resident("player")
	var previous_memories: int = player.memories.size()
	pointer(scene,target.rect.get_center())
	await capture(viewport,scene,prefix+"-object-hover")
	pointer(scene,target.rect.get_center(),true)
	if scene.pending_item.is_empty() or player.memories.size() != previous_memories:
		fail("Object selection must begin an approach, without learning from a distance: " + room)
		return
	for _frame in range(700):
		scene.move_resident(player,1.0/30.0)
		scene.resolve_player_arrival()
		scene.update_room()
		if scene.pending_item.is_empty(): break
	if not scene.pending_item.is_empty() or scene.position_of(player).distance_to(target.item.stand_at) >= 5:
		fail("Object reading did not reach its real interaction point: " + room)
	scene.interaction_hover.clear()
	scene.paused = true
	scene.refresh_status()
	await capture(viewport,scene,prefix+"-object-read")

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
	directory = ProjectSettings.globalize_path("res://../artifacts/home-ui/"+phase)
	DirAccess.make_dir_recursive_absolute(directory)
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for size: Vector2i in SIZES:
		viewport.size = size
		for room: String in HOMES:
			var scene: Control = fixture(viewport,room)
			if not scene.preview_mode:
				fail("Nonisolated world refused.")
				scene.free()
				quit(1)
				return
			var prefix := "%dx%d-%s" % [size.x,size.y,room]
			await capture(viewport,scene,prefix+"-entry")
			if room in ["cesar","player"]: await capture_object(viewport,scene,room,prefix)
			if not scene.dialogue_job.is_empty() or not scene.visit_job.is_empty() or scene.decision_pending or scene.colony.minute != 480:
				fail("Home preview changed the clock or scheduled provider work: " + room)
			scene.free()
			await process_frame
	var file := FileAccess.open(directory.path_join("captures.json"),FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"synthetic":true,"captures":records,"failures":failures},"\t"))
		file.close()
	else: fail("Could not save capture metadata.")
	viewport.free()
	await process_frame
	print("HOME UI CAPTURE: %d images; %d failures" % [captures,failures.size()])
	quit(0 if failures.is_empty() else 1)
