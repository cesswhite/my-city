extends SceneTree
## Integration fixture: main scene + movement + homes; isolated memory, no network.

const Navigation = preload("res://scripts/navigation.gd")
var checks: int = 0
var failures: Array[String] = []
var walk_samples: int = 0
var blocked_samples: int = 0
var speed_violations: int = 0
var first_bad_sample: String = ""

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)

func step_world(scene: Node, frames: int) -> void:
	for frame in range(frames):
		for resident in scene.colony.residents:
			var before: Vector2 = scene.position_of(resident)
			var old_room: String = resident.get("room", "street")
			scene.move_resident(resident, 1.0 / 30.0)
			var position: Vector2 = scene.position_of(resident)
			var room: String = resident.get("room", "street")
			walk_samples += 1
			if not Navigation.is_walkable(position, room):
				blocked_samples += 1
				if first_bad_sample.is_empty(): first_bad_sample = "%s in %s at %s" % [resident.id, room, position]
			if old_room == room and before.distance_to(position) > (1.61 if resident.id == "player" else 1.01):
				speed_violations += 1
		scene.resolve_player_arrival()
		scene.update_room()

func click(scene: Node, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	event.position = scene.world_to_screen(point)
	scene._gui_input(event)

func run() -> void:
	# Apply after engine startup: the headless window otherwise remains 64×64.
	root.size = Vector2i(768, 432)
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Run with -- --ui-test to prevent loading or saving user progress.")
		quit(1)
		return
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.set_process(false)
	scene.service_token = ""
	scene.use_jev = false
	scene.save_allowed = false
	scene.colony.save_path = "user://unused_world_fixture_%d.json" % OS.get_process_id()
	expect(scene.preview_mode and scene.paused, "fixture no carga ni guarda el progreso real")
	var player: Dictionary = scene.colony.get_resident("player")
	for resident in scene.colony.residents:
		expect(Navigation.is_walkable(scene.position_of(resident), resident.get("room", "street")), "posición inicial válida de " + str(resident.id))

	# Normal night/morning routines must traverse the real navigation and portals.
	scene.colony.minute = 1315
	scene.colony.tick(false)
	for resident in scene.colony.residents:
		if resident.id != "player":
			expect(Vector2(resident.target[0], resident.target[1]) == Navigation.door_positions()[resident.id], "rutina nocturna apunta a puerta propia de " + str(resident.id))
	step_world(scene, 1000)
	for resident in scene.colony.residents:
		if resident.id != "player": expect(resident.room == resident.id, "regresa caminando a su casa: " + str(resident.id))
	scene.colony.minute = 1440 + 600
	scene.colony.tick(false)
	step_world(scene, 1000)
	for resident in scene.colony.residents:
		if resident.id != "player":
			expect(resident.room == "street", "sale de casa por rutina matinal: " + str(resident.id))
			expect(scene.position_of(resident).distance_to(Vector2(resident.target[0], resident.target[1])) < 2, "alcanza destino matinal: " + str(resident.id))

	# A blocked click is ignored; a valid point across the fountain routes around it.
	player.pos = [192.0, 230.0]
	player.target = player.pos.duplicate()
	scene.paths.erase("player")
	var original_target: Array = player.target.duplicate()
	expect(not Navigation.is_walkable(Vector2(236, 234)), "fuente tiene una huella de colisión")
	click(scene, Vector2(236, 234))
	expect(player.target == original_target, "clic dentro de fuente no ordena atravesarla")
	click(scene, Vector2(284, 236))
	expect(Navigation.is_walkable(Vector2(player.target[0], player.target[1])), "clic al otro lado define destino transitable")
	step_world(scene, 400)
	expect(scene.position_of(player).distance_to(Vector2(284, 236)) < 2, "camina alrededor de fuente hasta destino")

	# Owner is outside after the morning routine, so offline entry is deterministic.
	scene.walk_to_door("cesar")
	step_world(scene, 1000)
	expect(scene.pending_home.is_empty(), "llegar a puerta resuelve intención pendiente")
	expect(is_instance_valid(scene.door_panel), "se abre panel de puerta al llegar caminando")
	expect(scene.position_of(player).distance_to(Navigation.door_positions().cesar) < 5, "jugador realmente está frente a puerta")
	expect(not scene.colony.visit_context("player", "cesar").occupied, "casa de prueba está vacía")
	scene.knock_home("cesar")
	expect(player.room == "cesar" and scene.current_room == "cesar", "entrada local cruza al interior y cambia vista")
	expect(Navigation.is_walkable(scene.position_of(player), "cesar"), "entrada interior es transitable")
	expect(scene.visit_job.is_empty(), "visita local no dispara petición Jev")
	await process_frame
	var object: Dictionary = preload("res://scripts/pixel_art.gd").interior_items("cesar")[1]
	var object_memories_before: int = player.memories.size()
	click(scene, object.rect.get_center())
	expect(not scene.pending_item.is_empty(), "inspeccionar un objeto primero requiere caminar hasta él")
	expect(player.memories.size() == object_memories_before, "no observa el objeto a distancia")
	step_world(scene, 600)
	expect(scene.pending_item.is_empty() and scene.position_of(player).distance_to(object.stand_at) < 5, "alcanza el punto de interacción del objeto")
	expect(player.memories.size() == object_memories_before + 1 and player.memories[-1].kind == "objeto", "inspección completada conserva el descubrimiento personal")

	# Equal world coordinates in different rooms never count as a conversation.
	var owner: Dictionary = scene.colony.get_resident("cesar")
	owner.pos = player.pos.duplicate()
	owner.target = owner.pos.duplicate()
	scene.paths.erase("cesar")
	scene.selected_id = "cesar"
	scene.page = "hablar"
	scene.build_inspector()
	scene.chat_input.text = "¿Puedes escucharme desde otra habitación?"
	scene.service_token = "fixture-token-never-used-for-a-network-request"
	scene.send_player_dialogue()
	expect(scene.dialogue_job.is_empty() and not scene.dialogue_request.busy, "UI rechaza diálogo entre habitaciones antes de llamar a red")
	var before_memories: int = owner.memories.size()
	expect(not scene.colony.record_dialogue("player", "cesar", "Hola", "Hola", "Fixture"), "motor rechaza memoria de charla entre habitaciones")
	expect(owner.memories.size() == before_memories, "charla imposible no crea recuerdos")
	scene.service_token = ""

	scene.go_outside()
	step_world(scene, 200)
	expect(player.room == "street" and scene.current_room == "street", "salida camina hasta portal y regresa a calle")
	expect(not scene.pending_exit, "salida limpia intención pendiente")
	expect(scene.position_of(player).distance_to(Navigation.door_positions().cesar) < 5, "salida conserva puerta correcta")
	expect(blocked_samples == 0, "todos los %d pasos muestreados son transitables: %s" % [walk_samples, first_bad_sample])
	expect(speed_violations == 0, "pasos normales respetan 48 píxeles/s para jugador y 30 para vecinos")
	expect(scene.dialogue_job.is_empty() and scene.visit_job.is_empty() and not scene.decision_pending, "ningún trabajo de IA queda pendiente")
	scene.queue_free()
	await process_frame
	print("WORLD: %d/%d checks passed; %d sampled positions." % [checks - failures.size(), checks, walk_samples])
	quit(0 if failures.is_empty() else 1)
