extends SceneTree

var checks = 0
var failures: Array[String] = []

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# Apply after engine startup: the headless window otherwise remains 64×64.
	root.size = Vector2i(768, 432)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	expect(scene.colony.residents.size() == 6, "Five neighbors plus player exist")
	expect(scene.preview_mode and scene.paused, "UI tests do not load or save real progress")
	for node in scene.inspector.get_children():
		if node is Label:
			expect(node.position.x + node.size.x <= 254, "Profile text remains inside inspector")
	scene.selected_id = "player"
	scene.page = "aspecto"
	scene.build_inspector()
	var player: Dictionary = scene.colony.get_resident("player")
	var original: int = player.appearance.eyes
	scene.change_look(scene.APPEARANCE[3], 1)
	expect(player.appearance.eyes == (original + 1) % 5, "Eye control changes actual sprite state")
	scene.cycle_person(1)
	expect(scene.selected_id == "cesar", "Resident selection wraps correctly")
	var click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(415, 267)
	scene._gui_input(click)
	expect(preload("res://scripts/navigation.gd").is_walkable(Vector2(player.target[0], player.target[1])), "Movement stays on walkable ground")
	scene.page = "recuerdos"
	scene.build_inspector()
	await process_frame
	expect(scene.inspector.get_child_count() > 5, "Memory inspector builds")
	scene.selected_id = "lupita"
	scene.page = "hablar"
	scene.build_inspector()
	scene.chat_input.text = "Hola, soy tu nuevo vecino."
	scene.service_token = ""
	scene.send_player_dialogue()
	expect(scene.dialogue_job.is_empty(), "A distant player cannot send even in local conversation mode")
	var neighbor: Dictionary = scene.colony.get_resident("lupita")
	player.pos = neighbor.pos.duplicate()
	expect(scene.start_player_conversation("lupita"), "Streaming fixture starts a nearby player conversation")
	var before: int = neighbor.memories.size()
	scene.dialogue_serial += 1
	scene.dialogue_job = {"a": "player", "b": "lupita", "first": "Me gusta el té.", "phase": "reply", "manual_session": true, "serial": scene.dialogue_serial}
	scene.stream_prefix = "Lupita: "
	scene._dialogue_delta("Vamos al café.")
	expect(scene.chat_transcript_for("lupita").contains("Me gusta el té.") and scene.chat_output.text == "Vamos al café.", "Streaming retains the player's turn and displays the neighbor in its own bubble")
	scene.dialogue_request.metrics = {"ttft_ms": 120, "total_ms": 600}
	scene._dialogue_completed({"text": "Vamos al café.", "source": "openai"})
	expect(neighbor.memories.size() == before + 1, "Complete streamed conversation becomes persistent memory")
	expect(scene.dialogue_job.is_empty(), "Complete conversation releases the request slot")
	scene.dialogue_job = {"a": "player", "b": "lupita", "first": "Otra charla", "phase": "reply", "manual_session": true, "serial": scene.dialogue_serial}
	scene._dialogue_failed("Timeout de prueba")
	expect(neighbor.memories.size() == before + 1, "Incomplete streaming does not invent a memory")
	scene.queue_free()
	await process_frame
	print("UI: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
