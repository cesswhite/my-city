extends SceneTree
## Regression coverage through the live scene clock, controls and stream signals.
## Run with -- --ui-test: never load, save or contact a provider.

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)

func advance(scene: Node, frames: int) -> void:
	for _frame in range(frames):
		scene._process(1.0 / 30.0)

func memory_container(scene: Node) -> ScrollContainer:
	for child in scene.inspector.get_children():
		if child is ScrollContainer:
			return child
	return null

func run() -> void:
	# Apply after engine startup: the headless window otherwise remains 64×64.
	root.size = Vector2i(768, 432)
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --ui-test so the fixture cannot load or save user progress.")
		quit(1)
		return
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.colony._social._willingness_roll = func(): return 1.0
	await process_frame
	await process_frame
	# Drive full _process deterministically; this includes the actual four-second tick.
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_token = ""
	expect(scene.preview_mode and scene.colony.minute == 480, "isolated scene begins at eight without loading the real save")
	var player: Dictionary = scene.colony.get_resident("player")
	var mentor: Dictionary = scene.colony.get_resident("mateo")
	var old_mentor_position: Vector2 = scene.position_of(mentor)
	scene.walk_to_mentor("mateo")
	for _frame in range(900):
		scene._process(1.0 / 30.0)
		if scene.pending_mentor.is_empty():
			break
	expect(scene.colony.minute >= 485 and scene.position_of(mentor).distance_to(old_mentor_position) > 20, "actual morning tick moves Mateo away from his initial workshop position")
	expect(scene.pending_mentor.is_empty(), "following a moving mentor completes")
	expect(player.room == mentor.room and scene.position_of(player).distance_to(scene.position_of(mentor)) < 20, "arrival is near Mateo now, not his obsolete starting position")
	expect(scene.position_of(player).distance_to(old_mentor_position) > 20, "player avoids stopping at the old workshop destination")

	# Populate genuine memory records, then let a scheduled UI refresh happen.
	for index in range(30):
		scene.colony._remember(player, scene.colony._memory("fixture", ["player"],
			"Recuerdo %d. " % index + "Una historia suficientemente larga para necesitar desplazamiento. ".repeat(4), "prueba aislada"))
	scene.selected_id = "player"
	scene.page = "recuerdos"
	scene.build_inspector()
	await process_frame
	await process_frame
	var scroll: ScrollContainer = memory_container(scene)
	scroll.scroll_vertical = 300
	var before_scroll: int = scroll.scroll_vertical
	var before_tick: int = scene.colony.minute
	advance(scene, 125)
	await process_frame
	await process_frame
	expect(scene.colony.minute > before_tick, "memory regression is exercised while world time advances")
	expect(before_scroll == 300 and memory_container(scene).scroll_vertical == before_scroll, "memory reading position survives a scheduled refresh")
	scene.selected_id = "mateo"
	scene.build_inspector()
	await process_frame
	await process_frame
	scene.selected_id = "player"
	scene.build_inspector()
	await process_frame
	await process_frame
	expect(memory_container(scene).scroll_vertical == 300, "each resident retains a separate memory reading position")

	# Meet Lupita via navigation; feed real SSE parser signals without making a request.
	scene.walk_to_mentor("lupita")
	for _frame in range(1200):
		scene._process(1.0 / 30.0)
		if scene.pending_mentor.is_empty():
			break
	var neighbor: Dictionary = scene.colony.get_resident("lupita")
	expect(player.room == neighbor.room and scene.position_of(player).distance_to(scene.position_of(neighbor)) < 20, "chat participants first meet by walking")
	scene.selected_id = "lupita"
	scene.page = "hablar"
	scene.build_inspector()
	expect(scene.start_player_conversation("lupita"), "stream fixture begins a real nearby manual conversation")
	var next_draft: String = "Mi siguiente pregunta todavía no debe enviarse."
	scene.chat_input.text = next_draft
	var memories_before: int = player.memories.size()
	scene.dialogue_serial += 1
	scene.dialogue_job = {"a": "player", "b": "lupita", "first": "Una pregunta ya enviada.", "phase": "reply", "manual_session": true, "serial": scene.dialogue_serial}
	scene.stream_prefix = "Lupita: "
	scene.stream_text = ""
	scene.dialogue_request._reset_state()
	scene.dialogue_request.busy = true
	scene.dialogue_request.set_process(false)
	scene.dialogue_request._accept_bytes("event: delta\ndata: {\"text\":\"Respuesta de prueba.\"}\n\n".to_utf8_buffer())
	expect(scene.chat_output.text.ends_with("Respuesta de prueba.") and player.memories.size() == memories_before, "partial stream displays while the next draft and memories stay separate")
	before_tick = scene.colony.minute
	advance(scene, 125)
	expect(scene.colony.minute > before_tick, "chat regression includes a live clock tick during streaming")
	scene.dialogue_request._accept_bytes("event: done\ndata: {\"text\":\"Respuesta de prueba.\",\"source\":\"fixture\"}\n\n".to_utf8_buffer())
	expect(scene.dialogue_job.is_empty() and player.memories.size() == memories_before + 1, "complete stream commits the conversation once")
	expect(scene.chat_input.text == next_draft, "completion preserves the next unsent message through inspector rebuilding")
	scene.selected_id = "mateo"
	scene.build_inspector()
	expect(scene.chat_input.text.is_empty(), "Lupita's draft does not appear in Mateo's editor")
	scene.chat_input.text = "Un borrador distinto para Mateo."
	scene.selected_id = "lupita"
	scene.build_inspector()
	expect(scene.chat_input.text == next_draft, "returning to Lupita restores only her draft")

	# Enter the player's own house through its portal, then keep the clock running.
	var appearance_before: Dictionary = player.appearance.duplicate(true)
	var inventory_before: Dictionary = scene.colony.progression_state().inventory.duplicate(true)
	scene.walk_to_door("player")
	for _frame in range(1500):
		scene._process(1.0 / 30.0)
		if scene.pending_home.is_empty() and is_instance_valid(scene.door_panel):
			break
	expect(is_instance_valid(scene.door_panel), "player reaches the real front door before entering")
	scene.knock_home("player")
	expect(player.room == "player" and scene.current_room == "player", "own-house portal changes room and visible scenery")
	expect(player.target == player.pos and scene.position_of(player) == Vector2(236, 252), "player enters at the safe entry without receiving an automatic rest destination")
	before_tick = scene.colony.minute
	advance(scene, 125)
	expect(scene.colony.minute > before_tick and scene.position_of(player) == Vector2(236, 252), "player stays in control while indoor world time continues")
	expect(player.appearance == appearance_before and scene.colony.progression_state().inventory == inventory_before, "entering home preserves appearance and owned items")
	expect(not scene.dialogue_request.busy and scene.dialogue_job.is_empty() and scene.visit_job.is_empty(), "fixture ends without pending provider work")
	scene.free()
	await process_frame
	print("INTERACTION: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
