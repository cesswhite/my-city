extends SceneTree
## Isolated visual review of the full-world presentation. Never loads a saved game.
var viewport: SubViewport
var scene: Control

func _initialize() -> void: call_deferred("run")

func capture(name: String) -> void:
	scene.actors.queue_redraw()
	for frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var path: String = OS.get_environment("MY_CITY_CAPTURE_DIR")
	if not path.is_empty(): viewport.get_texture().get_image().save_png(path.path_join(name + ".png"))

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		quit(1)
		return
	viewport = SubViewport.new()
	viewport.size = Vector2i(960,540)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	scene = load("res://scenes/main.tscn").instantiate()
	viewport.add_child(scene)
	scene.set_process(false)
	scene.save_allowed = false
	scene.service_token = ""
	scene.controls_active = true
	scene.overlay.dismiss_toast()
	scene.paused = false
	scene.colony.minute = 610
	scene.refresh_status()
	await capture("world")
	scene.open_inspector("cesar","historia")
	await capture("profile")
	scene.open_inspector("player","aspecto")
	await capture("appearance")
	scene.hide_inspector()
	var player: Dictionary = scene.colony.get_resident("player")
	var neighbor: Dictionary = scene.colony.get_resident("mateo")
	player.pos = [308,184]
	player.target = player.pos.duplicate()
	neighbor.pos = [332,184]
	neighbor.target = neighbor.pos.duplicate()
	scene.start_player_conversation("mateo")
	scene.player_chat._messages.assign([{"speaker_id":"player","name":"Tú","text":"Hola, Mateo. ¿En qué andabas?"},{"speaker_id":"mateo","name":"Mateo","text":"Estaba ordenando las herramientas del taller. ¿Cómo vas?"}])
	scene.player_chat.session_exchanges = 1
	scene.build_inspector()
	await capture("chat")
	scene.close_chat_panel()
	player.room = "player"
	player.pos = [236,252]
	player.target = player.pos.duplicate()
	scene.update_room()
	await capture("interior")
	scene.free()
	viewport.free()
	quit()
