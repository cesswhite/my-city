extends SceneTree
## Isolated rendered evidence. No save file or provider calls.
const Main = preload("res://scenes/main.tscn")
const Layout = preload("res://scripts/world_layout.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		quit(1)
		return
	root.size = Vector2i(1152, 648)
	var scene = Main.instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.use_jev = false
	scene.save_allowed = false
	if "--sleep" in OS.get_cmdline_user_args() or "--choices" in OS.get_cmdline_user_args():
		var player: Dictionary = scene.colony.get_resident("player")
		var bed: Vector2 = Layout.stand_at("bed", "player")
		player.room = "player"
		player.pos = [bed.x, bed.y]
		player.target = player.pos.duplicate()
		player.energy = 40.0
		scene.colony.minute = 1380
		scene.selected_id = "player"
		scene.update_room()
		if "--choices" in OS.get_cmdline_user_args(): scene.sleep_ui.show_choices()
		else: scene.sleep_ui.start(480)
	else:
		for _tick in range(20):
			scene.colony.tick(true)
			for _frame in range(40):
				for resident: Dictionary in scene.colony.residents: scene.move_resident(resident, 0.1)
		scene.selected_id = "cesar"
	scene.build_inspector()
	scene.refresh_status()
	scene.actors.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var destination: String = OS.get_environment("MY_CITY_CAPTURE")
	if destination.is_empty(): quit(1)
	else:
		var result: Error = root.get_texture().get_image().save_png(destination)
		quit(0 if result == OK else 1)
